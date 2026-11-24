require_relative "lib/db_tools/version"

Gem::Specification.new do |spec|
  spec.name = "db_tools"
  spec.version = DbTools::VERSION
  spec.authors = ["Seth Horsley"]
  spec.email = ["git-public.ch12j@seth4242.com"]

  spec.summary = "Snapshot and restore your local development database."
  spec.description = "Save, list and restore snapshots of a Rails app's development " \
    "database. Supports PostgreSQL, MySQL and SQLite."
  spec.homepage = "https://github.com/sethhorsley/db_tools"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.files = Dir["lib/**/*", "bin/db", "README.md", "LICENSE.txt"]
  spec.bindir = "bin"
  spec.executables = ["db"]
  spec.require_paths = ["lib"]
end
