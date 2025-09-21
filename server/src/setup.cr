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
      CREATE TABLE IF NOT EXISTS users (
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
      CREATE TABLE IF NOT EXISTS music (
        music_id VARCHAR PRIMARY KEY,
        title VARCHAR,
        artist VARCHAR,
        creation_time TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        user_id UUID,
        CONSTRAINT music_user_id_fkey FOREIGN KEY(user_id) REFERENCES users(user_id)
          ON DELETE CASCADE
          ON UPDATE CASCADE
      );
    SQL
  )

  # Create playlist table
  db.exec(
    <<-SQL
      CREATE TABLE IF NOT EXISTS playlists (
        playlist_id VARCHAR PRIMARY KEY,
        name VARCHAR UNIQUE,
        creation_time TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        user_id UUID,
        CONSTRAINT playlists_user_id_fkey FOREIGN KEY(user_id) REFERENCES users(user_id)
          ON DELETE CASCADE
          ON UPDATE CASCADE,
        UNIQUE (user_id, name)
      );
    SQL
  )

  # Create playlist music table
  db.exec(
    <<-SQL
      CREATE TABLE IF NOT EXISTS playlist_music (
        playlist_id VARCHAR,
        music_id VARCHAR,
        music_number INTEGER NOT NULL,
        user_id UUID,
        CONSTRAINT playlist_music_user_id_fkey FOREIGN KEY(user_id) REFERENCES users(user_id)
          ON DELETE CASCADE
          ON UPDATE CASCADE,
        CONSTRAINT playlist_music_playlist_id_fkey FOREIGN KEY(playlist_id) REFERENCES playlists(playlist_id)
          ON DELETE CASCADE
          ON UPDATE CASCADE,
        CONSTRAINT playlist_music_music_id_fkey FOREIGN KEY(music_id) REFERENCES music(music_id)
          ON DELETE CASCADE
          ON UPDATE CASCADE,
        PRIMARY KEY (playlist_id, music_id)
      );
    SQL
  )
end
