require "http/server"
require "db"
require "pg"
require "./controllers/user_controller"
require "./repositories/user_repository"
require "./utils/env"

# Load environment
Utils::Env.load_env()

DB_USER = ENV["DB_USER"]
DB_PASSWORD = ENV["DB_PASSWORD"]
DB_HOST = ENV["DB_HOST"]
DB_PORT = ENV["DB_PORT"]
DB_NAME = ENV["DB_NAME"]

# Connect to database
db = DB.open("postgres://#{DB_USER}:#{DB_PASSWORD}@#{DB_HOST}:#{DB_PORT}/#{DB_NAME}")

# Initialize repositories
user_repository = Repositories::UserRepository.new(db)

# Initialize resource controllers
user_controller = Controllers::UserController.new(user_repository)

# Define server handling of requests
server = HTTP::Server.new do |context|
	if context.request.resource.starts_with?("/api/v1/users")
		user_controller.handle_request(context)
	end
end

# Run server
address = server.bind_tcp 8080
puts "Listening on port #{address.port}"
server.listen
