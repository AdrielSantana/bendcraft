import Base
import ./lib.bend as Lib
import ../src/day.bend as Day
import ../src/inventory.bend as Inventory
import ../src/sky.bend as Sky
import ../src/render.bend as Render
import ../src/world.bend as World
import ../src/player.bend as Player
import ../src/save.bend as Save
import ../src/clouds.bend as Clouds
import ../src/rain.bend as Rain
import ../src/wet.bend as Wet
import ../src/util.bend as Util
import ../src/water.bend as Water
import ../src/lens.bend as Lens
import ../src/shafts.bend as Shafts
import ../src/torch.bend as Torch

def blocked(r: Array<U32> & Bool) -> Bool:
  (w, got) = r
  got

# Each blocker is five cells away, beyond the initial cell and in range
# of the fixed shadow walk. Reversing the ray must leave it behind.
def probe(+x: U32, +y: U32, +z: U32, +dx: F32, +dy: F32, +dz: F32) -> Bool:
  w = Array.set(U32, [0 : U32^20n], World.col_at(0, x, z), U32.shln(1, U32.to_nat(y)))
  blocked(Render.shadow_fin(0, 64.5, 10.5, 64.5, dx, dy, dz, Render.run_glance(24n, w, 0, 64.5, 10.5, 64.5, dx, dy, dz, 0, 0)))

def white(t: Sky.Tint) -> Bool:
  Sky.Tint{r, g, b} = t
  F32.is_eq(r, 1.0) && F32.is_eq(g, 1.0) && F32.is_eq(b, 1.0)

# how much redder than blue a light is
def warmth(t: Sky.Tint) -> F32:
  Sky.Tint{r, g, b} = t
  (r - b : F32)

def seen_in(r: Array<U32> & Render.Cam) -> F32:
  (w, cam) = r
  Render.Cam{px, py, pz, yaw, pit, base, far, sel, items, stat, fl, rw, rh, lx, ly, lz, clock, seen} = cam
  seen

# how much of the fixed sun (0.48, 0.8, 0.36) an eye at (64.5, 10.5, 64.5)
# of the world w sees, the lens on with the flags more; with the day's
# cycle (33554432) at night, of the moon, at the same place in the sky
def eye_sun(w: Array<U32>, +more: U32) -> F32:
  seen_in(Render.sighted(w, Render.camera(64.5, 10.5, 64.5, 0.0, 0.0, 0, 0, 0, 0, 0, 0,
    (524288 + more : U32), 64, 64, (524288 + Day.morning() : U32))))

def near_corner(r: Array<U32> & Shafts.Beams) -> U32:
  (w, b) = r
  Shafts.Beams{tl, tr, bl, br} = b
  tl

# the shafts along the ray from an eye at y 20 of the world w straight
# ahead, level, under the fixed sun, the clouds' shadows off
def shafts_in(w: Array<U32>) -> U32:
  near_corner(Render.beams(Render.camera(64.5, 20.0, 64.5, 0.0, 0.0, 0, 0, Render.looks_base(), 0, 0, 0, 0, 64, 64, 0), w, 32, 32))

def clock(g: Player.Game) -> U32:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, sel, res, t, bag} = g
  t

def restored(r: Player.Game & String) -> U32:
  (g, text) = r
  clock(Save.parse(String.lines(text), Player.res512()))

def fixture(t: U32) -> Player.Game:
  Player.G{World.W{[0 : U32^20n], World.Meta{Map.new(&2, World.Col), 1048512, 1048512, Nil{}, 0, 0}},
    64.5, 30.0, 64.5, 0.0, 0.0, 0.0, 0, 0, 0, Player.res512(), t, Inventory.empty()}

def shown(r: Array<U32> & U32) -> U32:
  (w, c) = r
  c

def clouds_map() -> Array<U32>:
  Clouds.load(256n, [0 : U32^20n], 0)

# a ray from the eye at (64.5, 30, 64.5) of a window whose corner is 0
# mod 256, and the same ray from a window 10 columns further along x
def cloud_at(+fm: U32, +ox: F32, +dx: F32, +dy: F32, +dz: F32) -> U32:
  shown(Clouds.over(True{}, clouds_map(), fm, 154747, 12345, ox, 30.0, 64.5, dx, dy, dz, 0.48, 0.8, 0.36, 1.0, 6789))

