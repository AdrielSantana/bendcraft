import Base

# An interactive voxel world: walk, jump, break blocks, place blocks.
#
# THE WORLD IS ENDLESS, AND ONE ARRAY OF IT IS SHARED BY EVERY PIXEL.
#
# `Array` in Bend is a `Type`: one owner. Since Bend 2.0.22 an `@unsafe` def
# may hand one array to both sides of a fork anyway (two handles to one
# block, `Array.join` gives it back), so the columns around the player live
# in an `Array<U32>`, each a word whose bit y says "there is a block at
# height y". Every ray reads it through its handle, an edit is one
# `Array.set` on the host, and a built world costs what an untouched one
# does. Before 2.0.22 the world was a quadtree of edits over the terrain
# function, read by a borrowed walk (bendlang/bend#885).
#
# 32 heights in one word is what makes this cheap: a column is a single
# machine word, and break/place is one bit.
#
#   W A S D  move   space  jump   arrows  look   Esc  quit
#   mouse: drag to look, left click breaks, right click places (or J / L)

# ---------- little helpers ----------

# RESOLUTION lives here and nowhere else. The render is RES x RES pixels,
# built by `fork!(k)` over 4x4 leaves, so RES = 4 << k: k=6 -> 256, k=7 -> 512.
# The fork shape is the lane cube's: a `!` runs 16384 lanes, so 4^7 leaves per
# bang keep them all busy (`bend guide shaders`). Two things must agree: the
# `k` in `fork!` below and `halfu()` here.
def halfu() -> U32: 256
def half() -> F32: U32.to_f32(halfu())

def rgb(r: U32, g: U32, b: U32) -> U32:
  (r * 65536 + g * 256 + b : U32)

def floorf(+x: F32) -> F32:
  U32.to_f32(F32.to_u32(x))

def absf(+x: F32) -> F32:
  F32.max(x, (0.0 - x : F32))

def f2u(+x: F32) -> U32:
  F32.to_u32(F32.max(x, 0.0))

def u2f(+x: U32) -> F32:
  U32.to_f32(x)

def on(+mask: U32, +bit: U32) -> Bool:
  ((mask .&. bit) > 0 : U32)

def fracf(+x: F32) -> F32:
  (x - floorf(x) : F32)

# value noise: a hash on a lattice, blended smoothly. The texture's hash
# is a product, fine at the eight tile coordinates; the terrain's mixes
# its bits, since a product is a ramp along each axis at any distance.
def h01(+i: U32, +j: U32) -> F32:
  (u2f((U32.xor((i * 73856093 : U32), (j * 19349663 : U32)) / 256 % 256 : U32)) / 255.0 : F32)

def seed() -> U32: 7

def hmix(+i: U32, +j: U32) -> F32:
  +h = (i * 374761393 + j * 668265263 + seed() * 2246822519 : U32)
  +g = (U32.xor(h, (h / 8192 : U32)) * 1274126177 : U32)
  (u2f((U32.xor(g, (g / 65536 : U32)) % 256 : U32)) / 255.0 : F32)

def smooth(+f: F32) -> F32:
  (f * f * (3.0 - 2.0 * f) : F32)

def vnoise(+u: F32, +v: F32) -> F32:
  +i = f2u(u)
  +j = f2u(v)
  +fu = smooth((u - u2f(i) : F32))
  +fv = smooth((v - u2f(j) : F32))
  +a = h01(i, j)
  +b = h01((i + 1 : U32), j)
  +c = h01(i, (j + 1 : U32))
  +d = h01((i + 1 : U32), (j + 1 : U32))
  ((a * (1.0 - fu) + b * fu) * (1.0 - fv) + (c * (1.0 - fu) + d * fu) * fv : F32)

def tnoise(+u: F32, +v: F32) -> F32:
  +i = f2u(u)
  +j = f2u(v)
  +fu = smooth((u - u2f(i) : F32))
  +fv = smooth((v - u2f(j) : F32))
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
  +fx = u2f(x)
  +fz = u2f(z)
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
  (w, on(b, ybit))

def solid_at(ok: Bool, w: Array<U32>, +base: U32, +x: U32, +z: U32, +ybit: U32) -> Array<U32> & Bool:
  match ok:
    case False{}:
      (w, False{})
    case True{}:
      solid_bit(ybit, Array.get(U32, w, col_at(base, x, z)))

def solid(w: Array<U32>, +base: U32, +vx: F32, +vy: F32, +vz: F32) -> Array<U32> & Bool:
  solid_at(inside(vx, vy, vz), w, base, f2u(vx), f2u(vz), U32.shln(1, F32.to_nat(F32.max(vy, 0.0))))

# the same, on the world
def wsolid_fin(m: Map<&2, U32>, ox: U32, oz: U32, r: Array<U32> & Bool) -> World & Bool:
  (ring, s) = r
  (W{ring, m, ox, oz}, s)

def wsolid(w: World, +x: F32, +y: F32, +z: F32) -> World & Bool:
  W{ring, m, +ox, +oz} = w
  wsolid_fin(m, ox, oz, solid(ring, (ox * 128 + oz : U32), x, y, z))

# ---------- looks ----------

# The column word already holds all 32 heights, so "is the block above me
# empty?" and "am I three deep?" are bit tests on a value we already have.
# `U32.shln(a, n)` is O(n) -- a recursive shl per unit of n. So nothing here
# ever shifts by a variable: the DDA carries the mask 1<<y and moves it one
# bit per y step, and "above" / "three deep" are constant shl of that mask.
# 0 grass (nothing above), 2 stone (three deep), 1 dirt
def kind(+bits: U32, +ymask: U32) -> U32:
  +top = Bool.not(on(bits, U32.shl(ymask)))
  +deep = on(bits, U32.shl(U32.shl(U32.shl(ymask))))
  Bool.pick(U32, deep, 2, Bool.pick(U32, top, 0, 1))

def scale(+c: U32, +k: F32) -> U32:
  F32.to_u32(F32.min((U32.to_f32(c) * k : F32), 255.0))

def dim(+c: U32, +k: F32) -> U32:
  +r = (c / 65536 : U32)
  +g = (c / 256 % 256 : U32)
  +b = (c % 256 : U32)
  rgb(scale(r, k), scale(g, k), scale(b, k))

def sky_at(+yq: U32) -> U32:
  +g = (yq * 55 / (halfu() * 2) : U32)
  rgb((110 + g : U32), (150 + g : U32), 235)

def band(+y: U32) -> U32:
  (y / 8 * 8 : U32)

# ---------- DDA over the array ----------

# Only a step in x or z can change which column we are in, so the column is
# read once per crossing instead of once per voxel, and never again once
# this ray has found its block.
def refetch(need: Bool, w: Array<U32>, +base: U32, +x: U32, +z: U32, +old: U32) -> Array<U32> & U32:
  match need:
    case True{}:
      Array.get(U32, w, col_at(base, x, z))
    case False{}:
      (w, old)

