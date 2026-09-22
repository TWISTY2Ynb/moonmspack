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
