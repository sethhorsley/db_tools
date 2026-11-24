require "shellwords"

module DbTools
  module Adapters
    # MySQL can't copy a database server-side, so snapshots are gzipped
    # mysqldump files. Restoring recreates the database and loads the dump.
    class Mysql
      include FileSnapshots

      attr_reader :root, :database

      def initialize(config, root)
        @root = root
        @database = config.fetch("database")
        @encoding = config["encoding"]
        @connection = {
          "--host" => config["host"],
          "--port" => config["port"]&.to_s,
          "--user" => config["username"],
          "--socket" => config["socket"]
        }.compact.map { |flag, value| "#{flag}=#{value}" }
        @env = config["password"] ? {"MYSQL_PWD" => config["password"].to_s} : {}
      end

      private

      attr_reader :connection, :encoding, :env

      def extension
        ".sql.gz"
      end

      def dump(path)
        mysqldump = ["mysqldump", *connection, "--single-transaction", "--routines", "--triggers", "--events", database]
        pipeline("#{mysqldump.shelljoin} | gzip > #{path.shellescape}")
      end

      def load(path)
        create = "CREATE DATABASE #{ident(database)}"
        create += " CHARACTER SET #{encoding}" if encoding
        DbTools.run("mysql", *connection, "-e", "DROP DATABASE IF EXISTS #{ident(database)}; #{create}", env: env)
        pipeline("gunzip -c #{path.shellescape} | #{["mysql", *connection, database].shelljoin}")
      end

      # pipefail so a failing mysqldump/mysql isn't hidden by gzip succeeding.
      def pipeline(command)
        DbTools.run("bash", "-o", "pipefail", "-c", command, env: env)
      end

      def ident(name)
        "`#{name.gsub("`", "``")}`"
      end
    end
  end
end
