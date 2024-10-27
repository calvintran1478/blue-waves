require "http"
require "http/server"
require "http/status"
require "../schemas/music_schemas"
require "../exceptions/exception_response"

module Validators::MusicValidator
  include Schemas::MusicSchemas
  include Exceptions

  def validate_add_music_request(context : HTTP::Server::Context) : (AddMusicRequest | Nil)
    # Parse form data
    file = nil
    title = nil
    artist = nil

    begin
      HTTP::FormData.parse(context.request) do |part|
        case part.name
        when "file"
          file = File.tempfile("music_file")
          File.write(file.path, part.body.gets_to_end)
        when "artist"
          artist = part.body.gets_to_end
        when "title"
          title = part.body.gets_to_end
        end
      end
    rescue
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << ExceptionResponse.new("Malformed request").to_json
      return
    end

    if file.nil?
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << ExceptionResponse.new("No file found").to_json
      return
    end

    # Check that the title and artist fields exist and are not blank
    if title.nil? || title.blank?
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << ExceptionResponse.new("Title cannot be blank").to_json
      return
    end

    if artist.nil? || artist.blank?
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << ExceptionResponse.new("Artist cannot be blank").to_json
      return
    end

    # Check that the given title name is valid
    title.each_char do |ch|
      if ch == '/' || ch == '.'
        context.response.status = HTTP::Status::BAD_REQUEST
        context.response.output << ExceptionResponse.new("Invalid title").to_json
      end
    end

    # Return validated data
    return AddMusicRequest.new(title, artist, file)
  end
end