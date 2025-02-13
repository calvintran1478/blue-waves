require "http/server"
require "http/status"
require "validator"
require "./controller"
require "../schemas/music_schemas"
require "../validators/music_validator"
require "../repositories/music_repository"

# Controller for handling requests made to the music resource
class Controllers::MusicController < Controllers::Controller
  include Validators::MusicValidator

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
      if path.size == 0 || path[0] == '?'.ord
        get_music(context)

      # Fetch music file or cover art
      elsif path.size > 1 && path[0] == '/'.ord
        # Determine if cover art or music file is requested
        sub_path = path[1...]
        slash_index = sub_path.index('/'.ord)

        # Handle request
        if slash_index.nil?
          get_music_file(context, String.new(sub_path))
        elsif sub_path[slash_index...] == "/cover-art".to_slice
          get_music_cover_art(context, String.new(sub_path[...slash_index]))
        else
          context.response.status = HTTP::Status::NOT_FOUND
        end
      else
        context.response.status = HTTP::Status::NOT_FOUND
      end
    when {"PUT", _}
      if path.size > 1 && path[0] == '/'.ord
        sub_path = path[1...]
        slash_index = sub_path.index('/'.ord)
        if sub_path[slash_index...] == "/cover-art".to_slice
          set_cover_art(context, String.new(sub_path[...slash_index]))
        else
          context.response.status = HTTP::Status::NOT_FOUND
        end
      else
        context.response.status = HTTP::Status::NOT_FOUND
      end
    when {"PATCH", _}
      if path.size > 1 && path[0] == '/'.ord
        update_music(context, String.new(path[1...]))
      else
        context.response.status = HTTP::Status::NOT_FOUND
      end
    when {"DELETE", _}
      if path.size > 1 && path[0] == '/'.ord
        delete_music_file(context, String.new(path[1...]))
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

    # Delete temporary files
    data.music_file.delete
    data.art_file.as(File).delete unless data.art_file.nil?

    # Return error response if there were issues adding the music file
    if music_id.nil?
      context.response.status = HTTP::Status::INTERNAL_SERVER_ERROR
      return
    end

    # Send success response
    context.response.content_type = "application/json"
    context.response.status = HTTP::Status::CREATED
    response_body = AddMusicResponse.new(
      music_id: music_id,
      title: data.title,
      artist: data.artist,
    )
    response_body.to_json(context.response.output)
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

    # Fetch music data
    music_items = @music_repository.list(user_id, limit_value, offset_value)

    # Send music data
    context.response.content_type = "application/json"
    context.response.status = HTTP::Status::OK
    response_body = GetMusicResponse.new(
      music: music_items
    )
    response_body.to_json(context.response.output)
  end

  # Retreives a music file from the user's collection
  #
  # Method: GET
  # Path: /api/v1/users/music/{music_id}
  def get_music_file(context : HTTP::Server::Context, music_id : String) : Nil
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
  def get_music_cover_art(context : HTTP::Server::Context, music_id : String) : Nil
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
  def set_cover_art(context : HTTP::Server::Context, music_id : String) : Nil
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
    music_file_exists = @music_repository.exists_by_id(user_id, music_id)
    if !music_file_exists
      context.response.status = HTTP::Status::NOT_FOUND
      context.response.output << "Music file not found"
      return
    end

    # Validate user input
    data = validate_set_cover_art_request context
    return if data.nil?

    # Set cover art for the music file
    cover_art_created = @music_repository.set_cover_art(user_id, music_id, data.art_file)

    # Send success response
    if cover_art_created
      context.response.status = HTTP::Status::CREATED
      context.response.headers["Location"] = "/users/music/#{music_id}/cover-art"
    else
      context.response.status = HTTP::Status::NO_CONTENT
    end
  end

  # Updates metadata for a music file from the user's collection
  #
  # Method: PATCH
  # Path: /api/v1/users/music/{music_id}
  def update_music(context : HTTP::Server::Context, music_id : String) : Nil
    # Get user
    user_id = @auth_middleware.get_user(context)
    return if user_id.nil?

    # Validate user input
    data = validate_update_music_request context
    return if data.nil?

    # Update music file
    music_updated = @music_repository.update(user_id, music_id, data.title, data.artist)
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
  def delete_music_file(context : HTTP::Server::Context, music_id : String) : Nil
    # Get user
    user_id = @auth_middleware.get_user(context)
    return if user_id.nil?

    # Delete music file
    file_removed = @music_repository.delete(user_id, music_id)
    unless file_removed
      context.response.status = HTTP::Status::NOT_FOUND
      context.response.output << "Music file not found"
      return
    end

    # Send success response
    context.response.status = HTTP::Status::NO_CONTENT
  end
end