# the hit is a word: 0 none, else 1 + kind + 4 * face; its look comes after
# the loop (a match, not the strict Bool.pick, so only a hit pays for it)
def hit(here: Bool, +bits: U32, +ymask: U32, +axis: F32, +col: U32) -> U32:
  match here:
    case True{}:
      (1 + kind(bits, ymask) + f2u(axis) * 4 : U32)
    case False{}:
      col

def dda_end(+col: U32, +t: F32, r: Array<U32> & U32) -> Array<U32> & (U32 & F32):
  (w, b) = r
  (w, (col, t))

def dda(fuel: Nat, +base: U32,
        +vx: F32, +vy: F32, +vz: F32,
        +sx: F32, +sy: F32, +sz: F32,
        +mx: F32, +my: F32, +mz: F32,
        +ex: F32, +ey: F32, +ez: F32,
        +axis: F32, +col: U32, +t: F32, +ymask: U32, r: Array<U32> & U32) -> Array<U32> & (U32 & F32):
  match fuel:
    case 0n:
      dda_end(col, t, r)
    case 1n+f:
      (w, +bits) = r
      +here = inside(vx, vy, vz) && on(bits, ymask) && (col < 1 : U32)
      +ncol = hit(here, bits, ymask, axis, col)
      +ux = (mx < my : F32) && (mx < mz : F32)
      +uy = Bool.pick(Bool, ux, False{}, (my < mz : F32))
      +nvx = Bool.pick(F32, ux, (vx + sx : F32), vx)
      nvy = Bool.pick(F32, uy, (vy + sy : F32), vy)
      +nvz = Bool.pick(F32, ux, vz, Bool.pick(F32, uy, vz, (vz + sz : F32)))
      nmx = Bool.pick(F32, ux, (mx + ex : F32), mx)
      nmy = Bool.pick(F32, uy, (my + ey : F32), my)
      nmz = Bool.pick(F32, ux, mz, Bool.pick(F32, uy, mz, (mz + ez : F32)))
      naxis = Bool.pick(F32, ux, 0.0, Bool.pick(F32, uy, 1.0, 2.0))
      # the mask moves one bit, never by a variable amount
      nymask = Bool.pick(U32, uy,
        Bool.pick(U32, (sy > 0.0 : F32), U32.shl(ymask), U32.shr(ymask)), ymask)
      # t is where the ray enters the next voxel; it stops moving at the hit
      nt = Bool.pick(F32, (ncol < 1 : U32), Bool.pick(F32, ux, mx, Bool.pick(F32, uy, my, mz)), t)
      dda(f, base, nvx, nvy, nvz, sx, sy, sz, nmx, nmy, nmz, ex, ey, ez, naxis, ncol, nt, nymask,
          refetch(Bool.not(uy) && (ncol < 1 : U32), w, base, f2u(nvx), f2u(nvz), bits))

# ---------- the hit's look: sun, texture, ambient occlusion, fog ----------
# The hit point is o + d t, on a face of the voxel V; the cell before the
# face, O, is air. A face turned to the sun casts a second, shorter DDA
# towards it, and is lit if nothing is in the way (24 steps); a face turned
# away is in shadow. The point's two coordinates along the face, u and w,
# sample a value noise (two octaves, continuous across blocks) that
# brightens or darkens the block's colour; a grass block's sides are dirt
# under a green band. The four cells beside O along the face each darken
# the half of the face they touch, more towards their edge: the ambient
# occlusion, four column reads through the handle the ray brought back.
# The fog blends the result into this row's sky by the square of t / 48.

def lerp(+x: U32, +y: U32, +f: F32) -> U32:
  F32.to_u32((u2f(x) * (1.0 - f) + u2f(y) * f : F32))

def mix(+a: U32, +b: U32, +f: F32) -> U32:
  rgb(lerp((a / 65536 : U32), (b / 65536 : U32), f),
      lerp((a / 256 % 256 : U32), (b / 256 % 256 : U32), f),
      lerp((a % 256 : U32), (b % 256 : U32), f))

# a tile of 8x8 texels, the same on every block: each texel is one of four
# shades, from a smooth noise sampled at its centre, so the shades come in
# patches, as pixel art does
def texture(+u: F32, +v: F32) -> F32:
  +i = (u2f(f2u((fracf(u) * 8.0 : F32))) + 0.5 : F32)
  +j = (u2f(f2u((fracf(v) * 8.0 : F32))) + 0.5 : F32)
  +n = (0.6 * vnoise((i * 0.55 : F32), (j * 0.55 : F32)) + 0.4 * vnoise((i * 1.3 + 5.0 : F32), (j * 1.3 + 9.0 : F32)) : F32)
  (0.76 + 0.12 * u2f(f2u((n * 3.99 : F32))) : F32)

# grass green, dirt brown, stone grey; a grass block's side is dirt below
# the top quarter
def blockcol(+kind: U32, +side: Bool, +yf: F32) -> U32:
  +grassy = U32.is_eq(kind, 0) && (Bool.not(side) || (yf > 0.72 : F32))
  Bool.pick(U32, U32.is_eq(kind, 2), rgb(130, 130, 130),
  Bool.pick(U32, grassy, rgb(117, 176, 73), rgb(134, 96, 67)))

# the sun: direction (0.48, 0.80, 0.36), so every step is +1 and the
# crossings advance by 1 / that component
def shadow_end(hit: Bool, r: Array<U32> & U32) -> Array<U32> & Bool:
  (w, b) = r
  (w, hit)

def shadow(fuel: Nat, +base: U32, +vx: F32, +vy: F32, +vz: F32, +mx: F32, +my: F32, +mz: F32,
           +ymask: U32, +hit: Bool, r: Array<U32> & U32) -> Array<U32> & Bool:
  match fuel:
    case 0n:
      shadow_end(hit, r)
    case 1n+f:
      (w, +bits) = r
      +here = hit || (inside(vx, vy, vz) && on(bits, ymask))
      +ux = (mx < my : F32) && (mx < mz : F32)
      +uy = Bool.pick(Bool, ux, False{}, (my < mz : F32))
      +nvx = Bool.pick(F32, ux, (vx + 1.0 : F32), vx)
      nvy = Bool.pick(F32, uy, (vy + 1.0 : F32), vy)
      +nvz = Bool.pick(F32, ux, vz, Bool.pick(F32, uy, vz, (vz + 1.0 : F32)))
      nmx = Bool.pick(F32, ux, (mx + 2.0833 : F32), mx)
      nmy = Bool.pick(F32, uy, (my + 1.25 : F32), my)
      nmz = Bool.pick(F32, ux, mz, Bool.pick(F32, uy, mz, (mz + 2.7778 : F32)))
      nymask = Bool.pick(U32, uy, U32.shl(ymask), ymask)
      shadow(f, base, nvx, nvy, nvz, nmx, nmy, nmz, nymask, here,
             refetch(Bool.not(uy) && Bool.not(here), w, base, f2u(nvx), f2u(nvz), bits))

