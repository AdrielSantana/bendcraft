import Base
import ./lib.bend as Lib
import ../src/world.bend as World
import ../src/render.bend as Render
import ../src/util.bend as Util
import ../src/sky.bend as Sky
import ../src/water.bend as Water

# The far walk, windowless: a map of columns written by hand, rays from
# the window over it, and the look of what they meet. `bend test/far.bend`.

def near(a: F32, b: F32, epsilon: F32) -> Bool:
  (F32.abs((a - b : F32)) <= epsilon : F32)

# flat grass twelve high; the far base 0, so the window's local block x
# lies at far-local block x + 64
def flat() -> U32:
  World.far_word(12, 12, 0, 0)

def tall() -> U32:
  World.far_word(24, 24, 0, 0)

def sea() -> U32:
  World.far_word(8, 12, 0, 0)

def trunk() -> U32:
  World.far_word(12, 16, 16, 18)

def leaves() -> U32:
  World.far_word(12, 12, 14, 17)

def fill(n: Nat, ring: Array<U32>, +i: U32) -> Array<U32>:
  match n:
    case 0n:
      ring
    case 1n+k:
      fill(k, Array.set(U32, ring, (262144 + i : U32), flat()), (i + 1 : U32))

def put(ring: Array<U32>, +x: U32, +z: U32, +word: U32) -> Array<U32>:
  Array.set(U32, ring, World.far_at(x, z), word)

# a column of ground 24 high at far-local (160, 128), the sea at (140,
# 150), a trunk at (128, 100) and a canopy alone at (120, 90), and the
# cells' tops over them; the corner's remainders are 0
def map() -> Array<U32>:
  World.load_grid(64n, put(put(put(put(fill(65536n, [0 : U32^19n], 0), 160, 128, tall()), 140, 150, sea()), 128, 100, trunk()), 120, 90, leaves()), 0)

# a miss keeps walking, so its distance says nothing: only a hit's is held
def met(r: Array<U32> & Render.Far, +hit: U32, +word: U32, t: F32) -> Bool:
  (w, fr) = r
  Render.Far{h, at_word, at} = fr
  U32.is_eq(h, hit) && ((hit < 1 : U32) || (U32.is_eq((at_word % 1048576 : U32), word) && near(at, t, 0.001)))

def walk(+ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, +t0: F32, +hit: U32, +word: U32, t: F32) -> Bool:
  met(Render.run_far(128n, map(), 0, ox, oy, oz, dx, dy, dz, t0), hit, word, t)

# what the far walk shows of a hit, fog and all, in the noon sun
def look(+fl: U32, +word: U32, +axis: U32, +oy: F32, +dx: F32, +dy: F32, +dz: F32, +t: F32) -> U32:
  Render.far_look(fl, 123456, oy, 0.5, 0.8, 0.0, word, t, Render.face(axis, 64.5, oy, 64.5, dx, dy, dz, t))

def day(+tone: F32) -> F32:
  (tone * (0.18 + 0.82 * Sky.daylight(0.8)) : F32)

