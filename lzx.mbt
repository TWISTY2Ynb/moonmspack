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
/// Reverse the low `width` bits of a canonical Huffman code.
fn reverse_huffman_bits(value : Int, width : Int) -> Int {
  let mut source = value
  let mut result = 0
  for _ in 0..<width {
    result = (result << 1) | (source & 1)
    source = source >> 1
  }
  result
}

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
      codes[i] = reverse_huffman_bits(next[n], n)
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

///|
/// LZX format constants shared by block decoders.
pub let lzx_min_match : Int = 2

///|
pub let lzx_max_match : Int = 257

///|
pub let lzx_num_chars : Int = 256

///|
pub let lzx_block_verbatim : Int = 1

///|
pub let lzx_block_aligned : Int = 2

///|
pub let lzx_block_uncompressed : Int = 3

///|
pub let lzx_pretree_symbols : Int = 20

///|
pub let lzx_aligned_symbols : Int = 8

///|
pub let lzx_primary_lengths : Int = 7

///|
pub let lzx_secondary_lengths : Int = 249

///|
pub let lzx_frame_size : Int = 32768

///|
/// Return the number of position slots for an LZX window.
pub fn lzx_position_slots(window_bits : Int) -> Int raise MspackError {
  if window_bits < 15 || window_bits > 21 {
    raise MspackError("unsupported LZX window size")
  }
  if window_bits == 15 {
    30
  } else if window_bits == 16 {
    32
  } else {
    32 + (window_bits - 17) * 8
  }
}

///|
/// Build the extra-bit table for the LZX position slots.
pub fn lzx_position_extra_bits(
  window_bits : Int,
) -> Array[Int] raise MspackError {
  let slots = lzx_position_slots(window_bits)
  let result : Array[Int] = []
  for slot in 0..<slots {
    if slot < 4 {
      result.push(0)
    } else {
      result.push(slot / 2 - 1)
    }
  }
  result
}

///|
/// Convert an LZX length symbol into a match length.
pub fn lzx_match_length(symbol : Int) -> Int raise MspackError {
  if symbol < 0 || symbol >= lzx_secondary_lengths {
    raise MspackError("invalid LZX length symbol")
  }
  if symbol < lzx_primary_lengths {
    lzx_min_match + symbol
  } else {
    lzx_min_match + symbol
  }
}

///|
/// Decode a run of LZX code lengths using a pretree.
pub fn decode_lzx_code_lengths(
  bits : BitReader,
  pretree : HuffmanTable,
  count : Int,
  previous? : Int = 0,
) -> (BitReader, Array[Int]) raise MspackError {
  if count < 0 || count > 4096 {
    raise MspackError("invalid LZX code length count")
  }
  let result : Array[Int] = []
  let mut cursor = bits
  let mut last = previous
  while result.length() < count {
    let (next, symbol) = pretree.decode(cursor)
    cursor = next
    if symbol <= 16 {
      let delta = cursor.read(4)
      let value = (last - delta + 17) % 17
      result.push(value)
      last = value
    } else if symbol == 17 {
      let extra = cursor.read(4)
      let run = extra + 4
      if result.length() + run > count {
        raise MspackError("LZX code length run exceeds tree")
      }
      for _ in 0..<run {
        result.push(0)
      }
      last = 0
    } else if symbol == 18 {
      let extra = cursor.read(5)
      let run = extra + 20
      if result.length() + run > count {
        raise MspackError("LZX code length run exceeds tree")
      }
      for _ in 0..<run {
        result.push(0)
      }
      last = 0
    } else {
      let extra = cursor.read(1)
      let run = extra + 4
      if result.length() + run > count {
        raise MspackError("LZX code length run exceeds tree")
      }
      for _ in 0..<run {
        result.push(last)
      }
    }
  }
  (cursor, result)
}

///|
/// Validate a Huffman tree before it is used for an LZX block.
pub fn validate_lzx_tree(lengths : Array[Int]) -> Unit raise MspackError {
  if lengths.length() == 0 || lengths.length() > 4096 {
    raise MspackError("invalid LZX tree size")
  }
  let mut nonzero = 0
  for length in lengths {
    if length < 0 || length > 16 {
      raise MspackError("invalid LZX tree code length")
    }
    if length > 0 {
      nonzero = nonzero + 1
    }
  }
  if nonzero == 0 {
    raise MspackError("empty LZX huffman tree")
  }
}

///|
/// Build and validate a decoding tree from serialized code lengths.
pub fn build_lzx_tree(lengths : Array[Int]) -> HuffmanTable raise MspackError {
  validate_lzx_tree(lengths)
  HuffmanTable::build(lengths)
}

///|
/// Decode a complete tree from a pretree-coded length stream.
pub fn decode_lzx_tree(
  bits : BitReader,
  pretree : HuffmanTable,
  symbols : Int,
) -> (BitReader, HuffmanTable) raise MspackError {
  let (bits, lengths) = decode_lzx_code_lengths(bits, pretree, symbols)
  let tree = build_lzx_tree(lengths)
  (bits, tree)
}

///|
/// Return whether a block type uses the aligned offset tree.
pub fn lzx_uses_aligned_tree(block_type : Int) -> Bool {
  block_type == lzx_block_aligned
}

///|
/// Convert an LZX slot and footer into a match distance.
pub fn lzx_match_distance(
  slot : Int,
  footer : Int,
  recent0 : Int,
  recent1 : Int,
  recent2 : Int,
  window_bits : Int,
) -> Int raise MspackError {
  let extra = lzx_position_extra_bits(window_bits)
  if slot < 0 || slot >= extra.length() {
    raise MspackError("invalid LZX position slot")
  }
  if slot == 0 {
    recent0
  } else if slot == 1 {
    recent1
  } else if slot == 2 {
    recent2
  } else {
    let distance = (1 << extra[slot]) + footer - 1
    if distance <= 0 {
      raise MspackError("invalid LZX match distance")
    }
    distance
  }
}
