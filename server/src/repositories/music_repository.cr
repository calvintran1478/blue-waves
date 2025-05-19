require "db"
require "uuid"
require "awscr-s3"
require "./repository"
require "../schemas/music_schemas"
require "../utils/str"

# Provides an easy-to-use interface for accessing the music table in the database.
#
# Contains a set of methods for working with the music table. All queries made to the
# music table should be made though a MusicRepository object.
class Repositories::MusicRepository < Repositories::Repository
  include Schemas::MusicSchemas

  USER_ID_LENGTH = 36
  MUSIC_ID_LENGTH = 22
  MUSIC_FILE_ID_STRING_LENGTH = 72 # USER_ID_LENGTH + 1 + MUSIC_ID_LENGTH + 1 + String::HEADER_SIZE
  COVER_ART_ID_STRING_LENGTH = 82  # USER_ID_LENGTH + 1 + MUSIC_ID_LENGTH + 10 + 1 + String::HEADER_SIZE

  DEFAULT_S3_HEADER = Hash(String, String).new

  def initialize(@db : DB::Database, @music_db : Awscr::S3::Client)
  end

  # Returns whether a music file with the given id exists in the user's collection
  #
  # ```
  # music_repository.exists_by_id("user_id", "music_id") # => true if user with "user_id" has "music_id" in their collection
  # ```
  def exists_by_id(user_id : String, music_id : String) : Bool
    return @db.query_one "SELECT EXISTS(SELECT 1 FROM music WHERE user_id=$1 AND music_id=$2)", user_id, music_id, as: Bool
  end

  # Returns whether a music file with the given title exists in the user's collection
  #
  # ```
  # music_repository.exists_by_title("user_id", "music_title") # => true if user with "user_id" has "music_title" in their collection
  # ```
  def exists_by_title(user_id : String, title : String) : Bool
    return @db.query_one "SELECT EXISTS(SELECT 1 FROM music WHERE user_id=$1 AND title=$2)", user_id, title, as: Bool
  end

  # Adds a music file to the user's collection.
  #
  # ```
  # music_repository.create("music_title", "artist", music_file, "user_id")
  # ```
  def create(title : String, artist : String, music_file : Bytes, art_file : Bytes | Nil, music_file_type : String, art_file_type : String | Nil, user_id : String) : (String | Nil)
    begin
      @db.transaction do |tx|
        # Store metadata about the music file
        music_id = Random::Secure.urlsafe_base64
        tx.connection.exec "INSERT INTO music (music_id, title, artist, user_id) VALUES ($1, $2, $3, $4)", music_id, title, artist, user_id

        # Create object id for music file
        object_id_buffer = uninitialized UInt8[COVER_ART_ID_STRING_LENGTH]
        object_id = Utils::Str.stringify(user_id, "/", music_id, string_buffer: object_id_buffer.to_unsafe)

        # Upload music file to storage bucket
        @music_db.put_object("blue-waves", object_id, music_file, {"Content-Type" => music_file_type})

        # Upload cover art file to storage bucket (if one was included)
        unless art_file.nil?
          # Create object id for cover art file
          cover_art_str = "/cover-art"
          curr_buffer = (object_id_buffer.to_unsafe + object_id.size).as(String).to_unsafe
          curr_buffer.copy_from(cover_art_str.to_unsafe, cover_art_str.size)
          curr_buffer[cover_art_str.size] = 0_u8

          bytesize = USER_ID_LENGTH + 1 + MUSIC_ID_LENGTH + cover_art_str.size
          object_id = object_id_buffer.to_unsafe.as(String)
          object_id.initialize_header(bytesize, bytesize)

          @music_db.put_object("blue-waves", object_id, art_file, {"Content-Type" => art_file_type.as(String)})
        end

        return music_id
      end
    rescue
    end
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
  def list(user_id : String, context : HTTP::Server::Context, limit : (Int32 | Nil) = nil, offset : (Int32 | Nil) = nil) : Nil
    # Convert limit and offset to default values if not provided
    limit_value = limit.nil? ? "ALL" : limit
    offset_value = offset.nil? ? 0 : offset

    # Fetch music information
    initialized = false
    context.response.output << "["
    @db.query("SELECT music_id, title, artist FROM music WHERE user_id=$1 ORDER BY creation_time DESC LIMIT #{limit_value} OFFSET #{offset_value}", user_id) do |rs|
      rs.each do
        music_id, title, artist = rs.read(String, String, String)
        if initialized
          context.response.output << ","
        else
          initialized = true
        end
        context.response.output << "{"
        context.response.output << "\"music_id\":\"" << music_id << "\","
        context.response.output << "\"title\":\"" << title << "\","
        context.response.output << "\"artist\":\"" << artist << "\""
        context.response.output << "}"
      end
    end
    context.response.output << "]"
  end

  # Retreives a single music file in the user's collection based on music id
  # and writes it to the given context response output. Can be used to only
  # fetch a specific set of bytes if the range header is provided
  #
  # ```
  # music_repository.get("user_id", "music_id", context)
  # ```
  def get(user_id : String, music_id : (String | Bytes), context : HTTP::Server::Context) : Nil
    begin
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
        @music_db.get_object("blue-waves", object_id, s3_headers) do |music_file|
          context.response.content_type = music_file.headers["Content-Type"]
          context.response.status = HTTP::Status::PARTIAL_CONTENT
          IO.copy(music_file.body_io, context.response.output)
        end
      else
        # Fetch complete music file from storage bucket
        @music_db.get_object("blue-waves", object_id, DEFAULT_S3_HEADER) do |music_file|
          context.response.content_type = music_file.headers["Content-Type"]
          context.response.headers["Cache-Control"] = "private"
          context.response.status = HTTP::Status::OK
          IO.copy(music_file.body_io, context.response.output)
        end
      end
    rescue
      context.response.status = HTTP::Status::NOT_FOUND
      context.response.output << "Music file not found"
    end
  end

  # Retreives the cover art for a single music file in the user's collection
  #
  # ```
  # music_repository.get_cover_art("user_id", "music_id", context)
  # ```
  def get_cover_art(user_id : String, music_id : (String | Bytes), context : HTTP::Server::Context) : Nil
    begin
      # Get object id using the given parameters
      object_id_buffer = uninitialized UInt8[COVER_ART_ID_STRING_LENGTH]
      object_id = Utils::Str.stringify(user_id, "/", music_id, "/cover-art", string_buffer: object_id_buffer.to_unsafe)

      # Check for conditional request
      modified_since = context.request.headers["If-Modified-Since"]?
      if !modified_since.nil?
        headers = @music_db.head_object("blue-waves", object_id, DEFAULT_S3_HEADER)
        threshold_time = HTTP.parse_time(modified_since)

        if !threshold_time.nil? && headers.last_modified <= threshold_time
          context.response.headers["Last-Modified"] = HTTP.format_time(headers.last_modified)
          context.response.headers["Cache-Control"] = "private, no-cache"
          context.response.status = HTTP::Status::NOT_MODIFIED
          return
        end
      end

      # Fetch music cover art from storage bucket
      @music_db.get_object("blue-waves", object_id, DEFAULT_S3_HEADER) do |art_file|
        context.response.content_type = art_file.headers["Content-Type"]
        context.response.headers["Last-Modified"] = art_file.headers["Last-Modified"]
        context.response.headers["Cache-Control"] = "private, no-cache"
        context.response.status = HTTP::Status::OK
        IO.copy(art_file.body_io, context.response.output)
      end
    rescue
      context.response.status = HTTP::Status::NOT_FOUND
      context.response.output << "Cover art file not found"
    end
  end

  # Sets the cover art for a single music file in the user's collection.
  # Returns whether the cover art is being set for the first time
  #
  # ```
  # music_repository.set_cover_art("user_id", "music_id", art_file) # => true if the cover art is being set for the first time, and false if simply updated
  # ```
  def set_cover_art(user_id : String, music_id : (String | Bytes), art_file : Bytes, art_file_type : String) : Bool
    # Get object id using the given parameters
    object_id_buffer = uninitialized UInt8[COVER_ART_ID_STRING_LENGTH]
    object_id = Utils::Str.stringify(user_id, "/", music_id, "/cover-art", string_buffer: object_id_buffer.to_unsafe)

    # Check if cover art is being set for the first time
    first_created = false
    begin
      @music_db.head_object("blue-waves", object_id, DEFAULT_S3_HEADER)
    rescue
      first_created = true
    end

    # Set cover art
    @music_db.put_object("blue-waves", object_id, art_file, {"Content-Type" => art_file_type})

    return first_created
  end

  # Updates metadata for a single music file in the user's collection.
  #
  # ```
  # music_repository.update("user_id", "music_id", "title", "artist") # => true if update was successful
  # ```
  def update(user_id : String, music_id : String, title : String | Nil, artist : String | Nil) : Bool
    # Update metadata
    if !title.nil? && !artist.nil?
      result = @db.exec "UPDATE music SET title=$3,artist=$4 WHERE user_id=$1 AND music_id=$2", user_id, music_id, title, artist
    elsif !title.nil? && artist.nil?
      result = @db.exec "UPDATE music SET title=$3 WHERE user_id=$1 AND music_id=$2", user_id, music_id, title
    elsif title.nil? && !artist.nil?
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
  def delete(user_id : String, music_id : String) : Bool
    # Delete metadata
    a = @db.exec "DELETE FROM music WHERE user_id=$1 AND music_id=$2", user_id, music_id

    # Delete music file and its cover art
    file_exists = (a.rows_affected != 0)
    if file_exists
      # Delete music file
      object_id_buffer = uninitialized UInt8[COVER_ART_ID_STRING_LENGTH]
      object_id = Utils::Str.stringify(user_id, "/", music_id, string_buffer: object_id_buffer.to_unsafe)
      @music_db.delete_object("blue-waves", object_id, DEFAULT_S3_HEADER)

      # Delete cover art
      cover_art_str = "/cover-art"
      curr_buffer = (object_id_buffer.to_unsafe + object_id.size).as(String).to_unsafe
      curr_buffer.copy_from(cover_art_str.to_unsafe, cover_art_str.size)
      curr_buffer[cover_art_str.size] = 0_u8

      bytesize = USER_ID_LENGTH + 1 + MUSIC_ID_LENGTH + cover_art_str.size
      object_id = object_id_buffer.to_unsafe.as(String)
      object_id.initialize_header(bytesize, bytesize)

      @music_db.delete_object("blue-waves", object_id, DEFAULT_S3_HEADER)
    end

    return file_exists
  end
end
