require "http/server"
require "http/status"
require "./controller"
require "../schemas/playlist_schemas"
require "../validators/playlist_validator"
require "../repositories/playlist_repository"
require "../repositories/music_repository"
require "../utils/str"

# Controller for handling requests made to the playlist resource
struct Controllers::PlaylistController < Controllers::Controller
  include Validators::PlaylistValidator

  def initialize(@playlist_repository : Repositories::PlaylistRepository, @music_repository : Repositories::MusicRepository, @auth_middleware : Middleware::AuthMiddleware)
  end

  # Handles requests made to the /api/v1/users/playlists route by directing it to the correct handler
  def handle_request(context : HTTP::Server::Context) : Nil
    # Get distinguishing path from resource string
    path = context.request.resource.unsafe_byte_slice(PLAYLIST_ENDPOINT_PREFIX_LENGTH)

    # Call appropriate request handler
    case {context.request.method, path}
    when {"POST", _}
      if path.size == 0
        add_playlist(context)
      elsif path.size == ADD_PLAYLIST_MUSIC_PATH_SIZE && path.unsafe_fetch(0) == '/'.ord && context.request.resource.ends_with?("/music")
        add_playlist_music(context, Bytes.new(path.to_unsafe + 1, PLAYLIST_ID_LENGTH))
      else
        context.response.status = HTTP::Status::NOT_FOUND
      end
    when {"GET", _}
      if path.size == 0
        get_playlists(context)
      elsif path.size == GET_PLAYLIST_PATH_SIZE && path.unsafe_fetch(0) == '/'.ord
        get_playlist(context, Bytes.new(path.to_unsafe + 1, PLAYLIST_ID_LENGTH))
      else
        context.response.status = HTTP::Status::NOT_FOUND
      end
    when {"PATCH", _}
      if path.size == UPDATE_PLAYLIST_PATH_SIZE && path.unsafe_fetch(0) == '/'.ord
        update_playlist(context, Bytes.new(path.to_unsafe + 1, PLAYLIST_ID_LENGTH))
      elsif path.size == UPDATE_PLAYLIST_MUSIC_PATH_SIZE && path.unsafe_fetch(0) == '/'.ord && (path.to_unsafe + UPDATE_PLAYLIST_MUSIC_OFFSET).memcmp("/music/".to_unsafe, "/music/".bytesize) == 0
        update_playlist_music(context, Bytes.new(path.to_unsafe + 1, PLAYLIST_ID_LENGTH), Bytes.new(path.to_unsafe + UPDATE_PLAYLIST_MUSIC_MUSIC_ID_OFFSET, MUSIC_ID_LENGTH))
      else
        context.response.status = HTTP::Status::NOT_FOUND
      end
    when {"DELETE", _}
      if path.size == DELETE_PLAYLIST_PATH_SIZE && path.unsafe_fetch(0) == '/'.ord
        delete_playlist(context, Bytes.new(path.to_unsafe + 1, PLAYLIST_ID_LENGTH))
      elsif path.size == DELETE_PLAYLIST_MUSIC_PATH_SIZE && path.unsafe_fetch(0) == '/'.ord && (path.to_unsafe + DELETE_PLAYLIST_MUSIC_OFFSET).memcmp("/music/".to_unsafe, "/music/".bytesize) == 0
        delete_playlist_music(context, Bytes.new(path.to_unsafe + 1, PLAYLIST_ID_LENGTH), Bytes.new(path.to_unsafe + DELETE_PLAYLIST_MUSIC_MUSIC_ID_OFFSET, MUSIC_ID_LENGTH))
      else
        context.response.status = HTTP::Status::NOT_FOUND
      end
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
    user_id = @auth_middleware.get_user(context)
    return if user_id.nil?

    # Validate user input
    add_playlist_request_buffer = uninitialized UInt8[ADD_PLAYLIST_REQUEST_BUFFER_SIZE]
    data = validate_add_playlist_request(context, add_playlist_request_buffer.to_unsafe)
    return if data.nil?

    # Add playlist to the user's collection
    playlist_id = @playlist_repository.create(user_id, data.playlist_name)
    if playlist_id.nil?
      context.response.status = HTTP::Status::CONFLICT
      context.response.output << "Playlist with the given name already exists"
      return
    end

    # Send success responses
    context.response.content_type = "text/plain"
    context.response.status = HTTP::Status::CREATED
    context.response.output << playlist_id
  end

  # Adds a music track to one of the user's playlists
  #
  # Method: POST
  # Path: /api/v1/users/playlists/{playlist_id}/music
  def add_playlist_music(context : HTTP::Server::Context, playlist_id : Bytes) : Nil
    # Get user
    user_id = @auth_middleware.get_user(context)
    return if user_id.nil?

    # Validate user input
    add_playlist_music_request_buffer = uninitialized UInt8[ADD_PLAYLIST_MUSIC_REQUEST_BUFFER_SIZE]
    data = validate_add_playlist_music_request(context, add_playlist_music_request_buffer.to_unsafe)
    return if data.nil?

    # Add music track to the end of the playlist
    unless @playlist_repository.add_music(user_id, playlist_id, data.music_id)
      # Check if music exists
      if !@music_repository.exists_by_id(user_id, data.music_id)
        context.response.status = HTTP::Status::NOT_FOUND
        context.response.output << "Music file not found"

      # Check if music already exists in playlist
      elsif !@playlist_repository.exists_by_id(user_id, playlist_id)
        context.response.status = HTTP::Status::NOT_FOUND
        context.response.output << "Playlist not found"
      else
        context.response.status = HTTP::Status::CONFLICT
        context.response.output << "Music file already exists in playlist"
      end

      return
    end

    # Send success response
    context.response.content_type = "text/plain"
    context.response.status = HTTP::Status::CREATED
  end

  # Retreives the playlist id and name for each playlist in the user's collection
  #
  # Method: GET
  # Path: /api/v1/users/playlists
  def get_playlists(context : HTTP::Server::Context) : Nil
    # Get user
    user_id = @auth_middleware.get_user(context)
    return if user_id.nil?

    # Send music data
    context.response.content_type = "application/octet-stream"
    context.response.status = HTTP::Status::OK
    @playlist_repository.list(user_id, context.response.output)
  end

  # Retreives the name of a playlist in the user's collection, along with the
  # music ids, title, and artist for each music track in the playlist
  #
  # Method: GET
  # Path: /api/v1/users/playlists/{playlist_id}
  def get_playlist(context : HTTP::Server::Context, playlist_id : Bytes) : Nil
    # Get user
    user_id = @auth_middleware.get_user(context)
    return if user_id.nil?

    # Retreive playlist based on playlist id
    unless @playlist_repository.get(user_id, playlist_id, context)
      context.response.status = HTTP::Status::NOT_FOUND
      context.response.output << "Playlist not found"
      return
    end
  end

  # Updates the name of a playlist in the user's collection
  #
  # Method: PATCH
  # Path: /api/v1/users/playlists/{playlist_id}
  def update_playlist(context : HTTP::Server::Context, playlist_id : Bytes) : Nil
    # Get user
    user_id = @auth_middleware.get_user(context)
    return if user_id.nil?

    # Validate user input
    update_playlist_request_buffer = uninitialized UInt8[UPDATE_PLAYLIST_REQUEST_BUFFER_SIZE]
    data = validate_update_playlist_request(context, update_playlist_request_buffer.to_unsafe)
    return if data.nil?

    # Update playlist
    if @playlist_repository.exists_by_name_excluding_id(user_id, data.playlist_name, playlist_id)
      context.response.status = HTTP::Status::CONFLICT
      context.response.output << "Playlist with the given name already exists"
      return
    end

    unless @playlist_repository.update(user_id, playlist_id, data.playlist_name)
      context.response.status = HTTP::Status::NOT_FOUND
      context.response.output << "Playlist not found"
      return
    end

    # Send success responses
    context.response.status = HTTP::Status::NO_CONTENT
  end

  # Updates the position of a music track in a user's playlist
  #
  # Method : PATCH
  # Path: /api/v1/users/playlists/{playlist_id}/music/{music_id}
  def update_playlist_music(context : HTTP::Server::Context, playlist_id : Bytes, music_id : Bytes) : Nil
    # Get user
    user_id = @auth_middleware.get_user(context)
    return if user_id.nil?

    # Validate user input
    data = validate_update_playlist_music_request(context)
    return if data.nil?

    # Update music track
    @playlist_repository.update_music(user_id, playlist_id, music_id, data.music_number, context)
  end

  # Deletes a playlist from the user's collection
  #
  # Method: DELETE
  # Path: /api/v1/users/playlist/{playlist_id}
  def delete_playlist(context : HTTP::Server::Context, playlist_id : Bytes) : Nil
    # Get user
    user_id = @auth_middleware.get_user(context)
    return if user_id.nil?

    # Delete playlist
    unless @playlist_repository.delete(user_id, playlist_id)
      context.response.status = HTTP::Status::NOT_FOUND
      context.response.output << "Playlist not found"
      return
    end

    # Send success response
    context.response.status = HTTP::Status::NO_CONTENT
  end

  # Deletes a music track from one of the user's playlists
  #
  # Method: DELETE
  # Path: /api/v1/users/playlist/{playlist_id}/music/{music_id}
  def delete_playlist_music(context : HTTP::Server::Context, playlist_id : Bytes, music_id : Bytes) : Nil
    # Get user
    user_id = @auth_middleware.get_user(context)
    return if user_id.nil?

    # Remove music track
    unless @playlist_repository.remove_music(user_id, playlist_id, music_id)
      context.response.status = HTTP::Status::NOT_FOUND
      context.response.output << "Music not found"
      return
    end

    # Send success response
    context.response.status = HTTP::Status::NO_CONTENT
  end
end
