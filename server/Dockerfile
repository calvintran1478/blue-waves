# Set the base image using Crystal 1.18.2
FROM docker.io/crystallang/crystal:1.18.2-alpine

# Set the working directory to /app
WORKDIR /app

# Copy source files to working directory
COPY ./src /app
COPY shard.yml shard.lock rate_limit.conf /app

# Install required dependencies
RUN shards install

# Compile server code
RUN crystal build --release --static server.cr

# Expose port the app runs on
EXPOSE 8000

# Run the app
CMD ["./server", "0.0.0.0", "8000"]
