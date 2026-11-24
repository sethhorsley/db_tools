require "test_helper"

class SnapshotTest < Minitest::Test
  # Records what the snapshot commands ask storage to do, so these tests
  # cover the decisions (names, safety copy, refusals) independent of a database.
  class FakeAdapter
    attr_reader :calls, :root
    attr_accessor :fingerprints

    def initialize(existing = [], root: Dir.mktmpdir)
      @snapshots = existing.to_h { |name| [name, Time.now] }
      @calls = []
      @root = root
      @fingerprints = {}
    end

    def fingerprint(name = nil) = fingerprints[name]

    def database = "app_development"

    def list = @snapshots.map { |name, time| {name: name, created_at: time, size: 2048} }

    def create(name)
      @calls << [:create, name]
      @snapshots[name] = Time.now
    end

    def restore(name) = @calls << [:restore, name]

    def delete(name)
      @calls << [:delete, name]
      @snapshots.delete(name)
    end
  end

  def setup
    @out = StringIO.new
  end

  def snapshot(adapter) = DbTools::Snapshot.new(adapter, out: @out)

  def test_create_without_a_name_uses_a_timestamp
    adapter = FakeAdapter.new
    snapshot(adapter).run(["create"])

    assert_match(/\A\d{8}-\d{6}\z/, adapter.calls.last.last)
    assert_includes @out.string, "saved (2.0 KB"
  end

  def test_names_that_are_unsafe_as_file_or_database_names_are_refused
    ["has space", "../escape", "semi;colon", "x" * 41].each do |name|
      adapter = FakeAdapter.new
      error = assert_raises(DbTools::Error) { snapshot(adapter).create(name) }
      assert_match(/Invalid snapshot name/, error.message)
      assert_empty adapter.calls, "#{name.inspect} must not reach storage"
    end
  end

  def test_create_refuses_to_overwrite_an_existing_snapshot
    adapter = FakeAdapter.new(["good_state"])
    assert_raises(DbTools::Error) { snapshot(adapter).create("good_state") }
    assert_empty adapter.calls
  end

  def test_restore_saves_the_current_database_first_so_it_can_be_undone
    adapter = FakeAdapter.new(["good_state"])
    snapshot(adapter).restore("good_state")

    assert_equal [[:create, "auto-before-restore"], [:restore, "good_state"]], adapter.calls
  end

  def test_restore_replaces_the_previous_safety_copy
    adapter = FakeAdapter.new(["good_state", "auto-before-restore"])
    snapshot(adapter).restore("good_state")

    assert_equal [[:delete, "auto-before-restore"], [:create, "auto-before-restore"], [:restore, "good_state"]], adapter.calls
  end

  def test_restoring_the_safety_copy_does_not_overwrite_it_first
    adapter = FakeAdapter.new(["auto-before-restore"])
    snapshot(adapter).restore("auto-before-restore")

    assert_equal [[:restore, "auto-before-restore"]], adapter.calls
  end

  def test_restoring_an_unknown_snapshot_touches_nothing
    adapter = FakeAdapter.new(["good_state"])
    error = assert_raises(DbTools::Error) { snapshot(adapter).restore("typo") }

    assert_match(/No snapshot named "typo"/, error.message)
    assert_empty adapter.calls
  end

  def test_restore_and_delete_require_a_name
    assert_raises(DbTools::Error) { snapshot(FakeAdapter.new).run(["restore"]) }
    assert_raises(DbTools::Error) { snapshot(FakeAdapter.new).run(["delete"]) }
  end

  def test_list_shows_each_snapshot_with_its_size
    snapshot(FakeAdapter.new(["good_state", "before_task"])).list

    assert_match(/NAME\s+CREATED\s+SIZE/, @out.string)
    assert_match(/good_state\s+\d{4}-\d{2}-\d{2} \d{2}:\d{2}\s+2\.0 KB/, @out.string)
    assert_includes @out.string, "before_task"
  end

  def test_list_with_no_snapshots_says_how_to_make_one
    snapshot(FakeAdapter.new).list
    assert_includes @out.string, "No snapshots of app_development yet"
  end

  def test_status_without_snapshots_says_how_to_make_one
    adapter = FakeAdapter.new
    adapter.fingerprints[nil] = {"items" => [1200, "a"], "users" => [3, "b"]}
    snapshot(adapter).status

    assert_match(/Tables:\s+2 \(1,203 rows\)/, @out.string)
    assert_includes @out.string, "Last snapshot:  none"
  end

  def test_diff_labels_each_kind_of_change
    adapter = FakeAdapter.new(["good_state"])
    adapter.fingerprints["good_state"] = {"same" => [1, "a"], "grew" => [1, "a"], "edited" => [2, "a"], "dropped" => [1, "a"]}
    adapter.fingerprints[nil] = {"same" => [1, "a"], "grew" => [3, "b"], "edited" => [2, "b"], "created" => [5, "a"]}
    snapshot(adapter).diff

    assert_match(/created\s+-\s+5\s+table added/, @out.string)
    assert_match(/dropped\s+1\s+-\s+table removed/, @out.string)
    assert_match(/edited\s+2\s+2\s+rows edited/, @out.string)
    assert_match(/grew\s+1\s+3\s+\+2 rows/, @out.string)
    refute_match(/^\s+same/, @out.string)
    assert_includes @out.string, "4 tables changed."
  end

  def test_status_compares_with_the_snapshot_last_created_or_restored
    adapter = FakeAdapter.new(["older", "newer"])
    adapter.fingerprints.merge!("older" => {"t" => [1, "a"]}, "newer" => {"t" => [2, "b"]}, nil => {"t" => [1, "a"]})
    snapshot(adapter).restore("older")
    snapshot(adapter).status

    assert_match(/Last snapshot:\s+older.*\nChanged:\s+no/, @out.string)
  end

  def test_snapshots_without_a_fingerprint_are_reported_not_compared
    adapter = FakeAdapter.new(["old_dump"])
    adapter.fingerprints[nil] = {"t" => [1, "a"]}
    snapshot(adapter).status

    assert_match(/Changed:\s+unknown/, @out.string)
    assert_raises(DbTools::Error) { snapshot(adapter).diff }
  end

  def test_unknown_subcommand_prints_help
    snapshot(FakeAdapter.new).run(["bogus"])
    assert_includes @out.string, "Usage: db snapshot"
  end
end
