///|
/// Error categories returned by the archive readers.
pub suberror MspackError {
  MspackError(String)
}

///|
pub struct Reader {
  data : Bytes
  pos : Int
} derive(Show)

///|
pub fn Reader::new(data : Bytes) -> Reader {
  { data, pos: 0, }
}

///|
pub fn Reader::at(self : Reader) -> Int {
  self.pos
}

///|
pub fn Reader::remaining(self : Reader) -> Int {
  self.data.length() - self.pos
}

///|
pub fn Reader::seek(self : Reader, offset : Int) -> Reader raise MspackError {
  if offset < 0 || offset > self.data.length() {
    raise MspackError("input bounds error")
  }
  { ..self, pos: offset, }
}

///|
pub fn Reader::skip(self : Reader, count : Int) -> Reader raise MspackError {
  self.seek(self.pos + count)
}

///|
pub fn Reader::u8(self : Reader) -> (Reader, Int) raise MspackError {
  if self.pos >= self.data.length() {
    raise MspackError("truncated input")
  }
  ({ ..self, pos: self.pos + 1, }, self.data[self.pos].to_int())
}

///|
pub fn Reader::u16le(self : Reader) -> (Reader, Int) raise MspackError {
  let (r, a) = self.u8()
  let (r, b) = r.u8()
  (r, a | (b << 8))
}

///|
pub fn Reader::u32le(self : Reader) -> (Reader, UInt) raise MspackError {
  let (r, a) = self.u16le()
  let (r, b) = r.u16le()
  (r, a.to_uint() | (b.to_uint() << 16))
}

///|
pub fn Reader::bytes(
  self : Reader,
  count : Int,
) -> (Reader, Bytes) raise MspackError {
  if count < 0 || self.pos + count > self.data.length() {
    raise MspackError("truncated input")
  }
  let out : Array[Byte] = []
  for i in 0..<count {
    out.push(self.data[self.pos + i])
  }
  ({ ..self, pos: self.pos + count, }, Bytes::from_array(out))
}

///|
pub fn Reader::cstring(
  self : Reader,
  count : Int,
) -> (Reader, String) raise MspackError {
  let (r, b) = self.bytes(count)
  let end = b.length()
  let mut n = 0
  while n < end && b[n] != 0 {
    n = n + 1
  }
  (r, b[0:n].to_string())
}

///|
pub struct Limits {
  max_entries : Int
  max_output : Int
  max_window : Int
} derive(Show)

///|
pub let default_limits : Limits = {
  max_entries: 100000,
  max_output: 512 * 1024 * 1024,
  max_window: 32768,
}

///|
pub struct ArchiveEntry {
  pub name : String
  pub size : Int
  pub compressed_size : Int
  pub offset : Int
  pub folder : Int
  pub flags : Int
} derive(Show, Eq)

///|
pub struct ArchiveListing {
  pub format : String
  pub entries : Array[ArchiveEntry]
  pub warnings : Array[String]
} derive(Show)

///|
pub struct Extracted {
  pub entry : ArchiveEntry
  pub data : Bytes
} derive(Show)

///|
fn checked_range(
  total : Int,
  offset : Int,
  size : Int,
) -> Unit raise MspackError {
  if offset < 0 || size < 0 || offset > total || size > total - offset {
    raise MspackError("input bounds error")
  }
}

///|
fn append_bytes(dst : Array[Byte], src : Bytes) -> Unit {
  for i = 0; i < src.length(); i = i + 1 {
    dst.push(src[i])
  }
}

///|
fn bytes_to_array(data : Bytes) -> Array[Byte] {
  let a = []
  for i = 0; i < data.length(); i = i + 1 {
    a.push(data[i])
  }
  a
}

///|
fn array_to_bytes(data : Array[Byte]) -> Bytes {
  Bytes::from_array(data)
}

///|
/// Create a bounded reader view for a single archive entry.
pub fn entry_view(
  data : Bytes,
  entry : ArchiveEntry,
  limits? : Limits = default_limits,
) -> Reader raise MspackError {
  if entry.offset < 0 || entry.size < 0 || entry.size > limits.max_output {
    raise MspackError("invalid entry view")
  }
  checked_range(data.length(), entry.offset, entry.size)
  Reader::new(copy_range(data, offset=entry.offset, size=entry.size, limits~))
}

///|
/// Return a stable human-readable archive summary.
pub fn summary(listing : ArchiveListing) -> String {
  listing.format + ": " + listing.entries.length().to_string() + " entries"
}
