require "./str"
require "./constants"
require "./encoding"

module Utils::Token
  include Utils::Constants
  extend self

  # Claims stored within an access token
  struct AccessClaims
    getter user_id : Pointer(UInt8)
    getter exp : Int64

    # Default access claims constructor
    def initialize(@user_id : Pointer(UInt8), @exp : Int64)
    end

    # Creates an access token from self, which is signed using the provided key
    #
    # The contents of the token are written to the given IO
    def encode(key : String, io : IO) : Nil
      # Create encoded payload
      buffer = uninitialized UInt8[47]
      buffer.to_unsafe.copy_from(@user_id, USER_ID_LENGTH)
      Utils::Encoding.urlsafe_encode_int64(@exp, buffer.to_unsafe + USER_ID_LENGTH)
      encoded_payload = Bytes.new(buffer.to_unsafe, 47)

      # Write encoded payload and signature to the provided io
      io.write(encoded_payload)
      Utils::Encoding.urlsafe_encode(OpenSSL::HMAC.digest(:sha256, key, encoded_payload), io)
    end

    # Parses the provided access token for its contents
    #
    # Upon success this returns the expiration time of the token and writes the
    # user id to given buffer. Otherwise this function returns nil
    def AccessClaims.decode(token : Bytes, key : String, user_id_buffer : UInt8*) : (Int64 | Nil)
      # Parse token into its two segments
      encoded_payload = Bytes.new(token.to_unsafe, 47)
      encoded_signature = Bytes.new(token.to_unsafe + 47, 43)

      # Verify signature
      expected_signature_buffer = uninitialized UInt8[43]
      expected_encoded_signature = Utils::Encoding.urlsafe_encode(OpenSSL::HMAC.digest(:sha256, key, encoded_payload), expected_signature_buffer.to_unsafe)
      return if !Crypto::Subtle.constant_time_compare(encoded_signature, expected_encoded_signature)

      # Decode payload claims
      user_id_buffer.as(String).to_unsafe.copy_from(encoded_payload.to_unsafe, USER_ID_LENGTH)
      exp = Utils::Encoding.decode_int64(encoded_payload.to_unsafe + USER_ID_LENGTH)

      # Validate payload
      return if exp < Time.utc.to_unix

      exp
    end
  end

  # Claims stored within a refresh token
  struct RefreshClaims
    getter user_id : Pointer(UInt8)
    getter token_family_id : String
    getter sequence_number : Int32
    getter exp : Int64

    # Default refresh claims constructor
    def initialize(@user_id : Pointer(UInt8), @token_family_id : String, @sequence_number : Int32, @exp : Int64)
    end

    # Creates refresh claims from the given slice of bytes
    #
    # The first 36 bytes should be the UUID of the user and the next 36 bytes
    # should be a UUID describing the token family id. The next 4 bytes after
    # this should be the sequence number as a network-endian encoded Int32, and
    # the last 8 bytes should be the expiration timestamp as a network-endian
    # encoded Int64
    #
    # The string contents of the user id and token family id are written to the
    # provided buffers, which must be large enough to store 49 bytes each
    def initialize(bytes : Bytes, user_id_buffer : UInt8*, token_family_id_buffer : UInt8*)
      curr_buffer = bytes.to_unsafe

      @user_id = user_id_buffer.as(String).to_unsafe
      user_id.copy_from(curr_buffer, USER_ID_LENGTH)
      curr_buffer += USER_ID_LENGTH

      @token_family_id = Utils::Str.stringify(curr_buffer, token_family_id_buffer, TOKEN_FAMILY_ID_LENGTH)
      curr_buffer += TOKEN_FAMILY_ID_LENGTH

      @sequence_number = IO::ByteFormat::NetworkEndian.decode(Int32, Bytes.new(curr_buffer, sizeof(Int32)))
      curr_buffer += sizeof(Int32)

      @exp = IO::ByteFormat::NetworkEndian.decode(Int64, Bytes.new(curr_buffer, sizeof(Int64)))
    end

    # Writes the contents of these claims to the given buffer and returns the
    # result as a slice of 84 bytes
    #
    # The provided buffer must be large enough to store 84 bytes
    private def to_bytes(buffer : UInt8*) : Bytes
      curr_buffer = buffer

      curr_buffer.copy_from(@user_id, USER_ID_LENGTH)
      curr_buffer += USER_ID_LENGTH

      curr_buffer.copy_from(@token_family_id.to_unsafe, TOKEN_FAMILY_ID_LENGTH)
      curr_buffer += TOKEN_FAMILY_ID_LENGTH

      IO::ByteFormat::NetworkEndian.encode(@sequence_number, Bytes.new(curr_buffer, sizeof(Int32)))
      curr_buffer += sizeof(Int32)

      IO::ByteFormat::NetworkEndian.encode(@exp, Bytes.new(curr_buffer, sizeof(Int64)))

      Bytes.new(buffer, REFRESH_CLAIMS_SIZE)
    end

    # Creates a refresh token from the provided refresh claims, which are signed
    # using the provided key
    #
    # The contents of the token are returned as a string
    def encode(key : String) : String
      buffer = uninitialized UInt8[REFRESH_CLAIMS_SIZE]
      encoded_payload = Base64.urlsafe_encode(self.to_bytes(buffer.to_unsafe), false)
      encoded_signature = Base64.urlsafe_encode(OpenSSL::HMAC.digest(:sha256, key, encoded_payload), false)

      encoded_payload + encoded_signature
    end

    # Parses the provided refresh token for its contents
    #
    # Upon success this returns the refresh claims of the token. Otherwise this
    # function returns nil
    def RefreshClaims.decode(token : String, key : String, user_id_buffer : UInt8*, token_family_id_buffer : UInt8*) : (RefreshClaims | Nil)
      # Parse token into its two segments
      return if token.size != 155
      encoded_payload = Bytes.new(token.to_unsafe, 112)
      encoded_signature = Bytes.new(token.to_unsafe + 112, 43)

      # Verify signature
      expected_encoded_signature = Base64.urlsafe_encode(OpenSSL::HMAC.digest(:sha256, key, encoded_payload), false)
      return if !Crypto::Subtle.constant_time_compare(encoded_signature, expected_encoded_signature)

      # Decode payload claims
      decoded_payload = Base64.decode(encoded_payload) rescue nil
      return if decoded_payload.nil?

      payload = RefreshClaims.new(decoded_payload, user_id_buffer, token_family_id_buffer)

      # Validate payload
      return if payload.exp < Time.utc.to_unix

      payload
    end
  end
end
