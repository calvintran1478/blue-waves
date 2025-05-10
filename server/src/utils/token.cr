
module Utils::Token
  extend self

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
    encoded_payload = Base64.urlsafe_encode(payload.to_json, false)
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
