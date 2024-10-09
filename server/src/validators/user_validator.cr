require "http/server"
require "http/status"
require "../schemas/user_schemas"
require "../exceptions/exception_response"

module Validators::UserValidator
  include Schemas::UserSchemas
  include Exceptions

  ALPHABET = Set{'a','b','c','d','e','f','g','h','i','j','k','l','m','n','o','p','q','r','s','t','u','v','w','x','y','z'}

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
    # Parse JSON body
    begin
      data = RegisterRequest.from_json(context.request.body.as(IO))
    rescue
      context.response.status = HTTP::Status::BAD_REQUEST
      return
    end

    # Check email is valid
    if !(Valid.email? data.email)
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << ExceptionResponse.new("Invalid email").to_json
      return
    end

    # Check that the entered first and last names are non-empty
    if data.first_name.empty?  || data.last_name.empty?
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << ExceptionResponse.new("First and last names cannot be empty").to_json
      return
    end

    # Check that the entered first and last names consist of alphabetical characters
    normalized_first_name = data.first_name.downcase
    normalized_first_name.each_char do |ch|
      if !ALPHABET.includes?(ch)
        context.response.status = HTTP::Status::BAD_REQUEST
        context.response.output << ExceptionResponse.new("First and last names must consist of alphabetical characters").to_json
        return
      end
    end

    normalized_last_name = data.last_name.downcase
    normalized_last_name.each_char do |ch|
      if !ALPHABET.includes?(ch)
        context.response.status = HTTP::Status::BAD_REQUEST
        context.response.output << ExceptionResponse.new("First and last names must consist of alphabetical characters").to_json
        return
      end
    end
    
    # Check password is at least 8 characters
    if data.password.size < 8
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.output << ExceptionResponse.new("Password must be at least 8 characters").to_json
      return
    end

    # Return validated data
    return data
  end
end
