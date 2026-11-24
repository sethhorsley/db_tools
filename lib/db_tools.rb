require "erb"
require "open3"
require "time"
require "yaml"

require_relative "db_tools/version"
require_relative "db_tools/adapters/file_snapshots"
require_relative "db_tools/adapters/postgresql"
require_relative "db_tools/adapters/mysql"
require_relative "db_tools/adapters/sqlite"
require_relative "db_tools/snapshot"
require_relative "db_tools/cli"
require_relative "db_tools/railtie" if defined?(Rails::Railtie)

module DbTools
  class Error < StandardError; end

  ADAPTERS = {
    "postgresql" => Adapters::Postgresql,
    "postgis" => Adapters::Postgresql,
    "mysql2" => Adapters::Mysql,
    "trilogy" => Adapters::Mysql,
    "sqlite3" => Adapters::Sqlite
  }.freeze

  # Builds the adapter for the app's development database. Snapshots only
  # ever target development, so no other environment is read.
  def self.adapter(root: Dir.pwd)
    config = development_config(root)
    adapter_class = ADAPTERS.fetch(config["adapter"]) do
      raise Error, "Unsupported database adapter #{config["adapter"].inspect}. " \
        "Supported: #{ADAPTERS.keys.join(", ")}"
    end
    adapter_class.new(config, root)
  end

  def self.development_config(root)
    path = File.join(root, "config", "database.yml")
    raise Error, "No config/database.yml in #{root}" unless File.exist?(path)

    config = YAML.safe_load(render_erb(path, root), aliases: true)&.fetch("development", nil)
    raise Error, "config/database.yml has no development database" unless config.is_a?(Hash)

    # Multi-database apps nest each database under a name; snapshot the primary one.
    config = config["primary"] || config.values.first unless config.key?("adapter")
    config
  end

  def self.render_erb(path, root)
    ERB.new(File.read(path)).result
  rescue NameError
    # The YAML references the app (e.g. Rails credentials): boot it and try again.
    require File.join(root, "config", "environment")
    ERB.new(File.read(path)).result
  end

  # Runs a command without a shell and returns its stdout, raising on failure.
  def self.run(*command, env: {})
    stdout, stderr, status = Open3.capture3(env, *command)
    raise Error, "#{command.first} failed: #{stderr.strip.empty? ? stdout.strip : stderr.strip}" unless status.success?
    stdout
  rescue Errno::ENOENT
    raise Error, "#{command.first} not found. Is it installed and on your PATH?"
  end
end
