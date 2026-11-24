# db_tools

Save, list and restore snapshots of your Rails app's **development** database.
Snapshot before a risky migration or data task, try it, and roll back in seconds.

Works with PostgreSQL, MySQL and SQLite. It only ever touches the `development`
database from `config/database.yml`.

## Install

```ruby
# Gemfile
group :development do
  gem "db_tools"
end
```

## Usage

```
$ db s
Usage: db snapshot <command> [name]      (alias: db s)

  status               Show the database and whether it changed since the last snapshot
  diff [name]          Summarize what changed, per table, since the last snapshot (or name)
  list                 List snapshots of the development database
  create [name]        Save a snapshot (name defaults to a timestamp)
  restore <name>       Replace the development database with a snapshot
                       (the current database is saved as "auto-before-restore" first)
  delete <name>        Delete a snapshot
```

```
$ db s create good_state
Snapshot "good_state" of app_development saved (2.1 GB, 1.2s).

$ db s list
  NAME             CREATED           SIZE
  good_state       2026-11-24 15:20  2.1 GB

$ db s restore good_state
Saved current database as "auto-before-restore".
Restored app_development from "good_state" (1.1s). The snapshot is kept.
```

`status` and `diff` compare the database with the snapshot most recently
created or restored (or the snapshot you name):

```
$ db s status
Database:       app_development
Tables:         79 (4,402,190 rows)
Last snapshot:  good_state (2026-11-24 15:20)
Changed:        yes, 2 tables. Run `db s diff` for a summary.

$ db s diff
Changes in app_development since snapshot "good_state" (2026-11-24 15:20):

  TABLE       BEFORE         NOW  CHANGE
  orders       1,204       1,206  +2 rows
  users       44,481      44,481  rows edited

2 tables changed. BEFORE and NOW are row counts.
```

The comparison uses a row count and checksum per table, so it says which
tables changed and by how many rows, not which rows. On MySQL, snapshots made
before db_tools 0.2.0 can't be compared.

Restoring always saves the current database as `auto-before-restore` first, so
`db s restore auto-before-restore` undoes a restore.

The same commands are available as Rails tasks:

```
rails db:snapshot                       # help
rails db:snapshot:status
rails db:snapshot:diff[good_state]
rails db:snapshot:list
rails db:snapshot:create[good_state]
rails db:snapshot:restore[good_state]
rails db:snapshot:delete[good_state]
```

In zsh, quote the brackets: `rails "db:snapshot:create[good_state]"`.

## How snapshots are stored

| Database   | Snapshot                                                        | Tools needed          |
|------------|-----------------------------------------------------------------|-----------------------|
| PostgreSQL | A database on the same server, `<db>__snap__<name>`             | `psql`                |
| MySQL      | `tmp/db_snapshots/<db>/<name>.sql.gz` (mysqldump)               | `mysql`, `mysqldump`  |
| SQLite     | `tmp/db_snapshots/<db>/<name>.sqlite3` (SQLite's backup API)    | `sqlite3`             |

**PostgreSQL** copies with `CREATE DATABASE ... TEMPLATE`. On PostgreSQL 18+ it
sets `file_copy_method = clone`, so on a copy-on-write filesystem (APFS, Btrfs,
XFS) a snapshot takes about a second and shares disk blocks with the original
until either changes. Elsewhere it's a regular full copy. Postgres can't copy a
database that's in use, so creating or restoring a snapshot **closes open
connections** to it (your server, console and job workers reconnect on their
next query).

**MySQL** snapshots take as long as `mysqldump` and a reload do, roughly a minute
per GB.

## Development

```
bundle install
bundle exec rake test
```

The PostgreSQL and MySQL tests run against a real server when `psql` / `mysql`
can connect with default settings, and are skipped otherwise. They create and
drop their own scratch databases.

## License

MIT
