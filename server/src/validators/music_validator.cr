require "http"
require "http/server"
require "http/status"
require "../schemas/music_schemas"

module Validators::MusicValidator
  include Schemas::MusicSchemas

  MAX_MUSIC_FILE_SIZE = 25_000_000 # 25,000,000 bytes, or 25MB
  MAX_COVER_ART_FILE_SIZE = 8_000_000 # 8,000,000 bytes, or 8MB

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

  def validate_add_music_request(context : HTTP::Server::Context) : (AddMusicRequest | Nil)
    # Initialize variables
    title = nil
    artist = nil
    music_file = nil
    art_file = nil
    file_buffer = nil

    content_length = context.request.content_length
    buffer_size = Math.min(content_length.nil? ? UInt64::MAX : content_length, MAX_MUSIC_FILE_SIZE + MAX_COVER_ART_FILE_SIZE + 2)
    bytes_read = 0

    # Parse form data
    begin
      HTTP::FormData.parse(context.request) do |part|
        case part.name
        when "musicFile"
          music_file_name = part.filename.as(String)
          if music_file_name.ends_with?(".mp3") || music_file_name.ends_with?(".ogg")
            # Initialize file buffer if not done already
            if file_buffer.nil?
              file_buffer = LibC.malloc(buffer_size * sizeof(UInt8)).as(UInt8*)
            end

            # Read music file bytes
            byte_limit = Math.min(buffer_size - bytes_read, MAX_MUSIC_FILE_SIZE + 1)
            music_file_buffer = file_buffer + bytes_read
            music_file_size = read_io_to_buffer(part.body, music_file_buffer, byte_limit.to_i64)
            music_file = Bytes.new(music_file_buffer, music_file_size)

            # Increment bytes read
            bytes_read += music_file_size
          else
            raise "Invalid music file"
          end
        when "artFile"
          art_file_name = part.filename.as(String)
          if art_file_name.ends_with?("jpg") || art_file_name.ends_with?("jpeg") || art_file_name.ends_with?("png")
            # Initialize file buffer if not done already
            if file_buffer.nil?
              file_buffer = LibC.malloc(buffer_size * sizeof(UInt8)).as(UInt8*)
            end

            # Read art file bytes
            byte_limit = Math.min(buffer_size - bytes_read, MAX_COVER_ART_FILE_SIZE + 1)
            art_file_buffer = file_buffer + bytes_read
            art_file_size = read_io_to_buffer(part.body, art_file_buffer, byte_limit.to_i64)
            art_file = Bytes.new(art_file_buffer, art_file_size)

            # Increment bytes read
            bytes_read += art_file_size
          else
            raise "Invalid cover art file"
          end
        when "artist"
          artist = part.body.gets_to_end
        when "title"
          title = part.body.gets_to_end
        end
      end
    rescue
      LibC.free(file_buffer) unless file_buffer.nil?
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Malformed request"
      return
    end

    # Check that the file buffer is allocated
    if file_buffer.nil?
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Malformed request"
      return
    end

    # Check that the music file is included and does not exceed size limits
    if music_file.nil?
      LibC.free(file_buffer)
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "No music file found"
      return
    end

    if music_file.size > MAX_MUSIC_FILE_SIZE
      LibC.free(file_buffer)
      context.response.status = HTTP::Status::PAYLOAD_TOO_LARGE
      context.response.output << "Music file size exceeds allowed limits"
      return
    end

    # Check that the cover art file (if included) does not exceed size limits
    if !art_file.nil? && art_file.size > MAX_COVER_ART_FILE_SIZE
      LibC.free(file_buffer)
      context.response.status = HTTP::Status::PAYLOAD_TOO_LARGE
      context.response.output << "Cover art file size exceeds allowed limits"
      return
    end

    # Check that the title and artist fields exist and are not blank
    if title.nil? || title.blank?
      LibC.free(file_buffer)
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Title cannot be blank"
      return
    end

    if artist.nil? || artist.blank?
      LibC.free(file_buffer)
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Artist cannot be blank"
      return
    end

    # Check that the given title name is valid
    title.each_char do |ch|
      if ch == '/' || ch == '.'
        LibC.free(file_buffer)
        context.response.status = HTTP::Status::BAD_REQUEST
        context.response.output << "Invalid title"
        return
      end
    end

    # Return validated data
    return AddMusicRequest.new(title, artist, music_file, art_file, file_buffer)
  end

  def validate_set_cover_art_request(context : HTTP::Server::Context) : (SetCoverArtRequest | Nil)
    # Parse form data
    art_file_buffer = nil
    art_file_size = 0

    begin
      HTTP::FormData.parse(context.request) do |part|
        case part.name
        when "artFile"
          art_file_name = part.filename.as(String)
          if art_file_name.ends_with?("jpg") || art_file_name.ends_with?("jpeg") || art_file_name.ends_with?("png")
            content_length = context.request.content_length
            byte_limit = Math.min(content_length.nil? ? UInt64::MAX : content_length, MAX_COVER_ART_FILE_SIZE + 1)
            art_file_buffer = LibC.malloc(byte_limit * sizeof(UInt8)).as(UInt8*)
            art_file_size = read_io_to_buffer(part.body, art_file_buffer, byte_limit.to_i64)
          else
            raise "Invalid cover art file"
          end
        end
      end
    rescue
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Malformed request"
      return
    end

    # Check that the cover art file exists and does not exceed size limits
    if art_file_buffer.nil?
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "No cover art file found"
      return
    end

    if art_file_size > MAX_COVER_ART_FILE_SIZE
      LibC.free(art_file_buffer)
      context.response.status = HTTP::Status::PAYLOAD_TOO_LARGE
      context.response.output << "Cover art file size exceeds allowed limits"
      return
    end

    # Return validated data
    return SetCoverArtRequest.new(Bytes.new(art_file_buffer, art_file_size))
  end

  def validate_update_music_request(context : HTTP::Server::Context) : (UpdateMusicRequest | Nil)
    # Parse JSON body
    data = UpdateMusicRequest.from_json(context.request.body.as(IO)) rescue nil
    if data.nil?
      context.response.status = HTTP::Status::BAD_REQUEST
      return
    end

    # Check the given title is non-blank
    if data.title.blank?
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Title cannot be blank"
      return
    end

    # Check that the given title name is valid
    data.title.each_char do |ch|
      if ch == '/' || ch == '.'
        context.response.status = HTTP::Status::BAD_REQUEST
        context.response.output << "Invalid title"
        return
      end
    end

    # Return validated data
    return data
  end
end
