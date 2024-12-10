require "db"
require "uuid"
require "awscr-s3"
require "./repository"
require "../schemas/music_schemas"

# Provides an easy-to-use interface for accessing the music table in the database.
#
# Contains a set of methods for working with the music table. All queries made to the
# music table should be made though a MusicRepository object.
class Repositories::MusicRepository < Repositories::Repository
  include Schemas::MusicSchemas
  include Exceptions

  def initialize(@db : DB::Database, @music_db : Awscr::S3::Client)
    @music_uploader = Awscr::S3::FileUploader.new(@music_db)
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
  def create(title : String, artist : String, music_file : File, art_file : File | Nil, user_id : String) : (String | Nil)
    begin
      @db.transaction do |tx|
        # Store metadata about the music file
        music_id = Random::Secure.urlsafe_base64
        tx.connection.exec "INSERT INTO music (music_id, title, artist, user_id) VALUES ($1, $2, $3, $4)", music_id, title, artist, user_id

        # Upload music file to storage bucket
        File.open(music_file.path, "r") do |file|
          @music_uploader.upload("blue-waves", "#{user_id}/#{music_id}", file)
        end

        # Upload cover art file to storage bucket (if one was included)
        unless art_file.nil?
          File.open(art_file.path, "r") do |file|
            @music_uploader.upload("blue-waves", "#{user_id}/#{music_id}/cover-art", file)
          end
        end

        return music_id
      end
    rescue
    end
  end

  # Lists titles and artists from music files in the user's collection
  #
  # limit and offset may be provided to retreive a paginated selection. limit
  # specifies the maximum number of entries to retreive and offset specifies
  # how many entries to skip from the beginning before searching
  # ```
  # music_repository.list("user_id") # => [MusicMetadata(@music_id="music_id1", @title="Title1", @artist="Artist1"), ...]
  #
  # music_repository.list("user_id", 10, 10) # => [MusicMetadata(@music_id="music_id11", @title="Title11", @artist="Artist11"), ..., MusicMetadata(@music_id="music_id20", @title="Title20", @artist="Artist20")]
  # ```
  def list(user_id : String, limit : (Int32 | Nil) = nil, offset : (Int32 | Nil) = nil) : Array(MusicMetadata)
    # Create array to store music entries
    music_items = limit.nil? ? Array(MusicMetadata).new : Array(MusicMetadata).new(limit)

    # Convert limit and offset to default values if not provided
    limit_value = limit.nil? ? "ALL" : limit
    offset_value = offset.nil? ? 0 : offset

    # Fetch music information
    @db.query("SELECT music_id, title, artist FROM music WHERE user_id=$1 LIMIT #{limit_value} OFFSET #{offset_value}", user_id) do |rs|
      rs.each do
        music_id, title, artist = rs.read(String, String, String)
        music_items << MusicMetadata.new(music_id, title, artist)
      end
    end

    return music_items
  end

  # Retreives a single music file in the user's collection based on music id
  # and writes it to the given context response output. Can be used to only
  # fetch a specific set of bytes if the range header is provided
  #
  # ```
  # music_repository.get("user_id", "music_id", context)
  # ```
  def get(user_id : String, music_id : String, context : HTTP::Server::Context) : Nil
    begin
      # Check range header for requested bytes
      range_header = context.request.headers["Range"]?

      # Retreive requested number of bytes
      if !range_header.nil?
        # Add range header
        s3_headers = {"Range" => range_header}

        # Fetch requested byte range from storage bucket
        @music_db.get_object("blue-waves", "#{user_id}/#{music_id}", s3_headers) do |music_file|
          context.response.content_type = "audio/mpeg"
          context.response.status = HTTP::Status::PARTIAL_CONTENT
          IO.copy(music_file.body_io, context.response.output)
        end
      else
        # Fetch complete music file from storage bucket
        @music_db.get_object("blue-waves", "#{user_id}/#{music_id}") do |music_file|
          context.response.content_type = "audio/mpeg"
          context.response.status = HTTP::Status::OK
          IO.copy(music_file.body_io, context.response.output)
        end
      end
    rescue
      context.response.status = HTTP::Status::NOT_FOUND
      context.response.output << ExceptionResponse.new("Music file not found").to_json
    end
  end

  # Retreives the cover art for a single music file in the user's collection
  #
  # ```
  # music_repository.get_cover_art("user_id", "music_id", context)
  # ```
  def get_cover_art(user_id : String, music_id : String, context : HTTP::Server::Context) : Nil
    begin
      # Fetch music cover art from storage bucket
      @music_db.get_object("blue-waves", "#{user_id}/#{music_id}/cover-art") do |art_file|
        context.response.content_type = "image/jpeg"
        context.response.status = HTTP::Status::OK
        IO.copy(art_file.body_io, context.response.output)
      end
    rescue
      context.response.status = HTTP::Status::NOT_FOUND
      context.response.output << ExceptionResponse.new("Cover art file not found").to_json
    end
  end

  # Sets the cover art for a single music file in the user's collection.
  # Returns whether the cover art is being set for the first time
  #
  # ```
  # music_repository.set_cover_art("user_id", "music_id", art_file) # => true if the cover art is being set for the first time, and false if simply updated
  # ```
  def set_cover_art(user_id : String, music_id : String, art_file : File) : Bool
    # Check if cover art is being set for the first time
    first_created = false
    begin
      @music_db.head_object("blue-waves", "#{user_id}/#{music_id}/cover-art")
    rescue
      first_created = true
    end

    # Set cover art
    File.open(art_file.path, "r") do |file|
      @music_uploader.upload("blue-waves", "#{user_id}/#{music_id}/cover-art", file)
    end

    return first_created
  end

  # Updates metadata for a single music file in the user's collection.
  #
  # ```
  # music_repository.update("user_id", "music_id", "title", "artist") # => true if update was successful
  # ```
  def update(user_id : String, music_id : String, title : String, artist : String) : Bool
    # Update metadata
    result = @db.exec "UPDATE music SET title=$1,artist=$2 WHERE user_id=$3 AND music_id=$4", title, artist, user_id, music_id
    return result.rows_affected != 0
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
      @music_db.delete_object("blue-waves", "#{user_id}/#{music_id}")
      @music_db.delete_object("blue-waves", "#{user_id}/#{music_id}/cover-art")
    end

    return file_exists
  end
end
