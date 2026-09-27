import Base
import ./util.bend as Util
import ./sky.bend as Sky
import ./world.bend as World
import ./clouds.bend as Clouds

# RAIN: under a heavy sky, from the cloud over the eye, streaks fall on
# three cylinders about it, 2, 4 and 7 blocks out. A streak's place on its
# cylinder is the ray's bearing, and it falls with the clock. A ray shows
# a streak where it meets a cylinder before its hit or the water's
# surface, and only under the open sky: a block anywhere over that point
# keeps the rain off.

# how hard it rains: none under a weather of 0.62, all of it from 0.9
def amount(+wx: F32) -> F32:
  F32.clamp(((wx - 0.62) * 3.5 : F32), 0.0, 1.0)

def raining(+ck: U32) -> Bool:
  (amount(Clouds.weather(ck)) > 0.0 : F32)

# a streak on the cylinder cut in n cells around it, at the bearing a
# (0..1) and the height y: one cell in `much` holds a streak a twelfth of
# the cell wide, 0.9 of a block long in every 3 it falls
def streak(+n: U32, +seed: U32, +a: F32, +y: F32, +fall: F32, +much: F32) -> F32:
  +u = (a * U32.to_f32(n) : F32)
  +h = Sky.star_hash((F32.to_u32(F32.floor(u)) % n : U32), seed)
  +c = (0.3 + 0.4 * U32.to_f32((h / 1024 % 256 : U32)) * 0.0039215689 : F32)
  +across = F32.clamp((1.0 - Util.absf((Util.fracf(u) - c : F32)) * 12.0 : F32), 0.0, 1.0)
  +q = Util.fracf(((y + fall) * 0.33333334 + U32.to_f32((h / 262144 % 256 : U32)) * 0.0039215689 : F32))
  +along = F32.clamp(((0.3 - q) * 12.0 : F32), 0.0, 1.0)
  Bool.pick(F32, (U32.to_f32((h % 1024 : U32)) * 0.0009775171 < much : F32), (across * along : F32), 0.0)

# the streak where the ray meets it, if that point is in front of what the
# ray met and nothing solid stands over it: its column's mask has no bit
# above the point's
def open_sky(+front: Bool, +y: F32, +wt: F32, +acc: F32, r: Array<U32> & U32) -> Array<U32> & F32:
  (w, mask) = r
  +roofed = (U32.to_f32(mask) >= F32.pow(2.0, (F32.floor(y) + 1.0 : F32)) : F32)
  (w, Bool.pick(F32, front && Bool.not(roofed), F32.max(acc, wt), acc))

def layer(+rad: F32, +n: U32, +seed: U32, +near: F32, +base: U32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
          +flat: F32, +a: F32, +fall: F32, +much: F32, +reach: F32, r: Array<U32> & F32) -> Array<U32> & F32:
  (w, acc) = r
  +s = (rad / flat : F32)
  +y = (oy + dy * s : F32)
  open_sky((s < reach : F32), y, (near * streak(n, seed, a, y, fall, much) : F32), acc,
    Array.get(U32, w, World.col_at(base, Util.f2u((ox + dx * s : F32)), Util.f2u((oz + dz * s : F32)))))

def rained(+c: U32, +ly: F32, r: Array<U32> & F32) -> Array<U32> & U32:
  (w, wt) = r
  (w, Util.mix(c, Util.mix(Util.rgb(52, 58, 70), Util.rgb(190, 198, 210), Sky.daylight(ly)), (0.45 * wt : F32)))

# the rain over what the ray met, reach blocks out: grey streaks, lighter
# by day, the nearer the brighter, as many as the cloud over the eye holds
def fall(on: Bool, +ck: U32, +fm: U32, +base: U32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
         +reach: F32, +ly: F32, r: Array<U32> & U32) -> Array<U32> & U32:
  match on:
    case False{}:
      r
    case True{}:
      (w, c) = r
      +much = (amount(Clouds.weather(ck)) * F32.clamp((Clouds.cover(fm, ck, ox, oz, 0.0, 0.0) * 2.5 : F32), 0.0, 1.0) : F32)
      +flat = F32.max(F32.sqrt((dx * dx + dz * dz : F32)), 0.05)
      +a = (F32.atan2(dx, dz) * 0.15915494 + 0.5 : F32)
      +fall = (U32.to_f32((ck % 2500 : U32)) * 0.012 : F32)
      rained(c, ly,
        layer(2.0, 38, 911, 1.0, base, ox, oy, oz, dx, dy, dz, flat, a, fall, much, reach,
          layer(4.0, 75, 912, 0.8, base, ox, oy, oz, dx, dy, dz, flat, a, fall, much, reach,
            layer(7.0, 132, 913, 0.6, base, ox, oy, oz, dx, dy, dz, flat, a, fall, much, reach, (w, 0.0)))))
