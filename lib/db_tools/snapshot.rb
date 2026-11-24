module DbTools
  # The snapshot commands, shared by the `db` executable and the Rails tasks.
  # Storage is up to the adapter; this class handles names, safety and output.
  class Snapshot
    NAME_FORMAT = /\A[A-Za-z0-9_-]{1,40}\z/
    AUTO_NAME = "auto-before-restore"

    HELP = <<~TEXT
      Usage: db snapshot <command> [name]      (alias: db s)

        status               Show the database and whether it changed since the last snapshot
        diff [name]          Summarize what changed, per table, since the last snapshot (or name)
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
      when "status" then status
      when "diff" then diff(name)
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
        out.puts "  #{s[:name].ljust(width)}  #{created(s).ljust(16)}  #{human_size(s[:size])}"
      end
    end

    def create(name = nil)
      name ||= Time.now.strftime("%Y%m%d-%H%M%S")
      validate_name!(name)
      raise Error, "A snapshot named \"#{name}\" already exists." if exists?(name)

      seconds = timed { adapter.create(name) }
      record_last(name)
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
      record_last(name)
      out.puts "Restored #{adapter.database} from \"#{name}\" (#{seconds}s). The snapshot is kept."
    end

    def delete(name)
      require_existing!(name, "delete")
      adapter.delete(name)
      out.puts "Deleted snapshot \"#{name}\"."
    end

    def status
      current = adapter.fingerprint
      out.puts "Database:       #{adapter.database}"
      out.puts "Tables:         #{current.size} (#{delimit(current.values.sum(&:first))} rows)"

      snapshot = last_snapshot
      unless snapshot
        out.puts "Last snapshot:  none. Create one with `db s create [name]`."
        return
      end
      out.puts "Last snapshot:  #{snapshot[:name]} (#{created(snapshot)})"

      before = adapter.fingerprint(snapshot[:name])
      changed = before && changes(before, current)
      out.puts "Changed:        " +
        if changed.nil? then "unknown, \"#{snapshot[:name]}\" was saved before db_tools could compare snapshots"
        elsif changed.empty? then "no"
        else "yes, #{pluralize(changed.size, "table")}. Run `db s diff` for a summary."
        end
    end

    def diff(name = nil)
      snapshot = name ? find!(name, "diff") : last_snapshot
      raise Error, "No snapshots of #{adapter.database} yet. Create one with `db s create [name]`." unless snapshot

      before = adapter.fingerprint(snapshot[:name])
      raise Error, "Can't diff against \"#{snapshot[:name]}\": it was saved before db_tools could compare snapshots." unless before

      changed = changes(before, adapter.fingerprint)
      since = "since snapshot \"#{snapshot[:name]}\" (#{created(snapshot)})"
      if changed.empty?
        out.puts "No changes in #{adapter.database} #{since}."
        return
      end

      out.puts "Changes in #{adapter.database} #{since}:", ""
      width = [changed.map { |table, *| table.length }.max, 5].max
      out.puts "  #{"TABLE".ljust(width)}  #{"BEFORE".rjust(10)}  #{"NOW".rjust(10)}  CHANGE"
      changed.each do |table, was, now|
        out.puts "  #{table.ljust(width)}  #{rows_cell(was)}  #{rows_cell(now)}  #{change_label(was, now)}"
      end
      out.puts "", "#{pluralize(changed.size, "table")} changed. BEFORE and NOW are row counts."
    end

    private

    attr_reader :adapter, :out

    # Tables whose row count or checksum differ, as [table, [rows, checksum] or nil, same].
    def changes(before, after)
      (before.keys | after.keys).sort.filter_map do |table|
        [table, before[table], after[table]] unless before[table] == after[table]
      end
    end

    def change_label(was, now)
      return "table added" unless was
      return "table removed" unless now
      delta = now.first - was.first
      return "rows edited" if delta.zero?
      format("%+d %s", delta, (delta.abs == 1) ? "row" : "rows")
    end

    def rows_cell(fingerprint)
      (fingerprint ? delimit(fingerprint.first) : "-").rjust(10)
    end

    # The snapshot most recently created or restored here, falling back to the
    # newest one (e.g. snapshots made before this was recorded).
    def last_snapshot
      snapshots = adapter.list
      recorded = File.read(last_path).strip if File.exist?(last_path)
      snapshots.find { |s| s[:name] == recorded } || snapshots.max_by { |s| s[:created_at] || Time.at(0) }
    end

    def record_last(name)
      FileUtils.mkdir_p(File.dirname(last_path))
      File.write(last_path, name)
    end

    def last_path
      File.join(DbTools.snapshot_directory(adapter.root, adapter.database), ".last")
    end

    def find!(name, command)
      require_existing!(name, command)
      adapter.list.find { |s| s[:name] == name }
    end

    def created(snapshot)
      snapshot[:created_at]&.strftime("%Y-%m-%d %H:%M") || "unknown"
    end

    def delimit(number)
      number.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
    end

    def pluralize(count, word)
      "#{count} #{word}#{"s" unless count == 1}"
    end

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
