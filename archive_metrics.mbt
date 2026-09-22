///|
/// Aggregate statistics for an archive listing.
pub struct ArchiveMetrics {
  pub entry_count : Int
  pub total_size : Int
  pub total_compressed_size : Int
  pub largest_size : Int
  pub largest_index : Int
  pub folders : Int
  pub files_with_data : Int
} derive(Show, Eq)

///|
/// Calculate stable, allocation-free metrics for a parsed listing.
pub fn archive_metrics(listing : ArchiveListing) -> ArchiveMetrics {
  let mut total = 0
  let mut compressed = 0
  let mut largest = 0
  let mut largest_index = -1
  let mut folders = 0
  let mut data = 0
  let mut seen_folder = -1
  for i, entry in listing.entries {
    total = total + entry.size
    compressed = compressed + entry.compressed_size
    if entry.size > largest {
      largest = entry.size
      largest_index = i
    }
    if entry.folder != seen_folder {
      folders = folders + 1
      seen_folder = entry.folder
    }
    if entry.size > 0 {
      data = data + 1
    }
  }
  {
    entry_count: listing.entries.length(),
    total_size: total,
    total_compressed_size: compressed,
    largest_size: largest,
    largest_index,
    folders,
    files_with_data: data,
  }
}

///|
/// Find an entry by its exact archive path.
pub fn find_archive_entry(
  listing : ArchiveListing,
  name : String,
) -> ArchiveEntry? {
  for entry in listing.entries {
    if entry.name == name {
      return Some(entry)
    }
  }
  None
}

///|
/// Return all entries belonging to one CAB folder or CHM section.
pub fn entries_in_container(
  listing : ArchiveListing,
  container : Int,
) -> Array[ArchiveEntry] {
  let result : Array[ArchiveEntry] = []
  for entry in listing.entries {
    if entry.folder == container {
      result.push(entry)
    }
  }
  result
}

///|
/// Validate listing metadata before an extraction loop.
pub fn validate_listing(
  listing : ArchiveListing,
  limits? : Limits = default_limits,
) -> Unit raise MspackError {
  if listing.entries.length() > limits.max_entries {
    raise MspackError("listing entry limit exceeded")
  }
  let mut total = 0
  for entry in listing.entries {
    if entry.size < 0 ||
      entry.compressed_size < 0 ||
      entry.offset < 0 ||
      entry.folder < 0 {
      raise MspackError("negative archive entry metadata")
    }
    if entry.size > limits.max_output {
      raise MspackError("archive entry exceeds output limit")
    }
    if entry.compressed_size > limits.max_output {
      raise MspackError("compressed entry exceeds output limit")
    }
    total = total + entry.size
    if total < 0 || total > limits.max_output {
      raise MspackError("listing total output limit exceeded")
    }
  }
}

///|
/// Select entries whose uncompressed size is within a caller supplied range.
pub fn entries_by_size(
  listing : ArchiveListing,
  minimum : Int,
  maximum : Int,
) -> Array[ArchiveEntry] {
  let result : Array[ArchiveEntry] = []
  if minimum > maximum {
    return result
  }
  for entry in listing.entries {
    if entry.size >= minimum && entry.size <= maximum {
      result.push(entry)
    }
  }
  result
}

///|
/// Return true when all entry names are unique.
pub fn has_unique_entry_names(listing : ArchiveListing) -> Bool {
  for i, entry in listing.entries {
    for j in (i + 1)..<listing.entries.length() {
      if entry.name == listing.entries[j].name {
        return false
      }
    }
  }
  true
}

///|
/// Return entries in their original archive order, limited by count.
pub fn take_archive_entries(
  listing : ArchiveListing,
  count : Int,
) -> Array[ArchiveEntry] {
  let result : Array[ArchiveEntry] = []
  if count <= 0 {
    return result
  }
  let limit = if count < listing.entries.length() {
    count
  } else {
    listing.entries.length()
  }
  for i in 0..<limit {
    result.push(listing.entries[i])
  }
  result
}

///|
/// Compute a deterministic 32-bit FNV-1a digest for entry names.
pub fn archive_name_digest(listing : ArchiveListing) -> UInt {
  let mut hash : UInt = 2166136261
  for entry in listing.entries {
    for byte in entry.name.to_bytes() {
      hash = (hash ^ byte.to_uint()) * 16777619
    }
    hash = (hash ^ 0xFF) * 16777619
  }
  hash
}

///|
/// Check that offsets and sizes do not overflow an input buffer.
pub fn validate_entry_ranges(
  listing : ArchiveListing,
  input_size : Int,
) -> Unit raise MspackError {
  if input_size < 0 {
    raise MspackError("negative input size")
  }
  for entry in listing.entries {
    if entry.offset > input_size ||
      entry.compressed_size > input_size - entry.offset {
      raise MspackError("archive entry range exceeds input")
    }
  }
}

///|
/// Return a compact human-readable format label for diagnostics.
pub fn archive_format_label(listing : ArchiveListing) -> String {
  if listing.format == "CAB" {
    "Microsoft Cabinet"
  } else if listing.format == "CHM" {
    "Compiled HTML Help"
  } else {
    listing.format
  }
}

///|
/// Check whether extraction can proceed without exceeding a byte budget.
pub fn within_output_budget(listing : ArchiveListing, budget : Int) -> Bool {
  if budget < 0 {
    return false
  }
  let mut total = 0
  for entry in listing.entries {
    total = total + entry.size
    if total < 0 || total > budget {
      return false
    }
  }
  true
}

///|
/// Return the sum of sizes for one container.
pub fn container_size(listing : ArchiveListing, container : Int) -> Int {
  let mut total = 0
  for entry in listing.entries {
    if entry.folder == container {
      total = total + entry.size
    }
  }
  total
}

///|
/// Return the number of entries with a given compression flag mask.
pub fn count_entries_with_flags(listing : ArchiveListing, mask : Int) -> Int {
  let mut count = 0
  for entry in listing.entries {
    if (entry.flags & mask) == mask {
      count = count + 1
    }
  }
  count
}

///|
/// Verify that all entries have a non-empty name and valid container id.
pub fn validate_entry_identity(
  listing : ArchiveListing,
) -> Unit raise MspackError {
  for entry in listing.entries {
    if entry.name.length() == 0 {
      raise MspackError("archive entry has an empty name")
    }
    if entry.folder < 0 {
      raise MspackError("archive entry has an invalid container")
    }
  }
}
