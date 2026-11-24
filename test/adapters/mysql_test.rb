require "test_helper"
require "adapters/round_trip"

class MysqlTest < Minitest::Test
  include RoundTrip

  DATABASE = "db_tools_test_#{Process.pid}"

  attr_reader :root

  def setup
    DbTools.run("mysql", "-e", "SELECT 1")
  rescue DbTools::Error => e
    # CI sets REQUIRE_DB so a broken service fails the job instead of skipping.
    flunk "MySQL isn't reachable: #{e.message}" if ENV["REQUIRE_DB"] == "mysql"
    skip "MySQL isn't reachable: #{e.message}"
  else
    DbTools.run("mysql", "-e", "CREATE DATABASE #{DATABASE}")
    query("CREATE TABLE items (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(255))")
    @root = Dir.mktmpdir("db_tools")
    FileUtils.mkdir_p(File.join(root, "config"))
    File.write(File.join(root, "config", "database.yml"),
      {"development" => {"adapter" => "mysql2", "database" => DATABASE}}.to_yaml)
  end

  def teardown
    return unless root
    DbTools.run("mysql", "-e", "DROP DATABASE IF EXISTS #{DATABASE}")
    FileUtils.rm_rf(root)
  end

  def query(sql) = DbTools.run("mysql", "-N", "-e", sql, DATABASE)
end
