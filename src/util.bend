import Base

# Little helpers shared by every module: float and integer conversions,
# bit tests, and the smoothstep of the two noises.

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
