require "uuid"
require "./repository"

# Provides an easy-to-user interface for accessing the playlist table in the database.
#
# Contains a set of methods for working with the playlist table. All queries made to the
# playlist table should be made though a PlaylistRepository object.
class Repositories::PlaylistRepository < Repositories::Repository

  # Returns whether a playlist with the given id exists in the user's collection
  #
  # ```
  # playlist_repository.exists_by_id("user_id", "playlist_id") # => true if user with "user_id" has a playlist with "playlist_id" in their collection
  # ```
  def exists_by_id(user_id : String, playlist_id : String) : Bool
    @db.query_one "SELECT EXISTS(SELECT 1 FROM playlists WHERE user_id=$1 AND playlist_id=$2)", user_id, playlist_id, as: Bool
  end

  # Returns whether a playlist with the given name exists in the user's collection
  #
  # ```
  # playlist_repository.exists_by_name("user_id", "playlist_name") # => true if user with "user_id" has a playlist with "playlist_name" in their collection
  # ```
  def exists_by_name(user_id : String, playlist_name : String) : Bool
    @db.query_one "SELECT EXISTS(SELECT 1 FROM playlists WHERE user_id=$1 AND name=$2)", user_id, playlist_name, as: Bool
  end

  # Returns whether the given music file exists in the user's playlist
  #
  # ```
  # playlist_repository.contains_music_id("user_id", "playlist_id", "music_id") # => true if user with "user_id" has a playlist with "playlist_id" in their collection and it contains "music_id"
  # ```
  def contains_music_id(user_id : String, playlist_id : String, music_id : String) : Bool
    @db.query_one "SELECT EXISTS(SELECT 1 FROM playlist_music WHERE user_id=$1 AND playlist_id=$2 AND music_id=$3)", user_id, playlist_id, music_id, as: Bool
  end

  # Adds a music track to a playlist in the user's collection
  #
  # ```
  # playlist_repository.add_music("user_id", "playlist_name", "music_id")
  # ```
  def add_music(user_id : String, playlist_id : String, music_id : String) : Nil
    @db.exec "INSERT INTO playlist_music (user_id, playlist_id, music_id, music_number) VALUES ($1, $2, $3, (SELECT COUNT(*) FROM playlist_music WHERE user_id=$4 AND playlist_id=$5) + 1)", user_id, playlist_id, music_id, user_id, playlist_id
  end

  # Returns whether a playlist with the given name exists in the user's collection
  # (excluding the playlist with the given playlist id)
  #
  # ```
  # playlist_repository.exists_by_name_excluding_id("user_id", "playlist_name", "playlist_id") # => true if user with "user_id" has a playlist with "playlist_name" in their collection (excluding the chosen playlist id)
  # ```
  def exists_by_name_excluding_id(user_id : String, playlist_name : String, excluded_playlist_id : String)
    @db.query_one "SELECT EXISTS(SELECT 1 FROM playlists WHERE user_id=$1 AND name=$2 AND playlist_id<>$3)", user_id, playlist_name, excluded_playlist_id, as: Bool
  end

  # Adds a playlist to the user's collection
  #
  # ```
  # playlist_repository.create("user_id", "playlist_name")
  # ```
  def create(user_id : String, playlist_name : String) : String
    playlist_id = Random::Secure.urlsafe_base64
    @db.exec "INSERT INTO playlists (playlist_id, name, user_id) VALUES ($1, $2, $3)", playlist_id, playlist_name, user_id

    playlist_id
  end

  # Lists metadata from playlists in the user's collection and writes contents
  # to the context response body as JSON
  #
  # ```
  # playlist_repository.list("user_id", context)
  # ```
  def list(user_id : String, context : HTTP::Server::Context) : Nil
    initialized = false
    context.response.output << "["
    @db.query("SELECT playlist_id, name FROM playlists WHERE user_id=$1 ORDER BY creation_time", user_id) do |rs|
      rs.each do
        playlist_id, playlist_name = rs.read(String, String)
        if initialized
          context.response.output << ","
        else
          initialized = true
        end
        context.response.output << "{"
        context.response.output << "\"playlist_id\":\"" << playlist_id << "\","
        context.response.output << "\"name\":\"" << playlist_name << "\""
        context.response.output << "}"
      end
    end
    context.response.output << "]"
  end

  # Lists music tracks in the user's playlist
  #
  # ```
  # playlist_repository.list_music("user_id", "playlist_id")
  # ```
  def list_music(user_id : String, playlist_id : String, context : HTTP::Server::Context) : Nil
    initialized = false
    context.response.output << "["
    @db.query("SELECT m.music_id, m.title, m.artist FROM music m INNER JOIN playlist_music pm ON m.music_id = pm.music_id WHERE pm.user_id=$1 AND pm.playlist_id=$2 ORDER BY pm.music_number", user_id, playlist_id) do |rs|
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

  # Updates the name of a playlist in the user's collection.
  #
  # ```
  # playlist_repository.update("user_id", "playlist_id", "playlist_name") # => true if update was successful
  # ```
  def update(user_id : String, playlist_id : String, playlist_name : String) : Bool
    result = @db.exec "UPDATE playlists SET name=$3 WHERE user_id=$1 AND playlist_id=$2", user_id, playlist_id, playlist_name

    result.rows_affected != 0
  end

  # Updates the position of a music track in the user's playlist.
  #
  # ```
  # playlist_repository.update_music("user_id", "playlist_id", "music_id", music_number) # => true if update was successful
  # ```
  def update_music(user_id : String, playlist_id : String, music_id : String, music_number : Int32) : (String | Nil)
    @db.transaction do |tx|
      # Check if the new music number is valid
      max_number = @db.query_one "SELECT COUNT(*) FROM playlist_music WHERE user_id=$1 AND playlist_id=$2", user_id, playlist_id, as: Int64
      return "Music number exceeds playlist length" if music_number > max_number

      # Record the original music number of the track
      original_music_number = nil
      @db.query("SELECT music_number FROM playlist_music WHERE user_id=$1 AND playlist_id=$2 AND music_id=$3", user_id, playlist_id, music_id) do |rs|
        rs.each do
          original_music_number = rs.read(Int32)
        end
      end
      return "Music not found within playlist" if original_music_number.nil?

      # Set music number of selected music track a temporary value
      @db.exec "UPDATE playlist_music SET music_number=0 WHERE user_id=$1 AND playlist_id=$2 AND music_id=$3", user_id, playlist_id, music_id

      # Update other music numbers to their appropriate values
      if music_number > original_music_number
        @db.exec "UPDATE playlist_music SET music_number=music_number-1 WHERE user_id=$1 AND playlist_id=$2 AND $3 < music_number AND music_number <= $4", user_id, playlist_id, original_music_number, music_number
      elsif music_number < original_music_number
        @db.exec "UPDATE playlist_music SET music_number=music_number+1 WHERE user_id=$1 AND playlist_id=$2 AND $3 <= music_number AND music_number < $4", user_id, playlist_id, music_number, original_music_number
      end

      # Set music number of selected music track to its chosen value
      @db.exec "UPDATE playlist_music SET music_number=$1 WHERE user_id=$2 AND playlist_id=$3 AND music_id=$4", music_number, user_id, playlist_id, music_id
    end

    nil
  end

  # Deletes a playlist from the user's collection. Returns whether the deletion
  # was successful.
  #
  # ```
  # playlist_repository.delete("user_id", "playlist_id") # => true if the user originally had a playlist with the given playlist id
  # ```
  def delete(user_id : String, playlist_id : String) : Bool
    result = @db.exec "DELETE FROM playlists WHERE user_id=$1 AND playlist_id=$2", user_id, playlist_id

    result.rows_affected != 0
  end

  # Removes a music track from a playlist in the user's collection. Returns
  # whether the removal was successful
  #
  # ```
  # playlist_repository.remove_music("user_id", "playlist_id", "music_id") # => true if the user originally had "music_id" in their playlist with the given playlist id
  # ```
  def remove_music(user_id : String, playlist_id : String, music_id : String) : Bool
    @db.transaction do |tx|
      music_number = nil
      @db.query("SELECT music_number FROM playlist_music WHERE user_id=$1 AND playlist_id=$2 AND music_id=$3", user_id, playlist_id, music_id) do |rs|
        rs.each do
          music_number = rs.read(Int32)
        end
      end
      return false if music_number.nil?

      result = @db.exec "DELETE FROM playlist_music WHERE user_id=$1 AND playlist_id=$2 AND music_id=$3", user_id, playlist_id, music_id

      @db.exec "UPDATE playlist_music SET music_number = music_number - 1 WHERE user_id=$1 AND playlist_id=$2 AND music_number > $3", user_id, playlist_id, music_number
    end

    true
  end
end