# the march's reads along a line of the clouds' columns against the
# octaves they hold: the broad within a byte's step, the fine within
# what blending between columns loses of its smaller cells
def agrees(n: Nat, +x: F32, +ok: Bool, r: Array<U32> & Clouds.Cover) -> Bool:
  match n:
    case 0n:
      ok
    case 1n+k:
      (w, cv) = r
      Clouds.Cover{+c, +f, +s} = cv
      +z = (x * 0.61 : F32)
      +good = Lib.near(c, Clouds.broad(x, z), 0.004) && Lib.near(f, Clouds.fine(x, z), 0.01)
        && Lib.near(s, Clouds.broad(Clouds.wrap((x + 2.0 : F32)), Clouds.wrap((z - 1.5 : F32))), 0.004)
      agrees(k, (x + 1.37 : F32), ok && good, Clouds.coverage(w, (x + 1.37 : F32), ((x + 1.37 : F32) * 0.61 : F32), 2.0, (0.0 - 1.5 : F32)))

# the clouds the same eye's mirror, on the water at 12, shows
def glimpse_at(+fm: U32, +ox: F32, +dx: F32, +dy: F32, +dz: F32) -> U32:
  Clouds.glimpsed(True{}, fm, 154747, 12345, ox, 12.0, 64.5, dx, dy, dz, 0.48, 0.8, 0.36, 1.0, 6789)

def fixed(+dx: F32, +dy: F32, +dz: F32) -> Bool:
  U32.is_eq(cloud_at(0, 64.5, dx, dy, dz), cloud_at(2560, 54.5, dx, dy, dz))
    && U32.is_eq(glimpse_at(0, 64.5, dx, dy, dz), glimpse_at(2560, 54.5, dx, dy, dz))

# the sun's disc, looked at on the day t, with the clouds' looks or not
def sun_seen(on: Bool, +t: U32) -> U32:
  Clouds.heavens(on, 134217728, t, 12345, 0.48, 0.8, 0.36, 0.48, 0.8, 0.36)

# the sun's light on the ground along a row of columns: the least of it,
# and whether every column's lies between a heavy cloud's and the open's
def shaded(n: Nat, +x: F32, +least: F32, +ok: Bool) -> F32 & Bool:
  match n:
    case 0n:
      (least, ok)
    case 1n+k:
      +s = Clouds.shade(True{}, 0, 154747, x, 20.0, 64.5, 0.0, 1.0, 0.0)
      shaded(k, (x + 3.0 : F32), F32.min(least, s), ok && (s >= 0.55 : F32) && (s <= 1.0 : F32))

def row(r: F32 & Bool) -> Bool:
  (least, ok) = r
  ok && (least < 0.95 : F32)

# the ground's sun along a row, and along the row 10 columns east 20.48
# seconds later, when the wind has carried the clouds that far
def carried(n: Nat, +x: F32) -> Bool:
  match n:
    case 0n:
      True{}
    case 1n+k:
      Lib.near(Clouds.shade(True{}, 0, 0, x, 20.0, 64.5, 0.0, 1.0, 0.0), Clouds.shade(True{}, 0, 20480, (x + 10.0 : F32), 20.0, 64.5, 0.0, 1.0, 0.0), 0.005)
        && carried(k, (x + 3.0 : F32))

# the least and the most weather over n quarter days
def weathers(n: Nat, +t: U32, +lo: F32, +hi: F32) -> F32 & F32:
  match n:
    case 0n:
      (lo, hi)
    case 1n+k:
      +w = Clouds.weather(t)
      weathers(k, (t + 262144 : U32), F32.min(lo, w), F32.max(hi, w))

def spans(r: F32 & F32) -> Bool:
  (+lo, +hi) = r
  (lo >= 0.0 : F32) && (lo < 0.1 : F32) && (hi > 0.8 : F32) && (hi <= 1.0 : F32)

