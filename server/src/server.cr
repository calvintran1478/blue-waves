require "http/server"
require "db"
require "pg"
require "redis"
require "awscr-s3"
require "./middleware/auth_middleware"
require "./middleware/rate_limit_middleware"
require "./controllers/user_controller"
require "./controllers/music_controller"
require "./controllers/playlist_controller"
require "./repositories/user_repository"
require "./repositories/music_repository"
require "./repositories/playlist_repository"
require "./utils/env"
require "./utils/config"

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

MUSIC_DB_LOCATION = ENV["MUSIC_DB_LOCATION"]
MUSIC_DB_KEY = ENV["MUSIC_DB_KEY"]
MUSIC_DB_SECRET = ENV["MUSIC_DB_SECRET"]
MUSIC_DB_ENDPOINT = ENV["MUSIC_DB_ENDPOINT"]

# Connect to database
db = DB.open("postgres://#{DB_USER}:#{DB_PASSWORD}@#{DB_HOST}:#{DB_PORT}/#{DB_NAME}")
auth_db = Redis::PooledClient.new(host: AUTH_DB_HOST, port: AUTH_DB_PORT.to_i, password: AUTH_DB_PASSWORD, ssl: AUTH_TLS_ENABLED == "true")
music_db = Awscr::S3::Client.new(MUSIC_DB_LOCATION, MUSIC_DB_KEY, MUSIC_DB_SECRET, endpoint: MUSIC_DB_ENDPOINT)

# Initialize middleware
auth_middleware = Middleware::AuthMiddleware.new(auth_db, ENV["API_SECRET"])
token_buckets = Utils::Config.load_rate_limit_config("rate_limit.conf", auth_db)
rate_limit_middleware = Middleware::RateLimitMiddleware.new(auth_db, token_buckets)

# Initialize repositories
user_repository = Repositories::UserRepository.new(db)
music_repository = Repositories::MusicRepository.new(db, music_db)
playlist_repository = Repositories::PlaylistRepository.new(db)

# Initialize resource controllers
user_controller = Controllers::UserController.new(user_repository, auth_db, rate_limit_middleware)
music_controller = Controllers::MusicController.new(music_repository, auth_middleware, rate_limit_middleware)
playlist_controller = Controllers::PlaylistController.new(playlist_repository, auth_middleware)

# Define server handling of requests
server = HTTP::Server.new do |context|
  if context.request.resource.starts_with?("/api/v1/users")
    # Increment path pointer
    path_ptr = context.request.resource.to_unsafe + "/api/v1/users".size
    path_ptr_byte_count = context.request.resource.size - "/api/v1/users".size

    # Match resource path
    if path_ptr_byte_count >= "/playlists".bytesize && path_ptr.memcmp("/playlists".to_unsafe, "/playlists".bytesize) == 0
      playlist_controller.handle_request(context)
    elsif path_ptr_byte_count >= "/music".bytesize && path_ptr.memcmp("/music".to_unsafe, "/music".bytesize) == 0
      music_controller.handle_request(context)
    else
      user_controller.handle_request(context)
    end
  else
    context.response.status = HTTP::Status::NOT_FOUND
  end
end

# Run server
address = server.bind_tcp 8080
puts "Listening on port #{address.port}"
server.listen
