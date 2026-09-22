import Base
import ./util.bend as Util

# THE WORLD: endless, seeded, and one array of it shared by every pixel.
#
# `Array` in Bend is a `Type`: one owner. Since Bend 2.0.22 an `@unsafe` def
# may hand one array to both sides of a fork anyway (two handles to one
# block, `Array.join` gives it back), so the columns around the player live
# in an `Array<U32>`: sixteen words a column, the first a mask whose bit
# y says "there is a solid at height y", the next four the types of the
# 32 blocks, four bits each, then a non-solid water mask at slot + 5, and
# at slots 6..9 the amount of water in each cell, 0 to 8 units in a
# nibble (10..15 are spare). Every primary ray with water enabled reads
# both masks through its handle, once per column it crosses, the type
# once, at the hit, and the amount once, where it first enters water; an
# edit is a few `Array.set` on the host; a built world costs what an
# untouched one does. 32 heights in one word is what makes this cheap:
# the ray reads a column as a machine word, and break/place is one bit.

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
# slot (x * 128 + z) * 16, and Array.get wraps the index, so the loaded
# window is one-to-one with the slots and local column (lx, lz) is at
# (base + lx * 128 + lz) * 16, base = ox * 128 + oz: the one word a reader
# carries. Slot + 0 is the mask, + 1 + y / 8 the word with the type of
# height y, in its nibble y % 8. Slot + 5 holds water occupancy, and
# + 6 + y / 8 the amount of water at height y, in its nibble.

def col_at(+base: U32, +x: U32, +z: U32) -> U32:
  ((base + x * 128 + z) * 16 : U32)

# the block types: 0 grass, 1 dirt, 2 stone, 3 sand, 4 wood, 5 leaves,
# 6 brick, 7 snow; 8 is water, held in a separate non-solid mask
def nib_set(+word: U32, +y: U32, +what: U32) -> U32:
  +sh = U32.shln(1, U32.to_nat((y % 8 * 4 : U32)))
  ((word .&. U32.not((sh * 15 : U32))) .|. (sh * what : U32) : U32)

def nib_get(+word: U32, +y: U32) -> U32:
  (word / U32.shln(1, U32.to_nat((y % 8 * 4 : U32))) % 16 : U32)

# the same read for the device, which never shifts by a variable: 16^i as
# a select
def pow16(+i: U32) -> U32:
  Bool.pick(U32, (i < 4 : U32),
    Bool.pick(U32, (i < 2 : U32), Bool.pick(U32, U32.is_eq(i, 0), 1, 16), Bool.pick(U32, U32.is_eq(i, 2), 256, 4096)),
    Bool.pick(U32, (i < 6 : U32), Bool.pick(U32, U32.is_eq(i, 4), 65536, 1048576), Bool.pick(U32, U32.is_eq(i, 6), 16777216, 268435456)))

def nib_at(+word: U32, +y: U32) -> U32:
  (word / pow16((y % 8 : U32)) % 16 : U32)

# hills, three octaves of the noise
def terrain(+x: U32, +z: U32) -> U32:
  +fx = Util.u2f(x)
  +fz = Util.u2f(z)
  +n = (0.55 * tnoise((fx * 0.031 : F32), (fz * 0.031 : F32))
        + 0.3 * tnoise((fx * 0.09 + 17.0 : F32), (fz * 0.09 + 5.0 : F32))
        + 0.15 * tnoise((fx * 0.23 + 3.0 : F32), (fz * 0.23 + 11.0 : F32)) : F32)
  F32.to_u32(F32.clamp((3.0 + 24.0 * n : F32), 2.0, 27.0))

# Water's surface also sets where grass and trees can grow.
def sea() -> U32: 12

# The top is sand when low, dirt under water, grass on dry ground and
# snow when high; three of dirt under it, stone below.
def tnib(+y: U32, +h: U32) -> U32:
  +cap = Bool.pick(U32, (h <= 6 : U32), 3,
    Bool.pick(U32, (h < sea() : U32), 1, Bool.pick(U32, (h >= 25 : U32), 7, 0)))
  Bool.pick(U32, U32.is_eq((y + 1 : U32), h), cap, Bool.pick(U32, ((y + 4 : U32) >= h : U32), 1, 2))

def tree_ground(+h: U32) -> Bool:
  (h >= sea() : U32) && (h >= 7 : U32) && (h <= 24 : U32)

