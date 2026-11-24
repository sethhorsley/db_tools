require "test_helper"

class CliTest < Minitest::Test
  include TestHelpers

  def run_cli(args, root: Dir.pwd)
    out = StringIO.new
    err = StringIO.new
    status = DbTools::CLI.run(args, root: root, out: out, err: err)
    [status, out.string, err.string]
  end

  def test_db_alone_or_an_unknown_command_prints_help
    [[], ["bogus"]].each do |args|
      status, out, = run_cli(args)
      assert_equal 0, status
      assert_includes out, "snapshot, s"
    end
  end

  def test_s_is_an_alias_for_snapshot_and_shows_help_without_a_database
    Dir.mktmpdir do |empty|
      %w[s snapshot].each do |command|
        status, out, = run_cli([command], root: empty)
        assert_equal 0, status
        assert_includes out, "Usage: db snapshot <command>"
      end
    end
  end

  def test_errors_go_to_stderr_with_a_failing_exit_status
    Dir.mktmpdir do |empty|
      status, out, err = run_cli(%w[s list], root: empty)
      assert_equal 1, status
      assert_empty out
      assert_includes err, "No config/database.yml"
    end
  end
end
