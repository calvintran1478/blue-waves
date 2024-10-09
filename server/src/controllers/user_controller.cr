require "http/server"
require "http/status"
require "crypto/bcrypt/password"
require "validator"
require "./controller"
require "../schemas/user_schemas"
require "../validators/user_validator"
require "../repositories/user_repository"

# Controller for handling requests made to the user resource
class Controllers::UserController < Controllers::Controller
  include Validators::UserValidator

  def initialize(@user_repository : Repositories::UserRepository)
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
end