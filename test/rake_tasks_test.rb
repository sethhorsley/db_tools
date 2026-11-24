require "test_helper"
require "rake"

# Just enough of Rails for the tasks: they read Rails.env and Rails.root.
module Rails
  class << self
    attr_accessor :env, :root
  end
end

class RakeTasksTest < Minitest::Test
  include TestHelpers

  class Env < String
    def development? = self == "development"
  end

  def setup
    @rake = Rake::Application.new
    Rake.application = @rake
    load File.expand_path("../lib/tasks/db_tools.rake", __dir__)
  end

  def invoke(task, *args)
    out, err = capture_io { @rake[task].invoke(*args) }
    [out, err]
  end

  def test_tasks_snapshot_the_development_database
    with_app("adapter" => "sqlite3", "database" => "development.sqlite3") do |root|
      DbTools.run("sqlite3", File.join(root, "development.sqlite3"), "CREATE TABLE items (id INTEGER)")
      Rails.env = Env.new("development")
      Rails.root = Pathname(root)

      invoke("db:snapshot:create", "from_rake")

      assert_includes db(root, "s", "list"), "from_rake"
    end
  end

  def test_tasks_refuse_to_run_outside_development
    Rails.env = Env.new("production")
    error = assert_raises(SystemExit) { invoke("db:snapshot:restore", "good_state") }
    refute error.success?
  end

  # `rails -T` shows arg_names, so list must not advertise a name it ignores.
  def test_only_commands_that_take_a_name_accept_one
    assert_empty @rake["db:snapshot:list"].arg_names
    %w[create restore delete].each do |command|
      assert_equal [:name], @rake["db:snapshot:#{command}"].arg_names
    end
  end

  def test_db_snapshot_alone_prints_help_in_rake_syntax
    out, = invoke("db:snapshot")
    assert_includes out, "rails db:snapshot:<command>[name]"
  end
end
