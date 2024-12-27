
class Middleware::RateLimitMiddleware
  # A token bucket class used for rate limiting requests made to a particular endpoint.
  #
  # http_method should correspond to a HTTP verb (e.g., "POST", "GET", "DELETE", etc.).
  # endpoint should be a part of the url which occurs after the domain (e.g., /api/v1/users/login).
  # capacity indicates the maximum number of tokens this bucket can hold.
  # refill_amount indicates how many tokens are replenished per refill interval.
  # refill_interval indicates the length of each refill interval (in seconds).
  class TokenBucket
    def initialize(@auth_db : Redis::PooledClient, @http_method : String, @endpoint : String, @capacity : Int32, @refill_amount : Int32, @refill_interval : Int32)
    end

    # Returns whether the user is allowed to make a request at the endpoint
    # represented by this token bucket.
    #
    # Automatically refills and subtracts from the token bucket as needed upon
    # each successful call
    def rate_limit_request(user_id : String) : Bool
      # Get bucket details from the user
      tokens = @auth_db.hget("#{@http_method}:#{@endpoint}:#{user_id}", "tokens")
      ts = @auth_db.hget("#{@http_method}:#{@endpoint}:#{user_id}", "ts")

      tokens = tokens.nil? ? @capacity : tokens.to_i
      ts = ts.nil? ? Time.utc.to_unix : ts.to_i64

      # Refill bucket based on elapsed time
      elapsed_time = Time.utc.to_unix - ts
      elapsed_refill_intervals = (elapsed_time / @refill_interval).floor.to_i
      if elapsed_refill_intervals > 0
        ts += elapsed_refill_intervals * @refill_interval
        tokens += elapsed_refill_intervals * @refill_amount
        tokens = Math.min(tokens, @capacity)
      end

      # Check if any tokens are left for use
      allowed = tokens > 0

      # Save updated user bucket details if needed
      if allowed
        tokens -= 1
        @auth_db.hmset("#{@http_method}:#{@endpoint}:#{user_id}", {tokens: tokens, ts: ts})
      end

      # Return whether the user is allowed to use the endpoint
      return allowed
    end
  end
end