def main() -> IO(Unit):
  do IO<Unit>:
    Lib.expect(walk(64.5, 16.5, 64.5, 1.0, 0.0, 0.0, 0.0, 1, tall(), 31.5), "the walk meets a tall column's x side at the plane it begins on")
    Lib.expect(walk(64.5, 16.5, 64.5, 0.0, (0.0 - 0.1 : F32), 1.0, 0.0, 2, flat(), 45.0), "a ray sloping down meets the flat ground's top where it drops under it")
    Lib.expect(met(Render.run_far(12n, map(), 0, 64.5, 16.5, 64.5, 1.0, 0.0, 0.0, 0.0), 1, tall(), 31.5), "over cells whose tops it passes above, a step crosses a cell: twelve steps reach the tall column 32 columns off")
    Lib.expect(walk(76.5, 16.5, 64.5, 0.0, (0.0 - 0.205 : F32), 1.0, 0.0, 2, sea(), 21.95122), "and the sea's top at its plane")
    Lib.expect(walk(64.5, 15.5, 64.5, 0.0, 0.0, (0.0 - 1.0 : F32), 0.0, 3, trunk(), 27.5)
      && walk(64.5, 16.5, 64.5, 0.0, 0.0, (0.0 - 1.0 : F32), 0.0, 3, trunk(), 27.5), "a trunk's z side, below its leaves and in them")
    Lib.expect(walk(56.5, 13.0, 64.5, 0.0, 0.0, (0.0 - 1.0 : F32), 0.0, 0, 0, 0.0), "a ray through the gap between the ground and a canopy meets neither")
    Lib.expect(walk(56.5, 13.0, 64.5, 0.0, 0.0263, (0.0 - 1.0 : F32), 0.0, 2, leaves(), 38.02281)
      && walk(56.5, 18.0, 64.5, 0.0, (0.0 - 0.0263 : F32), (0.0 - 1.0 : F32), 0.0, 2, leaves(), 38.02281), "a canopy's underside where a ray climbs into it, its top where one drops into it")
    Lib.expect(walk(64.5, 16.5, 64.5, (0.0 - 1.0 : F32), 0.0, 0.0, 0.0, 0, 0, 0.0), "nothing to the west over low ground")
    Lib.expect(walk(64.5, 16.5, 64.5, 0.0, 1.0, 0.0, 0.0, 0, 0, 0.0), "a ray to the sky meets nothing")
    Lib.expect(walk(64.5, 10.0, 64.5, 1.0, 0.0, 0.0, 0.0, 1, flat(), 0.001), "a walk that starts under a top meets its side at once")
    Lib.expect(walk(64.5, 16.5, 64.5, 1.0, 0.0, 0.0, 10.0, 1, tall(), 31.5), "the walk picks up at the distance the window's walk stopped at, and the hit's distance is the same")
    Lib.expect(walk((0.0 - 35.5 : F32), 16.5, 64.5, 1.0, 0.0, 0.0, 100.0, 0, 0, 0.0), "the walk ends where the fog is whole: the tall column 131.5 blocks off is not met")
    Lib.expect(U32.is_eq(look(0, flat(), 1, 16.5, 0.0, (0.0 - 0.1 : F32), 1.0, 45.0), Render.dim(Render.blockcol(0, False{}, 0.0), day(1.0)))
      && U32.is_eq(look(0, tall(), 0, 16.5, 1.0, 0.0, 0.0, 31.5), Render.dim(Render.blockcol(2, True{}, 0.5), day(0.8)))
      && U32.is_eq(look(0, tall(), 0, 23.9, 1.0, 0.0, 0.0, 31.5), Render.dim(Render.blockcol(0, True{}, 0.9), day(0.8)))
      && U32.is_eq(look(0, tall(), 0, 23.5, 1.0, 0.0, 0.0, 31.5), Render.dim(Render.blockcol(1, True{}, 0.5), day(0.8))),
      "a far block is the window's: the grass top, stone deep in a side, the green band atop a grass block's side and the dirt under it")
    Lib.expect(U32.is_eq(look(1, tall(), 0, 16.5, 1.0, 0.0, 0.0, 31.5), Render.dim(Render.dim(Render.blockcol(2, True{}, 0.5), day(0.8)), 0.6))
      && U32.is_eq(look(1, flat(), 1, 16.5, 0.0, (0.0 - 0.1 : F32), 1.0, 45.0), Render.dim(Render.dim(Render.blockcol(0, False{}, 0.0), day(1.0)), 1.0)),
      "with the shadow flag, a side turned from the sun is darker and the top it shines on is not")
    Lib.expect(U32.is_eq(look(0, sea(), 1, 16.5, 0.0, (0.0 - 0.205 : F32), 1.0, 21.95122), Util.mix(Water.colour(0.8), 123456, 0.6))
      && U32.is_eq(look(8, tall(), 0, 16.5, 1.0, 0.0, 0.0, 10000.0), 123456),
      "the sea is its ink and the sky, and the fog takes a far block into the sky at the reach")
