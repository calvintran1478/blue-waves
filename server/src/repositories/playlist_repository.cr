require "uuid"
require "./repository"

# Provides an easy-to-user interface for accessing the playlist table in the database.
#
# Contains a set of methods for working with the playlist table. All queries made to the
# playlist table should be made though a PlaylistRepository object.
class Repositories::PlaylistRepository < Repositories::Repository

  # Returns whether a playlist with the given name exists in the user's collection
  #
  # ```
  # playlist_repository.exists_by_name("user_id", "playlist_name") # => true if user with "user_id" has a playlist with "playlist_name" in their collection
  # ```
  def exists_by_name(user_id : String, playlist_name : String) : Bool
    @db.query_one "SELECT EXISTS(SELECT 1 FROM playlists WHERE user_id=$1 AND name=$2)", user_id, playlist_name, as: Bool
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
        context.response.output << "\"name\":\"" << playlist_name << "\","
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
end
