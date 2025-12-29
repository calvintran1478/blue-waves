
module Utils::Str
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
  # string_bytes = "hello".to_slice
  #
  # my_string = Utils::Str.stringify(string_bytes, buffer.to_unsafe) # => "hello"
  # ```
  def stringify(value : Bytes, string_buffer : UInt8*) : String
    # Copy bytes over and terminate content with a null byte
    bytesize = value.bytesize
    string_buffer = string_buffer.as(String)
    buffer = string_buffer.to_unsafe
    buffer.copy_from(value.to_unsafe, bytesize)
    buffer[bytesize] = 0_u8

    # Initialize string header
    string_buffer.initialize_header(bytesize, bytesize)

    string_buffer
  end

  # Initializes the given buffer as a string with the provided bytesize
  #
  # This can be used to have the internal buffer of the string be allocated on
  # the stack instead of the heap, reducing pressure placed on the garbage
  # collector
  #
  # ```
  # require "../utils/env/str"
  #
  # buffer = uninitialized UInt8[18] # "hello".size + 1 + String::HEADER_SIZE
  # temp_buffer = buffer.as(String).to_unsafe
  # temp_buffer.copy_from("hello".to_unsafe, 5)
  #
  # my_string = Utils::Str.finalize_string(buffer.to_unsafe, 5)
  # ```
  def finalize_string(string_buffer : UInt8*, bytesize : Int32) : String
    string_buffer = string_buffer.as(String)
    string_buffer.to_unsafe[bytesize] = 0_u8
    string_buffer.initialize_header(bytesize, bytesize)

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
