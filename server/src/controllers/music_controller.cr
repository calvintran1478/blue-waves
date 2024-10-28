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
    when {"GET", ""}
      get_music(context)
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
    @music_repository.create(data.title, data.artist, data.file, user_id)

    # Close file IO
    data.file.close

    # Send success response
    context.response.content_type = "application/json"
    context.response.status = HTTP::Status::CREATED
    context.response.output << AddMusicResponse.new(
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
end
