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
end
