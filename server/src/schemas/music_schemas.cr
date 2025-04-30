require "json"

module Schemas::MusicSchemas
  # Request body schema for POST requests sent to /api/v1/users/music
  #
  # title and artist are expected to be not blank, and title is expected to
  # be a valid file name when used together with a .mp3 extension. file
  # is expected to be an mp3 file with size limits permitted by the user's
  # account type. These fields should be sent as form data.
  struct AddMusicRequest

    getter title : String
    getter artist : String
    getter music_file : Bytes
    getter art_file : Bytes | Nil
    getter file_buffer : UInt8*

    def initialize(@title : String, @artist : String, @music_file : Bytes, @art_file : Bytes | Nil, @file_buffer : UInt8*)
    end
  end

  # Response body schema for server responses to /api/v1/users/music POST requests.
  #
  # Represents the music file entered into the database
  struct AddMusicResponse

    def initialize(@music_id : String, @title : String, @artist : String)
    end

    def to_s(io : IO) : Nil
      io << "{"
      io << "\"music_id\":\"" << @music_id << "\","
      io << "\"title\":\"" << @title << "\","
      io << "\"artist\":\"" << @artist << "\""
      io << "}"
    end
  end

  # Request body schema for PUT requests sent to /api/v1/users/music/{music_id}/cover-art
  #
  # The given file is expected to be a png or jpeg file, and should be sent as
  # form data.
  struct SetCoverArtRequest

    getter art_file : Bytes

    def initialize(@art_file : Bytes)
    end
  end

  # Request body schema for PATCH requests sent to /api/v1/users/music/{music_id}
  #
  # title is expected be non blank
  struct UpdateMusicRequest
    include JSON::Serializable

    getter title : String
    getter artist : String

    def initialize(@title : String, @artist : String)
    end
  end
end