# Trees. A dry column of grass grows one when its hash
# says so, about one in eighty: a trunk of four wood on the top, two of
# leaves above it, and a canopy on the columns around: three layers one
# column out, two layers two columns out, none on the far corners. A
# column takes its wood and leaf bits from the trees of the 25 columns
# around it, so a canopy crosses columns without anyone writing across.
def tree_at(+x: U32, +z: U32) -> Bool:
  +h = (x * 2654435761 + z * 2246822519 + seed() * 3266489917 : U32)
  +g = (U32.xor(h, (h / 65536 : U32)) * 2654435761 : U32)
  U32.is_eq((U32.xor(g, (g / 8192 : U32)) % 80 : U32), 0)

type Masks is Data:
  Masks{wood: U32, leaf: U32}

# the tree at (tx, tz), d columns away: its bits in this column
def tree_bits(grows: Bool, +d: U32, +corner: Bool, +th: U32, m: Masks) -> Masks:
  match grows:
    case False{}:
      m
    case True{}:
      Masks{+wood, +leaf} = m
      +low = U32.shln(1, U32.to_nat(th))
      Masks{Bool.pick(U32, U32.is_eq(d, 0), (wood .|. (low * 15 : U32) : U32), wood),
            (leaf .|. Bool.pick(U32, U32.is_eq(d, 0), (low * 48 : U32),
                       Bool.pick(U32, U32.is_eq(d, 1), (low * 28 : U32),
                       Bool.pick(U32, corner, 0, (low * 12 : U32)))) : U32)}

def tree_here(+tx: U32, +tz: U32, +d: U32, +corner: Bool, m: Masks) -> Masks:
  +th = terrain(tx, tz)
  tree_bits(tree_at(tx, tz) && tree_ground(th), d, corner, th, m)

def canopy(n: Nat, +x: U32, +z: U32, +i: U32, m: Masks) -> Masks:
  match n:
    case 0n:
      m
    case 1n+k:
      +dx = (i / 5 : U32)
      +dz = (i % 5 : U32)
      +ax = Bool.pick(U32, (dx > 2 : U32), (dx - 2 : U32), (2 - dx : U32))
      +az = Bool.pick(U32, (dz > 2 : U32), (dz - 2 : U32), (2 - dz : U32))
      canopy(k, x, z, (i + 1 : U32),
             tree_here((x + dx - 2 : U32), (z + dz - 2 : U32), U32.max(ax, az), U32.is_eq(ax, 2) && U32.is_eq(az, 2), m))

# the type at height y: wood or leaves where a tree is, the terrain's else
def tnib2(+y: U32, +ybit: U32, +h: U32, +wood: U32, +leaf: U32) -> U32:
  Bool.pick(U32, Util.on(wood, ybit), 4, Bool.pick(U32, Util.on(leaf, ybit), 5, tnib(y, h)))

