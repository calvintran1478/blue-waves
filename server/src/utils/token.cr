require "./str"

module Utils::Token
  extend self

  UUID_LENGTH = 36
  ACCESS_CLAIMS_SIZE = 44
  REFRESH_CLAIMS_SIZE = 84
  CLAIMS_BUFFER_SIZE = 84

  struct AccessClaims
    getter user_id : String
    getter exp : Int64

    def initialize(@user_id : String, @exp : Int64)
    end

    def to_bytes(buffer : UInt8*) : Bytes
      buffer.copy_from(@user_id.to_unsafe, @user_id.bytesize)
      IO::ByteFormat::NetworkEndian.encode(@exp, Bytes.new(buffer + @user_id.bytesize, sizeof(Int64)))

      Bytes.new(buffer, ACCESS_CLAIMS_SIZE)
    end

    def AccessClaims.from_bytes(bytes : Bytes) : (AccessClaims | Nil)
      return if bytes.size != ACCESS_CLAIMS_SIZE
      user_id = String.new(Bytes.new(bytes.to_unsafe, UUID_LENGTH))
      exp = IO::ByteFormat::NetworkEndian.decode(Int64, Bytes.new(bytes.to_unsafe + UUID_LENGTH, sizeof(Int64)))

      AccessClaims.new(user_id, exp)
    end
  end

  struct RefreshClaims
    getter user_id : String
    getter token_family_id : String
    getter sequence_number : Int32
    getter exp : Int64

    def initialize(@user_id : String, @token_family_id : String, @sequence_number : Int32, @exp : Int64)
    end

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

    def RefreshClaims.from_bytes(bytes : Bytes) : (RefreshClaims | Nil)
      return if bytes.size != REFRESH_CLAIMS_SIZE
      curr_buffer = bytes.to_unsafe

      user_id = String.new(Bytes.new(curr_buffer, UUID_LENGTH))
      curr_buffer += UUID_LENGTH

      token_family_id = String.new(Bytes.new(curr_buffer, UUID_LENGTH))
      curr_buffer += UUID_LENGTH

      sequence_number = IO::ByteFormat::NetworkEndian.decode(Int32, Bytes.new(curr_buffer, sizeof(Int32)))
      curr_buffer += sizeof(Int32)

      exp = IO::ByteFormat::NetworkEndian.decode(Int64, Bytes.new(curr_buffer, sizeof(Int64)))

      RefreshClaims.new(user_id, token_family_id, sequence_number, exp)
    end
  end

  def encode(payload : (AccessClaims | RefreshClaims), key : String) : String
    buffer = uninitialized UInt8[CLAIMS_BUFFER_SIZE]
    encoded_payload = Base64.urlsafe_encode(payload.to_bytes(buffer.to_unsafe), false)
    encoded_signature = Base64.urlsafe_encode(OpenSSL::HMAC.digest(:sha256, key, encoded_payload), false)
    "#{encoded_payload}.#{encoded_signature}"
  end

  def decode(token : Bytes, key : String, token_type : Symbol) : (AccessClaims | RefreshClaims | Nil)
    # Parse token into its two segments
    dot_ptr = LibC.memchr(token.to_unsafe, '.'.ord, token.size).as(UInt8*)
    return if dot_ptr.null?

    encoded_payload = Bytes.new(token.to_unsafe, dot_ptr - token.to_unsafe)
    encoded_signature = Bytes.new(dot_ptr + 1, token.size - encoded_payload.size - 1)

    # Verify signature
    expected_encoded_signature = Base64.urlsafe_encode(OpenSSL::HMAC.digest(:sha256, key, encoded_payload), false)
    return if !Crypto::Subtle.constant_time_compare(encoded_signature, expected_encoded_signature)

    # Decode payload claims
    decoded_payload = Base64.decode(encoded_payload) rescue nil
    return if decoded_payload.nil?

    case token_type
    when :access_token  then payload = AccessClaims.from_bytes(decoded_payload)
    when :refresh_token then payload = RefreshClaims.from_bytes(decoded_payload)
    else return
    end

    return if payload.nil?

    # Validate payload
    return if payload.exp < Time.utc.to_unix

    payload
  end
end
