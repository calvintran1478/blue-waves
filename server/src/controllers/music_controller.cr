require "http/server"
require "http/status"
require "validator"
require "./controller"
require "../schemas/music_schemas"
require "../validators/music_validator"
require "../repositories/music_repository"
require "../utils/auth"

# Controller for handling requests made to the music resource
class Controllers::MusicController < Controllers::Controller
  include Validators::MusicValidator

  def initialize(@music_repository : Repositories::MusicRepository)
    @prefix_length = "/api/v1/users/music".size
  end

  # Handles requests made to the /api/v1/users/music route by directing it to the correct handler
  def handle_request(context : HTTP::Server::Context) : Nil
    # Get distinguishing path from resource string
    path = context.request.resource[@prefix_length, context.request.resource.size]

    # Call appropriate request handler
    case {context.request.method, path}
    when {"POST", ""}
      add_music(context)
    when {"GET", _}
      # Fetch music metadata
      if path.size == 0
        get_music(context)

      # Fetch music file or cover art
      elsif path.size > 1 && path[0] == '/'
        # Determine if cover art or music file is requested
        sub_path = path[1...]
        slash_index = sub_path.index("/")

        # Handle request
        if slash_index.nil?
          get_music_file(context, sub_path)
        elsif sub_path[slash_index...] == "/cover-art"
          get_music_cover_art(context, sub_path[...slash_index])
        else
          context.response.status = HTTP::Status::NOT_FOUND
        end
      else
        context.response.status = HTTP::Status::NOT_FOUND
      end
    when {"DELETE", _}
      if path.size != 0 && path[0] == '/'
        delete_music_file(context, path[1...])
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
    user_id = Utils::Auth.get_user(context)
    return if user_id.nil?

    # Validate user input
    data = validate_add_music_request context
    return if data.nil?

    # Check if music with the given title already exists
    music_exists = @music_repository.exists(data.title, user_id)
    if music_exists
      context.response.status = HTTP::Status::CONFLICT
      context.response.output << ExceptionResponse.new("Music with given title already exists").to_json
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
    context.response.output << AddMusicResponse.new(
      music_id: music_id,
      title: data.title,
      artist: data.artist,
    ).to_json
  end

  # Retreives the title and artist for each music file in the user's collection
  #
  # Method: GET
  # Path: /api/v1/users/music
  def get_music(context : HTTP::Server::Context) : Nil
    # Get user
    user_id = Utils::Auth.get_user(context)
    return if user_id.nil?

    # Fetch music data
    music_items = @music_repository.list(user_id)

    # Send music data
    context.response.content_type = "application/json"
    context.response.status = HTTP::Status::OK
    context.response.output << GetMusicResponse.new(
      music: music_items
    ).to_json
  end

  # Retreives a music file from the user's collection
  #
  # Method: GET
  # Path: /api/v1/users/music/{music_id}
  def get_music_file(context : HTTP::Server::Context, music_id : String) : Nil
    # Get user
    user_id = Utils::Auth.get_user(context)
    return if user_id.nil?

    # Fetch music file and write contents to the response body
    @music_repository.get(user_id, music_id, context)
  end

  # Retreives the cover art for a music file from the user's collection
  #
  # Method: GET
  # Path: /api/v1/users/music/{music_id}/cover-art
  def get_music_cover_art(context : HTTP::Server::Context, music_id : String) : Nil
    # Get user
    user_id = Utils::Auth.get_user(context)
    return if user_id.nil?

    # Fetch music cover art and write contents to the response body
    @music_repository.get_cover_art(user_id, music_id, context)
  end

  # Deletes a music file from the user's collection
  #
  # Method: DELETE
  # Path: /api/v1/users/music/{music_id}
  def delete_music_file(context : HTTP::Server::Context, music_id : String) : Nil
    # Get user
    user_id = Utils::Auth.get_user(context)
    return if user_id.nil?

    # Delete music file
    file_removed = @music_repository.delete(user_id, music_id)
    unless file_removed
      context.response.status = HTTP::Status::NOT_FOUND
      context.response.output << ExceptionResponse.new("Music file not found").to_json
      return
    end

    # Send success response
    context.response.status = HTTP::Status::NO_CONTENT
  end
end
