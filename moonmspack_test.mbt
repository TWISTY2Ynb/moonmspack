///|
test "detect formats" {
  let cab = Bytes::from_array([0x4D, 0x53, 0x43, 0x46])
  let chm = Bytes::from_array([0x49, 0x54, 0x53, 0x46])
  assert_eq(@moonmspack.detect(cab), "CAB")
  assert_eq(@moonmspack.detect(chm), "CHM")
  assert_eq(@moonmspack.detect(Bytes::from_array([0, 1, 2, 3])), "unknown")
}
