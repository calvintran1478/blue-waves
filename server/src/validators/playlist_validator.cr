require "../utils/constants"
require "../utils/buffer"

module Validators::PlaylistValidator
  include Schemas::PlaylistSchemas
  include Utils::Constants

  def validate_add_playlist_request(context : HTTP::Server::Context, add_playlist_request_buffer : UInt8*) : (AddPlaylistRequest | Nil)
    # Get request body
    if context.request.body.nil?
      context.response.status = HTTP::Status::BAD_REQUEST
      return
    end
    request_body = context.request.body.as(IO)

    # Read playlist name bytes
    playlist_name_bytesize = Utils::Buffer.read_io_to_buffer(request_body, add_playlist_request_buffer, MAX_PLAYLIST_NAME_LENGTH + 1).to_i32
    if playlist_name_bytesize > MAX_PLAYLIST_NAME_LENGTH
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Playlist name cannot exceed 80 characters"
      return
    end
    playlist_name = Bytes.new(add_playlist_request_buffer, playlist_name_bytesize)

    # Check playlist name is not blank
    if Utils::Buffer.blank?(playlist_name)
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Playlist name cannot be blank"
      return
    end

    AddPlaylistRequest.new(playlist_name)
  end

  def validate_add_playlist_music_request(context : HTTP::Server::Context, add_playlist_music_request_buffer : UInt8*) : (AddPlaylistMusicRequest | Nil)
    # Get request body
    if context.request.body.nil?
      context.response.status = HTTP::Status::BAD_REQUEST
      return
    end
    request_body = context.request.body.as(IO)
    peek = request_body.peek

    # Optimization: Check if we have a peek buffer
    if !peek.nil? && peek.size == MUSIC_ID_LENGTH
      return AddPlaylistMusicRequest.new(peek)
    end

    # Read music id bytes
    music_id_bytesize = Utils::Buffer.read_io_to_buffer(request_body, add_playlist_music_request_buffer, MUSIC_ID_LENGTH + 1).to_i32
    if music_id_bytesize != MUSIC_ID_LENGTH
      context.response.status = HTTP::Status::NOT_FOUND
      context.response.output << "Music not found"
      return
    end

    AddPlaylistMusicRequest.new(Bytes.new(add_playlist_music_request_buffer, MUSIC_ID_LENGTH))
  end

  def validate_update_playlist_request(context : HTTP::Server::Context, update_playlist_request_buffer : UInt8*) : (UpdatePlaylistRequest | Nil)
    # Get request body
    if context.request.body.nil?
      context.response.status = HTTP::Status::BAD_REQUEST
      return
    end
    request_body = context.request.body.as(IO)

    # Read playlist name bytes
    playlist_name_bytesize = Utils::Buffer.read_io_to_buffer(request_body, update_playlist_request_buffer, MAX_PLAYLIST_NAME_LENGTH + 1).to_i32
    if playlist_name_bytesize > MAX_PLAYLIST_NAME_LENGTH
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Playlist name cannot exceed 80 characters"
      return
    end
    playlist_name = Bytes.new(update_playlist_request_buffer, playlist_name_bytesize)

    # Check playlist name is not blank
    if Utils::Buffer.blank?(playlist_name)
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Playlist name cannot be blank"
      return
    end

    UpdatePlaylistRequest.new(playlist_name)
  end

  def validate_update_playlist_music_request(context : HTTP::Server::Context) : (UpdatePlaylistMusicRequest | Nil)
    # Get request body
    if context.request.body.nil?
      context.response.status = HTTP::Status::BAD_REQUEST
      return
    end
    request_body = context.request.body.as(IO)

    # Decode request body as an integer
    music_number = IO::ByteFormat::NetworkEndian.decode(Int32, request_body) rescue nil

    # Check if the provided music number is valid
    if music_number.nil? || music_number < -1
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Music number must be greater than or equal to -1"
      return
    end

    UpdatePlaylistMusicRequest.new(music_number)
  end
end
