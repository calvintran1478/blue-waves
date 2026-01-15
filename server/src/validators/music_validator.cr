require "http"
require "http/server"
require "http/status"
require "../schemas/music_schemas"
require "../utils/constants"
require "../utils/buffer"

module Validators::MusicValidator
  include Schemas::MusicSchemas
  include Utils::Constants

  @[AlwaysInline]
  private def valid_png(art_file : Bytes) : Bool
    art_file.size > 16 && art_file[...8] == PNG_HEADER.to_slice && art_file[(art_file.size - 8)...] == PNG_IMAGE_END.to_slice
  end

  @[AlwaysInline]
  private def valid_jpeg(art_file : Bytes) : Bool
    art_file.size > 4 && art_file[...2] == JPEG_HEADER.to_slice && art_file[(art_file.size - 2)...] == JPEG_IMAGE_END.to_slice
  end

  @[AlwaysInline]
  private def valid_ogg(music_file : Bytes) : Bool
    music_file.size > 4 && music_file[...4] == OGG_HEADER.to_slice
  end

  @[AlwaysInline]
  private def valid_mp3(music_file : Bytes) : Bool
    music_file.size > 4 && music_file[...4] == MP3_HEADER.to_slice
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
    if content_length == 0
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Content length must be positive"
      return
    end

    buffer_size = Math.min(content_length.nil? ? UInt64::MAX : content_length, MAX_MUSIC_FILE_SIZE + MAX_COVER_ART_FILE_SIZE + 2)
    bytes_read = 0

    # Parse form data
    begin
      HTTP::FormData.parse(context.request) do |part|
        case part.name
        when "musicFile"
          # Check for correct file type
          music_file_type = part.headers["Content-Type"]
          if music_file_type != "video/ogg" && music_file_type != "audio/mpeg"
            LibC.free(file_buffer) unless file_buffer.nil?
            context.response.status = HTTP::Status::BAD_REQUEST
            context.response.output << "Music file must be an MP3 or OGG"
            return
          end

          # Initialize file buffer if not done already
          file_buffer = LibC.malloc(buffer_size * sizeof(UInt8)).as(UInt8*) if file_buffer.nil?
          if file_buffer.null?
            context.response.status = HTTP::Status::INTERNAL_SERVER_ERROR
            return
          end

          # Read music file bytes
          byte_limit = Math.min(buffer_size - bytes_read, MAX_MUSIC_FILE_SIZE + 1)
          music_file_buffer = file_buffer + bytes_read
          music_file_size = Utils::Buffer.read_io_to_buffer(part.body, music_file_buffer, byte_limit.to_i64)
          music_file = Bytes.new(music_file_buffer, music_file_size)

          # Check for valid music file
          if music_file_type == "video/ogg" && !valid_ogg(music_file)
            LibC.free(file_buffer) unless file_buffer.nil?
            context.response.status = HTTP::Status::BAD_REQUEST
            context.response.output << "Invalid OGG"
            return
          elsif music_file_type == "audio/mp3" && !valid_mp3(music_file)
            LibC.free(file_buffer) unless file_buffer.nil?
            context.response.status = HTTP::Status::BAD_REQUEST
            context.response.output << "Invalid MP3"
            return
          end

          # Increment bytes read
          bytes_read += music_file_size
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
          file_buffer = LibC.malloc(buffer_size * sizeof(UInt8)).as(UInt8*) if file_buffer.nil?
          if file_buffer.null?
            context.response.status = HTTP::Status::INTERNAL_SERVER_ERROR
            return
          end

          # Read art file bytes
          byte_limit = Math.min(buffer_size - bytes_read, MAX_COVER_ART_FILE_SIZE + 1)
          art_file_buffer = file_buffer + bytes_read
          art_file_size = Utils::Buffer.read_io_to_buffer(part.body, art_file_buffer, byte_limit.to_i64)
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
          artist_buffer = add_music_request_buffer + MAX_TITLE_LENGTH
          artist_bytesize = Utils::Buffer.read_io_to_buffer(part.body, artist_buffer, MAX_ARTIST_LENGTH + 1).to_i32
          if artist_bytesize > MAX_ARTIST_LENGTH
            LibC.free(file_buffer) unless file_buffer.nil?
            context.response.status = HTTP::Status::BAD_REQUEST
            context.response.output << "Artist cannot exceed 100 characters"
            return
          end
          artist = Bytes.new(artist_buffer, artist_bytesize)
        when "title"
          # Read title bytes
          title_buffer = add_music_request_buffer
          title_bytesize = Utils::Buffer.read_io_to_buffer(part.body, title_buffer, MAX_TITLE_LENGTH + 1).to_i32
          if title_bytesize > MAX_TITLE_LENGTH
            LibC.free(file_buffer) unless file_buffer.nil?
            context.response.status = HTTP::Status::BAD_REQUEST
            context.response.output << "Title cannot exceed 150 characters"
            return
          end
          title = Bytes.new(title_buffer, title_bytesize)
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
    if title.nil? || Utils::Buffer.blank?(title)
      LibC.free(file_buffer)
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Title cannot be blank"
      return
    end

    if artist.nil? || Utils::Buffer.blank?(artist)
      LibC.free(file_buffer)
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Artist cannot be blank"
      return
    end

    # Return validated data
    return AddMusicRequest.new(title, artist, music_file, art_file, music_file_type, art_file_type, file_buffer)
  end

  def validate_set_cover_art_request(context : HTTP::Server::Context) : (SetCoverArtRequest | Nil)
    # Get request body
    if context.request.body.nil?
      context.response.status = HTTP::Status::BAD_REQUEST
      return
    end
    request_body = context.request.body.as(IO)

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
    if content_length == 0
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Content length must be positive"
      return
    end

    byte_limit = Math.min(content_length.nil? ? UInt64::MAX : content_length, MAX_COVER_ART_FILE_SIZE + 1)
    art_file_buffer = LibC.malloc(byte_limit * sizeof(UInt8)).as(UInt8*)
    if art_file_buffer.null?
      context.response.status = HTTP::Status::INTERNAL_SERVER_ERROR
      return
    end

    art_file_size = Utils::Buffer.read_io_to_buffer(request_body, art_file_buffer, byte_limit.to_i64)
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

  def validate_update_music_request(context : HTTP::Server::Context, update_music_buffer : UInt8*) : (UpdateMusicRequest | Nil)
    # Get request body
    if context.request.body.nil?
      context.response.status = HTTP::Status::BAD_REQUEST
      return
    end
    request_body = context.request.body.as(IO)

    # Search for delimiting newline character
    bytes_read = Utils::Buffer.read_io_to_buffer(request_body, update_music_buffer, UPDATE_MUSIC_REQUEST_BUFFER_SIZE)
    newline_ptr = LibC.memchr(update_music_buffer, '\n'.ord, Math.min(MAX_TITLE_LENGTH + 2, bytes_read)).as(UInt8*)
    if newline_ptr.null?
      context.response.status = HTTP::Status::BAD_REQUEST
      return
    end

    # Parse title
    title = Bytes.new(update_music_buffer, newline_ptr - update_music_buffer)
    if title.size != 0 && Utils::Buffer.blank?(title)
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Title cannot be blank"
      return
    elsif title.size > MAX_TITLE_LENGTH
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Title cannot exceed 150 characters"
      return
    end

    # Parse artist
    artist = Bytes.new(newline_ptr + 1, bytes_read - title.bytesize - 1)
    if artist.size != 0 && Utils::Buffer.blank?(artist)
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Artist cannot be blank"
      return
    elsif artist.size > MAX_ARTIST_LENGTH
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Artist cannot exceed 100 characters"
      return
    end

    # Check at least one of these fields is updated
    if title.size == 0 && artist.size == 0
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Both title and artist cannot be empty"
      return
    end

    # Return validated data
    UpdateMusicRequest.new(title, artist)
  end
end
