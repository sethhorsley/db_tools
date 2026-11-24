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

      private

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
