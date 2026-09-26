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

# a column of ground 24 high at far-local (160, 128) with the sea at its
# west foot, another just past the window's east side at (193, 128) and
# one west and north of the window at (40, 20), the sea at (140, 150), a
# trunk at (128, 100) and a canopy alone at (120, 90), and the cells'
# tops over them; the corner's remainders are 0, and the window's own
# columns are empty
def map() -> Array<U32>:
  World.load_grid(64n, put(put(put(put(put(put(put(fill(65536n, [0 : U32^19n], 0), 160, 128, tall()), 193, 128, tall()), 40, 20, tall()), 159, 128, sea()), 140, 150, sea()), 128, 100, trunk()), 120, 90, leaves()), 0)

def crossed(tr: Water.Trace, +entry: F32, +depth: F32) -> Bool:
  Water.Trace{e, d} = tr
  near(e, entry, 0.001) && near(d, depth, 0.001)

# a miss keeps walking, so its distance says nothing: only a hit's is
# held, and the water the ray crossed, where it went in and how deep
def met_wet(r: Array<U32> & Render.Far, +hit: U32, +word: U32, t: F32, +entry: F32, +depth: F32) -> Bool:
  (w, fr) = r
  Render.Far{h, at_word, at, tr} = fr
  U32.is_eq(h, hit) && ((hit < 1 : U32) || (U32.is_eq((at_word % 1048576 : U32), word) && near(at, t, 0.001))) && crossed(tr, entry, depth)

def met(r: Array<U32> & Render.Far, +hit: U32, +word: U32, t: F32) -> Bool:
  met_wet(r, hit, word, t, 0.0, 0.0)

def dry() -> Water.Trace:
  Water.Trace{0.0, 0.0}

def run(+ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, +t0: F32, tr: Water.Trace) -> Array<U32> & Render.Far:
  Render.run_far(128n, map(), 0, ox, oy, oz, dx, dy, dz, t0, Sky.reach(), True{}, tr)

def walk(+ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, +t0: F32, +hit: U32, +word: U32, t: F32) -> Bool:
  met(run(ox, oy, oz, dx, dy, dz, t0, dry()), hit, word, t)

# what the far walk shows of a hit, fog and all, in the noon sun, the
# map read for its occlusion, its shadow and its mirror
def shown(r: Array<U32> & U32) -> U32:
  (w, c) = r
  c

def holds(r: Array<U32> & Bool) -> Bool:
  (w, b) = r
  b

def look_on(+base: U32, +fl: U32, +word: U32, +axis: U32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, +t: F32) -> U32:
  shown(Render.from_far(0, False{}, 0.0, 123456, fl, 0.5, 0.8, 0.0, base, 0, ox, oy, oz, dx, dy, dz, (map(), Render.Far{(axis + 1 : U32), word, t, dry()})))

# the far walk's pixel for a ray from the eye, walked over the map
def far_pixel(+base: U32, +fl: U32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32) -> U32:
  shown(Render.after_walk(False{}, 0, 123456, fl, 0.5, 0.8, 0.0, base, 0, ox, oy, oz, dx, dy, dz, 0.0, 0.0, 0.0, map()))

# the window's water over a bed seen at the given depth, as the far sea
# should show it
def water_over(+bed: U32, +fl: U32, +oy: F32, +dy: F32, +t: F32, +entry: F32) -> U32:
  shown(Water.shade(True{}, fl, 123456, oy, dy, 0.5, 0.8, 0.0, True{}, t, True{}, Water.Trace{entry, (t - entry : F32)},
    ([0 : U32^1n], Water.Mirror{bed, Water.flat(0.0, dy, 0.0), False{}, 0, 1.0})))

def look_at(+fl: U32, +word: U32, +axis: U32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, +t: F32) -> U32:
  look_on(0, fl, word, axis, ox, oy, oz, dx, dy, dz, t)

def look(+fl: U32, +word: U32, +axis: U32, +oy: F32, +dx: F32, +dy: F32, +dz: F32, +t: F32) -> U32:
  look_at(fl, word, axis, 64.5, oy, 64.5, dx, dy, dz, t)

def apart(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, (a > b : U32), (a - b : U32), (b - a : U32))

# the most two colours part by on a channel
def part(+a: U32, +b: U32) -> U32:
  U32.max(U32.max(apart((a / 65536 : U32), (b / 65536 : U32)), apart((a / 256 % 256 : U32), (b / 256 % 256 : U32))), apart((a % 256 : U32), (b % 256 : U32)))

# no channel of a over b's, and not the same colour
def darker(+a: U32, +b: U32) -> Bool:
  ((a / 65536 : U32) <= b / 65536 : U32) && ((a / 256 % 256 : U32) <= b / 256 % 256 : U32) && ((a % 256 : U32) <= b % 256 : U32) && U32.is_ne(a, b)

