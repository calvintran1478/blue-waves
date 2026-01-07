require "http/server"
require "../utils/str"
require "../utils/token"
require "../utils/constants"

# Middleware for authenticating user requests made to a protected endpoint
class Middleware::AuthMiddleware
  include Utils::Constants

  def initialize(@auth_db : Redis::PooledClient, @API_SECRET : String)
  end

  # Retreives the user id from the given HTTP server context
  #
  # The user id is described by the 36 bytes addressed by the returned pointer.
  # If authentication fails for any reason this function returns nil and writes
  # a status code of 401 to the response header.
  #
  # ```
  # user_id = @auth_middleware.get_user(context)
  # ```
  def get_user(context : HTTP::Server::Context) : (UInt8* | Nil)
    # Check that the authorization header is included
    auth_header = context.request.headers["Authorization"]?
    if auth_header.nil? || auth_header.size != EXPECTED_AUTH_HEADER_SIZE
      context.response.status = HTTP::Status::UNAUTHORIZED
      return
    end

    # Extract access token
    auth_header_ptr = auth_header.to_unsafe
    if auth_header_ptr.memcmp("Bearer ".to_unsafe, 7) != 0
      context.response.status = HTTP::Status::UNAUTHORIZED
      return
    end
    access_token_ptr = auth_header_ptr + 7

    # Parse access token and get user id
    if Utils::Token::AccessClaims.decode(access_token_ptr, @API_SECRET).nil?
      context.response.status = HTTP::Status::UNAUTHORIZED
      return
    end

    auth_header_ptr + 50
  end
end
