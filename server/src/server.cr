require "http"
require "http/server"
require "db"
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
require "./utils/pg/src/pg"
require "./utils/env"
require "./utils/config"

# Read CLI arguments
case ARGV.size
when 0 then host, port = "127.0.0.1", 8080
when 2 then host, port = ARGV[0], ARGV[1].to_i
else
  puts "Error: Unexpected number of arguments"
  puts "Usage: ./server"
  puts "Usage: ./server [host] [port]"
  exit 1
end

# Load environment
Utils::Env.load_env() if host == "127.0.0.1"

# Connect to database
db = DB.open(ENV["DB_CONN"])
auth_db = Redis::PooledClient.new(url: ENV["AUTH_DB_CONN"])
music_db = Awscr::S3::Client.new(
  ENV["MUSIC_DB_LOCATION"], ENV["MUSIC_DB_KEY"], ENV["MUSIC_DB_SECRET"], endpoint: ENV["MUSIC_DB_ENDPOINT"]
)

# Initialize middleware
auth_middleware = Middleware::AuthMiddleware.new(auth_db, ENV["API_SECRET"])
token_buckets = Utils::Config.load_rate_limit_config("rate_limit.conf", auth_db)
rate_limit_middleware = Middleware::RateLimitMiddleware.new(auth_db, token_buckets)

# Initialize repositories
user_repository = Repositories::UserRepository.new(db)
music_repository = Repositories::MusicRepository.new(db, music_db, auth_db, ENV["MUSIC_DB_BUCKET"])
playlist_repository = Repositories::PlaylistRepository.new(db)

# Initialize resource controllers
user_controller = Controllers::UserController.new(user_repository, auth_db, rate_limit_middleware)
music_controller = Controllers::MusicController.new(music_repository, auth_middleware, rate_limit_middleware)
playlist_controller = Controllers::PlaylistController.new(playlist_repository, music_repository, auth_middleware)

# Set up static file handler
static_file_handler = HTTP::StaticFileHandler.new("static", directory_listing: false)

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
    # Serve static files
    context.request.path = "/index.html" unless context.request.path.includes?('.')
    static_file_handler.call(context)
  end
end

# Run server
address = server.bind_tcp(host, port)
puts "Listening on port #{address.port}"
server.listen