def run_shadow(w: Array<U32>, +base: U32, +ox: F32, +oy: F32, +oz: F32) -> Array<U32> & Bool:
  +vx = floorf(ox)
  +vy = floorf(oy)
  +vz = floorf(oz)
  shadow(24n, base, vx, vy, vz,
         ((vx + 1.0 - ox) * 2.0833 : F32), ((vy + 1.0 - oy) * 1.25 : F32), ((vz + 1.0 - oz) * 2.7778 : F32),
         U32.shln(1, F32.to_nat(F32.max(oy, 0.0))), False{},
         Array.get(U32, w, col_at(base, f2u(vx), f2u(vz))))

# a face turned away from the sun is in shadow without a ray
def shadow_if(sunny: Bool, w: Array<U32>, +base: U32, +ox: F32, +oy: F32, +oz: F32) -> Array<U32> & Bool:
  match sunny:
    case False{}:
      (w, True{})
    case True{}:
      run_shadow(w, base, ox, oy, oz)

# The eight cells around O along the face, as bits of m: 1 +u, 2 -u, 4 +w,
# 8 -w, 16 +u+w, 32 -u+w, 64 +u-w, 128 -u-w. A vertex of the face is lit by
# its two sides and its corner: 3 steps of light, none when both sides are
# solid; the face blends its four vertices.
def vao(+s1: Bool, +s2: Bool, c: Bool) -> F32:
  +n = (Bool.pick(U32, s1, 1, 0) + Bool.pick(U32, s2, 1, 0) + Bool.pick(U32, c, 1, 0) : U32)
  Bool.pick(F32, s1 && s2, 0.4, (1.0 - 0.2 * u2f(n) : F32))

def ao_fin(+v: U32, +col: U32, +f: F32, +sun: F32, +m: U32, +fu: F32, +fw: F32, r: Array<U32> & Bool) -> Array<U32> & U32:
  (w, s) = r
  +m8 = Bool.pick(U32, s, (m .|. 128 : U32), m)
  +pp = vao(on(m8, 1), on(m8, 4), on(m8, 16))
  +mp = vao(on(m8, 2), on(m8, 4), on(m8, 32))
  +pm = vao(on(m8, 1), on(m8, 8), on(m8, 64))
  +mm = vao(on(m8, 2), on(m8, 8), on(m8, 128))
  +ao = ((mm * (1.0 - fu) + pm * fu) * (1.0 - fw) + (mp * (1.0 - fu) + pp * fu) * fw : F32)
  (w, mix(dim(col, (ao * sun : F32)), sky_at(v), (f * f : F32)))

def ao7(+v: U32, +col: U32, +f: F32, +sun: F32, +base: U32, +m: U32, +ox: F32, +oy: F32, +oz: F32,
        +ux: F32, +uy: F32, +uz: F32, +ex: F32, +ey: F32, +ez: F32, +fu: F32, +fw: F32,
        r: Array<U32> & Bool) -> Array<U32> & U32:
  (w, s) = r
  ao_fin(v, col, f, sun, Bool.pick(U32, s, (m .|. 64 : U32), m), fu, fw,
         solid(w, base, (ox - ux - ex : F32), (oy - uy - ey : F32), (oz - uz - ez : F32)))

def ao6(+v: U32, +col: U32, +f: F32, +sun: F32, +base: U32, +m: U32, +ox: F32, +oy: F32, +oz: F32,
        +ux: F32, +uy: F32, +uz: F32, +ex: F32, +ey: F32, +ez: F32, +fu: F32, +fw: F32,
        r: Array<U32> & Bool) -> Array<U32> & U32:
  (w, s) = r
  ao7(v, col, f, sun, base, Bool.pick(U32, s, (m .|. 32 : U32), m), ox, oy, oz, ux, uy, uz, ex, ey, ez, fu, fw,
      solid(w, base, (ox + ux - ex : F32), (oy + uy - ey : F32), (oz + uz - ez : F32)))

def ao5(+v: U32, +col: U32, +f: F32, +sun: F32, +base: U32, +m: U32, +ox: F32, +oy: F32, +oz: F32,
        +ux: F32, +uy: F32, +uz: F32, +ex: F32, +ey: F32, +ez: F32, +fu: F32, +fw: F32,
        r: Array<U32> & Bool) -> Array<U32> & U32:
  (w, s) = r
  ao6(v, col, f, sun, base, Bool.pick(U32, s, (m .|. 16 : U32), m), ox, oy, oz, ux, uy, uz, ex, ey, ez, fu, fw,
      solid(w, base, (ox - ux + ex : F32), (oy - uy + ey : F32), (oz - uz + ez : F32)))

def ao4(+v: U32, +col: U32, +f: F32, +sun: F32, +base: U32, +m: U32, +ox: F32, +oy: F32, +oz: F32,
        +ux: F32, +uy: F32, +uz: F32, +ex: F32, +ey: F32, +ez: F32, +fu: F32, +fw: F32,
        r: Array<U32> & Bool) -> Array<U32> & U32:
  (w, s) = r
  ao5(v, col, f, sun, base, Bool.pick(U32, s, (m .|. 8 : U32), m), ox, oy, oz, ux, uy, uz, ex, ey, ez, fu, fw,
      solid(w, base, (ox + ux + ex : F32), (oy + uy + ey : F32), (oz + uz + ez : F32)))

def ao3(+v: U32, +col: U32, +f: F32, +sun: F32, +base: U32, +m: U32, +ox: F32, +oy: F32, +oz: F32,
        +ux: F32, +uy: F32, +uz: F32, +ex: F32, +ey: F32, +ez: F32, +fu: F32, +fw: F32,
        r: Array<U32> & Bool) -> Array<U32> & U32:
  (w, s) = r
  ao4(v, col, f, sun, base, Bool.pick(U32, s, (m .|. 4 : U32), m), ox, oy, oz, ux, uy, uz, ex, ey, ez, fu, fw,
      solid(w, base, (ox - ex : F32), (oy - ey : F32), (oz - ez : F32)))

def ao2(+v: U32, +col: U32, +f: F32, +sun: F32, +base: U32, +m: U32, +ox: F32, +oy: F32, +oz: F32,
        +ux: F32, +uy: F32, +uz: F32, +ex: F32, +ey: F32, +ez: F32, +fu: F32, +fw: F32,
        r: Array<U32> & Bool) -> Array<U32> & U32:
  (w, s) = r
  ao3(v, col, f, sun, base, Bool.pick(U32, s, (m .|. 2 : U32), m), ox, oy, oz, ux, uy, uz, ex, ey, ez, fu, fw,
      solid(w, base, (ox + ex : F32), (oy + ey : F32), (oz + ez : F32)))

