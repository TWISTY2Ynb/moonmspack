///|
/// Stateful LZX decoder configuration.
pub struct LzxConfig {
  pub window_bits : Int
  pub reset_interval : Int
  pub max_output : Int
} derive(Show, Eq)

///|
/// Default safe LZX configuration.
pub let default_lzx_config : LzxConfig = {
  window_bits: 15,
  reset_interval: 32768,
  max_output: 512 * 1024 * 1024,
}

///|
/// Stateful LZX decoder.
pub struct LzxDecoder {
  pub config : LzxConfig
  pub window : LzxWindow
  pub mut recent0 : Int
  pub mut recent1 : Int
  pub mut recent2 : Int
  pub mut produced : Int
} derive(Show)

///|
/// Create a stateful LZX decoder.
pub fn LzxDecoder::new(
  config? : LzxConfig = default_lzx_config,
) -> LzxDecoder raise MspackError {
  if config.reset_interval <= 0 || config.max_output <= 0 {
    raise MspackError("invalid LZX decoder configuration")
  }
  {
    config,
    window: LzxWindow::new(config.window_bits),
    recent0: 1,
    recent1: 1,
    recent2: 1,
    produced: 0,
  }
}

///|
/// Reset the decoder window and repeated offsets.
pub fn LzxDecoder::reset(self : LzxDecoder) -> Unit {
  self.window.position = 0
  self.recent0 = 1
  self.recent1 = 1
  self.recent2 = 1
  self.produced = 0
}

///|
/// Record a newly used match distance in the repeated-offset queue.
pub fn LzxDecoder::remember_distance(
  self : LzxDecoder,
  distance : Int,
) -> Unit raise MspackError {
  if distance <= 0 || distance > self.window.size {
    raise MspackError("invalid LZX distance")
  }
  self.recent2 = self.recent1
  self.recent1 = self.recent0
  self.recent0 = distance
}

///|
/// Emit one decoded token while updating decoder state.
pub fn LzxDecoder::emit(
  self : LzxDecoder,
  token : LzxToken,
) -> Unit raise MspackError {
  match token {
    Literal(byte) => {
      if self.produced >= self.config.max_output {
        raise MspackError("LZX output exceeds limit")
      }
      self.window.put(byte)
      self.produced = self.produced + 1
    }
    Match(distance~, length~) => {
      if self.produced + length > self.config.max_output {
        raise MspackError("LZX output exceeds limit")
      }
      self.window.copy(distance, length)
      self.remember_distance(distance)
      self.produced = self.produced + length
    }
  }
}

///|
/// Return the number of bytes produced by a decoder.
pub fn LzxDecoder::output_size(self : LzxDecoder) -> Int {
  self.produced
}

///|
/// Decode a token sequence with persistent repeated-offset state.
pub fn decode_lzx_tokens(
  tokens : Array[LzxToken],
  config? : LzxConfig = default_lzx_config,
) -> Bytes raise MspackError {
  let decoder = LzxDecoder::new(config~)
  let output : Array[Byte] = []
  for token in tokens {
    decoder.emit(token)
    match token {
      Literal(byte) => output.push(byte)
      Match(distance~, length~) => {
        let start = decoder.window.position - length
        for i in 0..<length {
          output.push(decoder.window.data[(start + i) % decoder.window.size])
        }
        ignore(distance)
      }
    }
  }
  Bytes::from_array(output)
}
