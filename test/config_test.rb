require "test_helper"

class ConfigTest < Minitest::Test
  def with_database_yml(yaml)
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "config"))
      File.write(File.join(root, "config", "database.yml"), yaml)
      yield root
    end
  end

  def test_only_the_development_database_is_used_with_erb_and_aliases
    yaml = <<~YAML
      default: &default
        adapter: postgresql
        pool: <%= 2 + 3 %>
      development:
        <<: *default
        database: app_development
      production:
        <<: *default
        database: app_production
    YAML
    with_database_yml(yaml) do |root|
      adapter = DbTools.adapter(root: root)
      assert_instance_of DbTools::Adapters::Postgresql, adapter
      assert_equal "app_development", adapter.database
    end
  end

  def test_multi_database_apps_snapshot_the_primary_database
    yaml = <<~YAML
      development:
        primary:
          adapter: sqlite3
          database: storage/development.sqlite3
        cache:
          adapter: sqlite3
          database: storage/development_cache.sqlite3
    YAML
    with_database_yml(yaml) do |root|
      assert_equal "storage/development.sqlite3", DbTools.adapter(root: root).database
    end
  end

  def test_each_supported_adapter_maps_to_its_snapshot_strategy
    {
      "postgresql" => DbTools::Adapters::Postgresql,
      "mysql2" => DbTools::Adapters::Mysql,
      "trilogy" => DbTools::Adapters::Mysql,
      "sqlite3" => DbTools::Adapters::Sqlite
    }.each do |name, adapter_class|
      with_database_yml("development:\n  adapter: #{name}\n  database: app\n") do |root|
        assert_instance_of adapter_class, DbTools.adapter(root: root)
      end
    end
  end

  def test_unsupported_adapter_is_refused
    with_database_yml("development:\n  adapter: oracle\n  database: app\n") do |root|
      error = assert_raises(DbTools::Error) { DbTools.adapter(root: root) }
      assert_match(/Unsupported database adapter "oracle"/, error.message)
    end
  end

  def test_missing_development_entry_is_refused
    with_database_yml("production:\n  adapter: postgresql\n  database: app\n") do |root|
      error = assert_raises(DbTools::Error) { DbTools.adapter(root: root) }
      assert_match(/no development database/, error.message)
    end
  end
end
