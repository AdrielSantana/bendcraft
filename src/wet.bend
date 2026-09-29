import Base
import ./util.bend as Util
import ./clouds.bend as Clouds
import ./rain.bend as Rain
import ./water.bend as Water

# WET: the rain wets what it falls on. A face with no block over the air
# before it darkens and takes a sheen of the sky it mirrors, the more the
# flatter it is seen; on the tops of the ground puddles gather, from a
# noise over the world's columns, and mirror the sky and the world almost
# whole at a glance (the render walks the mirror). The world stays wet a while after the rain, from what the rain
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

def pool_fin(+wet: F32, p: Clouds.Slope, q: Clouds.Slope) -> Clouds.Slope:
  Clouds.Slope{+v, +gx, +gz} = p
  Clouds.Slope{+v2, +gx2, +gz2} = q
  Clouds.Slope{((0.65 * v + 0.35 * v2 - 1.0 + 0.45 * wet) * 8.0 : F32), ((0.65 * gx + 0.35 * gx2) * 8.0 : F32), ((0.65 * gz + 0.35 * gz2) * 8.0 : F32)}

# how deep into a puddle a top of the ground at (x, z), in the window's
# columns, lies, 0 at its edge and 1 where it covers the top whole, with
# its slope: a noise over cells of two columns and of one, deeper the wetter
def pool(+fm: U32, +x: F32, +z: F32, +wet: F32) -> Clouds.Slope:
  +a = Clouds.wrap((x + Clouds.corner_x(fm) : F32))
  +b = Clouds.wrap((z + Clouds.corner_z(fm) : F32))
  pool_fin(wet, Clouds.slope(a, b, 0.5, 128, 509), Clouds.slope(a, b, 1.0, 256, 601))

# how much of the top a puddle covers at a depth d
def cover(+d: F32) -> F32:
  Util.smooth(F32.clamp(d, 0.0, 1.0))

def puddle(+fm: U32, +x: F32, +z: F32, +wet: F32) -> F32:
  cover(Clouds.value(pool(fm, x, z, wet)))

# what of the rain, or of the wet it left, reaches the cell at cy: all of
# it if no block of the cell's column (its mask) is over it, none under a
# roof. The cell is open (air, or water), so its column's highest block
# is under cy or over cy + 1, and the log2's rounding cannot tell them
# wrong. A distant cell is not in the window, and is taken as open.
def reached(+distant: Bool, +amount: F32, +cy: F32, +mask: U32) -> F32:
  Bool.pick(F32, distant || (F32.log2(U32.to_f32(mask)) < (cy + 0.5 : F32) : F32), amount, 0.0)

# the face's colour c, fogged by f towards v, soaked by soak and under a
# puddle by pud: darker where it is lit, and what its mirror shows over
# it by the sheen, more the flatter the mirrored ray leaves (its cosine)
def sheen(+c: U32, +v: U32, +f: F32, +soak: F32, +pud: F32, +cosine: F32, +shown: U32) -> U32:
  +g = (1.0 - cosine : F32)
  +fres = (g * g * g : F32)
  Util.mix(Util.mix(c, Util.mix(0, v, f), (0.3 * soak + 0.35 * pud : F32)),
    Util.mix(shown, v, f), (0.25 * soak * fres + pud * (0.2 + 0.75 * fres) : F32))

# the ray m mirrored by a top of the ground, shivered by the rain's rings
# on its puddle (Water.rings) as the lake's ripples shiver its own
def mirror_of(puddly: Bool, +base: U32, +ck: U32, +rain: F32, +x: F32, +z: F32, +strength: F32, m: Water.Reflection) -> Water.Reflection:
  match puddly:
    case False{}:
      m
    case True{}:
      Water.Reflection{+rx, +ry, +rz, cosine} = m
      Water.tilted(rx, (0.0 - ry : F32), rz, strength, Water.rings(base, ck, rain, x, z))
