import Base
import ./util.bend as Util
import ./world.bend as World
import ./clouds.bend as Clouds
import ./rain.bend as Rain

# WET: the rain wets what it falls on. A face with no block over the air
# before it darkens and takes a sheen of the sky it mirrors, the more the
# flatter it is seen; on the tops of the ground puddles gather, from a
# noise over the world's columns, and mirror the sky almost whole at a
# glance. The world stays wet a while after the rain, from what the rain
# of a quarter and of half a day ago left, the puddles shrinking as it
# dries.

# how wet the world is, with the look on: the rain now, or what the
# earlier rain left
def wetness(on: Bool, +ck: U32) -> F32:
  match on:
    case False{}:
      0.0
    case True{}:
      F32.max(Rain.amount(Clouds.weather(ck)),
        F32.max((0.7 * Rain.amount(Clouds.weather((ck - U32.min(ck, 262144) : U32))) : F32),
          (0.4 * Rain.amount(Clouds.weather((ck - U32.min(ck, 524288) : U32))) : F32)))

# how much of a top of the ground at (x, z), in the window's columns, a
# puddle covers: cells of two columns and of one, more the wetter
def puddle(+fm: U32, +x: F32, +z: F32, +wet: F32) -> F32:
  +a = Clouds.wrap((x + Clouds.corner_x(fm) : F32))
  +b = Clouds.wrap((z + Clouds.corner_z(fm) : F32))
  +n = (0.65 * Clouds.lattice(a, b, 0.5, 128, 509) + 0.35 * Clouds.lattice(a, b, 1.0, 256, 601) : F32)
  Util.smooth(F32.clamp(((n - 1.0 + 0.45 * wet) * 8.0 : F32), 0.0, 1.0))

# the face's colour c, fogged by f towards v: darker where it is lit, and
# the sky of the mirrored direction (rx, ry, rz) over it by the sheen, if
# no block of the air cell's column (its mask) is over it. The air cell
# is open, so its column's highest block is under cy or over cy + 1, and
# the log2's rounding cannot tell them wrong. A distant face's air is not
# in the window, and is taken as open.
def soaked(+distant: Bool, +wet: F32, +fm: U32, +ck: U32, +cy: F32, +puddly: Bool, +x: F32, +z: F32, +glance: F32,
           +rx: F32, +ry: F32, +rz: F32, +v: U32, +f: F32, +fl: U32, +lx: F32, +ly: F32, +lz: F32, +c: U32,
           r: Array<U32> & U32) -> Array<U32> & U32:
  (w, mask) = r
  +soak = Bool.pick(F32, distant || (F32.log2(U32.to_f32(mask)) < (cy + 0.5 : F32) : F32), wet, 0.0)
  +pud = Bool.pick(F32, puddly, puddle(fm, x, z, soak), 0.0)
  +fres = (glance * glance * glance : F32)
  (w, Util.mix(Util.mix(c, Util.mix(0, v, f), (0.3 * soak + 0.35 * pud : F32)),
    Util.mix(Clouds.mirrored(fl, ck, rx, ry, rz, lx, ly, lz), v, f), (0.25 * soak * fres + pud * (0.2 + 0.75 * fres) : F32)))

# the face soaked, or as it was in a dry world, whose air is not read
def soak(on: Bool, +distant: Bool, +wet: F32, +base: U32, +fm: U32, +ck: U32, +cx: F32, +cy: F32, +cz: F32, +puddly: Bool,
         +x: F32, +z: F32, +glance: F32, +rx: F32, +ry: F32, +rz: F32, +v: U32, +f: F32, +fl: U32, +lx: F32, +ly: F32, +lz: F32,
         r: Array<U32> & U32) -> Array<U32> & U32:
  match on:
    case False{}:
      r
    case True{}:
      (w, c) = r
      soaked(distant, wet, fm, ck, cy, puddly, x, z, glance, rx, ry, rz, v, f, fl, lx, ly, lz, c,
        Array.get(U32, w, World.col_at(base, Util.f2u(cx), Util.f2u(cz))))
