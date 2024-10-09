require "json"

# Represents an HTTP exception.
#
# Is meant to be used as an efficient way of serializing a json
# error response upon encountering an error.
#
# ```
# require "./exceptions/exception_response"
# include Exception
#
# context.response.output << ExceptionResponse.new("Error message").to_json
# ```
struct Exceptions::ExceptionResponse
  include JSON::Serializable

  def initialize(@error : String)
  end
end
