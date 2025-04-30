require "http/server"
require "http/status"
require "validator"
require "./controller"
require "../schemas/music_schemas"
require "../validators/music_validator"
require "../repositories/music_repository"
require "../utils/str"

# Controller for handling requests made to the music resource
class Controllers::MusicController < Controllers::Controller
  include Validators::MusicValidator

  MUSIC_ID_LENGTH = 22
  MUSIC_ID_STRING_LENGTH = 35 # MUSIC_ID_LENGTH + 1 + String::HEADER_SIZE

  def initialize(@music_repository : Repositories::MusicRepository, @auth_middleware : Middleware::AuthMiddleware, @rate_limit_middleware : Middleware::RateLimitMiddleware)
    @prefix_length = "/api/v1/users/music".size
  end

  # Handles requests made to the /api/v1/users/music route by directing it to the correct handler
  def handle_request(context : HTTP::Server::Context) : Nil
    # Get distinguishing path from resource string
    path = context.request.resource.unsafe_byte_slice(@prefix_length)

    # Call appropriate request handler
    case {context.request.method, path}
    when {"POST", "".to_slice}
      add_music(context)
    when {"GET", _}
      # Fetch music metadata
      if path.size == 0 || path.unsafe_fetch(0) == '?'.ord
        get_music(context)

      # Fetch music file or cover art
      elsif path.size > 1 && path.unsafe_fetch(0) == '/'.ord
        # Determine if cover art or music file is requested
        sub_path_ptr = path.to_unsafe + 1
        slash_ptr = LibC.memchr(sub_path_ptr, '/'.ord, path.size - 1)

        # Handle request
        if slash_ptr.null?
          get_music_file(context, Bytes.new(sub_path_ptr, path.size - 1))
        elsif context.request.resource.ends_with?("cover-art")
          get_music_cover_art(context, Bytes.new(sub_path_ptr, slash_ptr.as(UInt8*) - sub_path_ptr))
        else
          context.response.status = HTTP::Status::NOT_FOUND
        end
      else
        context.response.status = HTTP::Status::NOT_FOUND
      end
    when {"PUT", _}
      if path.size > 1 && path.unsafe_fetch(0) == '/'.ord
        sub_path_ptr = path.to_unsafe + 1
        slash_ptr = LibC.memchr(sub_path_ptr, '/'.ord, path.size - 1)

        if !slash_ptr.null? && context.request.resource.ends_with?("cover-art")
          set_cover_art(context, Bytes.new(sub_path_ptr, slash_ptr.as(UInt8*) - sub_path_ptr))
        else
          context.response.status = HTTP::Status::NOT_FOUND
        end
      else
        context.response.status = HTTP::Status::NOT_FOUND
      end
    when {"PATCH", _}
      if path.size > 1 && path.unsafe_fetch(0) == '/'.ord
        update_music(context, Bytes.new(path.to_unsafe + 1, path.size - 1))
      else
        context.response.status = HTTP::Status::NOT_FOUND
      end
    when {"DELETE", _}
      if path.size > 1 && path.unsafe_fetch(0) == '/'.ord
        delete_music_file(context, Bytes.new(path.to_unsafe + 1, path.size - 1))
      else
        context.response.status = HTTP::Status::NOT_FOUND
      end
    else
      context.response.status = HTTP::Status::NOT_FOUND
    end
  end

  # Adds a music file to the user's collection
  #
  # Method: POST
  # Path: /api/v1/users/music
  def add_music(context : HTTP::Server::Context) : Nil
    # Get user
    user_id = @auth_middleware.get_user(context)
    return if user_id.nil?

    # Validate user input
    data = validate_add_music_request context
    return if data.nil?

    # Check if music with the given title already exists
    music_exists = @music_repository.exists_by_title(user_id, data.title)
    if music_exists
      context.response.status = HTTP::Status::CONFLICT
      context.response.output << "Music with given title already exists"
      return
    end

    # Add music to the user's collection
    music_id = @music_repository.create(data.title, data.artist, data.music_file, data.art_file, user_id)

    # Free allocated memory
    LibC.free(data.file_buffer)

    # Return error response if there were issues adding the music file
    if music_id.nil?
      context.response.status = HTTP::Status::INTERNAL_SERVER_ERROR
      return
    end

    # Send success response
    context.response.content_type = "application/json"
    context.response.status = HTTP::Status::CREATED
    context.response.output << AddMusicResponse.new(
      music_id: music_id,
      title: data.title,
      artist: data.artist,
    )
  end

  # Retreives the title and artist for each music file in the user's collection
  #
  # Method: GET
  # Path: /api/v1/users/music
  def get_music(context : HTTP::Server::Context) : Nil
    # Get user
    user_id = @auth_middleware.get_user(context)
    return if user_id.nil?

    # Read pagination parameters
    limit = context.request.query_params["limit"]?
    offset = context.request.query_params["offset"]?

    # Validate limit and offset values
    limit_value = limit.nil? ? nil : limit.to_i?
    if !limit.nil? && (limit_value.nil? || limit_value < 0)
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Invalid limit parameter"
      return
    end

    offset_value = offset.nil? ? nil : offset.to_i?
    if !offset.nil? && (offset_value.nil? || offset_value < 0)
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Invalid offset parameter"
      return
    end

    # Send music data
    context.response.content_type = "application/json"
    context.response.status = HTTP::Status::OK
    @music_repository.list(user_id, context, limit_value, offset_value)
  end

  # Retreives a music file from the user's collection
  #
  # Method: GET
  # Path: /api/v1/users/music/{music_id}
  def get_music_file(context : HTTP::Server::Context, music_id : Bytes) : Nil
    # Get user
    user_id = @auth_middleware.get_user(context)
    return if user_id.nil?

    # Perform rate limiting
    music_request_allowed = @rate_limit_middleware.rate_limit_request(user_id, "GET", "/api/v1/users/music/{music_id}")
    if !music_request_allowed
      context.response.status = HTTP::Status::TOO_MANY_REQUESTS
      context.response.output << "Too Many Requests"
      return
    end

    # Fetch music file and write contents to the response body
    @music_repository.get(user_id, music_id, context)
  end

  # Retreives the cover art for a music file from the user's collection
  #
  # Method: GET
  # Path: /api/v1/users/music/{music_id}/cover-art
  def get_music_cover_art(context : HTTP::Server::Context, music_id : Bytes) : Nil
    # Get user
    user_id = @auth_middleware.get_user(context)
    return if user_id.nil?

    # Perform rate limiting
    get_cover_art_request_allowed = @rate_limit_middleware.rate_limit_request(user_id, "GET", "/api/v1/users/music/{music_id}/cover-art")
    if !get_cover_art_request_allowed
      context.response.status = HTTP::Status::TOO_MANY_REQUESTS
      context.response.output << "Too Many Requests"
      return
    end

    # Fetch music cover art and write contents to the response body
    @music_repository.get_cover_art(user_id, music_id, context)
  end

  # Sets the cover art for a music file from the user's collection
  #
  # Method: PUT
  # Path: /api/v1/users/music/{music_id}/cover-art
  def set_cover_art(context : HTTP::Server::Context, music_id : Bytes) : Nil
    # Get user
    user_id = @auth_middleware.get_user(context)
    return if user_id.nil?

    # Perform rate limiting
    set_cover_art_request_allowed = @rate_limit_middleware.rate_limit_request(user_id, "PUT", "/api/v1/users/music/{music_id}/cover-art")
    if !set_cover_art_request_allowed
      context.response.status = HTTP::Status::TOO_MANY_REQUESTS
      context.response.output << "Too Many Requests"
      return
    end

    # Check if music file exists
    music_id_buffer = uninitialized UInt8[MUSIC_ID_STRING_LENGTH]
    music_file_exists = false
    if music_id.size == MUSIC_ID_LENGTH
      music_id_str = Utils::Str.stringify(music_id, music_id_buffer.to_unsafe)
      music_file_exists = @music_repository.exists_by_id(user_id, music_id_str)
    end

    unless music_file_exists
      context.response.status = HTTP::Status::NOT_FOUND
      context.response.output << "Music file not found"
      return
    end

    # Validate user input
    data = validate_set_cover_art_request context
    return if data.nil?

    # Set cover art for the music file
    cover_art_created = @music_repository.set_cover_art(user_id, music_id, data.art_file)

    # Free allocated memory
    LibC.free(data.art_file.to_unsafe)

    # Send success response
    if cover_art_created
      context.response.status = HTTP::Status::CREATED
      context.response.headers["Location"] = Utils::Str.combine_bytes("/users/music/", music_id, "/cover-art")
    else
      context.response.status = HTTP::Status::NO_CONTENT
    end
  end

  # Updates metadata for a music file from the user's collection
  #
  # Method: PATCH
  # Path: /api/v1/users/music/{music_id}
  def update_music(context : HTTP::Server::Context, music_id : Bytes) : Nil
    # Get user
    user_id = @auth_middleware.get_user(context)
    return if user_id.nil?

    # Validate user input
    data = validate_update_music_request context
    return if data.nil?

    # Update music file
    music_id_buffer = uninitialized UInt8[MUSIC_ID_STRING_LENGTH]
    music_updated = false
    if music_id.size == MUSIC_ID_LENGTH
      music_id_str = Utils::Str.stringify(music_id, music_id_buffer.to_unsafe)
      music_updated = @music_repository.update(user_id, music_id_str, data.title, data.artist)
    end

    unless music_updated
      context.response.status = HTTP::Status::NOT_FOUND
      context.response.output << "Music file not found"
      return
    end

    # Send success response
    context.response.status = HTTP::Status::NO_CONTENT
  end

  # Deletes a music file from the user's collection
  #
  # Method: DELETE
  # Path: /api/v1/users/music/{music_id}
  def delete_music_file(context : HTTP::Server::Context, music_id : Bytes) : Nil
    # Get user
    user_id = @auth_middleware.get_user(context)
    return if user_id.nil?

    # Delete music file
    music_id_buffer = uninitialized UInt8[MUSIC_ID_STRING_LENGTH]
    file_removed = false
    if music_id.size == MUSIC_ID_LENGTH
      music_id_str = Utils::Str.stringify(music_id, music_id_buffer.to_unsafe)
      file_removed = @music_repository.delete(user_id, music_id_str)
    end

    unless file_removed
      context.response.status = HTTP::Status::NOT_FOUND
      context.response.output << "Music file not found"
      return
    end

    # Send success response
    context.response.status = HTTP::Status::NO_CONTENT
  end
end
