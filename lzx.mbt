///|
pub struct BitReader {
  data : Bytes
  mut byte_pos : Int
  mut bit_buffer : UInt
  mut bits : Int
} derive(Show)

///|
pub fn BitReader::new(data : Bytes) -> BitReader {
  { data, byte_pos: 0, bit_buffer: 0, bits: 0, }
}

///|
pub fn BitReader::read(self : BitReader, count : Int) -> Int raise MspackError {
  if count < 0 || count > 24 {
    raise MspackError("invalid bit count")
  }
  while self.bits < count {
    if self.byte_pos >= self.data.length() {
      raise MspackError("truncated LZX bitstream")
    }
    self.bit_buffer = self.bit_buffer |
      (self.data[self.byte_pos].to_uint() << self.bits)
    self.bits = self.bits + 8
    self.byte_pos = self.byte_pos + 1
  }
  let mask = if count == 0 { 0 } else { (1 << count) - 1 }
  let value = (self.bit_buffer & mask.to_uint()).to_int()
  self.bit_buffer = self.bit_buffer >> count
  self.bits = self.bits - count
  value
}

///|
pub fn BitReader::align_word(self : BitReader) -> Unit raise MspackError {
  let discard = self.bits % 16
  ignore(self.read(discard))
}

///|
pub struct HuffmanTable {
  lengths : Array[Int]
  codes : Array[Int]
  max_bits : Int
} derive(Show)

///|
pub fn HuffmanTable::build(
  lengths : Array[Int],
) -> HuffmanTable raise MspackError {
  let max_bits = lengths.fold(init=0, fn(max, n) {
    if n > max {
      n
    } else {
      max
    }
  })
  if max_bits > 16 {
    raise MspackError("LZX huffman code is too long")
  }
  let counts : Array[Int] = Array::make(max_bits + 1, 0)
  for n in lengths {
    if n < 0 {
      raise MspackError("negative huffman length")
    }
    if n > 0 {
      counts[n] = counts[n] + 1
    }
  }
  let next : Array[Int] = Array::make(max_bits + 1, 0)
  let mut code = 0
  for bits in 1..<(max_bits + 1) {
    code = (code + counts[bits - 1]) << 1
    next[bits] = code
  }
  let codes : Array[Int] = Array::make(lengths.length(), 0)
  for i in 0..<lengths.length() {
    let n = lengths[i]
    if n > 0 {
      codes[i] = next[n]
      next[n] = next[n] + 1
    }
  }
  { lengths, codes, max_bits, }
}

///|
pub fn HuffmanTable::decode(
  self : HuffmanTable,
  bits : BitReader,
) -> (BitReader, Int) raise MspackError {
  let mut code = 0
  for width in 1..<(self.max_bits + 1) {
    let bit = bits.read(1)
    code = code | (bit << (width - 1))
    for i in 0..<self.lengths.length() {
      if self.lengths[i] == width && self.codes[i] == code {
        return (bits, i)
      }
    }
  }
  raise MspackError("invalid LZX huffman symbol")
}

///|
pub struct LzxWindow {
  pub size : Int
  pub mut position : Int
  pub data : Array[Byte]
} derive(Show)

///|
pub fn LzxWindow::new(window_bits : Int) -> LzxWindow raise MspackError {
  if window_bits < 15 || window_bits > 21 {
    raise MspackError("unsupported LZX window size")
  }
  let size = 1 << window_bits
  { size, position: 0, data: Array::make(size, 0), }
}

///|
pub fn LzxWindow::put(self : LzxWindow, value : Byte) -> Unit {
  self.data[self.position % self.size] = value
  self.position = self.position + 1
}

///|
pub fn LzxWindow::copy(
  self : LzxWindow,
  distance : Int,
  length : Int,
) -> Unit raise MspackError {
  if distance <= 0 || distance > self.size {
    raise MspackError("invalid LZX match distance")
  }
  if length < 0 || length > self.size {
    raise MspackError("invalid LZX match length")
  }
  for _ in 0..<length {
    let source = (self.position - distance) % self.size
    let value = self.data[source]
    self.put(value)
  }
}

///|
pub fn decode_lzx_block(
  data : Bytes,
  window_bits~ : Int,
  expected~ : Int,
  limits? : Limits = default_limits,
) -> Bytes raise MspackError {
  let window = LzxWindow::new(window_bits)
  if expected < 0 || expected > limits.max_output {
    raise MspackError("LZX output exceeds limit")
  }
  if data.length() == 0 && expected != 0 {
    raise MspackError("empty LZX block")
  }
  if expected == 0 {
    ignore(window)
    b""
  } else {
    let bits = BitReader::new(data)
    let block_type = bits.read(3)
    let block_length_low = bits.read(16)
    let block_length_high = bits.read(8)
    let block_length = block_length_low | (block_length_high << 16)
    if block_length != expected {
      raise MspackError("LZX block length does not match expected output")
    }
    if block_type == 3 {
      bits.align_word()
      ignore(bits.read(32))
      ignore(bits.read(32))
      ignore(bits.read(32))
      let (bits, raw) = bits.bytes(expected)
      ignore(bits)
      raw
    } else {
      raise MspackError("compressed LZX block decoder is not yet complete")
    }
  }
}

///|
/// Read whole bytes after the current bit cursor is byte aligned.
pub fn BitReader::bytes(
  self : BitReader,
  count : Int,
) -> (BitReader, Bytes) raise MspackError {
  if count < 0 || self.bits != 0 || self.byte_pos + count > self.data.length() {
    raise MspackError("truncated LZX uncompressed block")
  }
  let out : Array[Byte] = []
  for i in 0..<count {
    out.push(self.data[self.byte_pos + i])
  }
  ({ ..self, byte_pos: self.byte_pos + count, }, Bytes::from_array(out))
}
