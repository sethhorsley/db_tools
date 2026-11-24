module DbTools
  module Adapters
    # Snapshots are copies made with SQLite's online backup API (the sqlite3
    # shell's .backup and .restore), which is safe while the app has the
    # database open, including in WAL mode.
    class Sqlite
      include FileSnapshots

      attr_reader :root, :database

      def initialize(config, root)
        @root = root
        @database = config.fetch("database")
      end

      # Row count and a SHA3 of the contents per table, of the development
      # database or of a snapshot file. sha3_query is built into the sqlite3 shell.
      def fingerprint(name = nil)
        file = name ? path(name) : database_path
        tables = DbTools.run("sqlite3", "-readonly", file,
          "SELECT name FROM sqlite_schema WHERE type = 'table' AND name NOT LIKE 'sqlite_%'").lines.map(&:chomp)
        return {} if tables.empty?

        sql = tables.map do |table|
          ident = %("#{table.gsub('"', '""')}")
          "SELECT (SELECT count(*) FROM #{ident}), hex(sha3_query(#{literal("SELECT * FROM #{ident}")})), #{literal(table)}"
        end.join(" UNION ALL ")
        DbTools.run("sqlite3", "-readonly", file, sql).lines.to_h do |line|
          count, hash, table = line.chomp.split("|", 3)
          [table, [count.to_i, hash]]
        end
      end

      private

      def literal(value)
        "'#{value.gsub("'", "''")}'"
      end

      def extension
        ".sqlite3"
      end

      def dump(path)
        DbTools.run("sqlite3", database_path, ".backup #{quote(path)}")
      end

      def load(path)
        DbTools.run("sqlite3", database_path, ".restore #{quote(path)}")
      end

      # Rails resolves relative SQLite paths against the app root.
      def database_path
        File.expand_path(database, root)
      end

      # The sqlite3 shell takes single-quoted arguments without escapes.
      def quote(path)
        raise Error, "Paths containing ' aren't supported: #{path}" if path.include?("'")
        "'#{path}'"
      end
    end
  end
end
