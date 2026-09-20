import Base
import ./util.bend as Util

# THE WORLD: endless, seeded, and one array of it shared by every pixel.
#
# `Array` in Bend is a `Type`: one owner. Since Bend 2.0.22 an `@unsafe` def
# may hand one array to both sides of a fork anyway (two handles to one
# block, `Array.join` gives it back), so the columns around the player live
# in an `Array<U32>`, each a word whose bit y says "there is a block at
# height y". Every ray reads it through its handle, an edit is one
# `Array.set` on the host, and a built world costs what an untouched one
# does. 32 heights in one word is what makes this cheap: a column is a
# single machine word, and break/place is one bit.

# The terrain's noise. Its hash mixes its bits: a product is a ramp along
# each axis at any distance (the texture's hash, in render.bend, is a
# product, fine at the eight tile coordinates).
def seed() -> U32: 7

def hmix(+i: U32, +j: U32) -> F32:
  +h = (i * 374761393 + j * 668265263 + seed() * 2246822519 : U32)
  +g = (U32.xor(h, (h / 8192 : U32)) * 1274126177 : U32)
  (Util.u2f((U32.xor(g, (g / 65536 : U32)) % 256 : U32)) / 255.0 : F32)

def tnoise(+u: F32, +v: F32) -> F32:
  +i = Util.f2u(u)
  +j = Util.f2u(v)
  +fu = Util.smooth((u - Util.u2f(i) : F32))
  +fv = Util.smooth((v - Util.u2f(j) : F32))
  +a = hmix(i, j)
  +b = hmix((i + 1 : U32), j)
  +c = hmix(i, (j + 1 : U32))
  +d = hmix((i + 1 : U32), (j + 1 : U32))
  ((a * (1.0 - fu) + b * fu) * (1.0 - fv) + (c * (1.0 - fu) + d * fu) * fv : F32)

# ---------- the world ----------

# A seeded noise says the terrain of any column; a Map keeps the columns
# the player edited (key "x,z"); a ring of 128 x 128 columns holds the ones
# around the player. Everything the renderer and the physics see is local
# to the ring's corner (ox, oz), which follows the player one column at a
# time, loading the row that came into view. World column (x, z) sits at
# slot x * 128 + z, and Array.get wraps the index, so the loaded window is
# one-to-one with the slots and local column (lx, lz) is at
# base + lx * 128 + lz, base = ox * 128 + oz: the one word a reader carries.

def col_at(+base: U32, +x: U32, +z: U32) -> U32:
  (base + x * 128 + z : U32)

# hills, three octaves of the noise
def terrain(+x: U32, +z: U32) -> U32:
  +fx = Util.u2f(x)
  +fz = Util.u2f(z)
  +n = (0.55 * tnoise((fx * 0.031 : F32), (fz * 0.031 : F32))
        + 0.3 * tnoise((fx * 0.09 + 17.0 : F32), (fz * 0.09 + 5.0 : F32))
        + 0.15 * tnoise((fx * 0.23 + 3.0 : F32), (fz * 0.23 + 11.0 : F32)) : F32)
  F32.to_u32(F32.clamp((3.0 + 24.0 * n : F32), 2.0, 27.0))

# a column: every level below the surface is solid
def column(+x: U32, +z: U32) -> U32:
  (U32.shln(1, U32.to_nat(terrain(x, z))) - 1 : U32)

type World is Type:
  W{ring: Array<U32>, edits: Map<&2, U32>, ox: U32, oz: U32}

def key(+x: U32, +z: U32) -> String:
  U32.show(x) ++ "," ++ U32.show(z)

# a column comes back from the edits if the player ever touched it, else
# from the terrain
def load_put(ring: Array<U32>, +ox: U32, +oz: U32, +slot: U32, r: Map<&2, U32> & U32) -> World:
  (m, bits) = r
  W{Array.set(U32, ring, slot, bits), m, ox, oz}

def load_had(had: Bool, ring: Array<U32>, m: Map<&2, U32>, +ox: U32, +oz: U32, +x: U32, +z: U32) -> World:
  match had:
    case True{}:
      load_put(ring, ox, oz, (x * 128 + z : U32), Map.get(U32, 0, m, key(x, z)))
    case False{}:
      W{Array.set(U32, ring, (x * 128 + z : U32), column(x, z)), m, ox, oz}

def load_go(ring: Array<U32>, +ox: U32, +oz: U32, +x: U32, +z: U32, r: Map<&2, U32> & Bool) -> World:
  (m, had) = r
  load_had(had, ring, m, ox, oz, x, z)

def load(w: World, +x: U32, +z: U32) -> World:
  W{ring, m, ox, oz} = w
  load_go(ring, ox, oz, x, z, Map.has(&2, U32, m, key(x, z)))

