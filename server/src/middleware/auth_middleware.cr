require "http/server"
require "../utils/str"
require "../utils/token"
require "../utils/constants"

# Middleware for authenticating user requests made to a protected endpoint
class Middleware::AuthMiddleware
  include Utils::Constants

  def initialize(@auth_db : Redis::PooledClient, @API_SECRET : String)
  end

  # Retreives user id from the given HTTP server context.
  #
  # The user id is written to the provided buffer, which must be large enough to
  # store 49 bytes. If authentication fails for any reason this function returns
  # nil and writes a status code of 401 to the response header.
  #
  # ```
  # user_id_buffer = uninitialized UInt8[49]
  # user_id = @auth_middleware.get_user(context, user_id_buffer.to_unsafe)
  # ```
  def get_user(context : HTTP::Server::Context, user_id_buffer : UInt8*) : (Bytes | Nil)
    # Check that the authorization header is included
    auth_header = context.request.headers["Authorization"]?
    if auth_header.nil? || auth_header.size != EXPECTED_AUTH_HEADER_SIZE
      context.response.status = HTTP::Status::UNAUTHORIZED
      return
    end

    # Extract access token
    if !auth_header.starts_with?("Bearer ")
      context.response.status = HTTP::Status::UNAUTHORIZED
      return
    end
    access_token = auth_header.unsafe_byte_slice(7)

    # Check if the access token is black listed
    black_list_token_id_buffer = uninitialized UInt8[BLACK_LIST_TOKEN_ID_STRING_LENGTH]
    black_list_token_id = Utils::Str.stringify("black-list:", access_token, string_buffer: black_list_token_id_buffer.to_unsafe)
    if @auth_db.exists(black_list_token_id) == 1
      context.response.status = HTTP::Status::UNAUTHORIZED
      return
    end

    # Parse access token and get user id
    payload = Utils::Token.decode_access_token(access_token, @API_SECRET, user_id_buffer)
    if payload.nil?
      context.response.status = HTTP::Status::UNAUTHORIZED
      return
    end

    payload.user_id
  end
end
