
module Validators::PlaylistValidator
  include Schemas::PlaylistSchemas

  MAX_PLAYLIST_NAME_LENGTH = 80
  MUSIC_ID_LENGTH = 22

  private def read_io_to_buffer(io : IO, buffer : UInt8*, limit : Int64) : Int64
    curr_buffer = Bytes.new(buffer, limit)
    remaining = limit
    bytes_read = io.read(curr_buffer[0, Math.min(curr_buffer.size, Math.max(remaining, 0))])

    while bytes_read > 0
      remaining -= bytes_read
      curr_buffer += bytes_read
      bytes_read = io.read(curr_buffer[0, Math.min(curr_buffer.size, Math.max(remaining, 0))])
    end

    limit - remaining
  end

  def validate_add_playlist_request(context : HTTP::Server::Context, add_playlist_request_buffer : UInt8*) : (AddPlaylistRequest | Nil)
    # Get request body
    if context.request.body.nil?
      context.response.status = HTTP::Status::BAD_REQUEST
      return
    end
    request_body = context.request.body.as(IO)

    # Read playlist name bytes
    playlist_name_buffer = add_playlist_request_buffer.as(String).to_unsafe
    playlist_name_bytesize = read_io_to_buffer(request_body, playlist_name_buffer, MAX_PLAYLIST_NAME_LENGTH + 1).to_i32
    if playlist_name_bytesize > MAX_PLAYLIST_NAME_LENGTH
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Playlist name cannot exceed 80 characters"
      return
    end

    # Initialize playlist name
    playlist_name_buffer[playlist_name_bytesize] = 0_u8
    playlist_name = add_playlist_request_buffer.as(String)
    playlist_name.initialize_header(playlist_name_bytesize, playlist_name_bytesize)

    # Check playlist name is not blank
    if playlist_name.blank?
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

    # Read music id bytes
    music_id_buffer = add_playlist_music_request_buffer.as(String).to_unsafe
    music_id_bytesize = read_io_to_buffer(request_body, music_id_buffer, MUSIC_ID_LENGTH + 1).to_i32
    if music_id_bytesize != MUSIC_ID_LENGTH
      context.response.status = HTTP::Status::NOT_FOUND
      context.response.output << "Music not found"
      return
    end

    # Initialize music id string
    music_id_buffer[music_id_bytesize] = 0_u8
    music_id = add_playlist_music_request_buffer.as(String)
    music_id.initialize_header(music_id_bytesize, music_id_bytesize)

    AddPlaylistMusicRequest.new(music_id)
  end

  def validate_update_playlist_request(context : HTTP::Server::Context, update_playlist_request_buffer : UInt8*) : (UpdatePlaylistRequest | Nil)
    # Get request body
    if context.request.body.nil?
      context.response.status = HTTP::Status::BAD_REQUEST
      return
    end
    request_body = context.request.body.as(IO)

    # Read playlist name bytes
    playlist_name_buffer = update_playlist_request_buffer.as(String).to_unsafe
    playlist_name_bytesize = read_io_to_buffer(request_body, playlist_name_buffer, MAX_PLAYLIST_NAME_LENGTH + 1).to_i32
    if playlist_name_bytesize > MAX_PLAYLIST_NAME_LENGTH
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Playlist name cannot exceed 80 characters"
      return
    end

    # Initialize playlist name
    playlist_name_buffer[playlist_name_bytesize] = 0_u8
    playlist_name = update_playlist_request_buffer.as(String)
    playlist_name.initialize_header(playlist_name_bytesize, playlist_name_bytesize)

    # Check playlist name is not blank
    if playlist_name.blank?
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
    if music_number.nil? || music_number <= 0
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Music number must be a positive integer"
      return
    end

    UpdatePlaylistMusicRequest.new(music_number)
  end
end
