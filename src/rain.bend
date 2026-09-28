import Base
import ./util.bend as Util
import ./sky.bend as Sky
import ./world.bend as World
import ./water.bend as Water
import ./clouds.bend as Clouds

# RAIN: under a heavy sky, from the cloud over the eye, drops fall in the
# world, three a column: thin vertical streaks at places in the column its
# hashes choose, falling with the clock. A ray walks the columns about the
# eye and shows the drops it passes close to, in front of what it met or
# of the water's surface, and only under the open sky: a block anywhere
# over a drop keeps it dry. Being in the world, a drop is wide near the
# eye and thin far from it, and the eye walks past it.

# how hard it rains: none under a weather of 0.62, all of it from 0.9
def amount(+wx: F32) -> F32:
  F32.clamp(((wx - 0.62) * 3.5 : F32), 0.0, 1.0)

# how hard it rains, with the look on
def falling(on: Bool, +ck: U32) -> F32:
  match on:
    case False{}:
      0.0
    case True{}:
      amount(Clouds.weather(ck))

# a drop of the column (cx, cz), by its hash h: where the ray passes
# nearest to its line (s along the ray), a streak 0.04 of a block wide
# and 0.9 long in every 3 it falls, if h's top byte falls under `much`,
# if that pass is in front of the ray's end, and if no block of the
# column is over it: top is the log2 of its solid mask, its highest
# block's height, less than 0 when it has none
def drop(+h: U32, +cx: U32, +cz: U32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
         +inv: F32, +fall: F32, +much: F32, +reach: F32, +top: F32) -> F32:
  +qx = (U32.to_f32(cx) + 0.1 + U32.to_f32((h % 256 : U32)) * 0.0031372549 : F32)
  +qz = (U32.to_f32(cz) + 0.1 + U32.to_f32((h / 256 % 256 : U32)) * 0.0031372549 : F32)
  +s = (((qx - ox) * dx + (qz - oz) * dz) * inv : F32)
  +ex = (ox + dx * s - qx : F32)
  +ez = (oz + dz * s - qz : F32)
  +y = (oy + dy * s : F32)
  +across = F32.clamp((1.0 - (ex * ex + ez * ez) * 2500.0 : F32), 0.0, 1.0)
  +q = Util.fracf(((y + fall) * 0.33333334 + U32.to_f32((h / 65536 % 256 : U32)) * 0.0039215689 : F32))
  +along = F32.clamp(((0.3 - q) * 12.0 : F32), 0.0, 1.0)
  +near = (F32.clamp(((s - 0.8) * 2.0 : F32), 0.0, 1.0) * F32.clamp((1.0 - s * 0.085 : F32), 0.0, 1.0) : F32)
  +open = (s < reach : F32) && (top < (F32.floor(y) + 1.0 : F32) : F32)
  +there = (U32.to_f32((h / 16777216 : U32)) * 0.00390625 < much : F32)
  Bool.pick(F32, open && there, (across * along * near : F32), 0.0)

# the column's three drops: the one the ray shows most of
def column(+key: U32, +cx: U32, +cz: U32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
           +inv: F32, +fall: F32, +much: F32, +reach: F32, +mask: U32) -> F32:
  +top = F32.log2(U32.to_f32(mask))
  F32.max(drop(Sky.star_hash(key, 101), cx, cz, ox, oy, oz, dx, dy, dz, inv, fall, much, reach, top),
    F32.max(drop(Sky.star_hash(key, 102), cx, cz, ox, oy, oz, dx, dy, dz, inv, fall, much, reach, top),
      drop(Sky.star_hash(key, 103), cx, cz, ox, oy, oz, dx, dy, dz, inv, fall, much, reach, top)))

# the columns the ray crosses from the eye's, as the render's walk does in
# three: tx and tz the ray's distance to the next side along x and along
# z, ux and uz the distance between sides, stx and stz the step (1, or -1
# as a word); each column's mask is read for its drops' roof
def walk(fuel: Nat, +cx: U32, +cz: U32, +tx: F32, +tz: F32, +ux: F32, +uz: F32, +stx: U32, +stz: U32, +base: U32,
         +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, +inv: F32, +fall: F32, +much: F32, +reach: F32,
         +acc: F32, r: Array<U32> & U32) -> Array<U32> & F32:
  match fuel:
    case 0n:
      (w, mask) = r
      (w, F32.max(acc, column(Water.lattice(base, cx, cz), cx, cz, ox, oy, oz, dx, dy, dz, inv, fall, much, reach, mask)))
    case 1n+f:
      (w, mask) = r
      +wt = F32.max(acc, column(Water.lattice(base, cx, cz), cx, cz, ox, oy, oz, dx, dy, dz, inv, fall, much, reach, mask))
      +xs = (tx < tz : F32)
      +nx = Bool.pick(U32, xs, (cx + stx : U32), cx)
      +nz = Bool.pick(U32, xs, cz, (cz + stz : U32))
      walk(f, nx, nz, Bool.pick(F32, xs, (tx + ux : F32), tx), Bool.pick(F32, xs, tz, (tz + uz : F32)), ux, uz, stx, stz, base,
        ox, oy, oz, dx, dy, dz, inv, fall, much, reach, wt, Array.get(U32, w, World.col_at(base, nx, nz)))

def rained(+c: U32, +ly: F32, r: Array<U32> & F32) -> Array<U32> & U32:
  (w, wt) = r
  (w, Util.mix(c, Util.mix(Util.rgb(52, 58, 70), Util.rgb(190, 198, 210), Sky.daylight(ly)), (0.45 * wt : F32)))

# the rain over what the ray met, reach blocks out: grey streaks, lighter
# by day, as many as the cloud over the eye holds of how hard it rains, in
# the 11 columns the ray crosses first
def fall(on: Bool, +rain: F32, +ck: U32, +fm: U32, +base: U32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
         +reach: F32, +ly: F32, r: Array<U32> & U32) -> Array<U32> & U32:
  match on:
    case False{}:
      r
    case True{}:
      (w, c) = r
      +much = (rain * F32.clamp((Clouds.cover(fm, ck, ox, oz, 0.0, 0.0) * 2.5 : F32), 0.0, 1.0) : F32)
      +fx = F32.floor(ox)
      +fz = F32.floor(oz)
      +ux = (1.0 / F32.max(Util.absf(dx), 0.0001) : F32)
      +uz = (1.0 / F32.max(Util.absf(dz), 0.0001) : F32)
      +cx = Util.f2u(fx)
      +cz = Util.f2u(fz)
      rained(c, ly, walk(10n, cx, cz,
        (Bool.pick(F32, (dx > 0.0 : F32), (fx + 1.0 - ox : F32), (ox - fx : F32)) * ux : F32),
        (Bool.pick(F32, (dz > 0.0 : F32), (fz + 1.0 - oz : F32), (oz - fz : F32)) * uz : F32),
        ux, uz, Bool.pick(U32, (dx > 0.0 : F32), 1, 4294967295), Bool.pick(U32, (dz > 0.0 : F32), 1, 4294967295), base,
        ox, oy, oz, dx, dy, dz, (1.0 / F32.max((dx * dx + dz * dz : F32), 0.0025) : F32),
        (U32.to_f32((ck % 2500 : U32)) * 0.012 : F32), much, reach, 0.0,
        Array.get(U32, w, World.col_at(base, cx, cz))))
