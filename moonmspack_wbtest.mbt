// Whitebox tests for archive metrics and safety helpers.

///|
test "archive metrics" {
  let entries : Array[ArchiveEntry] = [
    { name: "a", size: 4, compressed_size: 3, offset: 0, folder: 0, flags: 0, },
    { name: "b", size: 8, compressed_size: 5, offset: 3, folder: 1, flags: 1, },
  ]
  let listing : ArchiveListing = { format: "CAB", entries, warnings: [], }
  let metrics = archive_metrics(listing)
  assert_eq(metrics.entry_count, 2)
  assert_eq(metrics.total_size, 12)
  assert_eq(metrics.total_compressed_size, 8)
  assert_eq(metrics.largest_size, 8)
  assert_eq(metrics.largest_index, 1)
  assert_eq(metrics.folders, 2)
  assert_eq(metrics.files_with_data, 2)
  assert_true(find_archive_entry(listing, "a") is Some(_))
  assert_true(find_archive_entry(listing, "z") is None)
  assert_eq(entries_in_container(listing, 0).length(), 1)
  assert_eq(entries_in_container(listing, 2).length(), 0)
  assert_eq(entries_by_size(listing, 4, 8).length(), 2)
  assert_eq(entries_by_size(listing, 9, 2).length(), 0)
  assert_true(has_unique_entry_names(listing))
  assert_eq(take_archive_entries(listing, 1).length(), 1)
  assert_eq(take_archive_entries(listing, 20).length(), 2)
  assert_eq(container_size(listing, 1), 8)
  assert_eq(count_entries_with_flags(listing, 1), 1)
  assert_eq(archive_format_label(listing), "Microsoft Cabinet")
  assert_true(within_output_budget(listing, 12))
  assert_false(within_output_budget(listing, 11))
  validate_listing(listing)
  validate_entry_identity(listing)
  validate_entry_ranges(listing, 20)
}

///|
test "duplicate and empty listings" {
  let duplicate : Array[ArchiveEntry] = [
    {
      name: "same",
      size: 1,
      compressed_size: 1,
      offset: 0,
      folder: 0,
      flags: 0,
    },
    {
      name: "same",
      size: 2,
      compressed_size: 2,
      offset: 1,
      folder: 0,
      flags: 0,
    },
  ]
  let listing : ArchiveListing = {
    format: "CHM",
    entries: duplicate,
    warnings: [],
  }
  assert_false(has_unique_entry_names(listing))
  assert_eq(archive_format_label(listing), "Compiled HTML Help")
  let empty : ArchiveListing = { format: "raw", entries: [], warnings: [], }
  assert_eq(archive_metrics(empty).largest_index, -1)
  assert_true(within_output_budget(empty, 0))
  assert_false(within_output_budget(empty, -1))
  validate_listing(empty, limits={
    max_entries: 0,
    max_output: 0,
    max_window: 1,
  })
}

///|
test "invalid entry ranges" {
  let entries : Array[ArchiveEntry] = [
    {
      name: "bad",
      size: 5,
      compressed_size: 5,
      offset: 9,
      folder: 0,
      flags: 0,
    },
  ]
  let listing : ArchiveListing = { format: "CAB", entries, warnings: [], }
  try {
    validate_entry_ranges(listing, 10)
    fail("expected bounds error")
  } catch {
    _ => ()
  }
}
