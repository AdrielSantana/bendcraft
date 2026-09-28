import Base
import ./util.bend as Util
import ./sky.bend as Sky
import ./clouds.bend as Clouds

# The meadow's map: 2^16 words past the clouds' map, a word a column of the
# world mod 256, filled at the world's birth, so the grass's walks read
# a word at each block where they computed a noise. A word holds how wild
# the meadow grows there (bits 0..7), which flower blooms in its 8 by 8
# blocks (8..10), and the wind's phase along z (16..23).
def map_at(+x: U32, +z: U32) -> U32:
  (458752 + x % 256 * 256 + z % 256 : U32)

# how wild the meadow grows at (xw, zw) of the world, some 4 blocks
# across: taller, thicker and flowering less
def wild(+xw: F32, +zw: F32) -> F32:
  Clouds.lattice(xw, zw, 0.25, 64, 911)

def pack(+wildness: U32, +flower: U32, +phase: U32) -> U32:
  (wildness + flower * 256 + phase * 65536 : U32)

def flower(+word: U32) -> U32:
  (word / 256 % 8 : U32)

def phase(+word: U32) -> U32:
  (word / 65536 : U32)

def word_at(+x: U32, +z: U32) -> U32:
  +xw = (U32.to_f32(x) + 0.5 : F32)
  +zw = (U32.to_f32(z) + 0.5 : F32)
  pack(F32.to_u32((wild(xw, zw) * 255.0 + 0.5 : F32)), (Sky.star_hash((x / 8 : U32), (z / 8 + 929 : U32)) % 5 : U32),
    F32.to_u32(((F32.sin((zw * 0.23 : F32)) + 1.0) * 127.5 + 0.5 : F32)))

def load_line(n: Nat, w: Array<U32>, +x: U32, +z: U32) -> Array<U32>:
  match n:
    case 0n:
      w
    case 1n+k:
      load_line(k, Array.set(U32, w, map_at(x, z), word_at(x, z)), x, (z + 1 : U32))

def load(n: Nat, w: Array<U32>, +x: U32) -> Array<U32>:
  match n:
    case 0n:
      w
    case 1n+k:
      load(k, load_line(256n, w, x, 0), (x + 1 : U32))
