module DbTools
  # The snapshot commands, shared by the `db` executable and the Rails tasks.
  # Storage is up to the adapter; this class handles names, safety and output.
  class Snapshot
    NAME_FORMAT = /\A[A-Za-z0-9_-]{1,40}\z/
    AUTO_NAME = "auto-before-restore"

    HELP = <<~TEXT
      Usage: db snapshot <command> [name]      (alias: db s)

        list                 List snapshots of the development database
        create [name]        Save a snapshot (name defaults to a timestamp)
        restore <name>       Replace the development database with a snapshot
                             (the current database is saved as "#{AUTO_NAME}" first)
        delete <name>        Delete a snapshot

      Names may use letters, numbers, - and _ (up to 40 characters).
    TEXT

    def initialize(adapter, out: $stdout)
      @adapter = adapter
      @out = out
    end

    def run(args)
      command, name = args
      case command
      when "list" then list
      when "create" then create(name)
      when "restore" then restore(name)
      when "delete" then delete(name)
      else out.puts HELP
      end
    end

    def list
      snapshots = adapter.list.sort_by { |s| s[:created_at] || Time.at(0) }
      if snapshots.empty?
        out.puts "No snapshots of #{adapter.database} yet. Create one with `db s create [name]`."
        return
      end

      width = [snapshots.map { |s| s[:name].length }.max, 4].max
      out.puts "  #{"NAME".ljust(width)}  #{"CREATED".ljust(16)}  SIZE"
      snapshots.each do |s|
        created = s[:created_at]&.strftime("%Y-%m-%d %H:%M") || "unknown"
        out.puts "  #{s[:name].ljust(width)}  #{created.ljust(16)}  #{human_size(s[:size])}"
      end
    end

    def create(name = nil)
      name ||= Time.now.strftime("%Y%m%d-%H%M%S")
      validate_name!(name)
      raise Error, "A snapshot named \"#{name}\" already exists." if exists?(name)

      seconds = timed { adapter.create(name) }
      out.puts "Snapshot \"#{name}\" of #{adapter.database} saved (#{human_size(size_of(name))}, #{seconds}s)."
    end

    def restore(name)
      require_existing!(name, "restore")

      # Keep the current state so a mistaken restore can be undone, unless
      # we're restoring that very safety copy.
      unless name == AUTO_NAME
        adapter.delete(AUTO_NAME) if exists?(AUTO_NAME)
        adapter.create(AUTO_NAME)
        out.puts "Saved current database as \"#{AUTO_NAME}\"."
      end

      seconds = timed { adapter.restore(name) }
      out.puts "Restored #{adapter.database} from \"#{name}\" (#{seconds}s). The snapshot is kept."
    end

    def delete(name)
      require_existing!(name, "delete")
      adapter.delete(name)
      out.puts "Deleted snapshot \"#{name}\"."
    end

    private

    attr_reader :adapter, :out

    def validate_name!(name)
      return if NAME_FORMAT.match?(name)
      raise Error, "Invalid snapshot name \"#{name}\". Use letters, numbers, - and _ (up to 40 characters)."
    end

    def require_existing!(name, command)
      raise Error, "Usage: db snapshot #{command} <name>" if name.nil?
      return if exists?(name)
      raise Error, "No snapshot named \"#{name}\". Run `db s list` to see them."
    end

    def exists?(name)
      adapter.list.any? { |s| s[:name] == name }
    end

    def size_of(name)
      adapter.list.find { |s| s[:name] == name }&.fetch(:size)
    end

    def timed
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
      (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(1)
    end

    def human_size(bytes)
      return "unknown" unless bytes
      units = %w[B KB MB GB TB]
      exponent = bytes.zero? ? 0 : [(Math.log(bytes) / Math.log(1024)).floor, units.size - 1].min
      format("%.1f %s", bytes.to_f / 1024**exponent, units[exponent]).sub(".0 B", " B")
    end
  end
end
