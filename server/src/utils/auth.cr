require "http/server"
require "jwt"

module Utils::Auth
  extend self

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
