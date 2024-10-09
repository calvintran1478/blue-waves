require "db"
require "pg"
require "./utils/env"

# Load environment
Utils::Env.load_env()

# Set up database connection
DB_USER = ENV["DB_USER"]
DB_PASSWORD = ENV["DB_PASSWORD"]
DB_HOST = ENV["DB_HOST"]
DB_PORT = ENV["DB_PORT"]
DB_NAME = ENV["DB_NAME"]

# Connect to database and create tables
DB.connect "postgres://#{DB_USER}:#{DB_PASSWORD}@#{DB_HOST}:#{DB_PORT}/#{DB_NAME}" do |db|
  # Create user table
  db.exec(
    <<-SQL
      CREATE TABLE users (
        email VARCHAR PRIMARY KEY,
        password VARCHAR NOT NULL CHECK (length(password) >= 8),
        first_name VARCHAR NOT NULL CHECK (first_name <> ''),
        last_name VARCHAR NOT NULL CHECK (last_name <> '')
      );
    SQL
  )
end
