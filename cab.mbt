///|
pub fn read_cab(
  data : Bytes,
  limits? : Limits = default_limits,
) -> ArchiveListing raise MspackError {
  let r = Reader::new(data)
  let (r, m0) = r.u8()
  let (r, m1) = r.u8()
  let (r, m2) = r.u8()
  if m0 != 0x4D || m1 != 0x53 || m2 != 0x43 {
    raise MspackError("invalid CAB magic")
  }
  let (r, _) = r.u8()
  let (r, _) = r.u32le()
  let (r, cb_cabinet) = r.u32le()
  let (r, _) = r.u32le()
  let (r, _) = r.u32le()
  let (r, coff_files) = r.u32le()
  let (r, _) = r.u32le()
  let (r, c_folders) = r.u16le()
  let (r, c_files) = r.u16le()
  let (r, flags) = r.u16le()
  let (r, _) = r.u16le()
  if c_files > limits.max_entries {
    raise MspackError("archive limit exceeded")
  }
  if cb_cabinet.to_int() > data.length() {
    raise MspackError("archive bounds error")
  }
  let mut rr = r
  if (flags & 0x0001) != 0 {
    let (x, cb_prev) = rr.u16le()
    let (x, _) = x.u16le()
    let (x, _) = x.u16le()
    let (x, _) = x.cstring(cb_prev)
    rr = x
  }
  if (flags & 0x0002) != 0 {
    let (x, cb_next) = rr.u16le()
    let (x, _) = x.u16le()
    let (x, _) = x.u16le()
    let (x, _) = x.cstring(cb_next)
    rr = x
  }
  if (flags & 0x0004) != 0 {
    let (x, _) = rr.u16le()
    let (x, _) = x.u16le()
    rr = x
  }
  let folder_start = rr.at()
  let folders = []
  for _ in 0..<c_folders {
    let (x, data_off) = rr.u32le()
    let (x, blocks) = x.u16le()
    let (x, comp) = x.u16le()
    folders.push((data_off.to_int(), blocks, comp))
    rr = x
  }
  let files_start = coff_files.to_int()
  checked_range(data.length(), files_start, c_files * 16)
  let mut fr = Reader::new(data).seek(files_start)
  let entries = []
  for _ in 0..<c_files {
    let (x, size) = fr.u32le()
    let (x, off) = x.u32le()
    let (x, folder) = x.u16le()
    let (x, date) = x.u16le()
    let (x, time) = x.u16le()
    let (x, attr) = x.u16le()
    fr = x
    let chars = []
    let mut q = fr
    let mut done = false
    while !done {
      let (y, c) = q.u8()
      q = y
      if c == 0 {
        done = true
      } else {
        chars.push(c.to_byte())
      }
    }
    let name = Bytes::from_array(chars).to_string()
    fr = q
    entries.push({
      name,
      size: size.to_int(),
      compressed_size: 0,
      offset: off.to_int(),
      folder,
      flags: attr | (date << 16) | (time << 8),
    })
  }
  {
    format: "CAB",
    entries,
    warnings: ["folder compression is decoded during extraction"],
  }
}

///|
pub fn list_cab(data : Bytes) -> Array[ArchiveEntry] raise MspackError {
  read_cab(data).entries
}

///|
fn cab_folders(data : Bytes) -> Array[(Int, Int, Int)] raise MspackError {
  let r = Reader::new(data)
  let (r, m0) = r.u8()
  let (r, m1) = r.u8()
  let (r, m2) = r.u8()
  if m0 != 0x4D || m1 != 0x53 || m2 != 0x43 {
    raise MspackError("invalid CAB magic")
  }
  let (r, _) = r.u8()
  let (r, _) = r.u32le()
  let (r, _) = r.u32le()
  let (r, _) = r.u32le()
  let (r, _) = r.u32le()
  let (r, _) = r.u32le()
  let (r, _) = r.u32le()
  let (r, count) = r.u16le()
  let (r, _) = r.u16le()
  let (r, flags) = r.u16le()
  let (r, _) = r.u16le()
  let mut rr = r
  if (flags & 1) != 0 {
    let (x, n) = rr.u16le()
    let (x, _) = x.u16le()
    let (x, _) = x.u16le()
    let x = x.skip(n)
    rr = x
  }
  if (flags & 2) != 0 {
    let (x, n) = rr.u16le()
    let (x, _) = x.u16le()
    let (x, _) = x.u16le()
    let x = x.skip(n)
    rr = x
  }
  if (flags & 4) != 0 {
    let (x, _) = rr.u16le()
    let (x, _) = x.u16le()
    rr = x
  }
  let result : Array[(Int, Int, Int)] = []
  for _ in 0..<count {
    let (x, off) = rr.u32le()
    let (x, blocks) = x.u16le()
    let (x, typ) = x.u16le()
    result.push((off.to_int(), blocks, typ))
    rr = x
  }
  result
}

///|
pub fn extract_cab_entry(
  data : Bytes,
  entry : ArchiveEntry,
  limits? : Limits = default_limits,
) -> Bytes raise MspackError {
  let folders = cab_folders(data)
  if entry.folder < 0 || entry.folder >= folders.length() {
    raise MspackError("CAB folder index outside table")
  }
  let (offset, block_count, compression) = folders[entry.folder]
  let mut cursor = offset
  let output : Array[Byte] = []
  for _ in 0..<block_count {
    let block_start = cursor
    let block_reader = Reader::new(data).seek(block_start)
    let (block_reader, _) = block_reader.u32le()
    let (block_reader, compressed) = block_reader.u16le()
    let (block_reader, uncompressed) = block_reader.u16le()
    let (block_reader, payload) = block_reader.bytes(compressed)
    cursor = block_reader.at()
    let method = compression & 0x000F
    let decoded = if method == 0 {
      payload
    } else if method == 1 {
      decode_mszip_block(payload, expected=uncompressed, limits~)
    } else {
      raise MspackError("CAB compression method is not implemented")
    }
    for i in 0..<decoded.length() {
      output.push(decoded[i])
    }
  }
  let begin = entry.offset
  if begin < 0 || begin + entry.size > output.length() {
    raise MspackError("CAB entry range exceeds decoded folder")
  }
  let selected : Array[Byte] = []
  for i in begin..<(begin + entry.size) {
    selected.push(output[i])
  }
  Bytes::from_array(selected)
}
