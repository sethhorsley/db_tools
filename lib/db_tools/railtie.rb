module DbTools
  class Railtie < Rails::Railtie
    rake_tasks do
      load File.expand_path("../tasks/db_tools.rake", __dir__)
    end
  end
end
