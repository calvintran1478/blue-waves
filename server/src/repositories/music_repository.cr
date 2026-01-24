require "db"
require "uuid"
require "awscr-s3"
require "./repository"
require "../schemas/music_schemas"
require "../utils/str"
require "../utils/constants"

# Provides an easy-to-use interface for accessing the music table in the database.
#
# Contains a set of methods for working with the music table. All queries made to the
# music table should be made though a MusicRepository object.
class Repositories::MusicRepository < Repositories::Repository
  include Utils::Constants

  def initialize(@db : DB::Database, @music_db : Awscr::S3::Client, @cache_db : Redis::PooledClient, @bucket_name : String)
  end

  # Returns whether a music file with the given id exists in the user's collection
  #
  # ```
  # music_repository.exists_by_id("user_id", "music_id") # => true if user with "user_id" has "music_id" in their collection
  # ```
  def exists_by_id(user_id : Bytes, music_id : Bytes) : Bool
    @db.query_one "SELECT EXISTS(SELECT 1 FROM music WHERE user_id=$1 AND music_id=$2)", user_id, music_id do |rs|
      rs.read { |io, _| io.read_byte == 1}
    end
  end

  # Adds a music file to the user's collection.
  #
  # ```
  # music_repository.create("music_title", "artist", music_file, "user_id")
  # ```
  def create(title : Bytes, artist : Bytes, music_file : Bytes, art_file : Bytes | Nil, music_file_type : String, art_file_type : String | Nil, user_id : Bytes) : (String | Nil)
    @db.transaction do |tx|
      # Store metadata about the music file
      music_id = Random::Secure.urlsafe_base64
      tx.connection.exec "INSERT INTO music (music_id, title, artist, user_id) VALUES ($1, $2, $3, $4)", music_id.to_slice, title, artist, user_id

      # Create object id for music file
      object_id_buffer = uninitialized UInt8[COVER_ART_ID_STRING_LENGTH]
      object_id = Utils::Str.stringify(user_id, "/", music_id, string_buffer: object_id_buffer.to_unsafe)

      # Upload music file to storage bucket
      channel = Channel(Nil).new
      spawn do
        @music_db.put_object(@bucket_name, object_id, music_file, {"Content-Type" => music_file_type})
        channel.send(nil)
      end

      # Upload cover art file to storage bucket (if one was included)
      unless art_file.nil?
        spawn do
          # Create object id for cover art file
          cover_art_str = "/cover-art"
          curr_buffer = (object_id_buffer.to_unsafe + object_id.size).as(String).to_unsafe
          curr_buffer.copy_from(cover_art_str.to_unsafe, cover_art_str.size)
          curr_buffer[cover_art_str.size] = 0_u8

          bytesize = USER_ID_LENGTH + 1 + MUSIC_ID_LENGTH + cover_art_str.size
          object_id = object_id_buffer.to_unsafe.as(String)
          object_id.initialize_header(bytesize, bytesize)

          @music_db.put_object(@bucket_name, object_id, art_file, {"Content-Type" => art_file_type.as(String)})
          channel.send(nil)
        end
        channel.receive
      end
      channel.receive

      music_id
    end
  rescue
  end

  # Lists metadata from music files in the user's collection and writes contents
  # to the context response body as JSON
  #
  # limit and offset may be provided to retreive a paginated selection. limit
  # specifies the maximum number of entries to retreive and offset specifies
  # how many entries to skip from the beginning before searching
  #
  # ```
  # music_repository.list("user_id", context)
  #
  # music_repository.list("user_id", context, 10, 10)
  # ```
  def list(user_id : Bytes, output : IO, limit : (Int32 | Nil) = nil, offset : (Int32 | Nil) = nil) : Nil
    # Convert limit and offset to default values if not provided
    limit_value = limit.nil? ? "ALL" : limit
    offset_value = offset.nil? ? 0 : offset

    # Fetch music information
    @db.query("SELECT music_id, title, artist FROM music WHERE user_id=$1 ORDER BY creation_time DESC LIMIT #{limit_value} OFFSET #{offset_value}", user_id) do |rs|
      rs.each do
        rs.read { |music_id, _| IO.copy(music_id, output) }

        rs.read do |title, bytesize|
          output.write_byte(bytesize.to_u8)
          IO.copy(title, output)
        end

        rs.read do |artist, bytesize|
          output.write_byte(bytesize.to_u8)
          IO.copy(artist, output)
        end
      end
    end
  end

  # Retreives a single music file in the user's collection based on music id
  # and writes it to the given context response output. Can be used to only
  # fetch a specific set of bytes if the range header is provided
  #
  # ```
  # music_repository.get("user_id", "music_id", context)
  # ```
  def get(user_id : Bytes, music_id : Bytes, context : HTTP::Server::Context) : Nil
    # Get object id using the given parameters
    object_id_buffer = uninitialized UInt8[MUSIC_FILE_ID_STRING_LENGTH]
    object_id = Utils::Str.stringify(user_id, "/", music_id, string_buffer: object_id_buffer.to_unsafe)

    # Check range header for requested bytes
    range_header = context.request.headers["Range"]?

    # Retreive requested number of bytes
    if !range_header.nil?
      # Add range header
      s3_headers = {"Range" => range_header}

      # Fetch requested byte range from storage bucket
      @music_db.get_object(@bucket_name, object_id, s3_headers) do |music_file|
        context.response.content_type = music_file.headers["Content-Type"]
        context.response.status = HTTP::Status::PARTIAL_CONTENT
        IO.copy(music_file.body_io, context.response.output)
      end
    else
      # Fetch complete music file from storage bucket
      @music_db.get_object(@bucket_name, object_id, DEFAULT_S3_HEADER) do |music_file|
        context.response.content_type = music_file.headers["Content-Type"]
        context.response.headers["Cache-Control"] = "private"
        context.response.status = HTTP::Status::OK
        IO.copy(music_file.body_io, context.response.output)
      end
    end
  rescue XML::Error
    context.response.status = HTTP::Status::NOT_FOUND
    context.response.output << "Music file not found"
  end

  # Retreives the cover art for a single music file in the user's collection
  #
  # ```
  # music_repository.get_cover_art("user_id", "music_id", context)
  # ```
  def get_cover_art(user_id : Bytes, music_id : Bytes, context : HTTP::Server::Context, rate_limit_middleware : Middleware::RateLimitMiddleware) : Nil
    # Get object id using the given parameters
    object_id_buffer = uninitialized UInt8[COVER_ART_ID_STRING_LENGTH]
    object_id = Utils::Str.stringify(user_id, "/", music_id, "/cover-art", string_buffer: object_id_buffer.to_unsafe)

    # Check for cached value
    modified_since = context.request.headers["If-Modified-Since"]?
    unless modified_since.nil?
      threshold_time = HTTP.parse_time(modified_since)
      last_modified = @cache_db.get(object_id)
      if !threshold_time.nil? && !last_modified.nil? && last_modified.to_i64 <= threshold_time.to_unix
        context.response.status = HTTP::Status::NOT_MODIFIED
        return
      end
    end

    # Perform rate limiting
    get_cover_art_request_allowed = rate_limit_middleware.rate_limit_request(user_id, "GET", "/api/v1/users/music/{music_id}/cover-art")
    if !get_cover_art_request_allowed
      context.response.status = HTTP::Status::TOO_MANY_REQUESTS
      context.response.output << "Too Many Requests"
      return
    end

    # Fetch music cover art from storage bucket
    @music_db.get_object(@bucket_name, object_id, DEFAULT_S3_HEADER) do |art_file|
      context.response.headers["Cache-Control"] = "private, no-cache"

      # Check for conditional request
      not_modified = false
      unless modified_since.nil?
        threshold_time = HTTP.parse_time(modified_since)
        last_modified = HTTP.parse_time(art_file.headers["Last-Modified"])
        not_modified = !threshold_time.nil? && !last_modified.nil? && last_modified <= threshold_time
      end

      if not_modified
        context.response.status = HTTP::Status::NOT_MODIFIED
      else
        context.response.headers["Last-Modified"] = art_file.headers["Last-Modified"]
        context.response.content_type = art_file.headers["Content-Type"]
        context.response.status = HTTP::Status::OK
        IO.copy(art_file.body_io, context.response.output)
      end

      # Cache modified time
      @cache_db.set(object_id, HTTP.parse_time(art_file.headers["Last-Modified"]).as(Time).to_unix, 432000)
    end
  rescue XML::Error
    context.response.status = HTTP::Status::NOT_FOUND
    context.response.output << "Cover art file not found"
  end

  # Sets the cover art for a single music file in the user's collection.
  # Returns whether the cover art is being set for the first time
  #
  # ```
  # music_repository.set_cover_art("user_id", "music_id", art_file) # => true if the cover art is being set for the first time, and false if simply updated
  # ```
  def set_cover_art(user_id : Bytes, music_id : Bytes, art_file : Bytes, art_file_type : String) : Bool
    # Get object id using the given parameters
    object_id_buffer = uninitialized UInt8[COVER_ART_ID_STRING_LENGTH]
    object_id = Utils::Str.stringify(user_id, "/", music_id, "/cover-art", string_buffer: object_id_buffer.to_unsafe)

    # Check if cover art is being set for the first time
    first_created = false
    begin
      @music_db.head_object(@bucket_name, object_id, DEFAULT_S3_HEADER)
    rescue
      first_created = true
    end

    # Set cover art
    @music_db.put_object(@bucket_name, object_id, art_file, {"Content-Type" => art_file_type})

    first_created
  end

  # Updates metadata for a single music file in the user's collection.
  #
  # ```
  # music_repository.update("user_id", "music_id", "title", "artist") # => true if update was successful
  # ```
  def update(user_id : Bytes, music_id : Bytes, title : Bytes, artist : Bytes) : Bool
    # Update metadata
    if title.size != 0 && artist.size != 0
      result = @db.exec "UPDATE music SET title=$3,artist=$4 WHERE user_id=$1 AND music_id=$2", user_id, music_id, title, artist
    elsif title.size != 0 && artist.size == 0
      result = @db.exec "UPDATE music SET title=$3 WHERE user_id=$1 AND music_id=$2", user_id, music_id, title
    elsif title.size == 0 && artist.size != 0
      result = @db.exec "UPDATE music SET artist=$3 WHERE user_id=$1 AND music_id=$2", user_id, music_id, artist
    else
      return false
    end

    result.rows_affected != 0
  end

  # Deletes a music file from the user's collection along with its metadata
  # and cover art. Returns whether the deletion was successful.
  #
  # ```
  # music_repository.delete("user_id", "music_id") # => true if the user originally had a music file with the given music id
  # ```
  def delete(user_id : Bytes, music_id : Bytes) : Bool
    # Delete metadata
    result = @db.exec "DELETE FROM music WHERE user_id=$1 AND music_id=$2", user_id, music_id

    # Delete music file and its cover art
    file_exists = (result.rows_affected != 0)
    if file_exists
      # Create channel for synchronizing fibers
      channel = Channel(Nil).new

      # Delete music file
      object_id_buffer = uninitialized UInt8[COVER_ART_ID_STRING_LENGTH]
      object_id = Utils::Str.stringify(user_id, "/", music_id, string_buffer: object_id_buffer.to_unsafe)
      spawn do
        @music_db.delete_object(@bucket_name, object_id, DEFAULT_S3_HEADER)
        channel.send(nil)
      end

      # Delete cover art
      spawn do
        cover_art_str = "/cover-art"
        curr_buffer = (object_id_buffer.to_unsafe + object_id.size).as(String).to_unsafe
        curr_buffer.copy_from(cover_art_str.to_unsafe, cover_art_str.size)
        curr_buffer[cover_art_str.size] = 0_u8

        bytesize = USER_ID_LENGTH + 1 + MUSIC_ID_LENGTH + cover_art_str.size
        cover_art_id = object_id_buffer.to_unsafe.as(String)
        cover_art_id.initialize_header(bytesize, bytesize)

        @music_db.delete_object(@bucket_name, cover_art_id, DEFAULT_S3_HEADER)
        @cache_db.del(cover_art_id)
        channel.send(nil)
      end

      channel.receive
      channel.receive
    end

    file_exists
  end
end