def ao1(+v: U32, +col: U32, +f: F32, +sun: F32, +base: U32, +ox: F32, +oy: F32, +oz: F32,
        +ux: F32, +uy: F32, +uz: F32, +ex: F32, +ey: F32, +ez: F32, +fu: F32, +fw: F32,
        r: Array<U32> & Bool) -> Array<U32> & U32:
  (w, s) = r
  ao2(v, col, f, sun, base, Bool.pick(U32, s, 1, 0), ox, oy, oz, ux, uy, uz, ex, ey, ez, fu, fw,
      solid(w, base, (ox - ux : F32), (oy - uy : F32), (oz - uz : F32)))

# after the sun: the first neighbour read
def after_sun(+v: U32, +col: U32, +f: F32, +base: U32, +ox: F32, +oy: F32, +oz: F32,
              +ux: F32, +uy: F32, +uz: F32, +ex: F32, +ey: F32, +ez: F32, +fu: F32, +fw: F32,
              r: Array<U32> & Bool) -> Array<U32> & U32:
  (w, dark) = r
  ao1(v, col, f, Bool.pick(F32, dark, 0.6, 1.0), base, ox, oy, oz, ux, uy, uz, ex, ey, ez, fu, fw,
      solid(w, base, (ox + ux : F32), (oy + uy : F32), (oz + uz : F32)))

def shade_go(sky: Bool, w: Array<U32>, +base: U32, +v: U32, +ox: F32, +oy: F32, +oz: F32,
             +dx: F32, +dy: F32, +dz: F32, +c: U32, +t: F32) -> Array<U32> & U32:
  match sky:
    case True{}:
      (w, sky_at(v))
    case False{}:
      +kind = ((c - 1) % 4 : U32)
      +axis = ((c - 1) / 4 : U32)
      +px = (ox + dx * t : F32)
      +py = (oy + dy * t : F32)
      +pz = (oz + dz * t : F32)
      # the face's coordinates: u along z on an x face and along x otherwise,
      # w along z on a y face and along y otherwise
      +ax = U32.is_eq(axis, 0)
      +ay = U32.is_eq(axis, 1)
      +u = Bool.pick(F32, ax, pz, px)
      +wf = Bool.pick(F32, ay, pz, py)
      +shade = Bool.pick(F32, ax, 0.8, Bool.pick(F32, ay, 1.0, 0.7))
      +col = dim(blockcol(kind, Bool.not(ay), fracf(py)), (shade * texture(u, wf) : F32))
      +f = F32.min((t / 48.0 : F32), 1.0)
      # O, the air cell before the face: floor of p, except along the face's
      # axis, where p sits on the boundary and O is the side the ray came from
      +bx = floorf((px + 0.5 : F32))
      +by = floorf((py + 0.5 : F32))
      +bz = floorf((pz + 0.5 : F32))
      +cx = Bool.pick(F32, ax, Bool.pick(F32, (dx > 0.0 : F32), (bx - 1.0 : F32), bx), floorf(px))
      +cy = Bool.pick(F32, ay, Bool.pick(F32, (dy > 0.0 : F32), (by - 1.0 : F32), by), floorf(py))
      +cz = Bool.pick(F32, U32.is_eq(axis, 2), Bool.pick(F32, (dz > 0.0 : F32), (bz - 1.0 : F32), bz), floorf(pz))
      # the unit steps of u and w in space
      +ux = Bool.pick(F32, ax, 0.0, 1.0)
      +uz = Bool.pick(F32, ax, 1.0, 0.0)
      +ey = Bool.pick(F32, ay, 0.0, 1.0)
      +ez = Bool.pick(F32, ay, 1.0, 0.0)
      # where on the face, for the blend of the four vertices
      +fu = fracf(u)
      +fw = fracf(wf)
      # the face looks at the sun when the ray came against that axis; the
      # shadow ray starts a hair before the face, in O
      +da = Bool.pick(F32, ax, dx, Bool.pick(F32, ay, dy, dz))
      +nudge = Bool.pick(F32, (da > 0.0 : F32), (0.0 - 0.01 : F32), 0.01)
      after_sun(v, col, f, base, cx, cy, cz, ux, 0.0, uz, 0.0, ey, ez, fu, fw,
                shadow_if((da < 0.0 : F32), w, base,
                          Bool.pick(F32, ax, (px + nudge : F32), px),
                          Bool.pick(F32, ay, (py + nudge : F32), py),
                          Bool.pick(F32, U32.is_eq(axis, 2), (pz + nudge : F32), pz)))

def shade(+v: U32, w: Array<U32>, +base: U32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
          ct: U32 & F32) -> Array<U32> & U32:
  (+c, t) = ct
  shade_go((c < 1 : U32), w, base, v, ox, oy, oz, dx, dy, dz, c, t)

def finish(+v: U32, +base: U32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
           r: Array<U32> & (U32 & F32)) -> Array<U32> & U32:
  (w, ct) = r
  shade(v, w, base, ox, oy, oz, dx, dy, dz, ct)

def run_dda(w: Array<U32>, +base: U32, +ox: F32, +oy: F32, +oz: F32,
            +dx: F32, +dy: F32, +dz: F32, +v: U32) -> Array<U32> & U32:
  +vx = floorf(F32.max(ox, 0.0))
  +vy = floorf(F32.max(oy, 0.0))
  +vz = floorf(F32.max(oz, 0.0))
  +px = (dx > 0.0 : F32)
  +py = (dy > 0.0 : F32)
  +pz = (dz > 0.0 : F32)
  +ax = F32.max(absf(dx), 0.00001)
  +ay = F32.max(absf(dy), 0.00001)
  +az = F32.max(absf(dz), 0.00001)
  +nx = Bool.pick(F32, px, (vx + 1.0 - ox : F32), (ox - vx : F32))
  +ny = Bool.pick(F32, py, (vy + 1.0 - oy : F32), (oy - vy : F32))
  +nz = Bool.pick(F32, pz, (vz + 1.0 - oz : F32), (oz - vz : F32))
  finish(v, base, ox, oy, oz, dx, dy, dz, dda(60n, base, vx, vy, vz,
           Bool.pick(F32, px, 1.0, (0.0 - 1.0 : F32)),
           Bool.pick(F32, py, 1.0, (0.0 - 1.0 : F32)),
           Bool.pick(F32, pz, 1.0, (0.0 - 1.0 : F32)),
           (nx / ax : F32), (ny / ay : F32), (nz / az : F32),
           (1.0 / ax : F32), (1.0 / ay : F32), (1.0 / az : F32),
           1.0, 0, 0.0, U32.shln(1, F32.to_nat(F32.max(oy, 0.0))),
           Array.get(U32, w, col_at(base, f2u(vx), f2u(vz)))))

