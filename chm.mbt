///|
pub struct ChmHeader {
  pub version : Int
  pub dir_offset : Int
  pub dir_length : Int
  pub chunk_size : Int
  pub lang_id : Int
  pub num_chunks : Int
} derive(Show, Eq)

///|
pub fn read_chm(
  data : Bytes,
  limits? : Limits = default_limits,
) -> ArchiveListing raise MspackError {
  if data.length() < 76 {
    raise MspackError("truncated CHM header")
  }
  let r = Reader::new(data)
  let (r, a) = r.u8()
  let (r, b) = r.u8()
  let (r, c) = r.u8()
  let (r, d) = r.u8()
  if a != 0x49 || b != 0x54 || c != 0x53 || d != 0x46 {
    raise MspackError("invalid CHM magic")
  }
  let (r, version) = r.u32le()
  let (r, _) = r.u32le()
  let (r, _) = r.u32le()
  let (r, _) = r.u32le()
  let (r, dir_offset_lo) = r.u32le()
  let (r, dir_offset_hi) = r.u32le()
  let (r, dir_len_lo) = r.u32le()
  let (r, dir_len_hi) = r.u32le()
  let (r, _) = r.u32le()
  let (r, _) = r.u32le()
  let (r, _) = r.u32le()
  let (r, _) = r.u32le()
  let (r, _) = r.u32le()
  let (r, _) = r.u32le()
  let (r, _) = r.u32le()
  let (r, _) = r.u32le()
  let offset = dir_offset_lo.to_int()
  let length = dir_len_lo.to_int()
  if dir_offset_hi != 0 || dir_len_hi != 0 {
    raise MspackError("CHM offsets exceed supported word size")
  }
  checked_range(data.length(), offset, length)
  if length > limits.max_output {
    raise MspackError("CHM directory exceeds limit")
  }
  let warnings = []
  if version.to_int() != 3 {
    warnings.push("unusual CHM version")
  }
  let entries : Array[ArchiveEntry] = []
  { format: "CHM", entries, warnings, }
}

///|
pub fn detect(data : Bytes) -> String {
  if data.length() >= 4 &&
    data[0] == 0x4D &&
    data[1] == 0x53 &&
    data[2] == 0x43 &&
    data[3] == 0x46 {
    "CAB"
  } else if data.length() >= 4 &&
    data[0] == 0x49 &&
    data[1] == 0x54 &&
    data[2] == 0x53 &&
    data[3] == 0x46 {
    "CHM"
  } else {
    "unknown"
  }
}

///|
pub fn list(
  data : Bytes,
  limits? : Limits = default_limits,
) -> ArchiveListing raise MspackError {
  match detect(data) {
    "CAB" => read_cab(data, limits~)
    "CHM" => read_chm(data, limits~)
    _ => raise MspackError("unknown archive format")
  }
}

///|
pub struct ChmDirectory {
  pub version : Int
  pub chunk_size : Int
  pub first_chunk : Int
  pub last_chunk : Int
  pub listing_offset : Int
  pub listing_length : Int
} derive(Show, Eq)

///|
fn read_u32_at(data : Bytes, offset : Int) -> UInt raise MspackError {
  let r = Reader::new(data).seek(offset)
  let (_, value) = r.u32le()
  value
}

///|
fn read_chm_directory_header(
  data : Bytes,
  header : ChmHeader,
) -> ChmDirectory raise MspackError {
  checked_range(data.length(), header.dir_offset, 0x38)
  let r = Reader::new(data).seek(header.dir_offset)
  let (r, a) = r.u8()
  let (r, b) = r.u8()
  let (r, c) = r.u8()
  let (r, d) = r.u8()
  if a != 0x49 || b != 0x54 || c != 0x53 || d != 0x50 {
    raise MspackError("invalid CHM ITSP signature")
  }
  let (r, version) = r.u32le()
  let (r, header_len) = r.u32le()
  let (r, chunk_size) = r.u32le()
  let (r, density) = r.u32le()
  let (r, depth) = r.u32le()
  let (r, root) = r.u32le()
  let (r, first) = r.u32le()
  let (r, last) = r.u32le()
  let (r, next) = r.u32le()
  let (r, num_chunks) = r.u32le()
  if header_len.to_int() < 0x38 || header_len.to_int() > header.dir_length {
    raise MspackError("invalid CHM ITSP header length")
  }
  if chunk_size.to_int() < 0x100 || chunk_size.to_int() > 0x100000 {
    raise MspackError("unsupported CHM chunk size")
  }
  if density.to_int() > 0x10000 || depth.to_int() > 0x10000 {
    raise MspackError("invalid CHM index parameters")
  }
  if first.to_int() > last.to_int() && last.to_int() != 0xFFFFFFFF {
    raise MspackError("invalid CHM chunk range")
  }
  if num_chunks.to_int() > 100000000 {
    raise MspackError("CHM chunk count exceeds limit")
  }
  {
    version: version.to_int(),
    chunk_size: chunk_size.to_int(),
    first_chunk: first.to_int(),
    last_chunk: last.to_int(),
    listing_offset: header.dir_offset + header_len.to_int(),
    listing_length: header.dir_length - header_len.to_int(),
  }
}

///|
pub fn inspect_chm(data : Bytes) -> (ChmHeader, ChmDirectory) raise MspackError {
  if data.length() < 76 {
    raise MspackError("truncated CHM header")
  }
  let r = Reader::new(data)
  let (r, a) = r.u8()
  let (r, b) = r.u8()
  let (r, c) = r.u8()
  let (r, d) = r.u8()
  if a != 0x49 || b != 0x54 || c != 0x53 || d != 0x46 {
    raise MspackError("invalid CHM magic")
  }
  let (r, version) = r.u32le()
  let (r, _) = r.u32le()
  let (r, _) = r.u32le()
  let (r, _) = r.u32le()
  let (r, off_lo) = r.u32le()
  let (r, off_hi) = r.u32le()
  let (r, len_lo) = r.u32le()
  let (r, len_hi) = r.u32le()
  let (r, _) = r.u32le()
  let (r, _) = r.u32le()
  let (r, _) = r.u32le()
  let (r, _) = r.u32le()
  let (r, _) = r.u32le()
  let (r, _) = r.u32le()
  let (r, _) = r.u32le()
  let (r, _) = r.u32le()
  if off_hi != 0 || len_hi != 0 {
    raise MspackError("CHM offsets exceed supported word size")
  }
  let header = {
    version: version.to_int(),
    dir_offset: off_lo.to_int(),
    dir_length: len_lo.to_int(),
    chunk_size: 0,
    lang_id: 0,
    num_chunks: 0,
  }
  checked_range(data.length(), header.dir_offset, header.dir_length)
  (header, read_chm_directory_header(data, header))
}
