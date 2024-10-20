require "crypto/bcrypt/password"
require "./repository"

# Provides an easy-to-use interface for accessing the user table in the database.
#
# Contains a set of methods for working with the user table. All queries made to the
# user table should be made though a UserRepository object.
class Repositories::UserRepository < Repositories::Repository
  # Returns whether a user with the given email exists.
  #
  # ```
  # user_repository.exists("user@email.com") # => true if user@email.com exists in the database
  # ```
  def exists(email : String) : Bool
    return @db.query_one "SELECT EXISTS(SELECT 1 FROM users WHERE email=$1)", email, as: Bool
  end

  # Adds a user to the database.
  #
  # ```
  # user_repository.create("user@email.com", "hashed_password", "first_name", "last_name")
  # ```
  def create(email : String, password : Crypto::Bcrypt::Password, first_name : String, last_name : String) : Nil
    @db.exec "INSERT INTO users (email, password, first_name, last_name) VALUES ($1, $2, $3, $4)", email, password, first_name, last_name
  end

  # Returns the hashed password of a user.
  #
  # ```
  # user_repository.get_login_password("user@email.com") # => "hashed_password"
  # ```
  def get_login_password(email : String) : (Crypto::Bcrypt::Password | Nil)
    begin
      password = @db.query_one "SELECT password FROM users WHERE email=$1", email, as: String
      return Crypto::Bcrypt::Password.new(password)
    rescue DB::NoResultsError
      return nil
    end
  end
end