# A ray that misses the loaded box reads the world zero times.
def shoot(go: Bool, w: Array<U32>, +base: U32, +ox: F32, +oy: F32, +oz: F32,
          +dx: F32, +dy: F32, +dz: F32, +v: U32) -> Array<U32> & U32:
  match go:
    case False{}:
      (w, sky_at(v))
    case True{}:
      run_dda(w, base, ox, oy, oz, dx, dy, dz, v)

def clipped(w: Array<U32>, +base: U32, +ox: F32, +oy: F32, +oz: F32,
            +dx: F32, +dy: F32, +dz: F32, +v: U32) -> Array<U32> & U32:
  +rx = (1.0 / F32.max(absf(dx), 0.00001) * Bool.pick(F32, (dx > 0.0 : F32), 1.0, (0.0 - 1.0 : F32)) : F32)
  +ry = (1.0 / F32.max(absf(dy), 0.00001) * Bool.pick(F32, (dy > 0.0 : F32), 1.0, (0.0 - 1.0 : F32)) : F32)
  +rz = (1.0 / F32.max(absf(dz), 0.00001) * Bool.pick(F32, (dz > 0.0 : F32), 1.0, (0.0 - 1.0 : F32)) : F32)
  +xa = ((0.0 - ox) * rx : F32)
  +xb = ((128.0 - ox) * rx : F32)
  +ya = ((0.0 - oy) * ry : F32)
  +yb = ((32.0 - oy) * ry : F32)
  +za = ((0.0 - oz) * rz : F32)
  +zb = ((128.0 - oz) * rz : F32)
  +tin  = F32.max(F32.max(F32.min(xa, xb), F32.min(ya, yb)), F32.max(F32.min(za, zb), 0.0))
  +tout = F32.min(F32.min(F32.max(xa, xb), F32.max(ya, yb)), F32.max(za, zb))
  +s = (tin + 0.002 : F32)
  shoot((tin < tout : F32), w, base, (ox + dx * s : F32), (oy + dy * s : F32), (oz + dz * s : F32), dx, dy, dz, v)

# ---------- the player ----------

# The camera is Data, shared down the fork; the world is the array, threaded.
type Cam is Data:
  Cam{px: F32, py: F32, pz: F32, yaw: F32, pit: F32, base: U32}

type Game is Type:
  G{w: World, px: F32, py: F32, pz: F32, yaw: F32, pit: F32, vy: F32,
    held: U32, edge: U32, mx: U32, my: U32}

def look_x(+yaw: F32, +pit: F32) -> F32: (F32.cos(pit) * F32.sin(yaw) : F32)
def look_y(+pit: F32) -> F32: F32.sin(pit)
def look_z(+yaw: F32, +pit: F32) -> F32: (F32.cos(pit) * F32.cos(yaw) : F32)

def norm3(+x: F32, +y: F32, +z: F32) -> F32:
  F32.sqrt((x * x + y * y + z * z : F32))

def p2f(+p: U32) -> F32:
  (U32.to_f32(p) / half() - 1.0 : F32)

def shade_px(+cam: Cam, w: Array<U32>, +pxi: U32, +pyi: U32) -> Array<U32> & U32:
  Cam{ox, oy, oz, yaw, pit, base} = cam
  +u = p2f(pxi)
  +v = p2f(pyi)
  +fx = look_x(yaw, pit)
  +fy = look_y(pit)
  +fz = look_z(yaw, pit)
  # right = normalize(cross(fwd, up)), up = (0,1,0)
  +rl = F32.max(norm3(fz, 0.0, (0.0 - fx : F32)), 0.00001)
  +rx = (fz / rl : F32)
  +rz = ((0.0 - fx) / rl : F32)
  # up' = cross(right, fwd)
  +ux = (0.0 - rz * fy : F32)
  +uy = (rz * fx - rx * fz : F32)
  +uz = (rx * fy : F32)
  +dx = (fx + 0.9 * u * rx + 0.9 * v * ux : F32)
  +dy = (fy + 0.9 * v * uy : F32)
  +dz = (fz + 0.9 * u * rz + 0.9 * v * uz : F32)
  +n = F32.max(norm3(dx, dy, dz), 0.00001)
  clipped(w, base, ox, oy, oz, (dx / n : F32), (dy / n : F32), (dz / n : F32), band(pyi))

# a crosshair straight over the middle
def cross_at(+pxi: U32, +pyi: U32) -> Bool:
  +dx = Bool.pick(U32, (pxi > halfu() : U32), (pxi - halfu() : U32), (halfu() - pxi : U32))
  +dy = Bool.pick(U32, (pyi > halfu() : U32), (pyi - halfu() : U32), (halfu() - pyi : U32))
  ((dx < 1 : U32) && (dy < 5 : U32)) || ((dy < 1 : U32) && (dx < 5 : U32))

def paint(hair: Bool, +cam: Cam, w: Array<U32>, +pxi: U32, +pyi: U32) -> Array<U32> & U32:
  match hair:
    case True{}:
      (w, rgb(255, 255, 255))
    case False{}:
      shade_px(cam, w, pxi, pyi)

def pixel(+cam: Cam, w: Array<U32>, +pxi: U32, +pyi: U32) -> Array<U32> & U32:
  paint(cross_at(pxi, pyi), cam, w, pxi, pyi)

# ---------- tile, straight-line ----------
# Four pixels in a row, the handle passed from one to the next; a 2x2 of one
# colour collapses to a Pix.

def one4(same: Bool, +k0: U32, +k1: U32, +k2: U32, +k3: U32) -> Image:
  match same:
    case True{}:
      Pix{k0}
    case False{}:
      Qua{Pix{k0}, Pix{k1}, Pix{k2}, Pix{k3}}

def t2d(+k0: U32, +k1: U32, +k2: U32, r: Array<U32> & U32) -> Array<U32> & Image:
  (w, +k3) = r
  (w, one4(U32.is_eq(k0, k1) && U32.is_eq(k1, k2) && U32.is_eq(k2, k3), k0, k1, k2, k3))

def t2c(+cam: Cam, +x: U32, +y: U32, +k0: U32, +k1: U32, r: Array<U32> & U32) -> Array<U32> & Image:
  (w, k2) = r
  t2d(k0, k1, k2, pixel(cam, w, (x + 1 : U32), (y + 1 : U32)))

def t2b(+cam: Cam, +x: U32, +y: U32, +k0: U32, r: Array<U32> & U32) -> Array<U32> & Image:
  (w, k1) = r
  t2c(cam, x, y, k0, k1, pixel(cam, w, x, (y + 1 : U32)))

def t2a(+cam: Cam, +x: U32, +y: U32, r: Array<U32> & U32) -> Array<U32> & Image:
  (w, k0) = r
  t2b(cam, x, y, k0, pixel(cam, w, (x + 1 : U32), y))

