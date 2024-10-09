
module Utils::Env
  extend self

  # Loads values in the server .env file as enviornment variables.
  #
  # ```
  # require "./utils/env/load_env"
  #
  # Utils::Env.load_env()
  # ```
  def load_env()
    File.each_line(".env") do |line|
      equals_index = line.index("=")
      if !equals_index.nil?
        ENV[line[...equals_index]] = line[(equals_index + 1)..]
      end
    end
  end
end
