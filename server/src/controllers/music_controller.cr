require "http/server"
require "http/status"
require "validator"
require "./controller"
require "../schemas/music_schemas"
require "../validators/music_validator"
require "../repositories/music_repository"
require "../utils/str"

# Controller for handling requests made to the music resource
struct Controllers::MusicController < Controllers::Controller
  include Validators::MusicValidator

  def initialize(@music_repository : Repositories::MusicRepository, @auth_middleware : Middleware::AuthMiddleware, @rate_limit_middleware : Middleware::RateLimitMiddleware)
  end

  # Handles requests made to the /api/v1/users/music route by directing it to the correct handler
  def handle_request(context : HTTP::Server::Context) : Nil
    # Get distinguishing path from resource string
    path = context.request.resource.unsafe_byte_slice(MUSIC_ENDPOINT_PREFIX_LENGTH)

    # Call appropriate request handler
    case {context.request.method, path}
    when {"POST", "".to_slice}
      add_music(context)
    when {"GET", _}
      if path.size == 0 || path.unsafe_fetch(0) == '?'.ord
        get_music(context)
      elsif path.size == GET_MUSIC_FILE_PATH_SIZE && path.unsafe_fetch(0) == '/'.ord
        get_music_file(context, path.to_unsafe + 1)
      elsif path.size == GET_MUSIC_COVER_ART_PATH_SIZE && path.unsafe_fetch(0) == '/'.ord && context.request.resource.ends_with?("/cover-art")
        get_music_cover_art(context, path.to_unsafe + 1)
      else
        context.response.status = HTTP::Status::NOT_FOUND
      end
    when {"PUT", _}
      if path.size == SET_MUSIC_COVER_ART_PATH_SIZE && path.unsafe_fetch(0) == '/'.ord && context.request.resource.ends_with?("/cover-art")
        set_music_cover_art(context, path.to_unsafe + 1)
      else
        context.response.status = HTTP::Status::NOT_FOUND
      end
    when {"PATCH", _}
      if path.size == UPDATE_MUSIC_PATH_SIZE && path.unsafe_fetch(0) == '/'.ord
        update_music(context, path.to_unsafe + 1)
      else
        context.response.status = HTTP::Status::NOT_FOUND
      end
    when {"DELETE", _}
      if path.size == DELETE_MUSIC_PATH_SIZE && path.unsafe_fetch(0) == '/'.ord
        delete_music_file(context, path.to_unsafe + 1)
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
    add_music_request_buffer = uninitialized UInt8[ADD_MUSIC_REQUEST_BUFFER_SIZE]
    data = validate_add_music_request(context, add_music_request_buffer.to_unsafe)
    return if data.nil?

    # Add music to the user's collection
    user_id_str = Utils::Str.finalize_user_id(user_id)
    music_id = @music_repository.create(data.title, data.artist, data.music_file, data.art_file, data.music_file_type, data.art_file_type, user_id_str)

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
    user_id_str = Utils::Str.finalize_user_id(user_id)
    context.response.content_type = "application/json"
    context.response.status = HTTP::Status::OK
    @music_repository.list(user_id_str, context, limit_value, offset_value)
  end

  # Retreives a music file from the user's collection
  #
  # Method: GET
  # Path: /api/v1/users/music/{music_id}
  def get_music_file(context : HTTP::Server::Context, music_id : UInt8*) : Nil
    # Get user
    user_id = @auth_middleware.get_user(context)
    return if user_id.nil?

    # Perform rate limiting
    user_id_bytes = Bytes.new(user_id, USER_ID_LENGTH)
    music_request_allowed = @rate_limit_middleware.rate_limit_request(user_id_bytes, "GET", "/api/v1/users/music/{music_id}")
    if !music_request_allowed
      context.response.status = HTTP::Status::TOO_MANY_REQUESTS
      context.response.output << "Too Many Requests"
      return
    end

    # Fetch music file and write contents to the response body
    @music_repository.get(user_id_bytes, Bytes.new(music_id, MUSIC_ID_LENGTH), context)
  end

  # Retreives the cover art for a music file from the user's collection
  #
  # Method: GET
  # Path: /api/v1/users/music/{music_id}/cover-art
  def get_music_cover_art(context : HTTP::Server::Context, music_id : UInt8*) : Nil
    # Get user
    user_id = @auth_middleware.get_user(context)
    return if user_id.nil?

    # Fetch music cover art and write contents to the response body
    user_id_bytes = Bytes.new(user_id, USER_ID_LENGTH)
    @music_repository.get_cover_art(user_id_bytes, Bytes.new(music_id, MUSIC_ID_LENGTH), context, @rate_limit_middleware)
  end

  # Sets the cover art for a music file from the user's collection
  #
  # Method: PUT
  # Path: /api/v1/users/music/{music_id}/cover-art
  def set_music_cover_art(context : HTTP::Server::Context, music_id : UInt8*) : Nil
    # Get user
    user_id = @auth_middleware.get_user(context)
    return if user_id.nil?

    # Perform rate limiting
    user_id_bytes = Bytes.new(user_id, USER_ID_LENGTH)
    set_cover_art_request_allowed = @rate_limit_middleware.rate_limit_request(user_id_bytes, "PUT", "/api/v1/users/music/{music_id}/cover-art")
    if !set_cover_art_request_allowed
      context.response.status = HTTP::Status::TOO_MANY_REQUESTS
      context.response.output << "Too Many Requests"
      return
    end

    # Check if music file exists
    user_id_str = Utils::Str.finalize_user_id(user_id)
    music_id_str = Utils::Str.finalize_music_id(music_id)
    unless @music_repository.exists_by_id(user_id_str, music_id_str)
      context.response.status = HTTP::Status::NOT_FOUND
      context.response.output << "Music file not found"
      return
    end

    # Validate user input
    data = validate_set_cover_art_request context
    return if data.nil?

    # Set cover art for the music file
    cover_art_created = @music_repository.set_cover_art(user_id_bytes, music_id_str, data.art_file, data.art_file_type)

    # Free allocated memory
    LibC.free(data.art_file.to_unsafe)

    # Send success response
    if cover_art_created
      context.response.status = HTTP::Status::CREATED
      context.response.headers["Location"] = Utils::Str.combine_bytes("/users/music/", music_id_str, "/cover-art")
    else
      context.response.status = HTTP::Status::NO_CONTENT
    end
  end

  # Updates metadata for a music file from the user's collection
  #
  # Method: PATCH
  # Path: /api/v1/users/music/{music_id}
  def update_music(context : HTTP::Server::Context, music_id : UInt8*) : Nil
    # Get user
    user_id = @auth_middleware.get_user(context)
    return if user_id.nil?

    # Validate user input
    update_music_buffer = uninitialized UInt8[UPDATE_MUSIC_REQUEST_BUFFER_SIZE]
    data = validate_update_music_request(context, update_music_buffer.to_unsafe)
    return if data.nil?

    # Update music file
    user_id_str = Utils::Str.finalize_user_id(user_id)
    music_id_str = Utils::Str.finalize_music_id(music_id)
    unless @music_repository.update(user_id_str, music_id_str, data.title, data.artist)
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
  def delete_music_file(context : HTTP::Server::Context, music_id : UInt8*) : Nil
    # Get user
    user_id = @auth_middleware.get_user(context)
    return if user_id.nil?

    # Delete music file
    user_id_str = Utils::Str.finalize_user_id(user_id)
    music_id_str = Utils::Str.finalize_music_id(music_id)
    unless @music_repository.delete(user_id_str, music_id_str)
      context.response.status = HTTP::Status::NOT_FOUND
      context.response.output << "Music file not found"
      return
    end

    # Send success response
    context.response.status = HTTP::Status::NO_CONTENT
  end
end
