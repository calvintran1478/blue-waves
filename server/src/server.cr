require "http/server"
require "db"
require "pg"
require "redis"
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

AUTH_DB_USER = ENV["AUTH_DB_USER"]
AUTH_DB_PASSWORD = ENV["AUTH_DB_PASSWORD"]
AUTH_DB_HOST = ENV["AUTH_DB_HOST"]
AUTH_DB_PORT = ENV["AUTH_DB_PORT"]
AUTH_TLS_ENABLED = ENV["AUTH_TLS_ENABLED"]

# Connect to database
db = DB.open("postgres://#{DB_USER}:#{DB_PASSWORD}@#{DB_HOST}:#{DB_PORT}/#{DB_NAME}")
auth_db = Redis::PooledClient.new(host: AUTH_DB_HOST, port: AUTH_DB_PORT.to_i, password: AUTH_DB_PASSWORD, ssl: AUTH_TLS_ENABLED == "true")

# Initialize repositories
user_repository = Repositories::UserRepository.new(db)

# Initialize resource controllers
user_controller = Controllers::UserController.new(user_repository, auth_db)

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
