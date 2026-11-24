module DbTools
  module Adapters
    # Snapshots are databases on the same server, copied with
    # CREATE DATABASE ... TEMPLATE. On PostgreSQL 18+ the copy uses
    # file_copy_method = clone, which is near-instant on copy-on-write
    # filesystems (APFS, Btrfs, XFS); otherwise it is a regular file copy.
    class Postgresql
      SEPARATOR = "__snap__"
      MAX_NAME_BYTES = 63

      attr_reader :root, :database

      def initialize(config, root)
        @root = root
        @database = config.fetch("database")
        @env = {
          "PGHOST" => config["host"],
          "PGPORT" => config["port"]&.to_s,
          "PGUSER" => config["username"],
          "PGPASSWORD" => config["password"]
        }.compact
      end

      def list
        rows = psql("SELECT datname, pg_database_size(oid), coalesce(shobj_description(oid, 'pg_database'), '') FROM pg_database")
        rows.lines.filter_map do |line|
          datname, size, comment = line.chomp.split("|", 3)
          next unless datname.start_with?(prefix)
          {name: datname.delete_prefix(prefix), created_at: parse_time(comment), size: size.to_i}
        end
      end

      def create(name)
        snapshot = prefix + name
        if snapshot.bytesize > MAX_NAME_BYTES
          raise Error, "Snapshot name too long: PostgreSQL database names are limited to #{MAX_NAME_BYTES} bytes."
        end
        copy(from: database, to: snapshot)
        psql("COMMENT ON DATABASE #{ident(snapshot)} IS #{literal("db_tools snapshot #{Time.now.utc.iso8601}")}")
      end

      def restore(name)
        psql("DROP DATABASE IF EXISTS #{ident(database)} WITH (FORCE)")
        copy(from: prefix + name, to: database)
      end

      def delete(name)
        psql("DROP DATABASE #{ident(prefix + name)} WITH (FORCE)")
      end

      # Row count and a checksum per table, of the development database or of
      # a snapshot. The checksum sums each row's xmin (the transaction that
      # wrote it) rather than hashing contents: any insert, update or delete
      # changes it, it reads ~10x faster, and copies made with TEMPLATE keep
      # xmin, so a snapshot matches the database it was taken from.
      def fingerprint(name = nil)
        db = name ? prefix + name : database
        tables = psql(<<~SQL, database: db).lines.map { |line| line.chomp.split("|", 2) }
          SELECT CASE WHEN schemaname = 'public' THEN tablename ELSE schemaname || '.' || tablename END,
                 format('%I.%I', schemaname, tablename)
          FROM pg_tables WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
        SQL
        return {} if tables.empty?

        sql = tables.map do |table, qualified|
          "SELECT count(*), coalesce(sum(xmin::text::bigint), 0), #{literal(table)} FROM #{qualified}"
        end.join(" UNION ALL ")
        psql(sql, database: db).lines.to_h do |line|
          count, sum, table = line.chomp.split("|", 3)
          [table, [count.to_i, sum]]
        end
      end

      private

      attr_reader :env

      def prefix
        database + SEPARATOR
      end

      # Postgres refuses to copy a database with open connections, so block new
      # ones (a running app reconnects immediately), close the rest, copy, and
      # always reopen the source.
      def copy(from:, to:)
        psql("ALTER DATABASE #{ident(from)} ALLOW_CONNECTIONS false")
        begin
          psql("SELECT pg_terminate_backend(pid) FROM pg_stat_activity " \
            "WHERE datname = #{literal(from)} AND pid <> pg_backend_pid()")
          create_from_template(from, to)
        ensure
          psql("ALTER DATABASE #{ident(from)} ALLOW_CONNECTIONS true")
        end
      end

      def create_from_template(from, to)
        version = psql("SHOW server_version_num").to_i
        create = "CREATE DATABASE #{ident(to)} TEMPLATE #{ident(from)}"
        create += " STRATEGY = FILE_COPY" if version >= 150_000
        return psql(create) if version < 180_000

        begin
          psql("SET file_copy_method = clone", create)
        rescue Error
          # The filesystem can't clone; fall back to a regular copy.
          psql(create)
        end
      end

      # Each statement runs separately (CREATE/DROP DATABASE can't run in a
      # transaction) but in one session, so SET applies to what follows.
      def psql(*statements, database: "postgres")
        DbTools.run(
          "psql", "-X", "-q", "-A", "-t", "-v", "ON_ERROR_STOP=1", "-d", database,
          *statements.flat_map { |sql| ["-c", sql] },
          env: env
        )
      end

      def ident(name)
        %("#{name.gsub('"', '""')}")
      end

      def literal(value)
        "'#{value.gsub("'", "''")}'"
      end

      def parse_time(comment)
        Time.iso8601(comment.split.last.to_s)
      rescue ArgumentError
        nil
      end
    end
  end
end
