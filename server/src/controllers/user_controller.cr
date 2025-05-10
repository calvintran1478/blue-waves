require "http/server"
require "http/status"
require "http/cookie"
require "crypto/bcrypt/password"
require "uuid"
require "validator"
require "./controller"
require "../schemas/user_schemas"
require "../validators/user_validator"
require "../repositories/user_repository"
require "../utils/token"

# Controller for handling requests made to the user resource
class Controllers::UserController < Controllers::Controller
  include Validators::UserValidator

  @ACCESS_TOKEN_LIFESPAN : Int32
  @REFRESH_TOKEN_LIFESPAN : Int32
  @BCRYPT_COST : Int32
  @API_SECRET : String

  def initialize(@user_repository : Repositories::UserRepository, @auth_db : Redis::PooledClient, @rate_limit_middleware : Middleware::RateLimitMiddleware)
    @prefix_length = "/api/v1/users".size

    # Constant environment variables stored for quick lookup
    @ACCESS_TOKEN_LIFESPAN = ENV["ACCESS_TOKEN_MINUTE_LIFESPAN"].to_i * 60
    @REFRESH_TOKEN_LIFESPAN = ENV["REFRESH_TOKEN_HOUR_LIFESPAN"].to_i * 3600
    @BCRYPT_COST = ENV["BCRYPT_COST"].to_i
    @API_SECRET = ENV["API_SECRET"]
  end

  # Handles requests made to the /api/v1/users route by directing it to the correct handler
  def handle_request(context : HTTP::Server::Context) : Nil
    # Get distinguishing path from resource string
    path = context.request.resource.unsafe_byte_slice(@prefix_length)

    # Call appropriate request handler
    case {context.request.method, path}
    when {"POST", "".to_slice}
      register_user(context)
    when {"POST", "/login".to_slice}
      # Perform rate limiting based on IP address
      remote_address = context.request.remote_address.to_s
      ip_address = Bytes.new(remote_address.to_unsafe, remote_address.rindex(':').as(Int32))
      login_allowed = @rate_limit_middleware.rate_limit_request(ip_address, "POST", "/api/v1/users/login")

      # Let the request go through if the user is allowed
      if login_allowed
        login_user(context)
      else
        context.response.status = HTTP::Status::TOO_MANY_REQUESTS
        context.response.output << "Too Many Requests"
      end
    when {"POST", "/logout".to_slice}
      logout_user(context)
    when {"GET", "/token".to_slice}
      refresh_token(context)
    else
      context.response.status = HTTP::Status::NOT_FOUND
    end
  end

  # Registers an account for the user.
  #
  # Method: POST
  # Path: /api/v1/users
  def register_user(context : HTTP::Server::Context) : Nil
    # Validate user input
    data = validate_register_request context
    return if data.nil?

    # Check if a user with the given email already exists
    user_exists = @user_repository.exists_by_email(data.email)
    if user_exists
      context.response.status = HTTP::Status::CONFLICT
      context.response.output << "User with email already exists"
      return
    end

    # Hash password
    hashed_password = Crypto::Bcrypt::Password.create data.password, @BCRYPT_COST

    # Register user into the database
    @user_repository.create(data.email, hashed_password, data.first_name, data.last_name)

    # Send success response
    context.response.content_type = "application/json"
    context.response.status = HTTP::Status::CREATED
    context.response.output << RegisterResponse.new(
      email: data.email,
      first_name: data.first_name,
      last_name: data.last_name
    )
  end

  # Logs in the user by providing an access token they can use to authenticate
  # on protected endpoints. Also provides a refresh token that can be used to obtain
  # new access tokens.
  #
  # Method: POST
  # Path: /api/v1/users/login
  def login_user(context : HTTP::Server::Context) : Nil
    # Validate user input
    data = validate_login_request context
    return if data.nil?

    # Look up user in database
    user_id, password = @user_repository.get_login_password(data.email)
    if user_id.nil? || password.nil?
      context.response.status = HTTP::Status::NOT_FOUND
      context.response.output << "User with email not found"
      return
    end

    # Verify user password
    if !password.verify(data.password)
      context.response.status = HTTP::Status::UNAUTHORIZED
      context.response.output << "Incorrect password"
      return
    end

    # Start token family
    token_family_id = UUID.v4().to_s
    @auth_db.set(token_family_id, 1, ex: @REFRESH_TOKEN_LIFESPAN)

    # Generate access token and refresh token pair
    access_claims = Utils::Token::AccessClaims.new(user_id, Time.utc.to_unix + @ACCESS_TOKEN_LIFESPAN)
    access_token = Utils::Token.encode(access_claims, @API_SECRET)

    refresh_claims = Utils::Token::RefreshClaims.new(user_id, token_family_id, 1, Time.utc.to_unix + @REFRESH_TOKEN_LIFESPAN)
    refresh_token = Utils::Token.encode(refresh_claims, @API_SECRET)

    # Set http-only cookie containing refresh token
    context.response.cookies << HTTP::Cookie.new(
      name: "refresh-token",
      value: refresh_token,
      max_age: Time::Span.new(seconds: @REFRESH_TOKEN_LIFESPAN),
      http_only: true,
      secure: true,
      samesite: HTTP::Cookie::SameSite::Strict
    )

    # Send access token
    context.response.content_type = "text/plain"
    context.response.status = HTTP::Status::OK
    context.response.output << access_token
  end

  # Returns a new refresh token access token pair the user can use to authenticate
  # on protected endpoints. The user must have a valid refresh token cookie.
  #
  # Method: GET
  # Path: /api/v1/users/token
  def refresh_token(context : HTTP::Server::Context) : Nil
    # Parse claims if token is not expired
    refresh_token_cookie = context.request.cookies["refresh-token"]?
    if refresh_token_cookie.nil?
      context.response.status = HTTP::Status::UNAUTHORIZED
      return
    end

    payload = Utils::Token.decode(refresh_token_cookie.value.to_slice, @API_SECRET, :refresh_token)
    if payload.nil?
      context.response.status = HTTP::Status::UNAUTHORIZED
      return
    end

    payload = payload.as(Utils::Token::RefreshClaims)
    user_id = payload.user_id
    token_family_id = payload.token_family_id
    sequence_number = payload.sequence_number

    # Check that the user exists in the database
    user_exists = @user_repository.exists_by_id(user_id)
    unless user_exists
      context.response.status = HTTP::Status::UNAUTHORIZED
      return
    end

    # Check that the token family exists
    expected_sequence_number = @auth_db.get(token_family_id)
    if expected_sequence_number.nil?
      context.response.status = HTTP::Status::UNAUTHORIZED
      return
    end

    # Check the sequence number is as expected
    if sequence_number != expected_sequence_number.to_i
      @auth_db.del(token_family_id)
      context.response.status = HTTP::Status::UNAUTHORIZED
      return
    end

    # Update sequence number to reflect new token in the token family
    @auth_db.set(token_family_id, sequence_number + 1, ex: @REFRESH_TOKEN_LIFESPAN)

    # Generate access token and refresh token pair
    access_claims = Utils::Token::AccessClaims.new(user_id, Time.utc.to_unix + @ACCESS_TOKEN_LIFESPAN)
    access_token = Utils::Token.encode(access_claims, @API_SECRET)

    refresh_claims = Utils::Token::RefreshClaims.new(user_id, token_family_id, sequence_number + 1, Time.utc.to_unix + @REFRESH_TOKEN_LIFESPAN)
    refresh_token = Utils::Token.encode(refresh_claims, @API_SECRET)

    # Set http-only cookie containing refresh token
    context.response.cookies << HTTP::Cookie.new(
      name: "refresh-token",
      value: refresh_token,
      max_age: Time::Span.new(seconds: @REFRESH_TOKEN_LIFESPAN),
      http_only: true,
      secure: true,
      samesite: HTTP::Cookie::SameSite::Strict
    )

    # Send access token
    context.response.content_type = "text/plain"
    context.response.status = HTTP::Status::OK
    context.response.output << access_token
  end

  # Logs out the user by invalidating their access token and preventing new
  # access tokens from being generated using their refresh token.
  #
  # Method: POST
  # Path: /api/v1/users/logout
  def logout_user(context : HTTP::Server::Context) : Nil
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
    payload = Utils::Token.decode(access_token, @API_SECRET, :access_token)
    if payload.nil?
      context.response.status = HTTP::Status::UNAUTHORIZED
      return
    end

    # Determine remaining time for which the access token is valid
    remaining_time = payload.exp - Time.utc.to_unix

    # Add access token to black list
    @auth_db.set(black_list_token_id, "", ex: remaining_time)

    # Invalidate token family if refresh token is not expired
    refresh_token_cookie = context.request.cookies["refresh-token"]?
    if !refresh_token_cookie.nil?
      payload = Utils::Token.decode(refresh_token_cookie.value.to_slice, @API_SECRET, :refresh_token)
      if !payload.nil?
        @auth_db.del(payload.as(Utils::Token::RefreshClaims).token_family_id)
      end
    end

    # Remove refresh cookie from the client
    context.response.cookies << HTTP::Cookie.new(
      name: "refresh-token",
      value: "",
      samesite: HTTP::Cookie::SameSite::Strict,
      expires: Time::UNIX_EPOCH
    )

    # Send success response
    context.response.status = HTTP::Status::NO_CONTENT
  end
end
