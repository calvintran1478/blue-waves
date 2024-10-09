require "db"

# An abstract repository for accessing and modifying a particular resource.
abstract class Repositories::Repository
  def initialize(@db : DB::Database)
  end
end