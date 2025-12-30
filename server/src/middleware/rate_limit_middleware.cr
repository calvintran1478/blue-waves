require "./rate_limit_middleware/token_bucket"

class Middleware::RateLimitMiddleware
  def initialize(@auth_db : Redis::PooledClient, @token_buckets : Hash(NamedTuple(http_method: String, endpoint: String), TokenBucket))
  end

  def rate_limit_request(user_id : Bytes, http_method : String, endpoint : String) : Bool
    @token_buckets[{http_method: http_method, endpoint: endpoint}].rate_limit_request(user_id)
  end
end
