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
import ../src/water.bend as Water

def blocked(r: Array<U32> & Bool) -> Bool:
  (w, got) = r
  got

# Each blocker is five cells away, beyond the initial cell and in range
# of the fixed shadow walk. Reversing the ray must leave it behind.
def probe(+x: U32, +y: U32, +z: U32, +dx: F32, +dy: F32, +dz: F32) -> Bool:
  w = Array.set(U32, [0 : U32^19n], World.col_at(0, x, z), U32.shln(1, U32.to_nat(y)))
  blocked(Render.shadow_fin(0, 64.5, 10.5, 64.5, dx, dy, dz, Render.run_glance(24n, w, 0, 64.5, 10.5, 64.5, dx, dy, dz)))

def clock(g: Player.Game) -> U32:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, sel, res, t, bag} = g
  t

def restored(r: Player.Game & String) -> U32:
  (g, text) = r
  clock(Save.parse(String.lines(text), Player.res512()))

def fixture(t: U32) -> Player.Game:
  Player.G{World.W{[0 : U32^19n], World.Meta{Map.new(&2, World.Col), 1048512, 1048512, Nil{}, 0, 0}},
    64.5, 30.0, 64.5, 0.0, 0.0, 0.0, 0, 0, 0, Player.res512(), t, Inventory.empty()}

# a ray from the eye at (64.5, 30, 64.5) of a window whose corner is 0
# mod 256, and the same ray from a window 10 columns further along x
def cloud_at(+fm: U32, +ox: F32, +dx: F32, +dy: F32, +dz: F32) -> U32:
  Clouds.over(True{}, fm, 154747, 12345, ox, 30.0, 64.5, dx, dy, dz, 0.48, 0.8, 0.36, 6789)

def fixed(+dx: F32, +dy: F32, +dz: F32) -> Bool:
  U32.is_eq(cloud_at(0, 64.5, dx, dy, dz), cloud_at(2560, 54.5, dx, dy, dz))

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

def shown(r: Array<U32> & U32) -> U32:
  (w, c) = r
  c

# a face of the colour 6789, a top of the ground or not, over the air cell
# (x, 20, 64.5) of a world whose every word is `word`, seen at a slant at
# the clock t
def wet_face(+t: U32, +puddly: Bool, +x: F32, +word: U32) -> U32:
  shown(Wet.soak((Wet.wetness(True{}, t) > 0.0 : F32), False{}, Wet.wetness(True{}, t), 0, 0, t, x, 20.0, 64.5, puddly, x, 64.5, 3.0,
    Water.Reflection{0.3, 0.5, 0.2, 0.5}, 12345, 0.0, Render.looks(), 0.48, 0.8, 0.36, ([word : U32^19n], 6789)))

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
        || U32.is_ne(cloud_at(0, 64.5, (0.0 - 0.5 : F32), 0.4, 0.7), 6789)),
      "a cloud stays over its column when the window moves under it")
    Lib.expect(U32.is_eq(Clouds.over(False{}, 0, 154747, 12345, 64.5, 30.0, 64.5, 0.3, 0.6, 0.2, 0.48, 0.8, 0.36, 6789), 6789)
      && U32.is_eq(Clouds.over(True{}, 0, 3145728, 12345, 64.5, 30.0, 64.5, 0.3, (0.0 - 0.4 : F32), 0.2, 0.48, 0.8, 0.36, 6789), 6789),
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
    Lib.expect(Bool.not(dry(rays(128n, 0, 0, 0, 64.5, 1203323, 100.0, 0, ([0 : U32^19n], 0))))
      && dry(rays(128n, 0, 0, 0, 64.5, 1203323, 100.0, 0, ([33554432 : U32^19n], 0)))
      && dry(rays(128n, 0, 0, 0, 64.5, 1203323, 0.75, 0, ([0 : U32^19n], 0))),
      "rain falls around an eye under a cloud and the open sky, none under a roof over every column, none before a wall at arm's length")
    Lib.expect(U32.is_eq(rays(128n, 0, 0, 0, 64.5, 1203323, 100.0, 0, ([0 : U32^19n], 0)), rays(128n, 0, 256, 128, 63.5, 1203323, 100.0, 0, ([0 : U32^19n], 0)))
      && U32.is_ne(rays(128n, 0, 0, 0, 64.5, 1203323, 100.0, 0, ([0 : U32^19n], 0)), rays(128n, 0, 0, 0, 64.87, 1203323, 100.0, 0, ([0 : U32^19n], 0))),
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
    Lib.expect(F32.is_eq(Clouds.cover(0, 1203323, gap(120n, 1203323, 0.5), 64.5, 0.0, 0.0), 0.0)
      && dry(rays(128n, 0, 0, 0, gap(120n, 1203323, 0.5), 1203323, 100.0, 0, ([0 : U32^19n], 0))),
      "on the same morning, an eye under a gap in the clouds stays dry")
    Lib.expect((Sky.gradient(True{}, 0.5, (0.0 - 1.0 : F32)) < Sky.gradient(True{}, 0.5, 1.0) : U32), "night sky is darker")
    Lib.expect(F32.is_eq(Sky.fog(0, 40.0, 5.0, 5.0), 0.0), "fog flags disable both terms")
    Lib.expect(F32.is_eq(Sky.fog(8, 120.0, 30.0, 30.0), 1.0), "distant terrain reaches sky colour")
    Lib.expect((Sky.fog(2147483648, 20.0, 5.0, 5.0) > Sky.fog(2147483648, 20.0, 30.0, 30.0) : F32), "mist is denser near the ground")
    Lib.expect(U32.is_ne(Sky.sun(True{}, 0, 1.0, 0.8, 0.8), 0), "sun disc")
    Lib.expect(U32.is_eq(Sky.sun(False{}, 123, 1.0, 0.8, 0.8), 123), "sun flag")
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
