require "crypto/bcrypt/password"
require "uuid"
require "./repository"

# Provides an easy-to-use interface for accessing the user table in the database.
#
# Contains a set of methods for working with the user table. All queries made to the
# user table should be made though a UserRepository object.
class Repositories::UserRepository < Repositories::Repository

  # Returns whether a user with the given email exists.
  #
  # ```
  # user_repository.exists_by_email("user@email.com") # => true if user@email.com exists in the database
  # ```
  def exists_by_email(email : Bytes) : Bool
    @db.query_one "SELECT EXISTS(SELECT 1 FROM users WHERE email=$1)", email do |rs|
      rs.read { |io, _| io.read_byte == 1 }
    end
  end

  # Adds a user to the database.
  #
  # ```
  # user_repository.create("user@email.com", "hashed_password", "first_name", "last_name")
  # ```
  def create(email : Bytes, password : Bytes, first_name : Bytes, last_name : Bytes) : Nil
    user_id = UUID.v4.to_s

    @db.exec "INSERT INTO users (user_id, email, password, first_name, last_name) VALUES ($1, $2, $3, $4, $5)", user_id.to_slice, email, password, first_name, last_name
  end

  # Returns the hashed password of a user along with their id.
  #
  # ```
  # user_repository.get_login_password("user@email.com") # => "user_id", "hashed_password"
  # ```
  def get_login_password(email : Bytes, password_buffer : UInt8*) : Tuple(String, String)
    user_id, password_hash = "", ""
    @db.query "SELECT user_id, password FROM users WHERE email=$1", email do |rs|
      rs.each do
        # Read user id
        user_id = rs.read do |io, _|
          uuid_buffer = uninitialized UInt8[16]
          uuid_bytes = Bytes.new(uuid_buffer.to_unsafe, 16)
          io.read_fully(uuid_bytes)
          UUID.new(uuid_bytes).to_s
        end

        # Read password
        password_hash = rs.read do |io, _|
          string_buffer = password_buffer.as(String)
          string_buffer.initialize_header(60, 60)
          io.read_fully(Bytes.new(string_buffer.to_unsafe, 60))
          string_buffer.to_unsafe[60] = 0_u8

          string_buffer
        end
      end
    end

    {user_id, password_hash}
  end
end
