require "./constants"

module Utils::Str
  include Utils::Constants
  extend self

  # Concatenates the given sources of bytes into a string.
  #
  # The size of the string is set to be its bytesize.
  #
  # ```
  # require "../utils/env/str"
  #
  # Utils::Str.combine_bytes("abc", "d") # => "abcd"
  # ```
  def combine_bytes(*values : (Bytes | String)) : String
    # Calculate bytesize of the string
    bytesize = 0
    values.each do |arg|
      bytesize += arg.bytesize
    end

    # Copy bytes over from each source
    String.new(bytesize) do |buffer|
      values.each do |value|
        buffer.copy_from(value.to_unsafe, value.bytesize)
        buffer += value.bytesize
      end
      {bytesize, bytesize}
    end
  end

  # Initializes the given buffer as a string containing the same contents as the
  # provided bytes. The bytes are copied, leaving the original source unchanged
  #
  # This can be used to have the internal buffer of the string be allocated on
  # the stack instead of the heap, reducing pressure placed on the garbage
  # collector
  #
  # ```
  # require "../utils/env/str"
  #
  # buffer = uninitialized UInt8[18] # "hello".size + 1 + String::HEADER_SIZE
  # my_string = Utils::Str.stringify("hello".to_unsafe, buffer.to_unsafe, 5) # => "hello"
  # ```
  def stringify(src_buffer : UInt8*, string_buffer : UInt8*, size : Int32) : String
    # Copy bytes over and terminate content with a null byte
    string_buffer = string_buffer.as(String)
    buffer = string_buffer.to_unsafe
    buffer.copy_from(src_buffer, size)
    buffer[size] = 0_u8

    # Initialize string header
    string_buffer.initialize_header(size, size)

    string_buffer
  end

  # Initializes the given user id bytes as a string
  #
  # This can be used to have the internal buffer of the string be allocated on
  # the stack instead of the heap, reducing pressure placed on the garbage
  # collector
  #
  # ```
  # require "../utils/env/str"
  #
  # user_id_buffer = uninitialized UInt8[USER_ID_STRING_LENGTH]
  # temp_buffer = user_id_buffer.as(String).to_unsafe
  # temp_buffer.copy_from("<UUID>", USER_ID_LENGTH)
  #
  # user_id_str = Utils::Str.finalize_user_id(user_id_buffer.to_unsafe)
  # ```
  def finalize_user_id(user_id_buffer : UInt8*) : String
    string_buffer = (user_id_buffer - String::HEADER_SIZE).as(String)
    string_buffer.to_unsafe[USER_ID_LENGTH] = 0_u8
    string_buffer.initialize_header(USER_ID_LENGTH, USER_ID_LENGTH)

    string_buffer
  end

  # Initializes the given music id bytes as a string
  #
  # This can be used to have the internal buffer of the string be allocated on
  # the stack instead of the heap, reducing pressure placed on the garbage
  # collector
  #
  # ```
  # require "../utils/env/str"
  #
  # music_id_buffer = uninitialized UInt8[MUSIC_ID_STRING_LENGTH]
  # temp_buffer = music_id_buffer.as(String).to_unsafe
  # temp_buffer.copy_from("<MUSIC_ID>", MUSIC_ID_LENGTH)
  #
  # music_id_str = Utils::Str.finalize_music_id(music_id_buffer.to_unsafe)
  # ```
  def finalize_music_id(music_id_buffer : UInt8*) : String
    string_buffer = (music_id_buffer - String::HEADER_SIZE).as(String)
    string_buffer.to_unsafe[MUSIC_ID_LENGTH] = 0_u8
    string_buffer.initialize_header(MUSIC_ID_LENGTH, MUSIC_ID_LENGTH)

    string_buffer
  end

  # Initializes the given playlist id bytes as a string
  #
  # This can be used to have the internal buffer of the string be allocated on
  # the stack instead of the heap, reducing pressure placed on the garbage
  # collector
  #
  # ```
  # require "../utils/env/str"
  #
  # playlist_id_buffer = uninitialized UInt8[PLAYLIST_ID_STRING_LENGTH]
  # temp_buffer = playlist_id_buffer.as(String).to_unsafe
  # temp_buffer.copy_from("<PLAYLIST_ID>", PLAYLIST_ID_LENGTH)
  #
  # playlist_id_str = Utils::Str.finalize_playlist_id(playlist_id_buffer.to_unsafe)
  # ```
  def finalize_playlist_id(playlist_id_buffer : UInt8*) : String
    string_buffer = (playlist_id_buffer - String::HEADER_SIZE).as(String)
    string_buffer.to_unsafe[PLAYLIST_ID_LENGTH] = 0_u8
    string_buffer.initialize_header(PLAYLIST_ID_LENGTH, PLAYLIST_ID_LENGTH)

    string_buffer
  end

  # Initializes the given buffer as a string containing the same content as the
  # provided bytes/strings concatenated together. The bytes are copied, leaving
  # the original sources unchanged
  #
  # This can be used to have the internal buffer of the string be allocated on
  # the stack instead of the heap, reducing pressure placed on the garbage
  # collector
  #
  # ```
  # require "../utils/env/str"
  #
  # buffer = uninitialized UInt8[24] # "hello world".size + 1 + String::HEADER_SIZE
  # my_string = Utils::Str.stringify("hello", " ", "world", string_buffer: buffer.to_unsafe) # => "hello world"
  # ```
  def stringify(*values : (Bytes | String), string_buffer : UInt8*) : String
    # Copy bytes over and terminate content with a null byte
    string_buffer = string_buffer.as(String)
    buffer = string_buffer.to_unsafe
    curr_buffer = buffer
    bytesize = 0
    values.each do |value|
      curr_buffer.copy_from(value.to_unsafe, value.bytesize)
      bytesize += value.bytesize
      curr_buffer += value.bytesize
    end

    buffer[bytesize] = 0_u8

    # Initialize string header
    string_buffer.initialize_header(bytesize, bytesize)

    string_buffer
  end
end
