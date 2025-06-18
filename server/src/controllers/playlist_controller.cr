require "http/server"
require "http/status"
require "./controller"
require "../schemas/playlist_schemas"
require "../validators/playlist_validator"
require "../repositories/playlist_repository"

# Controller for handling requests made to the playlist resource
struct Controllers::PlaylistController < Controllers::Controller
  include Validators::PlaylistValidator

  USER_ID_STRING_LENGTH = 49 # UUID_LENGTH + 1 + String::HEADER_SIZE
  ADD_PLAYLIST_REQUEST_BUFFER_SIZE = 93 # MAX_PLAYLIST_NAME_LENGTH + 1 + String::HEADER_SIZE

  def initialize(@playlist_repository : Repositories::PlaylistRepository, @auth_middleware : Middleware::AuthMiddleware)
    @prefix_length = "/api/v1/users/playlists".size
  end

  # Handles requests made to the /api/v1/users/playlists route by directing it to the correct handler
  def handle_request(context : HTTP::Server::Context) : Nil
    # Get distinguishing path from resource string
    path = context.request.resource.unsafe_byte_slice(@prefix_length)

    # Call appropriate request handler
    case {context.request.method, path}
    when {"POST", "".to_slice}
      add_playlist(context)
    else
      context.response.status = HTTP::Status::NOT_FOUND
    end
  end

  # Adds a playlist for the user
  #
  # Method: POST
  # Path: /api/v1/users/playlists
  def add_playlist(context : HTTP::Server::Context) : Nil
    # Get user
    user_id_buffer = uninitialized UInt8[USER_ID_STRING_LENGTH]
    user_id = @auth_middleware.get_user(context, user_id_buffer.to_unsafe)
    return if user_id.nil?

    # Validate user input
    add_playlist_request_buffer = uninitialized UInt8[ADD_PLAYLIST_REQUEST_BUFFER_SIZE]
    data = validate_add_playlist_request(context, add_playlist_request_buffer.to_unsafe)
    return if data.nil?

    # Check if playlist with the given name already exists
    if @playlist_repository.exists_by_name(user_id, data.playlist_name)
      context.response.status = HTTP::Status::CONFLICT
      context.response.output << "Playlist with the given name already exists"
      return
    end

    # Add playlist to the user's collection
    playlist_id = @playlist_repository.create(user_id, data.playlist_name)

    # Send success responses
    context.response.content_type = "text/plain"
    context.response.status = HTTP::Status::CREATED
    context.response.output << playlist_id << '\n' << data.playlist_name
  end
end
