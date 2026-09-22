///|
/// Parse the variable-length integers used by CHM PMGL chunks.
fn chm_quick_u32(reader : Reader) -> (Reader, Int) raise MspackError {
  let mut r = reader
  let mut value = 0
  let mut shift = 0
  let mut done = false
  while !done {
    if shift >= 32 {
      raise MspackError("CHM variable integer is too large")
    }
    let (next, byte) = r.u8()
    r = next
    value = value | ((byte & 0x7F) << shift)
    if (byte & 0x80) == 0 {
      done = true
    } else {
      shift = shift + 7
    }
  }
  (r, value)
}

///|
fn chm_chunk_magic(data : Bytes, offset : Int) -> String raise MspackError {
  checked_range(data.length(), offset, 4)
  let r = Reader::new(data).seek(offset)
  let (r, a) = r.u8()
  let (r, b) = r.u8()
  let (r, c) = r.u8()
  let (_, d) = r.u8()
  if a == 0x50 && b == 0x4D && c == 0x47 && d == 0x4C {
    "PMGL"
  } else if a == 0x50 && b == 0x4D && c == 0x47 && d == 0x49 {
    "PMGI"
  } else {
    "????"
  }
}

///|
/// Parse one uncompressed PMGL listing chunk.
fn parse_pmgl_chunk(
  data : Bytes,
  offset : Int,
  chunk_size : Int,
  limits : Limits,
) -> Array[ArchiveEntry] raise MspackError {
  checked_range(data.length(), offset, chunk_size)
  if chm_chunk_magic(data, offset) != "PMGL" {
    raise MspackError("invalid CHM listing chunk")
  }
  let r = Reader::new(data).seek(offset + 4)
  let (r, free_space) = r.u32le()
  let used = chunk_size - 8 - free_space.to_int()
  if free_space.to_int() > chunk_size - 8 || used < 0 {
    raise MspackError("invalid CHM listing free space")
  }
  let end = offset + 8 + used
  let mut cursor = r
  let entries : Array[ArchiveEntry] = []
  while cursor.at() < end {
    let (next, name_len) = chm_quick_u32(cursor)
    cursor = next
    if name_len <= 0 ||
      name_len > limits.max_entries ||
      cursor.at() + name_len > end {
      raise MspackError("invalid CHM listing name")
    }
    let (next, name_bytes) = cursor.bytes(name_len)
    cursor = next
    let name = name_bytes.to_string()
    let (next, section) = chm_quick_u32(cursor)
    cursor = next
    let (next, start) = chm_quick_u32(cursor)
    cursor = next
    let (next, length) = chm_quick_u32(cursor)
    cursor = next
    if section > 0xFFFF || start < 0 || length < 0 {
      raise MspackError("unsupported CHM listing entry")
    }
    entries.push({
      name,
      size: length,
      compressed_size: length,
      offset: start,
      folder: section,
      flags: 0,
    })
    if entries.length() > limits.max_entries {
      raise MspackError("archive limit exceeded")
    }
  }
  entries
}

///|
/// Enumerate uncompressed CHM PMGL entries in the directory stream.
pub fn list_chm_directory(
  data : Bytes,
  header : ChmHeader,
  directory : ChmDirectory,
  limits? : Limits = default_limits,
) -> Array[ArchiveEntry] raise MspackError {
  if directory.chunk_size <= 0 || directory.listing_length <= 0 {
    []
  } else {
    let chunks = directory.listing_length / directory.chunk_size
    if chunks > limits.max_entries {
      raise MspackError("CHM chunk count exceeds limit")
    }
    let entries : Array[ArchiveEntry] = []
    for index in 0..<chunks {
      let offset = directory.listing_offset + index * directory.chunk_size
      if offset + directory.chunk_size > header.dir_offset + header.dir_length {
        raise MspackError("CHM listing exceeds directory")
      }
      if chm_chunk_magic(data, offset) == "PMGL" {
        let chunk_entries = parse_pmgl_chunk(
          data,
          offset,
          directory.chunk_size,
          limits,
        )
        for entry in chunk_entries {
          entries.push(entry)
          if entries.length() > limits.max_entries {
            raise MspackError("archive limit exceeded")
          }
        }
      }
    }
    entries
  }
}

///|
/// Read a CHM header and enumerate its uncompressed directory entries.
pub fn read_chm_entries(
  data : Bytes,
  limits? : Limits = default_limits,
) -> ArchiveListing raise MspackError {
  let (header, directory) = inspect_chm(data)
  let entries = list_chm_directory(data, header, directory, limits~)
  {
    format: "CHM",
    entries,
    warnings: ["compressed CHM content requires LZX decoding"],
  }
}
