
module Validators::PlaylistValidator
  include Schemas::PlaylistSchemas

  MAX_PLAYLIST_NAME_LENGTH = 80

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
end