def t2(+cam: Cam, w: Array<U32>, +x: U32, +y: U32) -> Array<U32> & Image:
  t2a(cam, x, y, pixel(cam, w, x, y))

def t4d(a: Image, b: Image, c: Image, r: Array<U32> & Image) -> Array<U32> & Image:
  (w, d) = r
  (w, Qua{a, b, c, d})

def t4c(+cam: Cam, +x: U32, +y: U32, a: Image, b: Image, r: Array<U32> & Image) -> Array<U32> & Image:
  (w, c) = r
  t4d(a, b, c, t2(cam, w, (x + 2 : U32), (y + 2 : U32)))

def t4b(+cam: Cam, +x: U32, +y: U32, a: Image, r: Array<U32> & Image) -> Array<U32> & Image:
  (w, b) = r
  t4c(cam, x, y, a, b, t2(cam, w, x, (y + 2 : U32)))

def t4a(+cam: Cam, +x: U32, +y: U32, r: Array<U32> & Image) -> Array<U32> & Image:
  (w, a) = r
  t4b(cam, x, y, a, t2(cam, w, (x + 2 : U32), y))

def t4(+cam: Cam, w: Array<U32>, +x: U32, +y: U32) -> Array<U32> & Image:
  t4a(cam, x, y, t2(cam, w, x, y))

# ---------- the fork ----------
# Each level hands its one handle to four kids and joins the four that come
# back; the images become a Qua.

def two(l: Array<U32> & Image, r: Array<U32> & Image) -> Array<U32> & (Image & Image):
  (wl, p) = l
  (wr, q) = r
  (Array.join(U32, wl, wr), (p, q))

def quad_fin(wl: Array<U32>, wm: Array<U32>, pq: Image & Image, rs: Image & Image) -> Array<U32> & Image:
  (p, q) = pq
  (r, s) = rs
  (Array.join(U32, wl, wm), Qua{p, q, r, s})

def quad(l: Array<U32> & (Image & Image), m: Array<U32> & (Image & Image)) -> Array<U32> & Image:
  (wl, pq) = l
  (wm, rs) = m
  quad_fin(wl, wm, pq, rs)

# fork down to 4x4 tiles: see RESOLUTION above.
@unsafe
def fork(+k: Nat, +cam: Cam, +w: Array<U32>, +x: U32, +y: U32) -> Array<U32> & Image:
  match k:
    case 0n:
      t4(cam, w, x, y)
    case 1n+e:
      +h = U32.shln(4, e)
      +x1 = (x + h : U32)
      +y1 = (y + h : U32)
      p q r s = fork(e, cam, w, x, y) fork(e, cam, w, x1, y) fork(e, cam, w, x, y1) fork(e, cam, w, x1, y1)
      quad(two(p, q), two(r, s))

def view_fin(px: F32, py: F32, pz: F32, yaw: F32, pit: F32, vy: F32,
             held: U32, edge: U32, mx: U32, my: U32, m: Map<&2, U32>, ox: U32, oz: U32,
             r: Array<U32> & Image) -> Game & Image:
  (ring, img) = r
  (G{W{ring, m, ox, oz}, px, py, pz, yaw, pit, vy, held, edge, mx, my}, img)

def view_w(+px: F32, +py: F32, +pz: F32, +yaw: F32, +pit: F32, vy: F32,
           held: U32, edge: U32, mx: U32, my: U32, w: World) -> Game & Image:
  W{ring, m, +ox, +oz} = w
  view_fin(px, py, pz, yaw, pit, vy, held, edge, mx, my, m, ox, oz,
           fork!(7n, Cam{px, py, pz, yaw, pit, (ox * 128 + oz : U32)}, ring, 0, 0))

def view(g: Game) -> Game & Image:
  G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my} = g
  view_w(px, py, pz, yaw, pit, vy, held, edge, mx, my, w)

# ---------- input ----------
# Keys are a bitmask in `held` (w a s d 1..8, arrows 16..128, j l 1024 2048,
# Esc 4096, space 8192) and the edge of a press in `edge`. The mouse keeps
# its last place in `mx`, `my` and two bits above the keys: 16384 while the
# left button is down, 32768 once that press has dragged. A drag looks, a
# left click (press and release without a drag) breaks, a right click places.

def kbit(+c: U32, +code: U32, +bit: U32) -> U32:
  Bool.pick(U32, U32.is_eq(c, code), bit, 0)

def kmask(+c: U32) -> U32:
  (kbit(c, 119, 1) .|. kbit(c, 97, 2) .|. kbit(c, 115, 4) .|. kbit(c, 100, 8)
    .|. kbit(c, 63232, 16) .|. kbit(c, 63233, 32)
    .|. kbit(c, 63234, 64) .|. kbit(c, 63235, 128)
    .|. kbit(c, 106, 1024) .|. kbit(c, 108, 2048)
    .|. kbit(c, 27, 4096) .|. kbit(c, 32, 8192) : U32)

def key_apply(down: Bool, w: World, px: F32, py: F32, pz: F32, yaw: F32, pit: F32, vy: F32,
              +held: U32, edge: U32, mx: U32, my: U32, +m: U32) -> Game:
  match down:
    case True{}:
      G{w, px, py, pz, yaw, pit, vy, (held .|. m : U32),
        (edge .|. (m .&. U32.not(held)) : U32), mx, my}
    case False{}:
      G{w, px, py, pz, yaw, pit, vy, (held .&. U32.not(m) : U32), edge, mx, my}

def on_key(g: Game, +code: U32, down: Bool) -> Game:
  G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my} = g
  +lower = Bool.pick(U32, ((code >= 65) && (code <= 90) : U32), (code + 32 : U32), code)
  key_apply(down, w, px, py, pz, yaw, pit, vy, held, edge, mx, my, kmask(lower))

# button 0 is the left one, 1 the right one, on both windows
def on_button(g: Game, +x: U32, +y: U32, +b: U32, +down: Bool) -> Game:
  G{w, px, py, pz, yaw, pit, vy, +held, +edge, mx, my} = g
  +press = U32.is_eq(b, 0) && down
  +release = U32.is_eq(b, 0) && Bool.not(down)
  +click = release && U32.is_eq((held .&. 49152 : U32), 16384)
  +place = U32.is_eq(b, 1) && down
  +held1 = Bool.pick(U32, press, ((held .|. 16384) .&. U32.not(32768) : U32), held)
  G{w, px, py, pz, yaw, pit, vy,
    Bool.pick(U32, release, (held1 .&. U32.not(16384) : U32), held1),
    (edge .|. Bool.pick(U32, click, 1024, 0) .|. Bool.pick(U32, place, 2048, 0) : U32),
    Bool.pick(U32, press, x, mx), Bool.pick(U32, press, y, my)}

