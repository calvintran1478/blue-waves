require "http/server"

# An abstract API controller for handling requests made to a particular resource.
abstract class Controllers::Controller
  abstract def handle_request(context : HTTP::Server::Context) : Nil
end