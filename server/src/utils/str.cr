
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
end
