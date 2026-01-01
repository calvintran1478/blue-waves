
# Select functions from the Base64 module of the Crystal standard library
# modified to allow for direct encoding/decoding to and from a buffer/io without
# allocating intermediary strings
module Utils::Encoding
  extend self

  private CHARS_SAFE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
  private NL         = '\n'.ord.to_u8
  private NR         = '\r'.ord.to_u8

  def urlsafe_encode_int64(value : Int64, buffer : UInt8*) : Nil
    int_buffer = uninitialized UInt8[8]
    int_bytes = Bytes.new(int_buffer.to_unsafe, 8)
    IO::ByteFormat::NetworkEndian.encode(value, int_bytes)

    appender = buffer.appender
    to_base64(int_bytes) do |byte|
      appender << byte
    end
  end

  # Writes the base64-encoded version of *data* using a urlsafe alphabet to *io*.
  # This method complies with "Base 64 Encoding with URL and Filename Safe
  # Alphabet" in [RFC 4648](https://tools.ietf.org/html/rfc4648).
  #
  # The alphabet uses `'-'` instead of `'+'` and `'_'` instead of `'/'`.
  def urlsafe_encode(data : Bytes, io : IO) : Nil
    to_base64(data) do |byte|
      io << byte.unsafe_chr
    end
    io.flush
  end

  def urlsafe_encode(data : Bytes, buffer : UInt8*) : Bytes
    appender = buffer.appender
    to_base64(data) do |byte|
      appender << byte
    end
    appender.to_slice
  end

  private def to_base64(data : Bytes, &)
    bytes = CHARS_SAFE.to_unsafe
    size = data.size
    cstr = data.to_unsafe
    return if cstr.null? || size == 0
    endcstr = cstr + size - size % 3 - 3

    # process bunch of full triples
    while cstr < endcstr
      n = cstr.as(UInt32*).value.byte_swap
      yield bytes[(n >> 26) & 63]
      yield bytes[(n >> 20) & 63]
      yield bytes[(n >> 14) & 63]
      yield bytes[(n >> 8) & 63]
      cstr += 3
    end

    # process last full triple manually, because reading UInt32 not correct for guarded memory
    if size >= 3
      n = (cstr.value.to_u32 << 16) | ((cstr + 1).value.to_u32 << 8) | (cstr + 2).value
      yield bytes[(n >> 18) & 63]
      yield bytes[(n >> 12) & 63]
      yield bytes[(n >> 6) & 63]
      yield bytes[(n) & 63]
      cstr += 3
    end

    # process last partial triple
    pd = size % 3
    if pd == 1
      n = (cstr.value.to_u32 << 16)
      yield bytes[(n >> 18) & 63]
      yield bytes[(n >> 12) & 63]
    elsif pd == 2
      n = (cstr.value.to_u32 << 16) | ((cstr + 1).value.to_u32 << 8)
      yield bytes[(n >> 18) & 63]
      yield bytes[(n >> 12) & 63]
      yield bytes[(n >> 6) & 63]
    end
  end

  def decode_int64(data : UInt8*) : Int64
    buffer = uninitialized UInt8[8]
    appender = buffer.to_unsafe.appender
    int64_from_base64(data) { |byte| appender << byte }

    IO::ByteFormat::NetworkEndian.decode(Int64, buffer.to_slice)
  end

  # Processes the given data and yields each byte.
  private def int64_from_base64(data : UInt8*, &block : UInt8 -> Nil)
    size = 11
    bytes = data
    bytes_begin = bytes

    # Get the position of the last valid base64 character (rstrip '\n', '\r' and '=')
    while (size > 0) && (sym = bytes[size - 1]) && sym.in?(NL, NR)
      size -= 1
    end

    # Process combinations of four characters until there aren't any left
    fin = bytes + size - 4
    while true
      break if bytes > fin

      # Move the pointer by one byte until there is a valid base64 character
      while bytes.value.in?(NL, NR)
        bytes += 1
      end
      break if bytes > fin

      yield_decoded_chunk_bytes(bytes[0], bytes[1], bytes[2], bytes[3], chunk_pos: bytes - bytes_begin)
      bytes += 4
    end

    # Move the pointer by one byte until there is a valid base64 character or the end of `bytes` was reached
    while (bytes < fin + 4) && bytes.value.in?(NL, NR)
      bytes += 1
    end

    # If the amount of base64 characters is not divisible by 4, the remainder of the previous loop is handled here
    unread_bytes = (fin - bytes) % 4
    case unread_bytes
    when 1
      raise Base64::Error.new("Wrong size")
    when 2
      yield_decoded_chunk_bytes(bytes[0], bytes[1], chunk_pos: bytes - bytes_begin)
    when 3
      yield_decoded_chunk_bytes(bytes[0], bytes[1], bytes[2], chunk_pos: bytes - bytes_begin)
    end
  end

  # This macro decodes the given chunk of (2-4) base64 characters.
  # The argument chunk_pos is only used for the resulting error message.
  # The resulting bytes are then each yielded.
  private macro yield_decoded_chunk_bytes(*bytes, chunk_pos)
    %buffer = 0_u32
    {% for byte, i in bytes %}
      %decoded = DECODE_TABLE.unsafe_fetch({{byte}})
      %buffer = (%buffer << 6) + %decoded
      raise Base64::Error.new("Unexpected byte 0x#{{{byte}}.to_s(16)} at #{{{chunk_pos}} + {{i}}}") if %decoded == 255_u8
    {% end %}

    # Each byte in the buffer is shifted to rightmost position of the buffer, then casted to a UInt8
    {% for i in 2..(bytes.size) %}
      yield (%buffer >> {{ (4 - bytes.size) * 2 + (8 * (bytes.size - i)) }}).to_u8!
    {% end %}
  end

  private DECODE_TABLE = Array(UInt8).new(size: 256) do |i|
    case i.unsafe_chr
    when 'A'..'Z' then (i - 0x41).to_u8!
    when 'a'..'z' then (i - 0x47).to_u8!
    when '0'..'9' then (i + 0x04).to_u8!
    when '+', '-' then 0x3E_u8
    when '/', '_' then 0x3F_u8
    else               255_u8
    end
  end
end