# a drag turns the camera, 0.0045 rad per pixel; y grows downwards
def on_move(g: Game, +x: U32, +y: U32) -> Game:
  G{w, px, py, pz, +yaw, +pit, vy, +held, edge, +mx, +my} = g
  +drag = on(held, 16384)
  +dx = (u2f(x) - u2f(mx) : F32)
  +dy = (u2f(y) - u2f(my) : F32)
  +far = ((absf(dx) + absf(dy) : F32) > 2.0 : F32)
  G{w, px, py, pz,
    Bool.pick(F32, drag, (yaw + 0.0045 * dx : F32), yaw),
    Bool.pick(F32, drag, F32.clamp((pit - 0.0045 * dy : F32), (0.0 - 1.45 : F32), 1.45), pit),
    vy,
    Bool.pick(U32, drag && far, (held .|. 32768 : U32), held),
    edge,
    Bool.pick(U32, drag, x, mx), Bool.pick(U32, drag, y, my)}

def quit_now(g: Game) -> Game:
  G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my} = g
  G{w, px, py, pz, yaw, pit, vy, held, (edge .|. 4096 : U32), mx, my}

def feed(evs: List<Event>, g: Game) -> Game:
  match evs:
    case Nil{}:
      g
    case Con{Key{code, down}, rest}:
      feed(rest, on_key(g, code, down))
    case Con{Mouse{x, y, b, down}, rest}:
      feed(rest, on_button(g, x, y, b, down))
    case Con{Move{x, y}, rest}:
      feed(rest, on_move(g, x, y))
    case Con{Close{}, rest}:
      feed(rest, quit_now(g))

# ---------- picking the block under the crosshair ----------
# A voxel is a word, 1 + (lx * 32 + y) * 128 + lz, 0 for none; the pick
# returns the one hit and the one before it.

def pk(+x: F32, +y: F32, +z: F32) -> U32:
  ((f2u(x) * 32 + f2u(y)) * 128 + f2u(z) : U32)

def pick_end(+prev: U32, +hit: U32, r: Array<U32> & Bool) -> Array<U32> & (U32 & U32):
  (w, s) = r
  (w, (prev, hit))

def pick(fuel: Nat, +base: U32,
         +vx: F32, +vy: F32, +vz: F32,
         +sx: F32, +sy: F32, +sz: F32,
         +mx: F32, +my: F32, +mz: F32,
         +ex: F32, +ey: F32, +ez: F32,
         +last: U32, +prev: U32, +hit: U32, r: Array<U32> & Bool) -> Array<U32> & (U32 & U32):
  match fuel:
    case 0n:
      pick_end(prev, hit, r)
    case 1n+f:
      (w, sol) = r
      +take = sol && (hit < 1 : U32)
      +here = (1 + pk(vx, vy, vz) : U32)
      +ux = (mx < my : F32) && (mx < mz : F32)
      +uy = Bool.pick(Bool, ux, False{}, (my < mz : F32))
      +nvx = Bool.pick(F32, ux, (vx + sx : F32), vx)
      +nvy = Bool.pick(F32, uy, (vy + sy : F32), vy)
      +nvz = Bool.pick(F32, ux, vz, Bool.pick(F32, uy, vz, (vz + sz : F32)))
      nmx = Bool.pick(F32, ux, (mx + ex : F32), mx)
      nmy = Bool.pick(F32, uy, (my + ey : F32), my)
      nmz = Bool.pick(F32, ux, mz, Bool.pick(F32, uy, mz, (mz + ez : F32)))
      pick(f, base, nvx, nvy, nvz, sx, sy, sz, nmx, nmy, nmz, ex, ey, ez, here,
           Bool.pick(U32, take, last, prev), Bool.pick(U32, take, here, hit),
           solid(w, base, nvx, nvy, nvz))

def aim(w: Array<U32>, +base: U32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32) -> Array<U32> & (U32 & U32):
  +vx = floorf(F32.max(ox, 0.0))
  +vy = floorf(F32.max(oy, 0.0))
  +vz = floorf(F32.max(oz, 0.0))
  +px = (dx > 0.0 : F32)
  +py = (dy > 0.0 : F32)
  +pz = (dz > 0.0 : F32)
  +ax = F32.max(absf(dx), 0.00001)
  +ay = F32.max(absf(dy), 0.00001)
  +az = F32.max(absf(dz), 0.00001)
  +nx = Bool.pick(F32, px, (vx + 1.0 - ox : F32), (ox - vx : F32))
  +ny = Bool.pick(F32, py, (vy + 1.0 - oy : F32), (oy - vy : F32))
  +nz = Bool.pick(F32, pz, (vz + 1.0 - oz : F32), (oz - vz : F32))
  pick(40n, base, vx, vy, vz,
       Bool.pick(F32, px, 1.0, (0.0 - 1.0 : F32)),
       Bool.pick(F32, py, 1.0, (0.0 - 1.0 : F32)),
       Bool.pick(F32, pz, 1.0, (0.0 - 1.0 : F32)),
       (nx / ax : F32), (ny / ay : F32), (nz / az : F32),
       (1.0 / ax : F32), (1.0 / ay : F32), (1.0 / az : F32),
       0, 0, 0, solid(w, base, vx, vy, vz))

def waim_fin(m: Map<&2, U32>, ox: U32, oz: U32, r: Array<U32> & (U32 & U32)) -> World & (U32 & U32):
  (ring, ph) = r
  (W{ring, m, ox, oz}, ph)

def waim(w: World, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32) -> World & (U32 & U32):
  W{ring, m, +cx, +cz} = w
  waim_fin(m, cx, cz, aim(ring, (cx * 128 + cz : U32), ox, oy, oz, dx, dy, dz))

# unpack: word -> lx, y, lz
def ix_x(+i: U32) -> U32: (i / 4096 : U32)
def ix_y(+i: U32) -> U32: (i / 128 % 32 : U32)
def ix_z(+i: U32) -> U32: (i % 128 : U32)

def apply_edit(act: Bool, w: World, +idx: U32, set: Bool) -> World:
  match act:
    case False{}:
      w
    case True{}:
      edit(w, ix_x(idx), ix_z(idx), U32.shln(1, U32.to_nat(ix_y(idx))), set)

# ---------- one tick ----------
# The player is 1.8 blocks tall with the eye at 1.6, so they stand in the
# block of `py - 1.6` and the one of `py + 0.2`. Walking tests those two
# per axis and stops at a wall (the feet test sits 0.05 up, so the block
# under the feet never counts). Gravity pulls `vy`; landing snaps the feet
# onto the block; space pushes off it. Then the world's corner follows, so
# the player is back in local column 64, and the crosshair's block is
# found. A block is never placed on the player. Every test reads the
# world, so the tick is a chain that passes it along.

def eye() -> F32: 1.6

def blocked_fin(feet: Bool, r: World & Bool) -> World & Bool:
  (w, head) = r
  (w, feet || head)

