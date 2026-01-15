
module Schemas::PlaylistSchemas
  # Request body schema for POST requests sent to /api/v1/users/playlists
  #
  # name is expected to be non-blank
  struct AddPlaylistRequest

    getter playlist_name : Bytes

    def initialize(@playlist_name : Bytes)
    end
  end

  # Request body schema for POST requests sent to /api/v1/users/playlists/{playlist_id}/music
  struct AddPlaylistMusicRequest

    getter music_id : Bytes

    def initialize(@music_id : Bytes)
    end
  end

  # Request body schema for UPDATE requests sent to /api/v1/users/playlists/{playlist_id}
  #
  # name is expected to be non-blank
  struct UpdatePlaylistRequest

    getter playlist_name : Bytes

    def initialize(@playlist_name : Bytes)
    end
  end

  # Request body schema for UPDATE requests sent to /api/v1/users/playlists/{playlist_id}/music/{music_id}
  #
  # music number is expected to be positive
  struct UpdatePlaylistMusicRequest

    getter music_number : Int32

    def initialize(@music_number : Int32)
    end
  end
end