# the word of eight nibbles from height y down, so height y - 7 lands in
# the low nibble
def tword(n: Nat, +y: U32, +ybit: U32, +h: U32, +wood: U32, +leaf: U32, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+k:
      tword(k, (y - 1 : U32), U32.shr(ybit), h, wood, leaf, (acc * 16 + tnib2(y, ybit, h, wood, leaf) : U32))

def types_word(+k: U32, +h: U32, +wood: U32, +leaf: U32) -> U32:
  tword(8n, (k * 8 + 7 : U32), U32.shln(128, U32.to_nat((k * 8 : U32))), h, wood, leaf, 0)

# Water fills low terrain to y=12. Keeping its mask separate lets physics,
# picking, shadows and occlusion read exactly the same solid word as before.
def flood(+h: U32, +solid: U32) -> U32:
  ((U32.shln(1, U32.to_nat(sea())) - 1) .&. U32.not(((U32.shln(1, U32.to_nat(h)) - 1) .|. solid : U32)) : U32)

# The amount of water in each cell, 0 to 8 units in a nibble: the water
# mask's bit y is set exactly when the amount at y is over zero, so the
# ray keeps walking the mask. A column is born full wherever its mask has
# a bit, as is one from a save that predates the amounts.
type Levels is Data:
  Levels{a: U32, b: U32, c: U32, d: U32}

# the eight nibbles of an octet, 8 under each of its mask bits
def full_word(n: Nat, +bits: U32, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+k:
      full_word(k, (bits * 2 : U32), (acc * 16 + Bool.pick(U32, Util.on(bits, 128), 8, 0) : U32))

def full_levels(+water: U32) -> Levels:
  Levels{full_word(8n, (water % 256 : U32), 0), full_word(8n, (water / 256 % 256 : U32), 0),
         full_word(8n, (water / 65536 % 256 : U32), 0), full_word(8n, (water / 16777216 : U32), 0)}

def level_word(+lv: Levels, +k: U32) -> U32:
  Levels{a, b, c, d} = lv
  Bool.pick(U32, (k < 2 : U32), Bool.pick(U32, U32.is_eq(k, 0), a, b), Bool.pick(U32, U32.is_eq(k, 2), c, d))

def amount(+lv: Levels, +y: U32) -> U32:
  nib_get(level_word(lv, (y / 8 : U32)), y)

type Col is Data:
  Col{mask: U32, t0: U32, t1: U32, t2: U32, t3: U32, water: U32, lv: Levels}

# a column from its six words, full wherever there is water
def col6(m: U32, a: U32, b: U32, c: U32, d: U32, +water: U32) -> Col:
  Col{m, a, b, c, d, water, full_levels(water)}

def masks(c: Col) -> U32 & U32:
  Col{m, a, b, cc, d, water, lv} = c
  (m, water)

def levels(c: Col) -> Levels:
  Col{m, a, b, cc, d, water, lv} = c
  lv

def column_fin(+h: U32, m: Masks) -> Col:
  Masks{+wood, +leaf} = m
  +solid = ((U32.shln(1, U32.to_nat(h)) - 1) .|. wood .|. leaf : U32)
  col6(solid,
       types_word(0, h, wood, leaf), types_word(1, h, wood, leaf), types_word(2, h, wood, leaf), types_word(3, h, wood, leaf), flood(h, solid))

def column(+x: U32, +z: U32) -> Col:
  column_fin(terrain(x, z), canopy(25n, x, z, 0, Masks{0, 0}))

def put_levels(ring: Array<U32>, +slot: U32, lv: Levels) -> Array<U32>:
  Levels{+la, +lb, +lc, +ld} = lv
  Array.set(U32, Array.set(U32, Array.set(U32, Array.set(U32, ring, (slot + 6 : U32), la),
    (slot + 7 : U32), lb), (slot + 8 : U32), lc), (slot + 9 : U32), ld)

def put_col(ring: Array<U32>, +slot: U32, c: Col) -> Array<U32>:
  Col{+m, +a, +b, +cc, +d, +water, lv} = c
  put_levels(Array.set(U32, Array.set(U32, Array.set(U32, Array.set(U32, Array.set(U32, Array.set(U32, ring, slot, m),
    (slot + 1 : U32), a), (slot + 2 : U32), b), (slot + 3 : U32), cc), (slot + 4 : U32), d), (slot + 5 : U32), water), slot, lv)

def get9(m: U32, a: U32, b: U32, c: U32, d: U32, water: U32, la: U32, lb: U32, lc: U32, r: Array<U32> & U32) -> Array<U32> & Col:
  (ring, ld) = r
  (ring, Col{m, a, b, c, d, water, Levels{la, lb, lc, ld}})

def get8(+slot: U32, m: U32, a: U32, b: U32, c: U32, d: U32, water: U32, la: U32, lb: U32, r: Array<U32> & U32) -> Array<U32> & Col:
  (ring, lc) = r
  get9(m, a, b, c, d, water, la, lb, lc, Array.get(U32, ring, (slot + 9 : U32)))

def get7(+slot: U32, m: U32, a: U32, b: U32, c: U32, d: U32, water: U32, la: U32, r: Array<U32> & U32) -> Array<U32> & Col:
  (ring, lb) = r
  get8(slot, m, a, b, c, d, water, la, lb, Array.get(U32, ring, (slot + 8 : U32)))

def get6(+slot: U32, m: U32, a: U32, b: U32, c: U32, d: U32, water: U32, r: Array<U32> & U32) -> Array<U32> & Col:
  (ring, la) = r
  get7(slot, m, a, b, c, d, water, la, Array.get(U32, ring, (slot + 7 : U32)))

def get5(+slot: U32, m: U32, a: U32, b: U32, c: U32, d: U32, r: Array<U32> & U32) -> Array<U32> & Col:
  (ring, water) = r
  get6(slot, m, a, b, c, d, water, Array.get(U32, ring, (slot + 6 : U32)))

def get4(+slot: U32, m: U32, a: U32, b: U32, c: U32, r: Array<U32> & U32) -> Array<U32> & Col:
  (ring, d) = r
  get5(slot, m, a, b, c, d, Array.get(U32, ring, (slot + 5 : U32)))

def get3(+slot: U32, +m: U32, +a: U32, +b: U32, r: Array<U32> & U32) -> Array<U32> & Col:
  (ring, c) = r
  get4(slot, m, a, b, c, Array.get(U32, ring, (slot + 4 : U32)))

def get2(+slot: U32, +m: U32, +a: U32, r: Array<U32> & U32) -> Array<U32> & Col:
  (ring, b) = r
  get3(slot, m, a, b, Array.get(U32, ring, (slot + 3 : U32)))

def get1(+slot: U32, +m: U32, r: Array<U32> & U32) -> Array<U32> & Col:
  (ring, a) = r
  get2(slot, m, a, Array.get(U32, ring, (slot + 2 : U32)))

def get0(+slot: U32, r: Array<U32> & U32) -> Array<U32> & Col:
  (ring, m) = r
  get1(slot, m, Array.get(U32, ring, (slot + 1 : U32)))

def get_col(ring: Array<U32>, +slot: U32) -> Array<U32> & Col:
  get0(slot, Array.get(U32, ring, slot))

type World is Type:
  W{ring: Array<U32>, edits: Map<&2, Col>, ox: U32, oz: U32}

def key(+x: U32, +z: U32) -> String:
  U32.show(x) ++ "," ++ U32.show(z)

# a column comes back from the edits if the player ever touched it, else
# from the terrain
def load_put(ring: Array<U32>, +ox: U32, +oz: U32, +slot: U32, r: Map<&2, Col> & Col) -> World:
  (m, c) = r
  W{put_col(ring, slot, c), m, ox, oz}

def load_had(had: Bool, ring: Array<U32>, m: Map<&2, Col>, +ox: U32, +oz: U32, +x: U32, +z: U32) -> World:
  match had:
    case True{}:
      load_put(ring, ox, oz, ((x * 128 + z) * 16 : U32), Map.get(Col, col6(0, 0, 0, 0, 0, 0), m, key(x, z)))
    case False{}:
      W{put_col(ring, ((x * 128 + z) * 16 : U32), column(x, z)), m, ox, oz}

def load_go(ring: Array<U32>, +ox: U32, +oz: U32, +x: U32, +z: U32, r: Map<&2, Col> & Bool) -> World:
  (m, had) = r
  load_had(had, ring, m, ox, oz, x, z)

def load(w: World, +x: U32, +z: U32) -> World:
  W{ring, m, ox, oz} = w
  load_go(ring, ox, oz, x, z, Map.has(&2, Col, m, key(x, z)))

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

# an edit: the height's bit in the mask, its type in the nibble, and the
# column is remembered; water placed is a full cell, and a cell that
# stops being water holds no amount
def edit_levels(+lv: Levels, +y: U32, +k: U32, +amt: U32) -> Levels:
  Levels{+la, +lb, +lc, +ld} = lv
  Levels{Bool.pick(U32, U32.is_eq(k, 0), nib_set(la, y, amt), la),
         Bool.pick(U32, U32.is_eq(k, 1), nib_set(lb, y, amt), lb),
         Bool.pick(U32, U32.is_eq(k, 2), nib_set(lc, y, amt), lc),
         Bool.pick(U32, U32.is_eq(k, 3), nib_set(ld, y, amt), ld)}

def edit_col(c: Col, +y: U32, +set: Bool, +what: U32) -> Col:
  Col{+m, +a, +b, +cc, +d, +water, +lv} = c
  +k = (y / 8 : U32)
  +bit = U32.shln(1, U32.to_nat(y))
  +wet = U32.is_eq(what, 8)
  +blocked = set && wet && Util.on(m, bit)
  +poured = set && wet && Bool.not(blocked)
  # Water cannot erase a bank; a solid placement can displace water.
  Col{Bool.pick(U32, blocked, m, setbit(m, bit, set && Bool.not(wet))),
      Bool.pick(U32, Bool.not(blocked) && U32.is_eq(k, 0), nib_set(a, y, what), a),
      Bool.pick(U32, Bool.not(blocked) && U32.is_eq(k, 1), nib_set(b, y, what), b),
      Bool.pick(U32, Bool.not(blocked) && U32.is_eq(k, 2), nib_set(cc, y, what), cc),
      Bool.pick(U32, Bool.not(blocked) && U32.is_eq(k, 3), nib_set(d, y, what), d),
      setbit(water, bit, poured),
      Bool.pick(Levels, blocked, lv, edit_levels(lv, y, k, Bool.pick(U32, poured, 8, 0)))}

def edit_fin(m: Map<&2, Col>, +ox: U32, +oz: U32, +x: U32, +z: U32, +y: U32, set: Bool, +what: U32,
             r: Array<U32> & Col) -> World:
  (ring, c) = r
  +nc = edit_col(c, y, set, what)
  W{put_col(ring, ((x * 128 + z) * 16 : U32), nc), Map.set(&2, Col, m, key(x, z), nc), ox, oz}

def edit(w: World, +lx: U32, +lz: U32, +y: U32, set: Bool, +what: U32) -> World:
  W{ring, m, +ox, +oz} = w
  +x = (ox + lx : U32)
  +z = (oz + lz : U32)
  edit_fin(m, ox, oz, x, z, y, set, what, get_col(ring, ((x * 128 + z) * 16 : U32)))

# The amount at a cell, set, the mask's bit following it (set exactly
# when the amount is over zero); a solid cell holds none, and 8 is the
# most a cell holds. The flow's one write.
def pour_col(c: Col, +y: U32, +a: U32) -> Col:
  Col{+m, ta, tb, tc, td, +water, +lv} = c
  +bit = U32.shln(1, U32.to_nat(y))
  +amt = Bool.pick(U32, Util.on(m, bit), 0, U32.min(a, 8))
  Col{m, ta, tb, tc, td, setbit(water, bit, (amt > 0 : U32)), edit_levels(lv, y, (y / 8 : U32), amt)}

def pour_fin(m: Map<&2, Col>, +ox: U32, +oz: U32, +x: U32, +z: U32, +y: U32, +a: U32, r: Array<U32> & Col) -> World:
  (ring, c) = r
  +nc = pour_col(c, y, a)
  W{put_col(ring, ((x * 128 + z) * 16 : U32), nc), Map.set(&2, Col, m, key(x, z), nc), ox, oz}

def pour(w: World, +lx: U32, +y: U32, +lz: U32, +a: U32) -> World:
  W{ring, m, +ox, +oz} = w
  +x = (ox + lx : U32)
  +z = (oz + lz : U32)
  pour_fin(m, ox, oz, x, z, y, a, get_col(ring, ((x * 128 + z) * 16 : U32)))

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
def wsolid_fin(m: Map<&2, Col>, ox: U32, oz: U32, r: Array<U32> & Bool) -> World & Bool:
  (ring, s) = r
  (W{ring, m, ox, oz}, s)

def wsolid(w: World, +x: F32, +y: F32, +z: F32) -> World & Bool:
  W{ring, m, +ox, +oz} = w
  wsolid_fin(m, ox, oz, solid(ring, (ox * 128 + oz : U32), x, y, z))

# the type of the block at a local cell (for the tests and the tools):
# 8 where the water mask has the bit, the type's nibble where the solid
# mask has it, 0 (air) where neither, whatever the nibble holds from
# before
def voxel_fin(m: Map<&2, Col>, ox: U32, oz: U32, +y: U32, +solid: U32, water: U32, r: Array<U32> & U32) -> World & U32:
  (ring, word) = r
  +bit = U32.shln(1, U32.to_nat(y))
  (W{ring, m, ox, oz}, Bool.pick(U32, Util.on(water, bit), 8, Bool.pick(U32, Util.on(solid, bit), nib_get(word, y), 0)))

def voxel_water(m: Map<&2, Col>, ox: U32, oz: U32, +y: U32, +slot: U32, +solid: U32, r: Array<U32> & U32) -> World & U32:
  (ring, water) = r
  voxel_fin(m, ox, oz, y, solid, water, Array.get(U32, ring, (slot + 1 + y / 8 : U32)))

def voxel_solid(m: Map<&2, Col>, ox: U32, oz: U32, +y: U32, +slot: U32, r: Array<U32> & U32) -> World & U32:
  (ring, solid) = r
  voxel_water(m, ox, oz, y, slot, solid, Array.get(U32, ring, (slot + 5 : U32)))

def voxel(w: World, +lx: U32, +y: U32, +lz: U32) -> World & U32:
  W{ring, m, +ox, +oz} = w
  +slot = col_at((ox * 128 + oz : U32), lx, lz)
  voxel_solid(m, ox, oz, y, slot, Array.get(U32, ring, slot))

# the amount of water at a local cell, 0 to 8 (for the tests and the flow)
def amount_fin(m: Map<&2, Col>, ox: U32, oz: U32, +y: U32, r: Array<U32> & U32) -> World & U32:
  (ring, word) = r
  (W{ring, m, ox, oz}, nib_get(word, y))

def amount_at(w: World, +lx: U32, +y: U32, +lz: U32) -> World & U32:
  W{ring, m, +ox, +oz} = w
  amount_fin(m, ox, oz, y, Array.get(U32, ring, (col_at((ox * 128 + oz : U32), lx, lz) + 6 + y / 8 : U32)))
