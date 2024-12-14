require "http/server"
require "jwt"

class Middleware::AuthMiddleware
  def initialize(@auth_db : Redis::PooledClient)
  end

  def get_user(context : HTTP::Server::Context) : (String | Nil)
    # Check that the authorization header is included
    auth_header = context.request.headers["Authorization"]?
    if auth_header.nil?
      context.response.status = HTTP::Status::UNAUTHORIZED
      return
    end

    # Extract access token
    delimiter_index = auth_header.index(" ")
    if delimiter_index.nil? || delimiter_index == auth_header.size - 1 || auth_header[...delimiter_index] != "Bearer"
      context.response.status = HTTP::Status::UNAUTHORIZED
      return
    end
    access_token = auth_header[(delimiter_index + 1)...]

    # Check if the access token is black listed
    black_listed = @auth_db.exists("black-list:#{access_token}")
    if black_listed == 1
      context.response.status = HTTP::Status::UNAUTHORIZED
      return
    end

    # Parse access token and get user id
    begin
      payload, _ = JWT.decode(access_token, ENV["API_SECRET"], JWT::Algorithm::HS256)
    rescue
      context.response.status = HTTP::Status::UNAUTHORIZED
      return
    end

    return payload["user_id"].as_s
  end
end

