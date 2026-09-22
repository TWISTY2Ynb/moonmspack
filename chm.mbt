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
