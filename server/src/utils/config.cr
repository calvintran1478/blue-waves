
module Utils::Config
  extend self

  # Loads the chosen rate limit config file by creating the corresponding token
  # buckets.
  #
  # ```
  # require "./utils/env/config"
  #
  # Utils::Config.load_rate_limit_config()
  # ```
  def load_rate_limit_config(filename : String, auth_db : Redis::PooledClient) : Hash(NamedTuple(http_method: String, endpoint: String), Middleware::RateLimitMiddleware::TokenBucket)
    token_buckets = Hash(NamedTuple(http_method: String, endpoint: String), Middleware::RateLimitMiddleware::TokenBucket).new
    File.each_line(filename) do |line|
      unless line.starts_with?("#")
        bucket_details = line.split(" ")
        token_buckets[{http_method: bucket_details[0], endpoint: bucket_details[1]}] = Middleware::RateLimitMiddleware::TokenBucket.new(auth_db, bucket_details[0], bucket_details[1], bucket_details[2].to_i, bucket_details[3].to_i, bucket_details[4].to_i)
      end
    end
    token_buckets
  end
end
