require "db"
require "awscr-s3"
require "./repository"
require "../schemas/music_schemas"

# Provides an easy-to-use interface for accessing the music table in the database.
#
# Contains a set of methods for working with the music table. All queries made to the
# music table should be made though a MusicRepository object.
class Repositories::MusicRepository < Repositories::Repository
  include Schemas::MusicSchemas

  def initialize(@db : DB::Database, @music_db : Awscr::S3::Client)
    @music_uploader = Awscr::S3::FileUploader.new(@music_db)
  end

  # Returns whether a music file with the given title exists in the user's collection
  #
  # ```
  # music_repository.exists("music_title", "user_id") # => true if user with "user_id" has "music_title" in their collection
  # ```
  def exists(title : String, user_id : String)
    return @db.query_one "SELECT EXISTS(SELECT 1 FROM music WHERE title=$1 AND user_id=$2)", title, user_id, as: Bool
  end

  # Adds a music file to the user's collection.
  #
  # ```
  # music_repository.create("music_title", "artist", music_file, "user_id")
  # ```
  def create(title : String, artist : String, file : File, user_id : String) : Nil
    # Store metadata about the music file
    @db.exec "INSERT INTO music (title, artist, user_id) VALUES ($1, $2, $3)", title, artist, user_id

    # Upload music file to storage bucket
    File.open(file.path, "r") do |music_file|
      @music_uploader.upload("blue-waves", "#{user_id}/#{title}", music_file)
    end
  end

  # Lists all titles and artists from music files in the user's collection
  #
  # ```
  # music_repository.list("user_id") # => [Schemas::MusicSchemas::MusicMetadata(@title="Title1", @artist="Artist1"), ...]
  # ```
  def list(user_id : String) : Array(MusicMetadata)
    # Fetch music information
    music_items = Array(MusicMetadata).new
    @db.query("SELECT title, artist FROM music WHERE user_id=$1", user_id) do |rs|
      rs.each do
        title, artist = rs.read(String, String)
        music_items << MusicMetadata.new(title, artist)
      end
    end

    return music_items
  end
end
