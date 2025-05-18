require "http"
require "http/server"
require "http/status"
require "../schemas/music_schemas"

module Validators::MusicValidator
  include Schemas::MusicSchemas

  MAX_MUSIC_FILE_SIZE = 25_000_000 # 25,000,000 bytes, or 25MB
  MAX_COVER_ART_FILE_SIZE = 8_000_000 # 8,000,000 bytes, or 8MB

  MAX_TITLE_LENGTH = 150
  MAX_ARTIST_LENGTH = 100

  MAX_TITLE_STRING_LENGTH = 163 # MAX_TITLE_LENGTH + 1 + String::HEADER_SIZE
  MAX_ARTIST_STRING_LENGTH = 113 # MAX_ARTIST_LENGTH + 1 + String::HEADER_SIZE

  PNG_HEADER = UInt8.static_array(137, 80, 78, 71, 13, 10, 26, 10)
  PNG_IMAGE_END = UInt8.static_array(73, 69, 78, 68, 174, 66, 96, 130)

  JPEG_HEADER = UInt8.static_array(255, 216)
  JPEG_IMAGE_END = UInt8.static_array(255, 217)

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

  @[AlwaysInline]
  private def valid_png(art_file : Bytes) : Bool
    art_file.size > 16 && art_file[...8] == PNG_HEADER.to_slice && art_file[(art_file.size - 8)...] == PNG_IMAGE_END.to_slice
  end

  @[AlwaysInline]
  private def valid_jpeg(art_file : Bytes) : Bool
    art_file.size > 4 && art_file[...2] == JPEG_HEADER.to_slice && art_file[(art_file.size - 2)...] == JPEG_IMAGE_END.to_slice
  end

  def validate_add_music_request(context : HTTP::Server::Context, add_music_request_buffer : UInt8*) : (AddMusicRequest | Nil)
    # Initialize variables
    title = nil
    artist = nil
    music_file = nil
    art_file = nil
    music_file_type = nil
    art_file_type = nil
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

            # Record content type of music file
            music_file_type = part.headers["Content-Type"]
          else
            raise "Invalid music file"
          end
        when "artFile"
          # Check for correct file type
          art_file_type = part.headers["Content-Type"]?
          if art_file_type != "image/png" && art_file_type != "image/jpeg"
            LibC.free(file_buffer) unless file_buffer.nil?
            context.response.status = HTTP::Status::BAD_REQUEST
            context.response.output << "Cover art file must be a PNG or JPEG"
            return
          end

          # Initialize file buffer if not done already
          if file_buffer.nil?
            file_buffer = LibC.malloc(buffer_size * sizeof(UInt8)).as(UInt8*)
          end

          # Read art file bytes
          byte_limit = Math.min(buffer_size - bytes_read, MAX_COVER_ART_FILE_SIZE + 1)
          art_file_buffer = file_buffer + bytes_read
          art_file_size = read_io_to_buffer(part.body, art_file_buffer, byte_limit.to_i64)
          art_file = Bytes.new(art_file_buffer, art_file_size)

          # Check for valid image file
          if art_file_type == "image/png" && !valid_png(art_file)
            LibC.free(file_buffer) unless file_buffer.nil?
            context.response.status = HTTP::Status::BAD_REQUEST
            context.response.output << "Invalid PNG"
            return
          elsif art_file_type == "image/jpeg" && !valid_jpeg(art_file)
            LibC.free(file_buffer) unless file_buffer.nil?
            context.response.status = HTTP::Status::BAD_REQUEST
            context.response.output << "Invalid JPEG"
            return
          end

          # Increment bytes read
          bytes_read += art_file_size
        when "artist"
          # Read artist bytes
          artist_buffer = (add_music_request_buffer + MAX_TITLE_STRING_LENGTH).as(String).to_unsafe
          artist_bytesize = read_io_to_buffer(part.body, artist_buffer, MAX_ARTIST_LENGTH + 1).to_i32
          if artist_bytesize > MAX_ARTIST_LENGTH
            LibC.free(file_buffer) unless file_buffer.nil?
            context.response.status = HTTP::Status::BAD_REQUEST
            context.response.output << "Artist cannot exceed 100 characters"
            return
          end
          artist_buffer[artist_bytesize] = 0_u8

          # Initialize artist string header
          artist = (add_music_request_buffer + MAX_TITLE_STRING_LENGTH).as(String)
          artist.initialize_header(artist_bytesize, artist_bytesize)
        when "title"
          # Read title bytes
          title_buffer = add_music_request_buffer.as(String).to_unsafe
          title_bytesize = read_io_to_buffer(part.body, title_buffer, MAX_TITLE_LENGTH + 1).to_i32
          if title_bytesize > MAX_TITLE_LENGTH
            LibC.free(file_buffer) unless file_buffer.nil?
            context.response.status = HTTP::Status::BAD_REQUEST
            context.response.output << "Title cannot exceed 150 characters"
            return
          end
          title_buffer[title_bytesize] = 0_u8

          # Initialize title string header
          title = add_music_request_buffer.as(String)
          title.initialize_header(title_bytesize, title_bytesize)
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
    if music_file.nil? || music_file_type.nil?
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

    # Return validated data
    return AddMusicRequest.new(title, artist, music_file, art_file, music_file_type, art_file_type, file_buffer)
  end

  def validate_set_cover_art_request(context : HTTP::Server::Context) : (SetCoverArtRequest | Nil)
    # Check for correct file type
    content_type = context.request.headers["Content-Type"]?
    if content_type != "image/jpeg" && content_type != "image/png"
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "File must be a JPEG or PNG"
      return
    end

    # Read request body
    if context.request.body.nil?
      context.response.status = HTTP::Status::BAD_REQUEST
      return
    end

    content_length = context.request.content_length
    byte_limit = Math.min(content_length.nil? ? UInt64::MAX : content_length, MAX_COVER_ART_FILE_SIZE + 1)
    art_file_buffer = LibC.malloc(byte_limit * sizeof(UInt8)).as(UInt8*)
    art_file_size = read_io_to_buffer(context.request.body.as(IO), art_file_buffer, byte_limit.to_i64)
    art_file = Bytes.new(art_file_buffer, art_file_size)

    # Check that the cover art file is non-empty and satisfies size limits
    if art_file_size == 0
      LibC.free(art_file_buffer)
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Cover art file cannot be empty"
      return
    end

    if art_file_size > MAX_COVER_ART_FILE_SIZE
      LibC.free(art_file_buffer)
      context.response.status = HTTP::Status::PAYLOAD_TOO_LARGE
      context.response.output << "Cover art file size exceeds allowed limits"
      return
    end

    # Check that the image file is valid
    if content_type == "image/png" && !valid_png(art_file)
      LibC.free(art_file_buffer)
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Invalid PNG"
    elsif content_type == "image/jpeg" && !valid_jpeg(art_file)
      LibC.free(art_file_buffer)
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Invalid JPEG"
    end

    # Return validated data
    return SetCoverArtRequest.new(art_file, content_type.as(String))
  end

  def validate_update_music_request(context : HTTP::Server::Context) : (UpdateMusicRequest | Nil)
    # Parse JSON body
    data = UpdateMusicRequest.from_json(context.request.body.as(IO)) rescue nil
    if data.nil?
      context.response.status = HTTP::Status::BAD_REQUEST
      return
    end

    # Check the given title is non-blank and is within size limits
    if data.title.blank?
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Title cannot be blank"
      return
    end

    if data.title.size > MAX_TITLE_LENGTH
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Title cannot exceed 150 characters"
      return
    end

    # Check the given artist is non-blank and is within size limits
    if data.artist.blank?
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Artist cannot be blank"
      return
    end

    if data.artist.size > MAX_ARTIST_LENGTH
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Artist cannot exceed 100 characters"
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
