require "test_helper"
require "adapters/round_trip"

class PostgresqlTest < Minitest::Test
  include RoundTrip

  DATABASE = "db_tools_test_#{Process.pid}"

  attr_reader :root

  def setup
    DbTools.run("psql", "-X", "-d", "postgres", "-c", "SELECT 1")
  rescue DbTools::Error => e
    skip "PostgreSQL isn't reachable: #{e.message}"
  else
    admin("CREATE DATABASE #{DATABASE}")
    query("CREATE TABLE items (id serial PRIMARY KEY, name text)")
    @root = Dir.mktmpdir("db_tools")
    FileUtils.mkdir_p(File.join(root, "config"))
    File.write(File.join(root, "config", "database.yml"),
      {"development" => {"adapter" => "postgresql", "database" => DATABASE}}.to_yaml)
  end

  def teardown
    return unless root
    scratch = admin("SELECT datname FROM pg_database WHERE datname LIKE '#{DATABASE}%'").split("\n")
    scratch.each { |name| admin(%(DROP DATABASE "#{name}" WITH (FORCE))) }
    FileUtils.rm_rf(root)
  end

  def admin(sql) = DbTools.run("psql", "-X", "-At", "-v", "ON_ERROR_STOP=1", "-d", "postgres", "-c", sql)

  def query(sql) = DbTools.run("psql", "-X", "-At", "-v", "ON_ERROR_STOP=1", "-d", DATABASE, "-c", sql)

  # A running app keeps connections open; Postgres can't copy a database in
  # use, so snapshotting must close them and leave the database usable.
  def test_snapshot_works_while_the_app_is_connected
    app = spawn("psql", "-X", "-d", DATABASE, "-c", "SELECT pg_sleep(60)", out: File::NULL, err: File::NULL)
    sleep 0.1 until admin("SELECT count(*) FROM pg_stat_activity WHERE datname = '#{DATABASE}'").to_i.positive?

    db(root, "s", "create", "while_connected")

    assert_includes db(root, "s", "list"), "while_connected"
    assert_equal "t", admin("SELECT datallowconn FROM pg_database WHERE datname = '#{DATABASE}'").strip,
      "the app must be able to reconnect afterwards"
  ensure
    Process.kill("TERM", app) rescue nil # standard:disable Style/RescueModifier
    Process.wait(app) rescue nil # standard:disable Style/RescueModifier
  end

  def test_snapshots_are_databases_named_after_the_development_database
    db(root, "s", "create", "good_state")
    assert_equal "1", admin("SELECT count(*) FROM pg_database WHERE datname = '#{DATABASE}__snap__good_state'").strip
  end
end
