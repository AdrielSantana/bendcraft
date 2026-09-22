import Base

# Little helpers shared by every module: float and integer conversions,
# bit tests, the smoothstep of the two noises, and colours as one word.

def floorf(+x: F32) -> F32:
  U32.to_f32(F32.to_u32(x))

def absf(+x: F32) -> F32:
  F32.max(x, (0.0 - x : F32))

def f2u(+x: F32) -> U32:
  F32.to_u32(F32.max(x, 0.0))

def u2f(+x: U32) -> F32:
  U32.to_f32(x)

def on(+mask: U32, +bit: U32) -> Bool:
  ((mask .&. bit) > 0 : U32)

def fracf(+x: F32) -> F32:
  (x - floorf(x) : F32)

def smooth(+f: F32) -> F32:
  (f * f * (3.0 - 2.0 * f) : F32)

def rgb(r: U32, g: U32, b: U32) -> U32:
  (r * 65536 + g * 256 + b : U32)

def lerp(+x: U32, +y: U32, +f: F32) -> U32:
  F32.to_u32((U32.to_f32(x) * (1.0 - f) + U32.to_f32(y) * f : F32))

def mix(+a: U32, +b: U32, +f: F32) -> U32:
  rgb(lerp((a / 65536 : U32), (b / 65536 : U32), f),
      lerp((a / 256 % 256 : U32), (b / 256 % 256 : U32), f),
      lerp((a % 256 : U32), (b % 256 : U32), f))
