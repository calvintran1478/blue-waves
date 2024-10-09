require "json"

module Schemas::UserSchemas
  # Request body schema for POST requests sent to /api/v1/users
  #
  # email is expected to be a valid email.
  # password is expected to be at least 8 characters.
  # first_name and last_name are expected to be non-empty strings consisting of alphabetical characters.
  #
  # The constraints above are checked after initializing instances of RegisterRequest.
  struct RegisterRequest
    include JSON::Serializable

    getter email : String
    getter password : String
    getter first_name : String
    getter last_name : String

    def initialize(@email : String, @password : String, @first_name : String, @last_name : String)
    end
  end

  # Response body schema for server responses to /api/v1/users POST requests.
  #
  # Represents the registered user in the database.
  struct RegisterResponse
    include JSON::Serializable

    def initialize(@email : String, @first_name : String, @last_name : String)
    end
  end
end
