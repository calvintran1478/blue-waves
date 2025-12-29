require "http/server"
require "http/status"
require "../schemas/user_schemas"
require "../utils/constants"

module Validators::UserValidator
  include Schemas::UserSchemas
  include Utils::Constants

  # Validates POST requests sent to api/v1/users when registering an account.
  #
  # Returns the parsed request body as a RegisterRequest struct if validation is successful, and nil otherwise.
  # Upon error an appropriate message is written to the response body and a status code of 400 is set accordingly.
  #
  # ```
  # require "validators/user_validator"
  # include "./Validators::UserValidator"
  #
  # data = validate_register_request context
  # if !data.nil?
  #   handle request...
  # end
  # ```
  def validate_register_request(context : HTTP::Server::Context) : (RegisterRequest | Nil)
    # Get request body
    if context.request.body.nil?
      context.response.status = HTTP::Status::BAD_REQUEST
      return
    end
    request_body = context.request.body.as(IO)

    # Parse and validate email
    email = request_body.gets('\n', MAX_EMAIL_LENGTH + 1, chomp: true)
    if email.nil?
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Email required"
      return
    end

    if !Valid.email?(email)
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Invalid email"
      return
    end

    # Parse and validate password
    password = request_body.gets('\n', MAX_PASSWORD_LENGTH + 1, chomp: true)
    if password.nil?
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Password required"
      return
    end

    if password.size < MIN_PASSWORD_LENGTH
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Password must be at least 8 characters"
      return
    end

    if password.size > MAX_PASSWORD_LENGTH
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Password cannot exceed 71 characters"
      return
    end

    # Parse and validate first name
    first_name = request_body.gets('\n', MAX_FIRST_NAME_LENGTH + 1, chomp: true)
    if first_name.nil?
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "First name required"
      return
    end

    if first_name.empty?
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "First name cannot be empty"
      return
    end

    if first_name.size > MAX_FIRST_NAME_LENGTH
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "First name cannot exceed 50 characters"
      return
    end

    first_name.each_char do |ch|
      if !ch.ascii_letter?
        context.response.status = HTTP::Status::BAD_REQUEST
        context.response.output << "First name must consist of alphabetical characters"
        return
      end
    end

    # Parse and validate last name
    last_name = request_body.gets('\n', MAX_LAST_NAME_LENGTH + 1, chomp: true)
    if last_name.nil?
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Last name required"
      return
    end

    if last_name.empty?
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Last name cannot be empty"
      return
    end

    if last_name.size > MAX_LAST_NAME_LENGTH
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Last name cannot exceed 50 characters"
      return
    end

    last_name.each_char do |ch|
      if !ch.ascii_letter?
        context.response.status = HTTP::Status::BAD_REQUEST
        context.response.output << "Last name must consist of alphabetical characters"
        return
      end
    end

    RegisterRequest.new(email, password, first_name, last_name)
  end

  # Validates POST requests sent to api/v1/users/login when logging into an account.
  #
  # Returns the parsed request body as a LoginRequest struct if validation is successful, and nil otherwise.
  # Upon error an appropriate message is written to the response body and a status code of 400 is set accordingly.
  #
  # ```
  # require "validators/user_validator"
  # include "./Validators::UserValidator"
  #
  # data = validate_login_request context
  # if !data.nil?
  #   handle request...
  # end
  # ```
  def validate_login_request(context : HTTP::Server::Context) : (LoginRequest | Nil)
    # Get request body
    if context.request.body.nil?
      context.response.status = HTTP::Status::BAD_REQUEST
      return
    end
    request_body = context.request.body.as(IO)

    # Parse and validate email
    email = request_body.gets('\n', MAX_EMAIL_LENGTH + 1, chomp: true)
    if email.nil?
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Email required"
      return
    end

    if !Valid.email?(email)
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Invalid email"
      return
    end

    # Parse and validate password
    password = request_body.gets('\n', MAX_PASSWORD_LENGTH + 1, chomp: true)
    if password.nil?
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Password required"
      return
    end

    if password.size > MAX_PASSWORD_LENGTH
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Password cannot exceed 71 characters"
      return
    end

    LoginRequest.new(email, password)
  end
end
