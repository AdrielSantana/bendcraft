import Base
import ./lib.bend as Lib
import ../src/water.bend as Water
import ../src/world.bend as World
import ../src/day.bend as Day

def near(a: F32, b: F32, epsilon: F32) -> Bool:
  (F32.abs((a - b : F32)) <= epsilon : F32)

def same(a: Water.Reflection, b: Water.Reflection, +epsilon: F32) -> Bool:
  Water.Reflection{ax, ay, az, ac} = a
  Water.Reflection{bx, by, bz, bc} = b
  near(ax, bx, epsilon) && near(ay, by, epsilon) && near(az, bz, epsilon) && near(ac, bc, epsilon)

def sample(base: U32, clock: U32, x: F32, z: F32) -> Water.Reflection:
  Water.reflected(True{}, Water.frame_base(base, clock), x, z, 6.0, 0.8, (0.0 - 0.6 : F32), 0.0)

# Exhaust the phase field while the address's bits are set. Also
# check that a saved day, and the highest U32 bits, cannot affect the phase.
def clocks(n: Nat, +i: U32) -> Bool:
  match n:
    case 0n: True{}
    case 1n+k:
      +b = Water.frame_base(16383, i)
      U32.is_eq(Water.clock(b), i) && U32.is_eq((b % 16384 : U32), 16383)
        && U32.is_eq(Water.clock(Water.frame_base(0, (i + 4294959104 : U32))), i)
        && U32.is_eq(Water.clock(Water.frame_base(0, Day.advance(i, Day.length()))), i)
        && clocks(k, (i + 1 : U32))

# Every ring address survives the highest phase, including a column
# offset which wraps through the end of the array.
def addresses(n: Nat, +i: U32) -> Bool:
  match n:
    case 0n: True{}
    case 1n+k:
      +b = Water.frame_base(i, 8191)
      U32.is_eq((World.col_at(b, 127, 127) % 262144 : U32), (World.col_at(i, 127, 127) % 262144 : U32))
        && U32.is_eq((b % 16384 : U32), i) && U32.is_eq(Water.clock(b), 8191)
        && addresses(k, (i + 1 : U32))

def unit(r: Water.Reflection) -> Bool:
  Water.Reflection{+x, +y, +z, +c} = r
  near((x * x + y * y + z * z : F32), 1.0, 0.00001)
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
      +b = Water.frame_base((16300 + i : U32), (i * 127 : U32))
      unit(Water.reflected(True{}, b, 63.375, 64.625, 0.0, (dx * 0.999999995 : F32), (0.0 - 0.0001 : F32), (dz * 0.999999995 : F32)))
        && unit(Water.reflected(True{}, b, 63.375, 64.625, 4.0, (dx * 0.8 : F32), (0.0 - 0.6 : F32), (dz * 0.8 : F32)))
        && unit(Water.reflected(True{}, b, 63.375, 64.625, 4.0, 0.0, (0.0 - 1.0 : F32), 0.0))
        && normals(k, (i + 1 : U32))

def main() -> IO(Unit):
  do IO<Unit>:
    Lib.expect(clocks(8192n, 0), "every ripple phase reads back beside ring and FPS bits")
    Lib.expect(addresses(16384n, 0), "packed time and FPS preserve every ring slot")
    Lib.expect(normals(64n, 0), "ripple normals keep reflected rays unit and above the horizon")
    Lib.expect(same(sample(16383, 1700, 65.375, 64.625), sample((16383 + 129 : U32), 1700, 64.375, 63.625), 0.00001)
      && same(sample(0, 1700, 65.375, 64.625), sample(4294967167, 1700, 66.375, 65.625), 0.00001),
      "ripples stay in world space through positive and negative ring shifts")
    Lib.expect(Bool.not(same(sample(0, 0, 64.375, 63.625), sample(0, 2048, 64.375, 63.625), 0.001)), "the game clock moves the normal")
    Lib.expect(same(sample(0, 8191, 64.375, 63.625), sample(0, 0, 64.375, 63.625), 0.0002)
      && same(sample(0, 100, 64.375, 63.625), sample(0, 8292, 64.375, 63.625), 0.0), "ripple wrap is continuous and a full period is identical")
    Lib.expect(same(Water.reflected(False{}, 4294967295, 64.375, 63.625, 0.0, 0.8, (0.0 - 0.6 : F32), 0.0),
      Water.Reflection{0.8, 0.6, 0.0, 0.6}, 0.0), "ripples off restores the exact flat reflection")
    Lib.expect(same(Water.reflected(True{}, 4294967295, 64.375, 63.625, 32.0, 0.8, (0.0 - 0.6 : F32), 0.0),
      Water.Reflection{0.8, 0.6, 0.0, 0.6}, 0.00001), "distant ripples fade before the fog horizon")