# a top of the flat ground 16.5 - 12 blocks under an eye 45 blocks off
def top_at(+fl: U32, +x: F32, +z: F32) -> U32:
  look_at(fl, flat(), 1, x, 16.5, (z - 45.0 : F32), 0.0, (0.0 - 0.1 : F32), 1.0, 45.0)

def day(+tone: F32) -> F32:
  (tone * (0.18 + 0.82 * Sky.daylight(0.8)) : F32)

def main() -> IO(Unit):
  do IO<Unit>:
    Lib.expect(walk(64.5, 16.5, 64.5, 1.0, 0.0, 0.0, 0.0, 1, tall(), 31.5), "the walk meets a tall column's x side at the plane it begins on")
    Lib.expect(walk(64.5, 16.5, 64.5, 0.0, (0.0 - 0.1 : F32), 1.0, 0.0, 2, flat(), 45.0), "a ray sloping down meets the flat ground's top where it drops under it")
    Lib.expect(met(Render.run_far(12n, map(), 0, 64.5, 16.5, 64.5, 1.0, 0.0, 0.0, 0.0, Sky.reach(), True{}, dry()), 1, tall(), 31.5), "over cells whose tops it passes above, a step crosses a cell: twelve steps reach the tall column 32 columns off")
    Lib.expect(met_wet(run(76.5, 16.5, 86.5, 0.0, (0.0 - 1.0 : F32), 0.0, 0.0, dry()), 2, sea(), 8.5, 4.5, 4.0)
      && met_wet(run(76.5, 16.5, 64.5, 0.0, (0.0 - 0.205 : F32), 1.0, 0.0, dry()), 3, flat(), 22.5, 21.95122, 0.54878),
      "the sea is no block: a ray goes under its plane, kept as where it went wet, and on to the bed or to a bank it meets under the water")
    Lib.expect(met_wet(run(95.2, 11.0, 64.5, 1.0, 0.0, 0.0, 0.0, dry()), 1, tall(), 0.8, 0.001, 0.799)
      && met_wet(run(95.2, 11.0, 64.5, 1.0, 0.0, 0.0, 0.0, Water.Trace{0.0, 23.5}), 0, 0, 0.0, 0.0, 24.299),
      "under the sea the walk adds its path to the water the ray crossed before, and ends where the fog is whole: a block of sea at the tall column's foot, then its side, or after 23.5 wet blocks the sea alone")
    Lib.expect(walk(64.5, 15.5, 64.5, 0.0, 0.0, (0.0 - 1.0 : F32), 0.0, 3, trunk(), 27.5)
      && walk(64.5, 16.5, 64.5, 0.0, 0.0, (0.0 - 1.0 : F32), 0.0, 3, trunk(), 27.5), "a trunk's z side, below its leaves and in them")
    Lib.expect(walk(56.5, 13.0, 64.5, 0.0, 0.0, (0.0 - 1.0 : F32), 0.0, 0, 0, 0.0), "a ray through the gap between the ground and a canopy meets neither")
    Lib.expect(walk(56.5, 13.0, 64.5, 0.0, 0.0263, (0.0 - 1.0 : F32), 0.0, 2, leaves(), 38.02281)
      && walk(56.5, 18.0, 64.5, 0.0, (0.0 - 0.0263 : F32), (0.0 - 1.0 : F32), 0.0, 2, leaves(), 38.02281), "a canopy's underside where a ray climbs into it, its top where one drops into it")
    Lib.expect(walk(64.5, 16.5, 64.5, (0.0 - 1.0 : F32), 0.0, 0.0, 0.0, 0, 0, 0.0), "nothing to the west over low ground")
    Lib.expect(walk(64.5, 16.5, 64.5, 0.0, 1.0, 0.0, 0.0, 0, 0, 0.0), "a ray to the sky meets nothing")
    Lib.expect(walk(64.0, 10.3, 64.5, 1.0, 0.0, 0.0, 0.0, 1, flat(), 0.001) && walk(64.3, 10.0, 64.5, 0.6, (0.0 - 0.8 : F32), 0.0, 0.0, 2, flat(), 0.001),
      "a walk that starts inside a block meets it at once, on the face whose plane it starts on: the window's walk ends on the plane it last crossed")
    Lib.expect(walk(64.5, 16.5, 64.5, 1.0, 0.0, 0.0, 10.0, 1, tall(), 31.5), "the walk picks up at the distance the window's walk stopped at, and the hit's distance is the same")
    Lib.expect(U32.is_eq(shown(Render.after_walk(False{}, 0, 123456, 0, 0.5, 0.8, 0.0, 0, 0, 124.5, 16.5, 64.5, 1.0, 0.0, 0.0, 10.0, 0.0, 0.0, map())),
        shown(Render.after_walk(False{}, 0, 123456, 0, 0.5, 0.8, 0.0, 0, 0, 124.5, 16.5, 64.5, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, map())))
      && holds(Render.shadow_if(True{}, True{}, False{}, map(), 0, 0, 127.5, 12.0, 64.5, 0.9578, 0.2873, 0.0))
      && Bool.not(holds(Render.shadow_if(True{}, True{}, False{}, map(), 0, 0, 127.5, 12.0, 64.5, (0.0 - 0.9578 : F32), 0.2873, 0.0)))
      && holds(Render.solid_in(False{}, map(), 0, 0, 129.5, 13.0, 64.5)) && Bool.not(holds(Render.solid_in(False{}, map(), 0, 0, 127.5, 13.0, 64.5))),
      "past the window's side the far map goes on: a ray the window's walk took ten blocks on meets the column just past it as from the eye, a top by the side is in that column's shadow and lit with the sun behind it, and a cell past the side is the map's")
    Lib.expect(walk((0.0 - 35.5 : F32), 16.5, 64.5, 1.0, 0.0, 0.0, 100.0, 0, 0, 0.0), "the walk ends where the fog is whole: the tall column 131.5 blocks off is not met")
    Lib.expect(U32.is_eq(look(0, flat(), 1, 16.5, 0.0, (0.0 - 0.1 : F32), 1.0, 45.0), Render.dim(Render.blockcol(0, False{}, 0.0), day(1.0)))
      && U32.is_eq(look(0, tall(), 0, 16.5, 1.0, 0.0, 0.0, 31.5), Render.dim(Render.blockcol(2, True{}, 0.5), day(0.8)))
      && U32.is_eq(look(0, tall(), 0, 23.9, 1.0, 0.0, 0.0, 31.5), Render.dim(Render.blockcol(0, True{}, 0.9), day(0.8)))
      && U32.is_eq(look(0, tall(), 0, 23.5, 1.0, 0.0, 0.0, 31.5), Render.dim(Render.blockcol(1, True{}, 0.5), day(0.8))),
      "a far block is the window's: the grass top, stone deep in a side, the green band atop a grass block's side and the dirt under it")
    Lib.expect(U32.is_eq(look(1, tall(), 0, 16.5, 1.0, 0.0, 0.0, 31.5), Render.dim(Render.dim(Render.blockcol(2, True{}, 0.5), day(0.8)), 0.6))
      && U32.is_eq(look(1, flat(), 1, 16.5, 0.0, (0.0 - 0.1 : F32), 1.0, 45.0), Render.dim(Render.dim(Render.blockcol(0, False{}, 0.0), day(1.0)), 1.0)),
      "with the shadow flag, a side turned from the sun is darker and the top it shines on is not")
    Lib.expect(U32.is_eq(look(8, tall(), 0, 16.5, 1.0, 0.0, 0.0, 10000.0), 123456), "the fog takes a far block into the sky at the reach")
    Lib.expect(U32.is_eq(top_at(2, 64.5, 109.5), top_at(0, 64.5, 109.5)) && darker(top_at(2, 95.5, 64.5), top_at(0, 95.5, 64.5)),
      "with the occlusion flag, a far top in the open is as it was, and one at the tall column's foot darkens")
    Lib.expect(U32.is_eq(top_at(6, (0.0 - 22.7 : F32), (0.0 - 43.6 : F32)), top_at(6, 97.3, 64.4)),
      "west and north of the window, where its coordinates are negative, a far top at a tall column's foot is textured and occluded as one east of it")
    Lib.expect(U32.is_eq(top_at(1, 90.5, 64.5), Render.dim(Render.dim(Render.blockcol(0, False{}, 0.0), day(1.0)), 0.6))
      && U32.is_eq(top_at(1, 90.5, 74.5), Render.dim(Render.dim(Render.blockcol(0, False{}, 0.0), day(1.0)), 1.0)),
      "the far walk casts a far block's shadow: a top the tall column hides from the sun is the window's shade, one beside it is lit")
    Lib.expect(U32.is_eq(far_pixel(0, 0, 76.5, 16.5, 86.5, 0.0, (0.0 - 1.0 : F32), 0.0), Render.dim(Render.blockcol(1, False{}, 0.0), day(1.0)))
      && U32.is_eq(far_pixel(0, 2097152, 76.5, 16.5, 86.5, 0.0, (0.0 - 1.0 : F32), 0.0),
                   water_over(far_pixel(0, 0, 76.5, 16.5, 86.5, 0.0, (0.0 - 1.0 : F32), 0.0), 2097152, 16.5, (0.0 - 1.0 : F32), 8.5, 4.5)),
      "without the water the far sea shows its bed, dirt; with it, the window's water over that bed from where the ray went under")
    Lib.expect(U32.is_ne(far_pixel(134217728, 27262976, 73.0, 16.5, 64.5, 0.9806, (0.0 - 0.1961 : F32), 0.0),
                         far_pixel(0, 27262976, 73.0, 16.5, 64.5, 0.9806, (0.0 - 0.1961 : F32), 0.0)),
      "with the world in the mirror, the far sea at the tall column's foot mirrors its side")
