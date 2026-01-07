require "uuid"

module PG
  # :nodoc:
  module Decoders
    module Decoder
      abstract def decode(io, bytesize, oid)
      abstract def oids : Array(Int32)
      abstract def type

      macro def_oids(oids)
        OIDS = {{oids}}

        def oids : Array(Int32)
          OIDS
        end
      end
    end

    struct StringDecoder
      include Decoder

      def_oids [
        19,   # name (internal type)
        25,   # text
        142,  # xml
        705,  # unknown
        1042, # blchar
        1043, # varchar
      ]

      def decode(io, bytesize, oid)
        String.new(bytesize) do |buffer|
          io.read_fully(Slice.new(buffer, bytesize))
          {bytesize, 0}
        end
      end

      def type
        String
      end
    end

    struct UUIDDecoder
      include Decoder

      def_oids [
        2950, # UUID
      ]

      def decode(io, bytesize, oid)
        bytes = uninitialized UInt8[16]

        slice = Bytes.new(bytes.to_unsafe, 16)

        io.read_fully slice

        UUID.new(slice)
      end

      def type
        UUID
      end
    end

    struct BoolDecoder
      include Decoder

      OIDS = [
        16, # bool
      ]

      def decode(io, bytesize, oid)
        case byte = io.read_byte
        when 0
          false
        when 1
          true
        else
          raise "bad boolean decode: #{byte}"
        end
      end

      def oids : Array(Int32)
        OIDS
      end

      def type
        Bool
      end
    end

    @@decoders = Hash(Int32, PG::Decoders::Decoder).new

    def self.from_oid(oid)
      @@decoders[oid]
    end

    def self.register_decoder(decoder)
      decoder.oids.each do |oid|
        @@decoders[oid] = decoder
      end
    end

    # https://github.com/postgres/postgres/blob/master/src/include/catalog/pg_type.h
    register_decoder StringDecoder.new
    register_decoder UUIDDecoder.new
    register_decoder BoolDecoder.new
  end
end
