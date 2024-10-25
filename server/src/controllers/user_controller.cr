require "http/server"
require "http/status"
require "http/cookie"
require "crypto/bcrypt/password"
require "uuid"
require "jwt"
require "validator"
require "./controller"
require "../schemas/user_schemas"
require "../validators/user_validator"
require "../repositories/user_repository"

# Controller for handling requests made to the user resource
class Controllers::UserController < Controllers::Controller
  include Validators::UserValidator

  def initialize(@user_repository : Repositories::UserRepository, @auth_db : Redis::PooledClient)
    @prefix_length = "/api/v1/users".size
  end

  # Handles requests made to the /api/v1/users route by directing it to the correct handler
  def handle_request(context : HTTP::Server::Context) : Nil
    # Get distinguishing path from resource string
    path = context.request.resource[@prefix_length, context.request.resource.size]

    # Call appropriate request handler
    case {context.request.method, path}
    when {"POST", ""}
      register_user(context)
    when {"POST", "/login"}
      login_user(context)
    when {"GET", "/token"}
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
      context.response.output << ExceptionResponse.new("User with email already exists").to_json
      return
    end

    # Hash password
    hashed_password = Crypto::Bcrypt::Password.create data.password, ENV["BCRYPT_COST"].to_i

    # Register user into the database
    @user_repository.create(data.email, hashed_password, data.first_name, data.last_name)

    # Send success response
    context.response.content_type = "application/json"
    context.response.status = HTTP::Status::CREATED
    context.response.output << RegisterResponse.new(
      email: data.email,
      first_name: data.first_name,
      last_name: data.last_name
    ).to_json
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
    if password.nil?
      context.response.status = HTTP::Status::NOT_FOUND
      context.response.output << ExceptionResponse.new("User with email not found").to_json
      return
    end

    # Verify user password
    if !password.verify(data.password)
      context.response.status = HTTP::Status::UNAUTHORIZED
      context.response.output << ExceptionResponse.new("Incorrect password").to_json
      return
    end

    # Start token family
    token_family_id = UUID.v4()
    @auth_db.set(token_family_id.to_s, 1, ex: ENV["REFRESH_TOKEN_HOUR_LIFESPAN"].to_i * 3600)

    # Generate access token and refresh token pair
    access_claims = {user_id: user_id, exp: Time.utc.to_unix + (60 * ENV["ACCESS_TOKEN_MINUTE_LIFESPAN"].to_i)}
    access_token = JWT.encode(access_claims, ENV["API_SECRET"], JWT::Algorithm::HS256)

    refresh_claims = {user_id: user_id, token_family_id: token_family_id.to_s, sequence_number: 1, exp: Time.utc.to_unix + (3600 * ENV["REFRESH_TOKEN_HOUR_LIFESPAN"].to_i)}
    refresh_token = JWT.encode(refresh_claims, ENV["API_SECRET"], JWT::Algorithm::HS256)

    # Set http-only cookie containing refresh token
    cookie = HTTP::Cookie.new(
      name: "refresh-token",
      value: refresh_token,
      max_age: Time::Span.new(hours: ENV["REFRESH_TOKEN_HOUR_LIFESPAN"].to_i),
      http_only: true,
      secure: true,
      samesite: HTTP::Cookie::SameSite::Strict
    )

    context.response.cookies << cookie

    # Send access token
    context.response.content_type = "application/json"
    context.response.status = HTTP::Status::OK
    context.response.output << LoginResponse.new(
      access_token: access_token
    ).to_json
  end

  # Returns a new refresh token access token pair the user can use to authenticate
  # on protected endpoints. The user must have a valid refresh token cookie.
  #
  # Method: GET
  # Path: /api/v1/users/token
  def refresh_token(context : HTTP::Server::Context) : Nil
    # Parse claims if token is not expired
    begin
      payload, _ = JWT.decode(context.request.cookies["refresh-token"].value, ENV["API_SECRET"], JWT::Algorithm::HS256)
      user_id = payload["user_id"].as_s
      token_family_id = payload["token_family_id"].as_s
      sequence_number = payload["sequence_number"].as_i
    rescue
      context.response.status = HTTP::Status::UNAUTHORIZED
      return
    end

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
    if (sequence_number != expected_sequence_number.to_i)
      @auth_db.del(token_family_id)
      context.response.status = HTTP::Status::UNAUTHORIZED
      return
    end

    # Update sequence number to reflect new token in the token family
    @auth_db.set(token_family_id, sequence_number + 1, ex: ENV["REFRESH_TOKEN_HOUR_LIFESPAN"].to_i * 3600)

    # Generate access token and refresh token pair
    access_claims = {user_id: user_id, exp: Time.utc.to_unix + (60 * ENV["ACCESS_TOKEN_MINUTE_LIFESPAN"].to_i)}
    access_token = JWT.encode(access_claims, ENV["API_SECRET"], JWT::Algorithm::HS256)

    refresh_claims = {user_id: user_id, token_family_id: token_family_id, sequence_number: sequence_number + 1, exp: Time.utc.to_unix + (3600 * ENV["REFRESH_TOKEN_HOUR_LIFESPAN"].to_i)}
    refresh_token = JWT.encode(refresh_claims, ENV["API_SECRET"], JWT::Algorithm::HS256)

    # Set http-only cookie containing refresh token
    cookie = HTTP::Cookie.new(
      name: "refresh-token",
      value: refresh_token,
      max_age: Time::Span.new(hours: ENV["REFRESH_TOKEN_HOUR_LIFESPAN"].to_i),
      http_only: true,
      secure: true,
      samesite: HTTP::Cookie::SameSite::Strict
    )

    context.response.cookies << cookie

    # Send access token
    context.response.content_type = "application/json"
    context.response.status = HTTP::Status::OK
    context.response.output << RefreshTokenResponse.new(
      access_token: access_token
    ).to_json
  end
end
