///|
test "detect formats" {
  let cab = Bytes::from_array([0x4D, 0x53, 0x43, 0x46])
  let chm = Bytes::from_array([0x49, 0x54, 0x53, 0x46])
  assert_eq(@moonmspack.detect(cab), "CAB")
  assert_eq(@moonmspack.detect(chm), "CHM")
  assert_eq(@moonmspack.detect(Bytes::from_array([0, 1, 2, 3])), "unknown")
}

///|
test "bounded extraction and bit reader" {
  let bits = @moonmspack.BitReader::new(Bytes::from_array([0b00000101]))
  assert_eq(bits.read(3), 5)
  let window = @moonmspack.LzxWindow::new(15)
  window.put(65)
  window.put(66)
  assert_eq(window.position, 2)
  try {
    ignore(@moonmspack.LzxWindow::new(10))
    fail("accepted invalid LZX window")
  } catch {
    _ => ()
  }
}

///|
fn put16(out : Array[Byte], value : Int) -> Unit {
  out.push((value & 255).to_byte())
  out.push(((value >> 8) & 255).to_byte())
}

///|
fn put32(out : Array[Byte], value : Int) -> Unit {
  put16(out, value)
  put16(out, value >> 16)
}

///|
fn tiny_stored_cab() -> Bytes {
  let out : Array[Byte] = []
  out.push(0x4D)
  out.push(0x53)
  out.push(0x43)
  out.push(0x46)
  put32(out, 0)
  put32(out, 78)
  put32(out, 0)
  put32(out, 44)
  put32(out, 0)
  out.push(3)
  out.push(1)
  put16(out, 1)
  put16(out, 1)
  put16(out, 0)
  put16(out, 0)
  put16(out, 0)
  put32(out, 66)
  put16(out, 1)
  put16(out, 0)
  put32(out, 4)
  put32(out, 0)
  put16(out, 0)
  put16(out, 0)
  put16(out, 0)
  put16(out, 0)
  out.push(0x61)
  out.push(0x2E)
  out.push(0x74)
  out.push(0x78)
  out.push(0x74)
  out.push(0)
  put32(out, 0)
  put16(out, 4)
  put16(out, 4)
  out.push(65)
  out.push(66)
  out.push(67)
  out.push(68)
  Bytes::from_array(out)
}

///|
test "stored CAB listing and extraction" {
  let data = tiny_stored_cab()
  let listing = @moonmspack.read_cab(data)
  assert_eq(listing.entries.length(), 1)
  assert_eq(listing.entries[0].name, "a.txt")
  assert_eq(listing.entries[0].offset, 0)
  assert_eq(listing.entries[0].folder, 0)
  let payload = @moonmspack.extract_cab_entry(data, listing.entries[0])
  assert_eq(payload.to_string(), "ABCD")
}
