///|
fn inflate_mszip(
  block : Bytes,
  expected : Int,
  limit : Int,
) -> Bytes raise MspackError {
  if block.length() < 2 || block[0] != 0x43 || block[1] != 0x4B {
    raise MspackError("MSZIP block is missing CK signature")
  }
  let payload_array : Array[Byte] = []
  for i in 2..<block.length() {
    payload_array.push(block[i])
  }
  let payload = Bytes::from_array(payload_array)
  try {
    let out = @flate.inflate_all_limited(payload, max_output=limit)
    if expected >= 0 && out.length() != expected {
      raise MspackError("MSZIP output length mismatch")
    }
    out
  } catch {
    _ => raise MspackError("MSZIP deflate stream is corrupt")
  }
}

///|
pub fn decode_mszip_block(
  data : Bytes,
  expected~ : Int,
  limits? : Limits = default_limits,
) -> Bytes raise MspackError {
  if data.length() > limits.max_output {
    raise MspackError("MSZIP input exceeds limit")
  }
  inflate_mszip(data, expected, limits.max_output)
}

///|
pub fn checksum32(data : Bytes) -> UInt {
  let mut value : UInt = 0
  for i in 0..<data.length() {
    value = value ^ (data[i].to_uint() << (i % 4 * 8))
  }
  value
}

///|
pub fn copy_range(
  data : Bytes,
  offset~ : Int,
  size~ : Int,
  limits? : Limits = default_limits,
) -> Bytes raise MspackError {
  checked_range(data.length(), offset, size)
  if size > limits.max_output {
    raise MspackError("requested extraction exceeds limit")
  }
  let out : Array[Byte] = []
  for i in 0..<size {
    out.push(data[offset + i])
  }
  Bytes::from_array(out)
}
