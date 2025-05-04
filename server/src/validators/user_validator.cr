require "http/server"
require "http/status"
require "../schemas/user_schemas"

module Validators::UserValidator
  include Schemas::UserSchemas

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
    # Parse request body
    if context.request.body.nil?
      context.response.status = HTTP::Status::BAD_REQUEST
      return
    end

    request_body = context.request.body.as(IO)
    email = request_body.gets
    password = request_body.gets
    first_name = request_body.gets
    last_name = request_body.gets

    if email.nil? || password.nil? || first_name.nil? || last_name.nil?
      context.response.status = HTTP::Status::BAD_REQUEST
      return
    end

    # Check email is valid
    if !Valid.email?(email)
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Invalid email"
      return
    end

    # Check that the entered first and last names are non-empty
    if first_name.empty? || last_name.empty?
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "First and last names cannot be empty"
      return
    end

    # Check that the entered first and last names consist of alphabetical characters
    first_name.each_char do |ch|
      if !ch.ascii_letter?
        context.response.status = HTTP::Status::BAD_REQUEST
        context.response.output << "First and last names must consist of alphabetical characters"
        return
      end
    end

    last_name.each_char do |ch|
      if !ch.ascii_letter?
        context.response.status = HTTP::Status::BAD_REQUEST
        context.response.output << "First and last names must consist of alphabetical characters"
        return
      end
    end

    # Check password meets length requirements
    if password.size < 8
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Password must be at least 8 characters"
      return
    end

    if password.size > 71
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << "Password cannot exceed 71 characters"
      return
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
    # Parse request body
    if context.request.body.nil?
      context.response.status = HTTP::Status::BAD_REQUEST
      return
    end

    request_body = context.request.body.as(IO)
    email = request_body.gets
    password = request_body.gets

    if email.nil? || password.nil?
      context.response.status = HTTP::Status::BAD_REQUEST
      return
    end

    LoginRequest.new(email, password)
  end
end
