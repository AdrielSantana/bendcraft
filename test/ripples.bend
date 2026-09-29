import Base
import ./lib.bend as Lib
import ../src/water.bend as Water
import ../src/world.bend as World
import ../src/day.bend as Day

def same(a: Water.Reflection, b: Water.Reflection, +epsilon: F32) -> Bool:
  Water.Reflection{ax, ay, az, ac} = a
  Water.Reflection{bx, by, bz, bc} = b
  Lib.near(ax, bx, epsilon) && Lib.near(ay, by, epsilon) && Lib.near(az, bz, epsilon) && Lib.near(ac, bc, epsilon)

def sample(base: U32, clock: U32, x: F32, z: F32) -> Water.Reflection:
  Water.reflected(True{}, base, clock, 0.0, x, z, 6.0, 0.8, (0.0 - 0.6 : F32), 0.0)

# a ray leaving the still surface up, from under it: the bent ray's x,
# the cosine of its angle out and the mirrored ray's y
def left(u: Water.Underside, +tx: F32, +out: F32, +ry: F32) -> Bool:
  Water.Underside{x, y, z, o, rx, rry, rz} = u
  Lib.near(x, tx, 0.0001) && Lib.near(o, out, 0.0001) && Lib.near(rry, ry, 0.0001)

def leaves(+dx: F32, +dy: F32, +tx: F32, +out: F32, +ry: F32) -> Bool:
  left(Water.refracted(False{}, 0, 0, 0.0, 64.375, 63.625, 0.0, dx, dy, 0.0), tx, out, ry)

# Every ring address survives the looks' bits, including a column offset
# which wraps through the end of the array.
def addresses(n: Nat, +i: U32) -> Bool:
  match n:
    case 0n: True{}
    case 1n+k:
      +b = Water.with_looks(i, 4294967295)
      U32.is_eq((World.col_at(b, 127, 127) % 262144 : U32), (World.col_at(i, 127, 127) % 262144 : U32))
        && U32.is_eq((b % 16384 : U32), i)
        && addresses(k, (i + 1 : U32))

def unit(r: Water.Reflection) -> Bool:
  Water.Reflection{+x, +y, +z, +c} = r
  Lib.near((x * x + y * y + z * z : F32), 1.0, 0.00001)
    && (y >= 0.0 : F32) && (c > 0.0 : F32) && (c <= 1.0 : F32)

# Look in every horizontal direction, head-on and close to grazing. A
# shaded top must keep a unit reflected ray above the water horizon.
def normals(n: Nat, +i: U32) -> Bool:
  match n:
    case 0n: True{}
    case 1n+k:
      +angle = (U32.to_f32(i) * 0.09817477 : F32)
      +dx = F32.sin(angle)
      +dz = F32.cos(angle)
      +b = (16300 + i : U32)
      +t = (i * 127 : U32)
      unit(Water.reflected(True{}, b, t, 0.0, 63.375, 64.625, 0.0, (dx * 0.999999995 : F32), (0.0 - 0.0001 : F32), (dz * 0.999999995 : F32)))
        && unit(Water.reflected(True{}, b, t, 0.0, 63.375, 64.625, 4.0, (dx * 0.8 : F32), (0.0 - 0.6 : F32), (dz * 0.8 : F32)))
        && unit(Water.reflected(True{}, b, t, 0.0, 63.375, 64.625, 4.0, 0.0, (0.0 - 1.0 : F32), 0.0))
        && normals(k, (i + 1 : U32))

def still(s: Water.Slope) -> Bool:
  Water.Slope{x, z} = s
  F32.is_eq(x, 0.0) && F32.is_eq(z, 0.0)

def alike(a: Water.Slope, b: Water.Slope) -> Bool:
  Water.Slope{ax, az} = a
  Water.Slope{bx, bz} = b
  Lib.near(ax, bx, 0.0001) && Lib.near(az, bz, 0.0001)

