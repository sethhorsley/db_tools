# The behavior every adapter must have, run against a real database.
# Includers provide #root (an app dir pointing at a scratch database) and
# #query(sql) returning stdout.
module RoundTrip
  include TestHelpers

  def rows
    query("SELECT name FROM items ORDER BY id").split("\n")
  end

  def test_restore_brings_back_the_snapshot_and_the_safety_copy_undoes_it
    query("INSERT INTO items (name) VALUES ('kept')")
    db(root, "s", "create", "good_state")
    query("INSERT INTO items (name) VALUES ('added later')")

    db(root, "s", "restore", "good_state")
    assert_equal ["kept"], rows

    db(root, "s", "restore", "auto-before-restore")
    assert_equal ["kept", "added later"], rows
  end

  def test_restore_keeps_the_snapshot_so_it_can_be_restored_again
    query("INSERT INTO items (name) VALUES ('kept')")
    db(root, "s", "create", "good_state")

    2.times do
      query("DELETE FROM items")
      db(root, "s", "restore", "good_state")
      assert_equal ["kept"], rows
    end
  end

  def test_list_and_delete
    db(root, "s", "create", "first")
    db(root, "s", "create", "second")

    listed = db(root, "s", "list")
    assert_match(/first\s+\d{4}-/, listed)
    assert_match(/second\s+\d{4}-/, listed)

    db(root, "s", "delete", "first")
    refute_includes db(root, "s", "list"), "first"
  end
end
