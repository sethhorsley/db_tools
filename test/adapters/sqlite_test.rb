require "test_helper"
require "adapters/round_trip"

class SqliteTest < Minitest::Test
  include RoundTrip

  attr_reader :root

  def setup
    @root = Dir.mktmpdir("db_tools")
    FileUtils.mkdir_p(File.join(root, "config"))
    File.write(File.join(root, "config", "database.yml"),
      {"development" => {"adapter" => "sqlite3", "database" => "storage/development.sqlite3"}}.to_yaml)
    FileUtils.mkdir_p(File.join(root, "storage"))
    query("PRAGMA journal_mode = WAL; CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT)")
  end

  def teardown
    FileUtils.rm_rf(root)
  end

  def query(sql)
    DbTools.run("sqlite3", File.join(root, "storage", "development.sqlite3"), sql)
  end

  def test_snapshots_are_stored_under_tmp_so_rails_ignores_them
    db(root, "s", "create", "good_state")
    assert File.exist?(File.join(root, "tmp", "db_snapshots", "development", "good_state.sqlite3"))
  end
end