# n points along a slant of the lake at n clocks, in a rain r: how many
# ring, whether every point on the side of a half rings none, and whether
# each rings as the same point does in a window moved a column along both
# axes
def ringing(n: Nat, +i: U32, +r: F32, +count: U32, +edges: Bool, +moved: Bool) -> U32 & (Bool & Bool):
  match n:
    case 0n:
      (count, (edges, moved))
    case 1n+k:
      +x = (64.0 + U32.to_f32(i) * 0.0137 : F32)
      +z = (64.0 + U32.to_f32(i) * 0.0291 : F32)
      +t = (i * 37 : U32)
      ringing(k, (i + 1 : U32), r, (count + Bool.pick(U32, still(Water.rings(16383, t, r, x, z)), 0, 1) : U32),
        edges && still(Water.rings(16383, t, r, (64.0 + U32.to_f32((i % 30 : U32)) * 0.5 : F32), z)),
        moved && alike(Water.rings(16383, t, r, x, z), Water.rings((16383 + 129 : U32), t, r, (x - 1.0 : F32), (z - 1.0 : F32))))

def fst_of(q: U32 & (Bool & Bool)) -> U32:
  (count, rest) = q
  count

def rings_ok(q: U32 & (Bool & Bool)) -> Bool:
  (+count, rest) = q
  (edges, moved) = rest
  (count > 5 : U32) && (count < 256 : U32) && edges && moved

def main() -> IO(Unit):
  do IO<Unit>:
    Lib.expect(addresses(16384n, 0), "the looks' bits preserve every ring slot")
    Lib.expect(normals(64n, 0), "ripple normals keep reflected rays unit and above the horizon")
    Lib.expect(same(sample(16383, 1700, 65.375, 64.625), sample((16383 + 129 : U32), 1700, 64.375, 63.625), 0.00001)
      && same(sample(0, 1700, 65.375, 64.625), sample(4294967167, 1700, 66.375, 65.625), 0.00001),
      "ripples stay in world space through positive and negative ring shifts")
    Lib.expect(Bool.not(same(sample(0, 0, 64.375, 63.625), sample(0, 2048, 64.375, 63.625), 0.001)), "the game clock moves the normal")
    Lib.expect(same(sample(0, 8191, 64.375, 63.625), sample(0, 0, 64.375, 63.625), 0.0002)
      && same(sample(0, 100, 64.375, 63.625), sample(0, 8292, 64.375, 63.625), 0.0), "ripple wrap is continuous and a full period is identical")
    Lib.expect(same(Water.reflected(False{}, 4294967295, 8191, 0.0, 64.375, 63.625, 0.0, 0.8, (0.0 - 0.6 : F32), 0.0),
      Water.Reflection{0.8, 0.6, 0.0, 0.6}, 0.0), "ripples off restores the exact flat reflection")
    Lib.expect(same(Water.reflected(True{}, 4294967295, 8191, 0.0, 64.375, 63.625, 32.0, 0.8, (0.0 - 0.6 : F32), 0.0),
      Water.Reflection{0.8, 0.6, 0.0, 0.6}, 0.00001), "distant ripples fade before the fog horizon")
    Lib.expect(rings_ok(ringing(512n, 0, 1.0, 0, True{}, True{})) && U32.is_eq(fst_of(ringing(512n, 0, 0.0, 0, True{}, True{})), 0),
      "in the rain drops ring still water here and there, each ring inside its half of a block and fixed in the world, and none when dry")
    Lib.expect(leaves(0.0, 1.0, 0.0, 1.0, (0.0 - 1.0 : F32)) && leaves(0.5, 0.8660254, 0.665, 0.7468434, (0.0 - 0.8660254 : F32))
      && leaves(0.8, 0.6, 1.064, 0.0, (0.0 - 0.6 : F32)),
      "from under the water a ray straight up leaves straight, one 30 degrees off the normal leaves at 1.33 times its sine, and one 53 degrees off, past the critical angle, is mirrored down")
