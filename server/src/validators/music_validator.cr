require "http"
require "http/server"
require "http/status"
require "../schemas/music_schemas"

module Validators::MusicValidator
  include Schemas::MusicSchemas

  MAX_MUSIC_FILE_SIZE = 25_000_000 # 25,000,000 bytes, or 25MB
  MAX_COVER_ART_FILE_SIZE = 8_000_000 # 8,000,000 bytes, or 8MB

  def validate_add_music_request(context : HTTP::Server::Context) : (AddMusicRequest | Nil)
    # Parse form data
    music_file = nil
    art_file = nil
    title = nil
    artist = nil
    music_file_size = 0
    art_file_size = 0

    begin
      HTTP::FormData.parse(context.request) do |part|
        case part.name
        when "musicFile"
          music_file_name = part.filename.as(String)
          if music_file_name.ends_with?(".mp3") || music_file_name.ends_with?(".ogg")
            music_file = File.tempfile("music_file") do |music_file|
              music_file_size = IO.copy(part.body, music_file, MAX_MUSIC_FILE_SIZE + 1)
            end
          else
            raise "Invalid music file"
          end
        when "artFile"
          art_file_name = part.filename.as(String)
          if art_file_name.ends_with?("jpg") || art_file_name.ends_with?("jpeg") || art_file_name.ends_with?("png")
            art_file = File.tempfile("art_file") do |art_file|
              art_file_size = IO.copy(part.body, art_file, MAX_COVER_ART_FILE_SIZE + 1)
            end
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
      music_file.delete if music_file.is_a?(File)
      art_file.delete if art_file.is_a?(File)
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Malformed request"
      return
    end

    # Check that the music file is included and does not exceed size limits
    if music_file.nil?
      art_file.delete if art_file.is_a?(File)
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "No music file found"
      return
    end

    if music_file_size > MAX_MUSIC_FILE_SIZE
      music_file.delete
      art_file.delete if art_file.is_a?(File)
      context.response.status = HTTP::Status::PAYLOAD_TOO_LARGE
      context.response.output << "Music file size exceeds allowed limits"
      return
    end

    # Check that the cover art file (if included) does not exceed size limits
    if !art_file.nil? && art_file_size > MAX_COVER_ART_FILE_SIZE
      music_file.delete
      art_file.delete
      context.response.status = HTTP::Status::PAYLOAD_TOO_LARGE
      context.response.output << "Cover art file size exceeds allowed limits"
      return
    end

    # Check that the title and artist fields exist and are not blank
    if title.nil? || title.blank?
      music_file.delete
      art_file.delete if art_file.is_a?(File)
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Title cannot be blank"
      return
    end

    if artist.nil? || artist.blank?
      music_file.delete
      art_file.delete if art_file.is_a?(File)
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Artist cannot be blank"
      return
    end

    # Check that the given title name is valid
    title.each_char do |ch|
      if ch == '/' || ch == '.'
        music_file.delete
        art_file.delete if art_file.is_a?(File)
        context.response.status = HTTP::Status::BAD_REQUEST
        context.response.output << "Invalid title"
        return
      end
    end

    # Return validated data
    return AddMusicRequest.new(title, artist, music_file, art_file)
  end

  def validate_set_cover_art_request(context : HTTP::Server::Context) : (SetCoverArtRequest | Nil)
    # Parse form data
    art_file = nil
    art_file_size = 0

    begin
      HTTP::FormData.parse(context.request) do |part|
        case part.name
        when "artFile"
          art_file_name = part.filename.as(String)
          if art_file_name.ends_with?("jpg") || art_file_name.ends_with?("jpeg") || art_file_name.ends_with?("png")
            art_file = File.tempfile("art_file") do |art_file|
              art_file_size = IO.copy(part.body, art_file, MAX_COVER_ART_FILE_SIZE + 1)
            end
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
    if art_file.nil?
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "No cover art file found"
      return
    end

    if art_file_size > MAX_COVER_ART_FILE_SIZE
      art_file.delete
      context.response.status = HTTP::Status::PAYLOAD_TOO_LARGE
      context.response.output << "Cover art file size exceeds allowed limits"
      return
    end

    # Return validated data
    return SetCoverArtRequest.new(art_file)
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
