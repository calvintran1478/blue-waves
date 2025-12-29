require "./str"
require "./constants"

module Utils::Token
  include Utils::Constants
  extend self

  # Claims stored within an access token
  struct AccessClaims
    getter user_id : Bytes
    getter exp : Int64

    def initialize(@user_id : Bytes, @exp : Int64)
    end

    # Writes the contents of these claims to the given buffer and returns the
    # result as a slice of 44 bytes
    #
    # The provided buffer must be large enough to store 44 bytes
    def to_bytes(buffer : UInt8*) : Bytes
      buffer.copy_from(@user_id.to_unsafe, @user_id.bytesize)
      IO::ByteFormat::NetworkEndian.encode(@exp, Bytes.new(buffer + @user_id.bytesize, sizeof(Int64)))

      Bytes.new(buffer, ACCESS_CLAIMS_SIZE)
    end

    # Creates access claims from the given slice of bytes
    #
    # The first 36 bytes should be the UUID of the user and the next 8 bytes
    # should be the network-endian encoded expiration timestamp as an Int64
    #
    # The string contents of the user id is written to the provided user id
    # buffer, which must be large enough to store 49 bytes
    def AccessClaims.from_bytes(bytes : Bytes, user_id_buffer : UInt8*) : AccessClaims
      user_id = Bytes.new(user_id_buffer.as(String).to_unsafe, USER_ID_LENGTH)
      user_id.to_unsafe.copy_from(bytes.to_unsafe, USER_ID_LENGTH)
      exp = IO::ByteFormat::NetworkEndian.decode(Int64, Bytes.new(bytes.to_unsafe + USER_ID_LENGTH, sizeof(Int64)))

      AccessClaims.new(user_id, exp)
    end
  end

  # Claims stored within a refresh token
  struct RefreshClaims
    getter user_id : String
    getter token_family_id : String
    getter sequence_number : Int32
    getter exp : Int64

    def initialize(@user_id : String, @token_family_id : String, @sequence_number : Int32, @exp : Int64)
    end

    # Writes the contents of these claims to the given buffer and returns the
    # result as a slice of 84 bytes
    #
    # The provided buffer must be large enough to store 84 bytes
    def to_bytes(buffer : UInt8*) : Bytes
      curr_buffer = buffer

      curr_buffer.copy_from(@user_id.to_unsafe, @user_id.bytesize)
      curr_buffer += @user_id.bytesize

      curr_buffer.copy_from(@token_family_id.to_unsafe, @token_family_id.bytesize)
      curr_buffer += @token_family_id.bytesize

      IO::ByteFormat::NetworkEndian.encode(@sequence_number, Bytes.new(curr_buffer, sizeof(Int32)))
      curr_buffer += sizeof(Int32)

      IO::ByteFormat::NetworkEndian.encode(@exp, Bytes.new(curr_buffer, sizeof(Int64)))

      Bytes.new(buffer, REFRESH_CLAIMS_SIZE)
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
    def RefreshClaims.from_bytes(bytes : Bytes, user_id_buffer : UInt8*, token_family_id_buffer : UInt8*) : RefreshClaims
      curr_buffer = bytes.to_unsafe

      user_id = Utils::Str.stringify(Bytes.new(curr_buffer, USER_ID_LENGTH), user_id_buffer)
      curr_buffer += USER_ID_LENGTH

      token_family_id = Utils::Str.stringify(Bytes.new(curr_buffer, TOKEN_FAMILY_ID_LENGTH), token_family_id_buffer)
      curr_buffer += TOKEN_FAMILY_ID_LENGTH

      sequence_number = IO::ByteFormat::NetworkEndian.decode(Int32, Bytes.new(curr_buffer, sizeof(Int32)))
      curr_buffer += sizeof(Int32)

      exp = IO::ByteFormat::NetworkEndian.decode(Int64, Bytes.new(curr_buffer, sizeof(Int64)))

      RefreshClaims.new(user_id, token_family_id, sequence_number, exp)
    end
  end

  # Creates an access token from the provided access claims, which are signed
  # using the provided key
  #
  # The contents of the token are written to the given IO
  def encode_access_token(payload : AccessClaims, key : String, io : IO) : Nil
    buffer = uninitialized UInt8[ACCESS_CLAIMS_SIZE]
    encoded_payload = Base64.urlsafe_encode(payload.to_bytes(buffer.to_unsafe), false)
    encoded_signature = Base64.urlsafe_encode(OpenSSL::HMAC.digest(:sha256, key, encoded_payload), false)

    io << encoded_payload
    io << encoded_signature
  end

  # Creates a refresh token from the provided refresh claims, which are signed
  # using the provided key
  #
  # The contents of the token are returned as a string
  def encode_refresh_token(payload : RefreshClaims, key : String) : String
    buffer = uninitialized UInt8[REFRESH_CLAIMS_SIZE]
    encoded_payload = Base64.urlsafe_encode(payload.to_bytes(buffer.to_unsafe), false)
    encoded_signature = Base64.urlsafe_encode(OpenSSL::HMAC.digest(:sha256, key, encoded_payload), false)

    encoded_payload + encoded_signature
  end

  # Parses the provided access token for its contents
  #
  # Upon success this returns the access claims of the token. Otherwise this
  # function returns nil
  def decode_access_token(token : Bytes, key : String, user_id_buffer : UInt8*) : (AccessClaims | Nil)
    # Parse token into its two segments
    encoded_payload = Bytes.new(token.to_unsafe, 59)
    encoded_signature = Bytes.new(token.to_unsafe + 59, 43)

    # Verify signature
    expected_encoded_signature = Base64.urlsafe_encode(OpenSSL::HMAC.digest(:sha256, key, encoded_payload), false)
    return if !Crypto::Subtle.constant_time_compare(encoded_signature, expected_encoded_signature)

    # Decode payload claims
    decoded_payload = Base64.decode(encoded_payload) rescue nil
    return if decoded_payload.nil?

    payload = AccessClaims.from_bytes(decoded_payload, user_id_buffer)

    # Validate payload
    return if payload.exp < Time.utc.to_unix

    payload
  end

  # Parses the provided refresh token for its contents
  #
  # Upon success this returns the refresh claims of the token. Otherwise this
  # function returns nil
  def decode_refresh_token(token : Bytes, key : String, user_id_buffer : UInt8*, token_family_id_buffer : UInt8*) : (RefreshClaims | Nil)
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

    payload = RefreshClaims.from_bytes(decoded_payload, user_id_buffer, token_family_id_buffer)

    # Validate payload
    return if payload.exp < Time.utc.to_unix

    payload
  end
end
