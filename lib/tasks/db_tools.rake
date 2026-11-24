namespace :db do
  desc "Show the db:snapshot commands"
  task :snapshot do
    puts DbTools::Snapshot::HELP.sub("db snapshot <command> [name]      (alias: db s)", "rails db:snapshot:<command>[name]")
  end

  namespace :snapshot do
    {
      status: "Show whether the development database changed since the last snapshot",
      diff: "Summarize what changed since the last snapshot (optional name)",
      list: "List snapshots of the development database",
      create: "Save a snapshot of the development database (optional name)",
      restore: "Replace the development database with a snapshot",
      delete: "Delete a snapshot"
    }.each do |command, description|
      desc description
      task command, %i[status list].include?(command) ? [] : [:name] do |_task, args|
        abort "db:snapshot only works in development (Rails.env is #{Rails.env})." unless Rails.env.development?

        DbTools::Snapshot.new(DbTools.adapter(root: Rails.root.to_s)).run([command.to_s, args[:name]].compact)
      rescue DbTools::Error => e
        abort e.message
      end
    end
  end
end
