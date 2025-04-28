
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
  # stack instead of the heap, reducing pressure placed on the garbage collector
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
    buffer = string_buffer.as(String).to_unsafe
    bytesize = value.bytesize
    buffer.copy_from(value.to_unsafe, bytesize)
    buffer[bytesize] = 0_u8

    # Initialize string header
    string_buffer = string_buffer.as(String)
    string_buffer.initialize_header(bytesize, bytesize)

    string_buffer
  end
end
