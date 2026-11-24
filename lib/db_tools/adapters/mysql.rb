require "json"
require "shellwords"

module DbTools
  module Adapters
    # MySQL can't copy a database server-side, so snapshots are gzipped
    # mysqldump files. Restoring recreates the database and loads the dump.
    # A dump can't be queried, so each snapshot's fingerprint is saved beside it.
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

      def create(name)
        super
        File.write(fingerprint_path(name), JSON.generate(fingerprint))
      end

      def delete(name)
        super
        FileUtils.rm_f(fingerprint_path(name))
      end

      # Row count and CHECKSUM TABLE per table. For a snapshot, the one saved
      # when it was created (nil for snapshots made before fingerprints existed).
      def fingerprint(name = nil)
        if name
          path = fingerprint_path(name)
          return File.exist?(path) ? JSON.parse(File.read(path)) : nil
        end

        tables = mysql("SELECT table_name FROM information_schema.tables " \
          "WHERE table_schema = DATABASE() AND table_type = 'BASE TABLE'").lines.map(&:chomp)
        return {} if tables.empty?

        counts = mysql(tables.map { |t| "SELECT #{literal(t)}, count(*) FROM #{ident(t)}" }.join(" UNION ALL "))
          .lines.to_h { |line| line.chomp.split("\t") }
        checksums = mysql("CHECKSUM TABLE #{tables.map { |t| ident(t) }.join(", ")}")
          .lines.to_h { |line| line.chomp.split("\t") }
        tables.to_h { |t| [t, [counts.fetch(t).to_i, checksums.fetch("#{database}.#{t}")]] }
      end

      private

      attr_reader :connection, :encoding, :env

      def fingerprint_path(name)
        path(name).delete_suffix(extension) + ".json"
      end

      def mysql(sql)
        DbTools.run("mysql", *connection, "--batch", "--skip-column-names", database, "-e", sql, env: env)
      end

      def literal(value)
        "'#{value.gsub("'", "''")}'"
      end

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
