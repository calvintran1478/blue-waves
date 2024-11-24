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
        user_id UUID PRIMARY KEY,
        email VARCHAR UNIQUE,
        password VARCHAR NOT NULL CHECK (length(password) >= 8),
        first_name VARCHAR NOT NULL CHECK (first_name <> ''),
        last_name VARCHAR NOT NULL CHECK (last_name <> '')
      );
    SQL
  )

  # Create music table
  db.exec(
    <<-SQL
      CREATE TABLE music (
        music_id VARCHAR PRIMARY KEY,
        title VARCHAR,
        artist VARCHAR,
        user_id UUID,
        CONSTRAINT fk_user FOREIGN KEY(user_id) REFERENCES users(user_id)
          ON DELETE CASCADE
          ON UPDATE CASCADE,
        UNIQUE(user_id, title)
      );
    SQL
  )
end
