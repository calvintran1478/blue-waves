
module Utils::JWT
  extend self

  EXPECTED_JWT_HEADER = "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9".to_slice # Base64 encoding of {"typ":"JWT","alg":"HS256"}

  struct AccessClaims
    include JSON::Serializable

    getter user_id : String
    getter exp : Int64

    def initialize(@user_id : String, @exp : Int64)
    end
  end

  struct RefreshClaims
    include JSON::Serializable

    getter user_id : String
    getter token_family_id : String
    getter sequence_number : Int32
    getter exp : Int64

    def initialize(@user_id : String, @token_family_id : String, @sequence_number : Int32, @exp : Int64)
    end
  end

  def encode(payload : (AccessClaims | RefreshClaims), key : String) : String
    verify_data = "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9." + Base64.urlsafe_encode(payload.to_json, false)
    encoded_signature = Base64.urlsafe_encode(OpenSSL::HMAC.digest(:sha256, key, verify_data), false)
    "#{verify_data}.#{encoded_signature}"
  end

  def decode(token : Bytes, key : String, token_type : Symbol) : (AccessClaims | RefreshClaims | Nil)
    # Parse token into its three segments
    first_dot_ptr = LibC.memchr(token.to_unsafe, '.'.ord, token.size).as(UInt8*)
    return if first_dot_ptr.null?

    encoded_header = Bytes.new(token.to_unsafe, first_dot_ptr - token.to_unsafe)
    return if encoded_header != EXPECTED_JWT_HEADER

    second_dot_ptr = LibC.memchr(token.to_unsafe + encoded_header.size + 1, '.'.ord, token.size - encoded_header.size - 1).as(UInt8*)
    return if second_dot_ptr.null?

    encoded_payload = Bytes.new(first_dot_ptr + 1, second_dot_ptr - (first_dot_ptr + 1))
    encoded_signature = Bytes.new(second_dot_ptr + 1, token.size - (encoded_header.size + encoded_payload.size + 2))

    # Verify signature
    verify_data = Bytes.new(token.to_unsafe, second_dot_ptr - token.to_unsafe)
    expected_encoded_signature = Base64.urlsafe_encode(OpenSSL::HMAC.digest(:sha256, key, verify_data), false)
    unless Crypto::Subtle.constant_time_compare(encoded_signature, expected_encoded_signature)
      return
    end

    # Decode payload claims
    begin
      payload_json = Base64.decode_string(encoded_payload)

      case token_type
      when :access_token  then payload = AccessClaims.from_json(payload_json)
      when :refresh_token then payload = RefreshClaims.from_json(payload_json)
      else return
      end
    rescue ex : Base64::Error | JSON::ParseException
      return
    end

    # Validate payload
    return if payload.exp < Time.utc.to_unix

    payload
  end
end
