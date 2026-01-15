struct Char
  struct ByteReader
    include Enumerable(Char)

    getter bytes : Bytes
    getter current_char : Char
    getter current_char_width : Int32
    getter pos : Int32
    getter error : UInt8?

    def initialize(@bytes : Bytes)
      @pos = 0
      @current_char = '\0'
      @current_char_width = 0
      decode_current_char
    end

    def has_next? : Bool
      @pos < @bytes.bytesize
    end

    def each(&) : Nil
      while has_next?
        yield current_char

        @pos += @current_char_width
        decode_current_char
      end
    end

    private def decode_char_at(pos, & : UInt32, Int32, UInt8? ->)
      first = byte_at(pos)
      if first < 0x80
        return yield first, 1, nil
      end

      if first < 0xc2
        invalid_byte_sequence
      end

      second = byte_at(pos + 1)
      if (second & 0xc0) != 0x80
        invalid_byte_sequence
      end

      if first < 0xe0
        return yield (first << 6) &+ (second &- 0x3080), 2, nil
      end

      third = byte_at(pos + 2)
      if (third & 0xc0) != 0x80
        invalid_byte_sequence
      end

      if first < 0xf0
        if first == 0xe0 && second < 0xa0
          invalid_byte_sequence
        end

        if first == 0xed && second >= 0xa0
          invalid_byte_sequence
        end

        return yield (first << 12) &+ (second << 6) &+ (third &- 0xE2080), 3, nil
      end

      if first == 0xf0 && second < 0x90
        invalid_byte_sequence
      end

      if first == 0xf4 && second >= 0x90
        invalid_byte_sequence
      end

      fourth = byte_at(pos + 3)
      if (fourth & 0xc0) != 0x80
        invalid_byte_sequence
      end

      if first < 0xf5
        return yield (first << 18) &+ (second << 12) &+ (third << 6) &+ (fourth &- 0x3C82080), 4, nil
      end

      invalid_byte_sequence
    end

    private macro invalid_byte_sequence
      return yield Char::REPLACEMENT.ord.to_u32!, 1, first.to_u8!
    end

    @[AlwaysInline]
    private def decode_current_char
      decode_char_at(@pos) do |code_point, width, error|
        @current_char_width = width
        @error = error
        @current_char = code_point.unsafe_chr
      end
    end

    private def byte_at(i)
      @bytes.to_unsafe[i].to_u32
    end
  end
end
