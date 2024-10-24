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
    user_exists = @user_repository.exists(data.email)
    if user_exists
      context.response.status = HTTP::Status::CONFLICT
      context.response.output << ExceptionResponse.new("User with email already exists").to_json
      return
    end

    # Hash password
    hashed_password = Crypto::Bcrypt::Password.create data.password, 10

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

  # Logs in the user by giving them an access token they can use to authenticate
  # on protected endpoints
  #
  # Method: POST
  # Path: /api/v1/users/login
  def login_user(context : HTTP::Server::Context) : Nil
    # Validate user input
    data = validate_login_request context
    return if data.nil?

    # Look up user in database
    password = @user_repository.get_login_password(data.email)
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
    access_claims = {user_id: data.email, exp: Time.utc.to_unix + (60 * ENV["ACCESS_TOKEN_MINUTE_LIFESPAN"].to_i)}
    access_token = JWT.encode(access_claims, ENV["API_SECRET"], JWT::Algorithm::HS256)

    refresh_claims = {user_id: data.email, token_family_id: token_family_id.to_s, sequence_number: 1, exp: Time.utc.to_unix + (3600 * ENV["REFRESH_TOKEN_HOUR_LIFESPAN"].to_i)}
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
end