# level rays all around an eye at (ox, 20.5, 64.5) of the window (fm,
# base) at the clock t, over a colour, each met reach blocks out: their
# colours summed, 128 times the colour where the rain touched none
def rays(n: Nat, +i: U32, +fm: U32, +base: U32, +ox: F32, +t: U32, +reach: F32, +sum: U32, r: Array<U32> & U32) -> U32:
  match n:
    case 0n:
      (w, c) = r
      (sum + c : U32)
    case 1n+k:
      (w, c) = r
      +a = (U32.to_f32(i) * 0.049087385 : F32)
      rays(k, (i + 1 : U32), fm, base, ox, t, reach, (sum + c : U32),
        Rain.fall(True{}, Rain.falling(True{}, t), t, fm, base, ox, 20.5, 64.5, F32.sin(a), 0.0, F32.cos(a), reach, 0.8, (w, 6789)))

def dry(+sum: U32) -> Bool:
  U32.is_eq(sum, 868992)

# a face of the colour 6789, a top of the ground or not, over the air cell
# (x, 20, 64.5) of a world whose every word is `word`, seen at a slant at
# the clock t
def wet_face(+t: U32, +puddly: Bool, +x: F32, +word: U32) -> U32:
  shown(Render.soak((Wet.wetness(True{}, t) > 0.0 : F32), False{}, Wet.wetness(True{}, t), 0, 0, t, x, 20.0, 64.5, puddly, x, 64.5, 3.0, 23.0,
    Water.Reflection{0.3, 0.5, 0.2, 0.5}, 12345, 0.0, Render.looks(), 0.48, 0.8, 0.36, ([word : U32^20n], 6789)))

# the same face, a puddle's, in the second morning's rain, beside a pillar
# standing a column along x from it (over z 64 and 65), with the looks in
# the camera's base: what it shows
def by_pillar(+more: U32, +x: F32) -> U32:
  shown(Render.soak(True{}, False{}, Wet.wetness(True{}, 1203323), Water.with_looks(0, more), 0, 1203323, x, 20.0, 64.5, True{}, x, 64.5, 3.0, 23.0,
    Water.Reflection{0.3, 0.5, 0.2, 0.5}, 12345, 0.0, Render.looks(), 0.48, 0.8, 0.36,
    (Array.set(U32, Array.set(U32, [0 : U32^20n], World.col_at(0, (Util.f2u(x) + 1 : U32), 64), 4294967295),
      World.col_at(0, (Util.f2u(x) + 1 : U32), 65), 4294967295), 6789)))

def bent(r: Array<U32> & Water.Mirror) -> F32:
  (w, m) = r
  Water.Mirror{bottom, n, colour} = m
  Water.Reflection{x, y, z, cosine} = n
  x

# how many of n points on water at 12 along z = 64.3, seen from 4 blocks
# over it in the second morning, mirror a ray the rain's rings bent, in a
# world whose every word is `word`
def ringed(n: Nat, +x: F32, +word: U32, +count: U32) -> U32:
  match n:
    case 0n:
      count
    case 1n+k:
      ringed(k, (x + 0.07 : F32), word, (count + Bool.pick(U32,
        F32.is_eq(bent(Render.mirrored(True{}, False{}, 0, 1203323, 1.0, Render.looks(), 0, x, 16.0, 64.3, 0.0, (0.0 - 1.0 : F32), 0.0, 4.0, 0.48, 0.8, 0.36, ([word : U32^20n], 0))),
          bent(Render.mirrored(True{}, False{}, 0, 1203323, 0.0, Render.looks(), 0, x, 16.0, 64.3, 0.0, (0.0 - 1.0 : F32), 0.0, 4.0, 0.48, 0.8, 0.36, ([word : U32^20n], 0)))), 0, 1) : U32))

# the first x along z = 64.5 from x where a puddle of the wettest ground
# covers the whole top
def puddled(n: Nat, +x: F32) -> F32:
  match n:
    case 0n:
      x
    case 1n+k:
      Bool.pick(F32, (Wet.puddle(0, x, 64.5, 1.0) >= 1.0 : F32), x, puddled(k, (x + 0.25 : F32)))