# n columns from (x, z), along z or along x; a whole window
def load_z(n: Nat, w: World, +x: U32, +z: U32) -> World:
  match n:
    case 0n:
      w
    case 1n+k:
      load_z(k, load(w, x, z), x, (z + 1 : U32))

def load_x(n: Nat, w: World, +x: U32, +z: U32) -> World:
  match n:
    case 0n:
      w
    case 1n+k:
      load_x(k, load(w, x, z), (x + 1 : U32), z)

def load_all(n: Nat, w: World, +x: U32, +z: U32) -> World:
  match n:
    case 0n:
      w
    case 1n+k:
      load_all(k, load_z(128n, w, x, z), (x + 1 : U32), z)

# the corner moves one column and the row that came into view loads
def shift_xp(w: World) -> World:
  W{ring, m, +ox, +oz} = w
  load_z(128n, W{ring, m, (ox + 1 : U32), oz}, (ox + 128 : U32), oz)

def shift_xn(w: World) -> World:
  W{ring, m, +ox, +oz} = w
  load_z(128n, W{ring, m, (ox - 1 : U32), oz}, (ox - 1 : U32), oz)

def shift_zp(w: World) -> World:
  W{ring, m, +ox, +oz} = w
  load_x(128n, W{ring, m, ox, (oz + 1 : U32)}, ox, (oz + 128 : U32))

def shift_zn(w: World) -> World:
  W{ring, m, +ox, +oz} = w
  load_x(128n, W{ring, m, ox, (oz - 1 : U32)}, ox, (oz - 1 : U32))

def shift_x(pos: Bool, w: World) -> World:
  match pos:
    case True{}:
      shift_xp(w)
    case False{}:
      shift_xn(w)

def shift_z(pos: Bool, w: World) -> World:
  match pos:
    case True{}:
      shift_zp(w)
    case False{}:
      shift_zn(w)

# the player keeps local column 64: n columns past it, n shifts
def follow_x(n: Nat, +pos: Bool, w: World) -> World:
  match n:
    case 0n:
      w
    case 1n+k:
      follow_x(k, pos, shift_x(pos, w))

def follow_z(n: Nat, +pos: Bool, w: World) -> World:
  match n:
    case 0n:
      w
    case 1n+k:
      follow_z(k, pos, shift_z(pos, w))

def setbit(+b: U32, +ybit: U32, set: Bool) -> U32:
  Bool.pick(U32, set, (b .|. ybit : U32), (b .&. U32.not(ybit) : U32))

# an edit: the bit flips in the ring's word, and the column is remembered
def edit_put(m: Map<&2, U32>, +ox: U32, +oz: U32, +x: U32, +z: U32, +ybit: U32, set: Bool,
             r: Array<U32> & U32) -> World:
  (ring, b) = r
  +bits = setbit(b, ybit, set)
  W{Array.set(U32, ring, (x * 128 + z : U32), bits), Map.set(&2, U32, m, key(x, z), bits), ox, oz}

def edit(w: World, +lx: U32, +lz: U32, +ybit: U32, set: Bool) -> World:
  W{ring, m, +ox, +oz} = w
  +x = (ox + lx : U32)
  +z = (oz + lz : U32)
  edit_put(m, ox, oz, x, z, ybit, set, Array.get(U32, ring, (x * 128 + z : U32)))

def inside(+vx: F32, +vy: F32, +vz: F32) -> Bool:
  (vx > (0.0 - 0.5) : F32) && (vx < 127.5 : F32) &&
  (vz > (0.0 - 0.5) : F32) && (vz < 127.5 : F32) &&
  (vy > (0.0 - 0.5) : F32) && (vy < 31.5 : F32)

def solid_bit(+ybit: U32, r: Array<U32> & U32) -> Array<U32> & Bool:
  (w, b) = r
  (w, Util.on(b, ybit))

def solid_at(ok: Bool, w: Array<U32>, +base: U32, +x: U32, +z: U32, +ybit: U32) -> Array<U32> & Bool:
  match ok:
    case False{}:
      (w, False{})
    case True{}:
      solid_bit(ybit, Array.get(U32, w, col_at(base, x, z)))

def solid(w: Array<U32>, +base: U32, +vx: F32, +vy: F32, +vz: F32) -> Array<U32> & Bool:
  solid_at(inside(vx, vy, vz), w, base, Util.f2u(vx), Util.f2u(vz), U32.shln(1, F32.to_nat(F32.max(vy, 0.0))))

# the same, on the world
def wsolid_fin(m: Map<&2, U32>, ox: U32, oz: U32, r: Array<U32> & Bool) -> World & Bool:
  (ring, s) = r
  (W{ring, m, ox, oz}, s)

def wsolid(w: World, +x: F32, +y: F32, +z: F32) -> World & Bool:
  W{ring, m, +ox, +oz} = w
  wsolid_fin(m, ox, oz, solid(ring, (ox * 128 + oz : U32), x, y, z))
