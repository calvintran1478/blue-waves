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

      # Write signature and encoded payload to the provided IO
      Utils::Encoding.urlsafe_encode(OpenSSL::HMAC.digest(:sha256, key, encoded_payload), io)
      io.write(encoded_payload)
    end

    # Parses the provided access token for its contents
    #
    # Upon success this returns the expiration time of the token and writes the
    # user id to given buffer. Otherwise this function returns nil
    def AccessClaims.decode(token : UInt8*, key : String) : (Int64 | Nil)
      # Parse token into its two segments
      encoded_signature = Bytes.new(token, 43)
      encoded_payload = Bytes.new(token + 43, 47)

      # Verify signature
      expected_signature_buffer = uninitialized UInt8[43]
      expected_encoded_signature = Utils::Encoding.urlsafe_encode(OpenSSL::HMAC.digest(:sha256, key, encoded_payload), expected_signature_buffer.to_unsafe)
      return if !Crypto::Subtle.constant_time_compare(encoded_signature, expected_encoded_signature)

      # Validate payload
      exp = Utils::Encoding.decode_int64(encoded_payload.to_unsafe + USER_ID_LENGTH)
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

    # Creates a refresh token from the provided refresh claims, which are signed
    # using the provided key
    #
    # The contents of the token are returned as a string
    def encode(key : String) : String
      bytesize = 132
      String.new(bytesize) do |buffer|
        curr_buffer = buffer

        # Encode payload
        curr_buffer.copy_from(@user_id, USER_ID_LENGTH)
        curr_buffer += USER_ID_LENGTH
        curr_buffer.copy_from(@token_family_id.to_unsafe, TOKEN_FAMILY_ID_LENGTH)
        curr_buffer += TOKEN_FAMILY_ID_LENGTH
        Utils::Encoding.urlsafe_encode_int32(@sequence_number, curr_buffer)
        curr_buffer += 6
        Utils::Encoding.urlsafe_encode_int64(@exp, curr_buffer)
        curr_buffer += 11

        # Encode signature
        encoded_payload = Bytes.new(buffer, 89)
        Utils::Encoding.urlsafe_encode(OpenSSL::HMAC.digest(:sha256, key, encoded_payload), curr_buffer)

        {bytesize, bytesize}
      end
    end

    # Parses the provided refresh token for its contents
    #
    # Upon success this returns the refresh claims of the token. Otherwise this
    # function returns nil
    def RefreshClaims.decode(token : UInt8*, key : String, user_id_buffer : UInt8*, token_family_id_buffer : UInt8*) : (RefreshClaims | Nil)
      # Parse token into its two segments
      encoded_payload = Bytes.new(token, 89)
      encoded_signature = Bytes.new(token + 89, 43)

      # Verify signature
      expected_signature_buffer = uninitialized UInt8[43]
      expected_encoded_signature = Utils::Encoding.urlsafe_encode(OpenSSL::HMAC.digest(:sha256, key, encoded_payload), expected_signature_buffer.to_unsafe)
      return if !Crypto::Subtle.constant_time_compare(encoded_signature, expected_encoded_signature)

      # Decode payload claims
      curr_buffer = encoded_payload.to_unsafe

      user_id_buffer.as(String).to_unsafe.copy_from(curr_buffer, USER_ID_LENGTH)
      curr_buffer += USER_ID_LENGTH

      token_family_id = Utils::Str.stringify(curr_buffer, token_family_id_buffer, TOKEN_FAMILY_ID_LENGTH)
      curr_buffer += TOKEN_FAMILY_ID_LENGTH

      sequence_number = Utils::Encoding.decode_int32(curr_buffer)
      curr_buffer += 6

      exp = Utils::Encoding.decode_int64(curr_buffer)

      # Validate payload
      return if exp < Time.utc.to_unix

      RefreshClaims.new(user_id_buffer, token_family_id, sequence_number, exp)
    end
  end
end
