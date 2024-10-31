require "json"

module Schemas::MusicSchemas
  # Request body schema for POST requests sent to /api/v1/users/music
  #
  # title and artist are expected to be not blank, and title is expected to
  # be a valid file name when used together with a .mp3 extension. file
  # is expected to be an mp3 file with size limits permitted by the user's
  # account type. These fields should be sent as form data.
  struct AddMusicRequest
    include JSON::Serializable

    getter title : String
    getter artist : String
    getter file : File

    def initialize(@title : String, @artist : String, @file : File)
    end
  end

  # Response body schema for server responses to /api/v1/users/music POST requests.
  #
  # Represents the music file entered into the database
  struct AddMusicResponse
    include JSON::Serializable

    def initialize(@music_id : String, @title : String, @artist : String)
    end
  end

  # Response body schema for server responses to /api/v1/users/music GET requests.
  #
  # Represents metadata for all music files in the user's collection
  struct GetMusicResponse
    include JSON::Serializable

    def initialize(@music : Array(MusicMetadata))
    end
  end

  # Represents metadata for a single music file in the user's collection
  struct MusicMetadata
    include JSON::Serializable

    def initialize(@music_id : String, @title : String, @artist : String)
    end
  end
end