def blocked_head(+x: F32, +y: F32, +z: F32, r: World & Bool) -> World & Bool:
  (w, feet) = r
  blocked_fin(feet, wsolid(w, x, (y + 0.2 : F32), z))

def blocked(w: World, +x: F32, +y: F32, +z: F32) -> World & Bool:
  blocked_head(x, y, z, wsolid(w, x, (y - 1.55 : F32), z))

def ax2(+held: U32, +negbit: U32, +posbit: U32) -> F32:
  (Bool.pick(F32, on(held, posbit), 1.0, 0.0)
   - Bool.pick(F32, on(held, negbit), 1.0, 0.0) : F32)

def step_edit(+npx: F32, +npy: F32, +npz: F32, nvy: F32, nyaw: F32, npit: F32,
              held: U32, +edge: U32, mx: U32, my: U32, w: World, ph: U32 & U32) -> Game:
  (+prev, +hit) = ph
  +got = (hit > 0 : U32)
  +tgt = (prev - 1 : U32)
  +onme = U32.is_eq(tgt, pk(npx, (npy - 1.55 : F32), npz)) || U32.is_eq(tgt, pk(npx, (npy + 0.2 : F32), npz))
  +brk = got && on(edge, 1024)
  +put = got && (prev > 0 : U32) && on(edge, 2048) && Bool.not(onme)
  G{apply_edit(put, apply_edit(brk, w, (hit - 1 : U32), False{}), tgt, True{}),
    npx, npy, npz, nyaw, npit, nvy, held, (edge .&. 4096 : U32), mx, my}

def step_aim(+npx: F32, +npy: F32, +npz: F32, nvy: F32, nyaw: F32, npit: F32,
             held: U32, edge: U32, mx: U32, my: U32, r: World & (U32 & U32)) -> Game:
  (w, ph) = r
  step_edit(npx, npy, npz, nvy, nyaw, npit, held, edge, mx, my, w, ph)

def step_bump(+npx: F32, +py: F32, +npz: F32, +ty: F32, +vy1: F32, +land: Bool,
              +nyaw: F32, +npit: F32, +held: U32, edge: U32, mx: U32, my: U32,
              r: World & Bool) -> Game:
  (w, above) = r
  +bump = (vy1 > 0.0 : F32) && above
  +feet = (ty - eye() : F32)
  +npy = F32.clamp(Bool.pick(F32, land, (floorf(feet) + 1.0 + eye() : F32),
                             Bool.pick(F32, bump, py, ty)), eye(), 31.5)
  +nvy = Bool.pick(F32, land && on(held, 8192), 0.2,
                   Bool.pick(F32, land || bump, 0.0, vy1))
  # the corner follows: back to local column 64
  +cx = f2u(npx)
  +cz = f2u(npz)
  +lx = (npx - u2f(cx) + 64.0 : F32)
  +lz = (npz - u2f(cz) + 64.0 : F32)
  step_aim(lx, npy, lz, nvy, nyaw, npit, held, edge, mx, my,
           waim(follow_z(U32.to_nat(Bool.pick(U32, (cz > 64 : U32), (cz - 64 : U32), (64 - cz : U32))), (cz > 64 : U32),
                follow_x(U32.to_nat(Bool.pick(U32, (cx > 64 : U32), (cx - 64 : U32), (64 - cx : U32))), (cx > 64 : U32), w)),
                lx, npy, lz, look_x(nyaw, npit), look_y(npit), look_z(nyaw, npit)))

def step_land(+npx: F32, +py: F32, +npz: F32, +ty: F32, +vy1: F32,
              nyaw: F32, npit: F32, held: U32, edge: U32, mx: U32, my: U32,
              r: World & Bool) -> Game:
  (w, below) = r
  step_bump(npx, py, npz, ty, vy1, (vy1 < 0.0 : F32) && below, nyaw, npit, held, edge, mx, my,
            wsolid(w, npx, (ty + 0.2 : F32), npz))

def step_z(+npx: F32, +py: F32, +pz: F32, +tz: F32, +vy1: F32,
           nyaw: F32, npit: F32, held: U32, edge: U32, mx: U32, my: U32,
           r: World & Bool) -> Game:
  (w, bz) = r
  +npz = Bool.pick(F32, bz, pz, tz)
  +ty = (py + vy1 : F32)
  step_land(npx, py, npz, ty, vy1, nyaw, npit, held, edge, mx, my,
            wsolid(w, npx, (ty - eye() : F32), npz))

def step_x(+px: F32, +py: F32, +pz: F32, +tx: F32, +tz: F32, +vy1: F32,
           nyaw: F32, npit: F32, held: U32, edge: U32, mx: U32, my: U32,
           r: World & Bool) -> Game:
  (w, bx) = r
  +npx = Bool.pick(F32, bx, px, tx)
  step_z(npx, py, pz, tz, vy1, nyaw, npit, held, edge, mx, my, blocked(w, npx, py, tz))

def step(g: Game) -> Game:
  G{w, +px, +py, +pz, yaw, pit, vy, +held, edge, mx, my} = g
  +nyaw = (yaw + 0.055 * ax2(held, 64, 128) : F32)
  +npit = F32.clamp((pit + 0.045 * ax2(held, 32, 16) : F32), (0.0 - 1.45 : F32), 1.45)
  +sy = F32.sin(nyaw)
  +cy = F32.cos(nyaw)
  +fw = ax2(held, 4, 1)
  +st = ax2(held, 2, 8)
  +tx = (px + 0.16 * (fw * sy + st * cy) : F32)
  +tz = (pz + 0.16 * (fw * cy - st * sy) : F32)
  +vy1 = F32.max((vy - 0.012 : F32), (0.0 - 0.9 : F32))
  step_x(px, py, pz, tx, tz, vy1, nyaw, npit, held, edge, mx, my, blocked(w, tx, py, pz))

def alive(g: Game) -> IO(Maybe<Game>):
  G{w, px, py, pz, yaw, pit, vy, held, +edge, mx, my} = g
  Bool.pick(IO(Maybe<Game>), on(edge, 4096),
    IO.pure(Maybe<Game>, None{}),
    IO.pure(Maybe<Game>, Some{G{w, px, py, pz, yaw, pit, vy, held, 0, mx, my}}))

def tick(evs: List<Event>, g: Game) -> IO(Maybe<Game>):
  alive(step(feed(evs, g)))

# the world's corner starts far from zero, so walking west never wraps it
def start() -> Game:
  G{load_all(128n, W{[0 : U32^14n], Map.new(&2, U32), 1048512, 1048512}, 1048512, 1048512),
    64.5, 30.0, 64.5, 0.0, (0.0 - 0.55 : F32), 0.0, 0, 0, 0, 0}

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("WASD move | space jump | drag to look | click break | right click place | J/L break/place | Esc quit")
    App.run(~Game, ~App{g => view(g), tick}, "Bendcraft", 512, 512, start())
