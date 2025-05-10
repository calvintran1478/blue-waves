require "http/server"
require "../utils/str"
require "../utils/jwt"

class Middleware::AuthMiddleware
  def initialize(@auth_db : Redis::PooledClient, @API_SECRET : String)
  end

  def get_user(context : HTTP::Server::Context) : (String | Nil)
    # Check that the authorization header is included
    auth_header = context.request.headers["Authorization"]?
    if auth_header.nil?
      context.response.status = HTTP::Status::UNAUTHORIZED
      return
    end

    # Extract access token
    if auth_header.size <= 7 || !auth_header.starts_with?("Bearer ")
      context.response.status = HTTP::Status::UNAUTHORIZED
      return
    end
    access_token = auth_header.unsafe_byte_slice(7)

    # Check if the access token is black listed
    black_list_token_id = Utils::Str.combine_bytes("black-list:", access_token)
    if @auth_db.exists(black_list_token_id) == 1
      context.response.status = HTTP::Status::UNAUTHORIZED
      return
    end

    # Parse access token and get user id
    payload = Utils::JWT.decode(access_token, @API_SECRET, :access_token)
    if payload.nil?
      context.response.status = HTTP::Status::UNAUTHORIZED
      return
    end

    payload.user_id
  end
end
