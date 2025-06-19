
module Schemas::PlaylistSchemas
  # Request body schema for POST requests sent to /api/v1/users/playlists
  #
  # name is expected to be non-blank
  struct AddPlaylistRequest

    getter playlist_name : String

    def initialize(@playlist_name : String)
    end
  end

  # Request body schema for UPDATE requests sent to /api/v1/users/playlists/{playlist_id}
  #
  # name is expected to be non-blank
  struct UpdatePlaylistRequest

    getter playlist_name : String

    def initialize(@playlist_name : String)
    end
  end
end
