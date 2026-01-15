
module Schemas::MusicSchemas
  # Request body schema for POST requests sent to /api/v1/users/music
  #
  # title and artist are expected to be not blank, and title is expected to
  # be a valid file name when used together with a .mp3 extension. file
  # is expected to be an mp3 file with size limits permitted by the user's
  # account type. These fields should be sent as form data.
  struct AddMusicRequest

    getter title : Bytes
    getter artist : Bytes
    getter music_file : Bytes
    getter art_file : Bytes | Nil
    getter music_file_type : String
    getter art_file_type : String | Nil
    getter file_buffer : UInt8*

    def initialize(@title : Bytes, @artist : Bytes, @music_file : Bytes, @art_file : Bytes | Nil, @music_file_type : String, @art_file_type : String | Nil, @file_buffer : UInt8*)
    end
  end

  # Request body schema for PUT requests sent to /api/v1/users/music/{music_id}/cover-art
  #
  # The given file is expected to be a png or jpeg file, and should be sent as
  # form data.
  struct SetCoverArtRequest

    getter art_file : Bytes
    getter art_file_type : String

    def initialize(@art_file : Bytes, @art_file_type : String)
    end
  end

  # Request body schema for PATCH requests sent to /api/v1/users/music/{music_id}
  #
  # title is expected be non blank
  struct UpdateMusicRequest

    getter title : Bytes
    getter artist : Bytes

    def initialize(@title : Bytes, @artist : Bytes)
    end
  end
end
