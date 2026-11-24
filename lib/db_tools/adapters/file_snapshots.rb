require "fileutils"

module DbTools
  module Adapters
    # Shared storage for adapters that keep snapshots as files in
    # tmp/db_snapshots/<database>/. Includers define #extension, #dump(path)
    # and #load(path).
    module FileSnapshots
      def list
        Dir.glob(File.join(directory, "*#{extension}")).map do |path|
          {name: File.basename(path, extension), created_at: File.mtime(path), size: File.size(path)}
        end
      end

      # Dumps to a temporary file first so a failed dump never leaves a
      # half-written snapshot behind.
      def create(name)
        FileUtils.mkdir_p(directory)
        partial = "#{path(name)}.partial"
        dump(partial)
        File.rename(partial, path(name))
      ensure
        FileUtils.rm_f(partial) if partial
      end

      def restore(name)
        load(path(name))
      end

      def delete(name)
        File.delete(path(name))
      end

      private

      def directory
        DbTools.snapshot_directory(root, database)
      end

      def path(name)
        File.join(directory, name + extension)
      end
    end
  end
end
