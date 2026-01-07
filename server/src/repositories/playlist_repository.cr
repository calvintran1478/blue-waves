require "uuid"
require "./repository"
require "../utils/constants"

# Provides an easy-to-user interface for accessing the playlist table in the database.
#
# Contains a set of methods for working with the playlist table. All queries made to the
# playlist table should be made though a PlaylistRepository object.
class Repositories::PlaylistRepository < Repositories::Repository
  include Utils::Constants

  # Returns whether a playlist with the given id exists in the user's collection
  #
  # ```
  # playlist_repository.exists_by_id("user_id", "playlist_id") # => true if user with "user_id" has a playlist with "playlist_id" in their collection
  # ```
  def exists_by_id(user_id : Bytes, playlist_id : Bytes) : Bool
    @db.query_one "SELECT EXISTS(SELECT 1 FROM playlists WHERE user_id=$1 AND playlist_id=$2)", user_id, playlist_id, as: Bool
  end

  # Returns whether the given music file exists in the user's playlist
  #
  # ```
  # playlist_repository.contains_music_id("user_id", "playlist_id", "music_id") # => true if user with "user_id" has a playlist with "playlist_id" in their collection and it contains "music_id"
  # ```
  def contains_music_id(user_id : Bytes, playlist_id : Bytes, music_id : Bytes) : Bool
    @db.query_one "SELECT EXISTS(SELECT 1 FROM playlist_music WHERE user_id=$1 AND playlist_id=$2 AND music_id=$3)", user_id, playlist_id, music_id, as: Bool
  end

  # Adds a music track to a playlist in the user's collection. Returns whether
  # the addition was successful
  #
  # ```
  # playlist_repository.add_music("user_id", "playlist_name", "music_id") # => true if the music track exists and does not already exist in the playlist
  # ```
  def add_music(user_id : Bytes, playlist_id : Bytes, music_id : Bytes) : Bool
    query = <<-SQL
      INSERT INTO playlist_music (user_id, playlist_id, music_id, music_number)
      SELECT $1, $2, $3, (SELECT COALESCE(MAX(pm.music_number), -256) FROM playlist_music pm WHERE user_id=$4 AND playlist_id=$5) + 256
      WHERE
        EXISTS(SELECT 1 FROM music WHERE user_id=$6 AND music_id=$7) AND
        EXISTS(SELECT 1 FROM playlists WHERE user_id=$8 AND playlist_id=$9) AND
        NOT EXISTS(SELECT 1 FROM playlist_music WHERE user_id=$10 AND playlist_id=$11 AND music_id=$12)
    SQL

    result = @db.exec query, user_id, playlist_id, music_id, user_id, playlist_id, user_id, music_id, user_id, playlist_id, user_id, playlist_id, music_id

    result.rows_affected != 0
  end

  # Returns whether a playlist with the given name exists in the user's collection
  # (excluding the playlist with the given playlist id)
  #
  # ```
  # playlist_repository.exists_by_name_excluding_id("user_id", "playlist_name", "playlist_id") # => true if user with "user_id" has a playlist with "playlist_name" in their collection (excluding the chosen playlist id)
  # ```
  def exists_by_name_excluding_id(user_id : Bytes, playlist_name : String, excluded_playlist_id : Bytes)
    @db.query_one "SELECT EXISTS(SELECT 1 FROM playlists WHERE user_id=$1 AND name=$2 AND playlist_id<>$3)", user_id, playlist_name, excluded_playlist_id, as: Bool
  end

  # Adds a playlist to the user's collection. Returns the newly created playlist
  # id if successful and nil otherwise
  #
  # ```
  # playlist_repository.create("user_id", "playlist_name") # => "<Playlist_ID>" if a playlist with the given name does not already exist in the user's collection
  # ```
  def create(user_id : Bytes, playlist_name : String) : (String | Nil)
    playlist_id = Random::Secure.urlsafe_base64
    result = @db.exec "INSERT INTO playlists (playlist_id, name, user_id) VALUES ($1, $2, $3) ON CONFLICT (user_id, name) DO NOTHING", playlist_id, playlist_name, user_id

    return playlist_id if result.rows_affected == 1
  end

  # Lists metadata from playlists in the user's collection and writes contents
  # to the context response body as JSON
  #
  # ```
  # playlist_repository.list("user_id", context)
  # ```
  def list(user_id : Bytes, output : IO) : Nil
    @db.query("SELECT playlist_id, name FROM playlists WHERE user_id=$1 ORDER BY creation_time", user_id) do |rs|
      rs.each do
        rs.read { |playlist_id, _| IO.copy(playlist_id, output) }

        rs.read do |playlist_name, bytesize|
          output.write_bytes(bytesize, IO::ByteFormat::NetworkEndian)
          IO.copy(playlist_name, output)
        end
      end
    end
  end

  # Gets the name of a playlist in the user's collection along with all music
  # tracks in that playlist. The playlist is selected by playlist id and the
  # contents are written to the context body as JSON. Returns whether a playlist
  # with the given id was successfully found
  #
  # ```
  # playlist_repository.get("user_id", "playlist_id", context) # => true if the playlist exists
  # ```
  def get(user_id : Bytes, playlist_id : Bytes, context : HTTP::Server::Context) : Bool
    # Get playlist name
    found = false
    @db.query("SELECT name FROM playlists WHERE user_id=$1 AND playlist_id=$2", user_id, playlist_id) do |rs|
      rs.each do
        rs.read do |name, bytesize|
          context.response.content_type = "application/octet-stream"
          context.response.status = HTTP::Status::OK
          context.response.output.write_bytes(bytesize, IO::ByteFormat::NetworkEndian)
          IO.copy(name, context.response.output)
          found = true
        end
      end
    end
    return false unless found

    # Get playlist music tracks
    @db.query("SELECT m.music_id, m.title, m.artist FROM music m INNER JOIN playlist_music pm ON m.music_id = pm.music_id WHERE pm.user_id=$1 AND pm.playlist_id=$2 ORDER BY pm.music_number", user_id, playlist_id) do |rs|
      rs.each do
        rs.read { |music_id, _| IO.copy(music_id, context.response.output) }

        rs.read do |title, bytesize|
          context.response.output.write_bytes(bytesize, IO::ByteFormat::NetworkEndian)
          IO.copy(title, context.response.output)
        end

        rs.read do |artist, bytesize|
          context.response.output.write_bytes(bytesize, IO::ByteFormat::NetworkEndian)
          IO.copy(artist, context.response.output)
        end
      end
    end

    true
  end

  # Updates the name of a playlist in the user's collection.
  #
  # ```
  # playlist_repository.update("user_id", "playlist_id", "playlist_name") # => true if update was successful
  # ```
  def update(user_id : Bytes, playlist_id : Bytes, playlist_name : String) : Bool
    result = @db.exec "UPDATE playlists SET name=$3 WHERE user_id=$1 AND playlist_id=$2", user_id, playlist_id, playlist_name

    result.rows_affected != 0
  end

  # Updates the position of a music track in the user's playlist.
  #
  # ```
  # playlist_repository.update_music("user_id", "playlist_id", "music_id", music_number, context)
  # ```
  def update_music(user_id : Bytes, playlist_id : Bytes, music_id : Bytes, music_number : Int32, context : HTTP::Server::Context) : Nil
    # Check for relative update: 0 -> swap with next, -1 -> swap with previous
    if music_number < 1
      # Select query based on which track to swap with
      query = if music_number == 0
        <<-SQL
          WITH swap_targets AS(
            SELECT pm2.music_id, pm2.music_number
            FROM playlist_music pm2
            WHERE user_id=$4 AND playlist_id=$5 AND music_number >= (SELECT pm1.music_number FROM playlist_music pm1 WHERE pm1.user_id=$1 AND pm1.playlist_id=$2 AND pm1.music_id=$3)
            ORDER BY music_number
            LIMIT 2
          ),
          swap_transformation AS(
            SELECT s1.music_id, s2.music_number
            FROM swap_targets s1 INNER JOIN swap_targets s2 ON s1.music_id <> s2.music_id
          )
          UPDATE playlist_music
          SET music_number=swap_transformation.music_number
          FROM swap_transformation
          WHERE playlist_music.user_id=$6 AND playlist_music.playlist_id=$7 AND playlist_music.music_id=swap_transformation.music_id
        SQL
      else
        <<-SQL
          WITH swap_targets AS(
            SELECT pm2.music_id, pm2.music_number
            FROM playlist_music pm2
            WHERE user_id=$4 AND playlist_id=$5 AND music_number <= (SELECT pm1.music_number FROM playlist_music pm1 WHERE pm1.user_id=$1 AND pm1.playlist_id=$2 AND pm1.music_id=$3)
            ORDER BY music_number DESC
            LIMIT 2
          ),
          swap_transformation AS(
            SELECT s1.music_id, s2.music_number
            FROM swap_targets s1 INNER JOIN swap_targets s2 ON s1.music_id <> s2.music_id
          )
          UPDATE playlist_music
          SET music_number=swap_transformation.music_number
          FROM swap_transformation
          WHERE playlist_music.user_id=$6 AND playlist_music.playlist_id=$7 AND playlist_music.music_id=swap_transformation.music_id
        SQL
      end

      # Swap music tracks within the playlist
      result = @db.exec query, user_id, playlist_id, music_id, user_id, playlist_id, user_id, playlist_id

      # Check for any update errors
      if result.rows_affected == 2
        context.response.status = HTTP::Status::NO_CONTENT
      elsif contains_music_id(user_id, playlist_id, music_id)
        context.response.status = HTTP::Status::CONFLICT
        context.response.output << "Music position cannot be incremented/decremented further"
      else
        context.response.status = HTTP::Status::NOT_FOUND
        context.response.output << "Music not found within playlist"
      end
    else
      @db.transaction do |tx|
        # Alias transaction connection for convenience
        cnn = tx.connection

        # Get information about existing music numbers
        original_music_number = nil
        music_numbers = [] of Int32
        music_id_buffer = uninitialized UInt8[MUSIC_ID_LENGTH]
        music_id_slice = Bytes.new(music_id_buffer.to_unsafe, MUSIC_ID_LENGTH)
        cnn.query("SELECT music_id, music_number FROM playlist_music WHERE user_id=$1 AND playlist_id=$2 ORDER BY music_number", user_id, playlist_id) do |rs|
          rs.each do
            rs.read do |music_id_io, _|
              if original_music_number.nil?
                music_id_io.read_fully(music_id_slice)
                original_music_number = music_numbers.size if music_id_slice == music_id
              end
            end

            rs.read do |music_number_io, _|
              music_numbers << music_number_io.read_bytes(Int32, IO::ByteFormat::NetworkEndian)
            end
          end
        end

        # Check for any errors
        if music_number > music_numbers.size
          context.response.status = HTTP::Status::CONFLICT
          context.response.output << "Music number exceeds playlist length"
          return
        elsif original_music_number.nil?
          context.response.status = HTTP::Status::NOT_FOUND
          context.response.output << "Music not found within playlist"
          return
        end

        # If no change is needed return early
        if music_number == original_music_number
          context.response.status = HTTP::Status::NO_CONTENT
          return
        end

        # Renormalize music numbers if needed
        music_numbers_ptr = music_numbers.to_unsafe
        num_music_tracks = music_numbers.size
        renormalize_required = (music_number == 1 && Int32::MIN <= music_numbers_ptr[0] < Int32::MIN + 256) || (music_number == num_music_tracks && Int32::MAX - 256 < music_numbers_ptr[num_music_tracks - 1] <= Int32::MAX) || (music_numbers_ptr[music_number - 2] == music_numbers_ptr[music_number - 1] - 1)

        if renormalize_required
          query = <<-SQL
            WITH numbered_rows AS(
              SELECT music_id, ((ROW_NUMBER() OVER (ORDER BY music_number)) - 1) * 256 as new_music_number
              FROM playlist_music
              WHERE user_id=$1 AND playlist_id=$2
            )
            UPDATE playlist_music
            SET music_number=numbered_rows.new_music_number
            FROM numbered_rows
            WHERE user_id=$3 AND playlist_id=$4 AND playlist_music.music_id=numbered_rows.music_id
          SQL
          cnn.exec query, user_id, playlist_id, user_id, playlist_id

          num_music_tracks.times do |i|
            music_numbers_ptr[i] = i * 256
          end
        end

        # Set music number of selected music track to its chosen value
        new_music_number = if music_number == 1
          music_numbers_ptr[0] - 256
        elsif music_number == num_music_tracks
          music_numbers_ptr[num_music_tracks - 1] + 256
        else
          (music_numbers_ptr[music_number - 2] + music_numbers_ptr[music_number - 1]) >> 1
        end
        cnn.exec "UPDATE playlist_music SET music_number=$1 WHERE user_id=$2 AND playlist_id=$3 AND music_id=$4", new_music_number, user_id, playlist_id, music_id

        context.response.status = HTTP::Status::NO_CONTENT
      end
    end
  end

  # Deletes a playlist from the user's collection. Returns whether the deletion
  # was successful.
  #
  # ```
  # playlist_repository.delete("user_id", "playlist_id") # => true if the user originally had a playlist with the given playlist id
  # ```
  def delete(user_id : Bytes, playlist_id : Bytes) : Bool
    result = @db.exec "DELETE FROM playlists WHERE user_id=$1 AND playlist_id=$2", user_id, playlist_id

    result.rows_affected != 0
  end

  # Removes a music track from a playlist in the user's collection. Returns
  # whether the removal was successful
  #
  # ```
  # playlist_repository.remove_music("user_id", "playlist_id", "music_id") # => true if the user originally had "music_id" in their playlist with the given playlist id
  # ```
  def remove_music(user_id : Bytes, playlist_id : Bytes, music_id : Bytes) : Bool
    result = @db.exec "DELETE FROM playlist_music WHERE user_id=$1 AND playlist_id=$2 AND music_id=$3", user_id, playlist_id, music_id

    result.rows_affected != 0
  end
end
