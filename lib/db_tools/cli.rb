module DbTools
  # Entry point for the `db` executable.
  module CLI
    HELP = <<~TEXT
      Usage: db <command>

        snapshot, s    Save, list and restore snapshots of the development database

      Run `db s` for snapshot commands.
    TEXT

    # @return [Integer] exit status
    def self.run(args, root: Dir.pwd, out: $stdout, err: $stderr)
      command, *rest = args
      case command
      when "snapshot", "s"
        if rest.empty?
          out.puts Snapshot::HELP
        else
          Snapshot.new(DbTools.adapter(root: root), out: out).run(rest)
        end
      else
        out.puts HELP
      end
      0
    rescue Error => e
      err.puts e.message
      1
    end
  end
end
