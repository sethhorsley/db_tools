$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "db_tools"
require "minitest/autorun"
require "stringio"
require "tmpdir"

module TestHelpers
  # Creates a throwaway app directory with a config/database.yml whose
  # development entry is +config+, and yields its path.
  def with_app(config)
    Dir.mktmpdir("db_tools") do |root|
      FileUtils.mkdir_p(File.join(root, "config"))
      File.write(File.join(root, "config", "database.yml"), {"development" => config}.to_yaml)
      yield root
    end
  end

  # Runs `db *args` in +root+ and returns stdout, failing the test on a non-zero exit.
  def db(root, *args)
    out = StringIO.new
    err = StringIO.new
    status = DbTools::CLI.run(args, root: root, out: out, err: err)
    assert_equal 0, status, "db #{args.join(" ")} failed: #{err.string}"
    out.string
  end
end