# how many of n points on a slant across the columns hold a puddle
def puddles(n: Nat, +x: F32, +wet: F32, +count: U32) -> U32:
  match n:
    case 0n:
      count
    case 1n+k:
      puddles(k, (x + 0.37 : F32), wet, (count + Bool.pick(U32, (Wet.puddle(0, x, (x * 0.61 : F32), wet) > 0.0 : F32), 1, 0) : U32))

# the first column along the row z = 64.5 with no cloud over it
def gap(n: Nat, +t: U32, +x: F32) -> F32:
  match n:
    case 0n:
      x
    case 1n+k:
      Bool.pick(F32, F32.is_eq(Clouds.cover(0, t, x, 64.5, 0.0, 0.0), 0.0), x, gap(k, t, (x + 1.0 : F32)))

def main() -> IO(Unit):
  do IO<Unit>:
    Lib.expect(U32.is_ne(Sky.gradient(True{}, 0.0, 0.8), Sky.gradient(True{}, 1.0, 0.8)), "sky has a vertical gradient")
    Lib.expect(fixed(0.0, 1.0, 0.0) && fixed(0.3, 0.6, 0.2) && fixed((0.0 - 0.5 : F32), 0.4, 0.7) && fixed(0.1, 0.9, (0.0 - 0.4 : F32))
      && (U32.is_ne(cloud_at(0, 64.5, 0.0, 1.0, 0.0), 6789) || U32.is_ne(cloud_at(0, 64.5, 0.3, 0.6, 0.2), 6789)
        || U32.is_ne(cloud_at(0, 64.5, (0.0 - 0.5 : F32), 0.4, 0.7), 6789))
      && (U32.is_ne(glimpse_at(0, 64.5, 0.0, 1.0, 0.0), 6789) || U32.is_ne(glimpse_at(0, 64.5, 0.3, 0.6, 0.2), 6789)
        || U32.is_ne(glimpse_at(0, 64.5, (0.0 - 0.5 : F32), 0.4, 0.7), 6789)),
      "a cloud, and its glimpse in a mirror, stays over its column when the window moves under it")
    Lib.expect(agrees(186n, 0.5, True{}, Clouds.coverage(clouds_map(), 0.5, 0.305, 2.0, (0.0 - 1.5 : F32))),
      "the clouds' map holds their coverage: the march reads it as the octaves give it")
    Lib.expect(U32.is_eq(shown(Clouds.over(False{}, clouds_map(), 0, 154747, 12345, 64.5, 30.0, 64.5, 0.3, 0.6, 0.2, 0.48, 0.8, 0.36, 1.0, 6789)), 6789)
      && U32.is_eq(shown(Clouds.over(True{}, clouds_map(), 0, 3145728, 12345, 64.5, 30.0, 64.5, 0.3, (0.0 - 0.4 : F32), 0.2, 0.48, 0.8, 0.36, 1.0, 6789)), 6789),
      "with the clouds off, or under the horizon on a fair day, the sky shows as it was")
    Lib.expect(row(shaded(86n, 0.0, 1.0, True{})) && F32.is_eq(Clouds.shade(False{}, 0, 154747, 10.0, 20.0, 10.0, 0.0, 1.0, 0.0), 1.0),
      "a cloud dims the sun on the ground under it, never below a heavy cloud's 0.55, and none with its look off")
    Lib.expect(carried(86n, 0.0), "the wind carries the clouds along x, 10 columns in 20.48 seconds")
    Lib.expect(spans(weathers(64n, 0, 1.0, 0.0)) && Lib.near(Clouds.weather(4294967295), Clouds.weather(0), 0.001)
      && (Clouds.weather(Day.morning()) > 0.3 : F32) && (Clouds.weather(Day.morning()) < 0.6 : F32),
      "the weather goes from clear to overcast within sixteen days, with no jump at the clock's wrap, and the first morning is fair")
    Lib.expect(U32.is_ne(Clouds.overcast(True{}, 1048576, 0.8, 6789), 6789) && U32.is_eq(Clouds.overcast(True{}, 3145728, 0.8, 6789), 6789)
      && U32.is_eq(Clouds.overcast(False{}, 1048576, 0.8, 6789), 6789)
      && U32.is_ne(sun_seen(True{}, 1048576), sun_seen(False{}, 1048576)) && U32.is_eq(sun_seen(True{}, 3145728), sun_seen(False{}, 3145728)),
      "a heavy sky greys the sky and its fog and veils its sun, moon and stars, a fair one leaves them, and none with the clouds off")
    Lib.expect((Rain.falling(True{}, 1203323) > 0.0 : F32) && F32.is_eq(Rain.falling(True{}, 3145728), 0.0) && F32.is_eq(Rain.falling(True{}, Day.morning()), 0.0)
      && F32.is_eq(Rain.falling(False{}, 1203323), 0.0),
      "it rains on the second morning, overcast, and not on a fair day nor on the first morning")
    Lib.expect(Bool.not(dry(rays(128n, 0, 0, 0, 64.5, 1203323, 100.0, 0, ([0 : U32^20n], 0))))
      && dry(rays(128n, 0, 0, 0, 64.5, 1203323, 100.0, 0, ([33554432 : U32^20n], 0)))
      && dry(rays(128n, 0, 0, 0, 64.5, 1203323, 0.75, 0, ([0 : U32^20n], 0))),
      "rain falls around an eye under a cloud and the open sky, none under a roof over every column, none before a wall at arm's length")
    Lib.expect(U32.is_eq(rays(128n, 0, 0, 0, 64.5, 1203323, 100.0, 0, ([0 : U32^20n], 0)), rays(128n, 0, 256, 128, 63.5, 1203323, 100.0, 0, ([0 : U32^20n], 0)))
      && U32.is_ne(rays(128n, 0, 0, 0, 64.5, 1203323, 100.0, 0, ([0 : U32^20n], 0)), rays(128n, 0, 0, 0, 64.87, 1203323, 100.0, 0, ([0 : U32^20n], 0))),
      "the drops are the world's: the same when the window moves a column under the eye, others when the eye moves through them")
    Lib.expect((Wet.wetness(True{}, 1203323) > 0.5 : F32) && F32.is_eq(Rain.amount(Clouds.weather(1769472)), 0.0) && (Wet.wetness(True{}, 1769472) > 0.0 : F32)
      && F32.is_eq(Wet.wetness(True{}, 2293760), 0.0) && F32.is_eq(Wet.wetness(True{}, 3145728), 0.0) && F32.is_eq(Wet.wetness(True{}, Day.morning()), 0.0)
      && F32.is_eq(Wet.wetness(False{}, 1203323), 0.0),
      "the ground is wet in the rain and a while after it, dry on a fair day and on the first morning, and never with its look off")
    Lib.expect(U32.is_ne(wet_face(1203323, False{}, 64.5, 0), 6789)
      && U32.is_ne(wet_face(1203323, True{}, puddled(512n, 0.5), 0), wet_face(1203323, False{}, puddled(512n, 0.5), 0))
      && U32.is_eq(wet_face(1203323, True{}, puddled(512n, 0.5), 33554432), 6789) && U32.is_eq(wet_face(3145728, True{}, puddled(512n, 0.5), 0), 6789),
      "in the rain a face under the open sky darkens and shines and a puddle more, one under a roof stays as it was, and so does one on a fair day")
    Lib.expect((puddles(512n, 0.5, 1.0, 0) > 51 : U32) && (puddles(512n, 0.5, 1.0, 0) < 307 : U32)
      && (puddles(512n, 0.5, 0.4, 0) < puddles(512n, 0.5, 1.0, 0) : U32) && U32.is_eq(puddles(512n, 0.5, 0.0, 0), 0),
      "puddles cover some of the ground's tops in the rain, less as it dries, and none on dry ground")
    Lib.expect(U32.is_ne(by_pillar(Render.looks_base(), puddled(512n, 0.5)), by_pillar(0, puddled(512n, 0.5))),
      "a puddle mirrors a pillar standing by it with the world in the mirror, the sky alone without")
    Lib.expect((ringed(64n, 64.0, 0, 0) > 0 : U32) && U32.is_eq(ringed(64n, 64.0, 33554432, 0), 0),
      "the rain rings water under the open sky, and none under a roof")
    Lib.expect(F32.is_eq(Clouds.cover(0, 1203323, gap(120n, 1203323, 0.5), 64.5, 0.0, 0.0), 0.0)
      && dry(rays(128n, 0, 0, 0, gap(120n, 1203323, 0.5), 1203323, 100.0, 0, ([0 : U32^20n], 0))),
      "on the same morning, an eye under a gap in the clouds stays dry")
    Lib.expect((Sky.gradient(True{}, 0.5, (0.0 - 1.0 : F32)) < Sky.gradient(True{}, 0.5, 1.0) : U32), "night sky is darker")
    Lib.expect(F32.is_eq(Sky.fog(0, 40.0, 5.0, 5.0), 0.0), "fog flags disable both terms")
    Lib.expect(F32.is_eq(Sky.fog(8, 120.0, 30.0, 30.0), 1.0), "distant terrain reaches sky colour")
    Lib.expect((Sky.fog(2147483648, 20.0, 5.0, 5.0) > Sky.fog(2147483648, 20.0, 30.0, 30.0) : F32), "mist is denser near the ground")
    Lib.expect(U32.is_ne(Sky.sun(True{}, 0, 1.0, 0.8, 0.8), 0), "sun disc")
    Lib.expect(U32.is_eq(Sky.sun(False{}, 123, 1.0, 0.8, 0.8), 123), "sun flag")
    Lib.expect(white(Sky.light(False{}, 1.0, 0.1)) && F32.is_eq(Sky.sunned(False{}, False{}, 0.83, 0.1), 0.83)
      && U32.is_eq(Sky.tinted(123456, Sky.light(False{}, 1.0, 0.1)), 123456), "the light's colour off leaves the light white and a face's sun as it was")
    Lib.expect((warmth(Sky.light(True{}, 1.0, 0.1)) > warmth(Sky.light(True{}, 1.0, 0.9)) : F32) && (warmth(Sky.light(True{}, 0.6, 0.9)) < 0.0 : F32)
      && (warmth(Sky.light(True{}, 1.0, 0.9)) > 0.0 : F32), "sunlight is warm and warmer as it sets, the shade's light blue")
    Lib.expect((Sky.sunned(True{}, False{}, 1.0, 0.05) < Sky.sunned(True{}, False{}, 1.0, 0.9) : F32) && F32.is_eq(Sky.sunned(True{}, False{}, 1.0, 0.9), 1.0)
      && F32.is_eq(Sky.sunned(True{}, True{}, 1.0, 0.9), 0.6), "a face the sun grazes takes less of it, one it meets square all, one in a shadow none")
    Lib.expect(F32.is_eq(Sky.side(True{}, 0.5), 1.0) && F32.is_eq(Sky.side(True{}, (0.0 - 0.5 : F32)), (0.0 - 1.0 : F32))
      && F32.is_eq(Sky.side(False{}, (0.0 - 0.5 : F32)), 1.0)
      && F32.is_eq(Sky.level(True{}, 0.8), Sky.level(False{}, 0.8)) && (Sky.level(True{}, (0.0 - 0.8 : F32)) > Sky.level(False{}, (0.0 - 0.8 : F32)) : F32),
      "once the sun has set the moon lights the world, from opposite it, and lifts the night's light; none by day, none with its look off")
    Lib.expect((Sky.moonsky(True{}, 1315860, 0.0, 1.0, 0.0, 0.0, (0.0 - 1.0 : F32), 0.0) > Sky.moonsky(True{}, 1315860, 1.0, 0.0, 0.0, 0.0, (0.0 - 1.0 : F32), 0.0) : U32)
      && (Sky.moonsky(True{}, 1315860, 1.0, 0.0, 0.0, 0.0, (0.0 - 1.0 : F32), 0.0) > 1315860 : U32)
      && U32.is_eq(Sky.moonsky(False{}, 1315860, 0.0, 1.0, 0.0, 0.0, (0.0 - 1.0 : F32), 0.0), 1315860)
      && U32.is_eq(Sky.moonsky(True{}, 1315860, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0), 1315860),
      "the full moon lifts the night's sky, most around it, and leaves the day's, and the sky with its look off")
    Lib.expect(Torch.held(Torch.in_hand(Water.with_looks(0, Render.looks_base()), Torch.slot()))
      && Bool.not(Torch.held(Torch.in_hand(Water.with_looks(0, Render.looks_base()), 8)))
      && Bool.not(Torch.held(Torch.in_hand(0, Torch.slot()))),
      "the torch is in hand when its slot is chosen with its look on, and not otherwise")
    Lib.expect((Torch.over(True{}, 0, 2.0, 1.0, 0.5) > Torch.over(True{}, 0, 8.0, 1.0, 0.5) : F32)
      && (Torch.over(True{}, 0, 8.0, 1.0, 0.5) > Torch.over(True{}, 0, 8.0, 0.0, 0.5) : F32)
      && F32.is_eq(Torch.over(True{}, 0, Torch.reach(), 1.0, 0.5), 0.0) && F32.is_eq(Torch.over(False{}, 0, 2.0, 1.0, 0.5), 0.0),
      "the torch's light fades with the distance and the angle, and ends at its reach")
    Lib.expect(U32.is_eq(Torch.lit(True{}, 8421504, 1.0, Sky.light(True{}, 1.0, 0.8), Torch.over(True{}, 0, 6.0, 1.0, Sky.level(True{}, 0.8))),
        Torch.lit(False{}, 8421504, 1.0, Sky.light(True{}, 1.0, 0.8), 0.0))
      && (Torch.lit(True{}, 8421504, 0.6, Sky.light(True{}, 0.6, (0.0 - 0.8 : F32)), Torch.over(True{}, 0, 3.0, 1.0, Sky.level(True{}, (0.0 - 0.8 : F32))))
        > Torch.lit(False{}, 8421504, 0.6, Sky.light(True{}, 0.6, (0.0 - 0.8 : F32)), 0.0) : U32),
      "a torch in hand leaves a face in the day's sun as it was and lights one near it at night")
    Lib.expect(U32.is_ne(Sky.halo(True{}, 123456, 0.6, 0.8, 0.0, 0.6, 0.8, 0.0), 123456)
      && U32.is_eq(Sky.halo(True{}, 123456, (0.0 - 0.6 : F32), (0.0 - 0.8 : F32), 0.0, 0.6, 0.8, 0.0), 123456)
      && U32.is_eq(Sky.halo(False{}, 123456, 0.6, 0.8, 0.0, 0.6, 0.8, 0.0), 123456), "the sun's halo brightens the sky at the sun and leaves it opposite as it was")
    Lib.expect(Lib.near(eye_sun([0 : U32^20n], 0), 1.0, 0.001)
      && F32.is_eq(eye_sun(Array.set(U32, [0 : U32^20n], World.col_at(0, 67, 66), U32.shln(1, 15n)), 0), 0.0),
      "the eye sees the whole sun in an open sky, and none of it behind a block on its line")
    Lib.expect(Lib.near(eye_sun([0 : U32^20n], (33554432 + 1073741824 : U32)), 0.35, 0.001)
      && F32.is_eq(eye_sun(Array.set(U32, [0 : U32^20n], World.col_at(0, 67, 66), U32.shln(1, 15n)), (33554432 + 1073741824 : U32)), 0.0)
      && F32.is_eq(eye_sun([0 : U32^20n], 33554432), 0.0),
      "at night the lens sees the moon, a third as bright as the sun, none of it behind a block on its line, and none with the moon off")
    Lib.expect(U32.is_eq(Lens.through(False{}, 123456, 1.0, 0.0, 0.0, 0.48, 0.8, 0.36, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.48, 0.8, 0.36), 123456)
      && U32.is_eq(Lens.through(True{}, 123456, 0.0, 0.0, 0.0, 0.48, 0.8, 0.36, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.48, 0.8, 0.36), 123456)
      && (Lens.through(True{}, 123456, 1.0, 0.0, 0.0, 0.48, 0.8, 0.36, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.48, 0.8, 0.36) > 123456 : U32),
      "the lens leaves a pixel as it was when off or when the sun is hidden, and brightens one towards a seen sun")
    Lib.expect(F32.is_eq(Shafts.lit(8n, 0, 50.0, 0, 0.0), 0.0) && Lib.near(Shafts.lit(8n, 4294967295, 50.0, 0, 0.0), Shafts.depth(50.0), 0.001)
      && (Shafts.lit(8n, 4294967295, 10.0, 0, 0.0) < Shafts.lit(8n, 4294967295, 50.0, 0, 0.0) : F32),
      "the shafts' light grows with the haze the eye looks through, and none shines where the sun reaches none of it")
    Lib.expect(U32.is_eq(Shafts.glowed(False{}, 123456, 4294967295, 50.0, 1.0, Day.morning(), 0.48, 0.8, 0.36, 0.48, 0.8, 0.36), 123456)
      && U32.is_eq(Shafts.glowed(True{}, 123456, 0, 50.0, 1.0, Day.morning(), 0.48, 0.8, 0.36, 0.48, 0.8, 0.36), 123456)
      && (Shafts.glowed(True{}, 123456, 4294967295, 50.0, 1.0, Day.morning(), 0.48, 0.8, 0.36, 0.48, 0.8, 0.36) > 123456 : U32),
      "the shafts leave a pixel as it was when off or when the haze before it is in the shade, and brighten it towards the sun")
    Lib.expect((Shafts.glowed(True{}, 123456, 4294967295, 50.0, 1.0, Day.morning(), (0.0 - 0.48 : F32), 0.8, (0.0 - 0.36 : F32), 0.48, (0.0 - 0.8 : F32), 0.36) > 123456 : U32)
      && Shafts.on(1073741824, 1073741824, (0.0 - 0.8 : F32)) && Bool.not(Shafts.on(0, 1073741824, (0.0 - 0.8 : F32))),
      "under the moon the haze glows towards it, and with the moon's look off the shafts are off at night")
    Lib.expect(U32.is_eq(shafts_in([0 : U32^20n]), 4294967295) && U32.is_eq(shafts_in([33554432 : U32^20n]), 4278190080),
      "the sun reaches every point of a ray's shafts in an open world, and none of the six within the window under a roof")
    Lib.expect(U32.is_ne(Sky.moon(True{}, 0, (0.0 - 1.0 : F32), 0.0, 1.0, 0.0, (0.0 - 1.0 : F32)), 0), "moon disc")
    Lib.expect(U32.is_eq(Sky.moon(False{}, 123, (0.0 - 1.0 : F32), 0.0, 1.0, 0.0, (0.0 - 1.0 : F32)), 123), "moon flag")
    Lib.expect(probe(69, 10, 64, 1.0, 0.0, 0.0), "shadow +x")
    Lib.expect(probe(59, 10, 64, (0.0 - 1.0 : F32), 0.0, 0.0), "shadow -x")
    Lib.expect(probe(64, 15, 64, 0.0, 1.0, 0.0), "shadow +y")
    Lib.expect(probe(64, 5, 64, 0.0, (0.0 - 1.0 : F32), 0.0), "shadow -y")
    Lib.expect(probe(64, 10, 69, 0.0, 0.0, 1.0), "shadow +z")
    Lib.expect(probe(64, 10, 59, 0.0, 0.0, (0.0 - 1.0 : F32)), "shadow -z")
    Lib.expect(Bool.not(probe(69, 10, 64, (0.0 - 1.0 : F32), 0.0, 0.0)), "block behind ray")
    Lib.expect(probe(59, 18, 60, (0.0 - 0.48 : F32), 0.8, (0.0 - 0.36 : F32)), "afternoon shadow")
    Lib.expect(U32.is_eq(Day.phase(clock(Player.advance(fixture(1048575), 2))), 1)
      && U32.is_eq(clock(Player.advance(fixture(1048575), 2)), 1048577), "the sun wraps to dawn and the clock counts the day")
    Lib.expect(U32.is_eq(clock(Player.advance(Player.advance(fixture(1234), 16), 17)),
                     clock(Player.advance(fixture(1234), 33))), "frame rate independent clock")
    Lib.expect(U32.is_eq(restored(Save.text(fixture(786432))), 786432), "save restores night")
    Lib.expect(U32.is_eq(restored(Save.text(fixture(3932160))), 3932160), "save keeps the days, the weather's")
