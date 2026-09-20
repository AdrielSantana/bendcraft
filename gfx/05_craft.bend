import Base

# An interactive voxel world: walk, jump, break blocks, place blocks.
#
# THE WORLD IS A TREE, NOT AN ARRAY.
#
# `Array` in Bend is a `Type`: one owner, so it cannot be read by both sides
# of a parallel call -- useless for a renderer where every pixel reads the
# world at once. So the world is a `Data` quadtree over the 32x32 columns,
# and each leaf is a U32 whose bit y says "there is a block at height y".
# Shared by every pixel and read without counting (see wget); editing
# rebuilds one path of five nodes and leaves the rest shared.
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
# bang keep them all busy (`bend guide shaders`). At 512x512, 7 levels over
# 4x4 tiles measured 13 ms untouched / 26 built; 8 levels over 2x2 tiles, 17 /
# 38, same image. On the CPU the same sweep is flat, so this only shows up
# with `!`. Two things must agree: the `k` in `fork!` below and `halfu()`
# here. `half()` is derived from `halfu()` so it cannot drift from it.
def halfu() -> U32: 256
def half() -> F32: U32.to_f32(halfu())

def rgb(r: U32, g: U32, b: U32) -> U32:
  (r * 65536 + g * 256 + b : U32)

# `F32.to_u32` / `U32.to_f32` are primitives (declared as `law`, not `def`).
# The `def` pair in Base -- U32.from_nat / F32.to_nat -- is O(value): it
# counts up one U32.inc at a time. Easy to miss -- though swapping these in
# measured NO speedup in this program, so the reason to prefer them is the
# complexity on paper, not a win I observed.
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

# ---------- the world ----------

# The world is a terrain FUNCTION plus a tree of EDITS. A ray reads the tree
# and, wherever it finds WNone, computes the column from the terrain instead.
# Untouched, the whole world is one WNone; each edit grows one five-node path.
#
# Storing every column in the tree cost 155 ms at 512x512 after everything
# else had been tuned; the overlay costs 26, against 23 for the terrain alone.
# Same image (checksum-verified at three resolutions) and bit-exact edits.
# What the overlay alone did not fix was an edited world: while the read owned
# the nodes it chose (see wget), 300 placed blocks cost 26 ms a frame against
# 4-5 untouched, at 256x256; with the read borrowed they cost 6-8.
type World is Data:
  WNone{}
  WLeaf{bits: U32}
  WNode{q0: World, q1: World, q2: World, q3: World}

def terrain(+x: U32, +z: U32) -> U32:
  +h = (12.0 + 5.0 * F32.sin((u2f(x) * 0.26 : F32)) + 4.0 * F32.cos((u2f(z) * 0.19 : F32)) : F32)
  F32.to_u32(F32.clamp(h, 2.0, 27.0))

# a column: every level below the surface is solid
def column(+x: U32, +z: U32) -> U32:
  (U32.shln(1, U32.to_nat(terrain(x, z))) - 1 : U32)

# The world is the terrain function plus this tree of edits. It starts
# empty: a single WNone.

def sel4(bx: Bool, bz: Bool, q0: World, q1: World, q2: World, q3: World) -> World:
  match bx bz:
    case False{} False{}:
      q0
    case True{} False{}:
      q1
    case False{} True{}:
      q2
    case True{} True{}:
      q3

# read a column: one recursive walk, BORROWED. The compiler borrows a boxed
# parameter that a def only matches or passes to a borrower, so this walk
# touches no count. The old walk picked its quadrant with `Bool.pick(World, ..)`,
# and a def that returns its argument shares it: a count on every node, per
# ray, per column crossing -- the whole cost of an edited world
# (`bend guide shaders`, Ownership). Two rules shape it: `match` takes only
# parameters, so each level hands the next its quadrant bits; and the GPU
# inlines every non-recursive def, so a four-armed unrolled walk is 4^5
# copies of the leaf (the Metal compile never finished). The tree is indexed
# low bit first, so the next bits are one shift away.
def wget(+k: Nat, w: World, bx: Bool, bz: Bool, +xs: U32, +zs: U32, +x: U32, +z: U32) -> U32:
  match k w bx bz:
    case _ WNone{} _ _:
      column(x, z)
    case _ WLeaf{b} _ _:
      b
    case 0n WNode{q0, q1, q2, q3} _ _:
      0
    case 1n+j WNode{q0, q1, q2, q3} False{} False{}:
      wget(j, q0, ((xs .&. 2) > 0 : U32), ((zs .&. 2) > 0 : U32), U32.shr(xs), U32.shr(zs), x, z)
    case 1n+j WNode{q0, q1, q2, q3} True{} False{}:
      wget(j, q1, ((xs .&. 2) > 0 : U32), ((zs .&. 2) > 0 : U32), U32.shr(xs), U32.shr(zs), x, z)
    case 1n+j WNode{q0, q1, q2, q3} False{} True{}:
      wget(j, q2, ((xs .&. 2) > 0 : U32), ((zs .&. 2) > 0 : U32), U32.shr(xs), U32.shr(zs), x, z)
    case 1n+j WNode{q0, q1, q2, q3} True{} True{}:
      wget(j, q3, ((xs .&. 2) > 0 : U32), ((zs .&. 2) > 0 : U32), U32.shr(xs), U32.shr(zs), x, z)

def wread(w: World, +x: U32, +z: U32) -> U32:
  wget(5n, w, ((x .&. 1) > 0 : U32), ((z .&. 1) > 0 : U32), x, z, x, z)

# `match` only takes a parameter or a pattern-bound variable, never a computed
# one -- and Bend forbids mutual recursion, so the quadrant choice splits into
# two NON-recursive helpers that take the bits as parameters.
def setbit(+b: U32, +ybit: U32, set: Bool) -> U32:
  Bool.pick(U32, set, (b .|. ybit : U32), (b .&. U32.not(ybit) : U32))

def put4(bx: Bool, bz: Bool, n: World, q0: World, q1: World, q2: World, q3: World) -> World:
  match bx bz:
    case False{} False{}:
      WNode{n, q1, q2, q3}
    case True{} False{}:
      WNode{q0, n, q2, q3}
    case False{} True{}:
      WNode{q0, q1, n, q3}
    case True{} True{}:
      WNode{q0, q1, q2, n}

# write a column: rebuild one path, every other subtree stays shared. Once
# per edit, on the host; the same low-bit-first layout as the read.
def wmod(+k: Nat, +w: World, +xs: U32, +zs: U32, +x: U32, +z: U32, +ybit: U32, set: Bool) -> World:
  match k w:
    case _ WLeaf{b}:
      WLeaf{setbit(b, ybit, set)}
    case 0n WNone{}:
      WLeaf{setbit(column(x, z), ybit, set)}
    case 0n WNode{q0, q1, q2, q3}:
      WNode{q0, q1, q2, q3}
    case 1n+j WNone{}:
      +bx = ((xs .&. 1) > 0 : U32)
      +bz = ((zs .&. 1) > 0 : U32)
      put4(bx, bz, wmod(j, WNone{}, U32.shr(xs), U32.shr(zs), x, z, ybit, set), WNone{}, WNone{}, WNone{}, WNone{})
    case 1n+j WNode{q0, q1, q2, q3}:
      +bx = ((xs .&. 1) > 0 : U32)
      +bz = ((zs .&. 1) > 0 : U32)
      put4(bx, bz, wmod(j, sel4(bx, bz, q0, q1, q2, q3), U32.shr(xs), U32.shr(zs), x, z, ybit, set), q0, q1, q2, q3)

def inside(+vx: F32, +vy: F32, +vz: F32) -> Bool:
  (vx > (0.0 - 0.5) : F32) && (vx < 31.5 : F32) &&
  (vz > (0.0 - 0.5) : F32) && (vz < 31.5 : F32) &&
  (vy > (0.0 - 0.5) : F32) && (vy < 31.5 : F32)

def solid(+w: World, +vx: F32, +vy: F32, +vz: F32) -> Bool:
  inside(vx, vy, vz) && on(wread(w, f2u(vx), f2u(vz)), U32.shln(1, F32.to_nat(F32.max(vy, 0.0))))

# ---------- looks ----------

# The column word already holds all 32 heights, so "is the block above me
# empty?" and "am I three deep?" are bit tests on a value we already have --
# no second trip down the tree.
# `U32.shln(a, n)` is O(n) -- a recursive shl per unit of n. So nothing here
# ever shifts by a variable: the DDA carries the mask 1<<y and moves it one
# bit per y step, and "above" / "three deep" are constant shl of that mask.
def voxel_color(+bits: U32, +ymask: U32) -> U32:
  +top = Bool.not(on(bits, U32.shl(ymask)))
  +deep = on(bits, U32.shl(U32.shl(U32.shl(ymask))))
  Bool.pick(U32, deep, rgb(130, 130, 130),
  Bool.pick(U32, top, rgb(117, 176, 73), rgb(134, 96, 67)))

def scale(+c: U32, +k: F32) -> U32:
  F32.to_u32((U32.to_f32(c) * k : F32))

def dim(+c: U32, +k: F32) -> U32:
  +r = (c / 65536 : U32)
  +g = (c / 256 % 256 : U32)
  +b = (c % 256 : U32)
  rgb(scale(r, k), scale(g, k), scale(b, k))

def lit(+bits: U32, +ymask: U32, +axis: F32) -> U32:
  +k = Bool.pick(F32, (axis < 0.5 : F32), 0.68,
       Bool.pick(F32, (axis < 1.5 : F32), 1.0, 0.48))
  dim(voxel_color(bits, ymask), k)

def sky_at(+yq: U32) -> U32:
  +g = (yq * 55 / (halfu() * 2) : U32)
  rgb((110 + g : U32), (150 + g : U32), 235)

def band(+y: U32) -> U32:
  (y / 8 * 8 : U32)

# ---------- DDA over the tree ----------

# Only a step in x or z can change which column we are in, so the column is
# re-read once per crossing instead of once per voxel. With the edit overlay
# a read is usually a single WNone match plus the terrain function, so this
# matters much less than it did when every column lived in the tree.
def refetch(need: Bool, +w: World, +x: U32, +z: U32, +old: U32) -> U32:
  match need:
    case True{}:
      wread(w, x, z)
    case False{}:
      old

# the hit's colour only on a hit: Bool.pick is strict, so it would light every
# step of every ray (measured: 1 ms of 6 at 512x512)
def hit(here: Bool, +bits: U32, +ymask: U32, +axis: F32, +col: U32) -> U32:
  match here:
    case True{}:
      lit(bits, ymask, axis)
    case False{}:
      col

def dda(fuel: Nat, +w: World,
        +vx: F32, +vy: F32, +vz: F32,
        +sx: F32, +sy: F32, +sz: F32,
        +mx: F32, +my: F32, +mz: F32,
        +ex: F32, +ey: F32, +ez: F32,
        +axis: F32, +col: U32, +bits: U32, +ymask: U32) -> U32:
  match fuel:
    case 0n:
      col
    case 1n+f:
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
      # the tree is touched only on a column crossing, and never again once
      # this ray has already found its block
      dda(f, w, nvx, nvy, nvz, sx, sy, sz, nmx, nmy, nmz, ex, ey, ez, naxis, ncol,
          refetch(Bool.not(uy) && (ncol < 1 : U32), w, f2u(nvx), f2u(nvz), bits),
          nymask)

def run_dda(+w: World, +ox: F32, +oy: F32, +oz: F32,
            +dx: F32, +dy: F32, +dz: F32, +v: U32) -> U32:
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
  # 60 steps: before Bend 2.0.19 a literal fuel unrolled the whole loop into
  # its caller (bendlang/bend#886); now it is a loop either way.
  +c = dda(60n, w, vx, vy, vz,
           Bool.pick(F32, px, 1.0, (0.0 - 1.0 : F32)),
           Bool.pick(F32, py, 1.0, (0.0 - 1.0 : F32)),
           Bool.pick(F32, pz, 1.0, (0.0 - 1.0 : F32)),
           (nx / ax : F32), (ny / ay : F32), (nz / az : F32),
           (1.0 / ax : F32), (1.0 / ay : F32), (1.0 / az : F32),
           1.0, 0, wread(w, f2u(vx), f2u(vz)),
           U32.shln(1, F32.to_nat(F32.max(oy, 0.0))))
  Bool.pick(U32, (c < 1 : U32), sky_at(v), c)

# A ray that misses the 32-cube reads the tree zero times. Ported from 04,
# where it was the single biggest win.
def shoot(go: Bool, +w: World, +ox: F32, +oy: F32, +oz: F32,
          +dx: F32, +dy: F32, +dz: F32, +v: U32) -> U32:
  match go:
    case False{}:
      sky_at(v)
    case True{}:
      run_dda(w, ox, oy, oz, dx, dy, dz, v)

def clipped(+w: World, +ox: F32, +oy: F32, +oz: F32,
            +dx: F32, +dy: F32, +dz: F32, +v: U32) -> U32:
  +rx = (1.0 / F32.max(absf(dx), 0.00001) * Bool.pick(F32, (dx > 0.0 : F32), 1.0, (0.0 - 1.0 : F32)) : F32)
  +ry = (1.0 / F32.max(absf(dy), 0.00001) * Bool.pick(F32, (dy > 0.0 : F32), 1.0, (0.0 - 1.0 : F32)) : F32)
  +rz = (1.0 / F32.max(absf(dz), 0.00001) * Bool.pick(F32, (dz > 0.0 : F32), 1.0, (0.0 - 1.0 : F32)) : F32)
  +xa = ((0.0 - ox) * rx : F32)
  +xb = ((32.0 - ox) * rx : F32)
  +ya = ((0.0 - oy) * ry : F32)
  +yb = ((32.0 - oy) * ry : F32)
  +za = ((0.0 - oz) * rz : F32)
  +zb = ((32.0 - oz) * rz : F32)
  +tin  = F32.max(F32.max(F32.min(xa, xb), F32.min(ya, yb)), F32.max(F32.min(za, zb), 0.0))
  +tout = F32.min(F32.min(F32.max(xa, xb), F32.max(ya, yb)), F32.max(za, zb))
  +s = (tin + 0.002 : F32)
  shoot((tin < tout : F32), w, (ox + dx * s : F32), (oy + dy * s : F32), (oz + dz * s : F32), dx, dy, dz, v)

# ---------- the player ----------

type Game is Data:
  G{w: World, px: F32, py: F32, pz: F32, yaw: F32, pit: F32, vy: F32,
    held: U32, edge: U32, mx: U32, my: U32}

def look_x(+yaw: F32, +pit: F32) -> F32: (F32.cos(pit) * F32.sin(yaw) : F32)
def look_y(+pit: F32) -> F32: F32.sin(pit)
def look_z(+yaw: F32, +pit: F32) -> F32: (F32.cos(pit) * F32.cos(yaw) : F32)

def norm3(+x: F32, +y: F32, +z: F32) -> F32:
  F32.sqrt((x * x + y * y + z * z : F32))

# ---------- rendering one pixel ----------

def p2f(+p: U32) -> F32:
  (U32.to_f32(p) / half() - 1.0 : F32)

def shade_px(+g: Game, +pxi: U32, +pyi: U32) -> U32:
  G{w, ox, oy, oz, yaw, pit, vy, held, edge, mx, my} = g
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
  clipped(w, ox, oy, oz, (dx / n : F32), (dy / n : F32), (dz / n : F32), band(pyi))

# a crosshair straight over the middle
def cross_at(+pxi: U32, +pyi: U32) -> Bool:
  +dx = Bool.pick(U32, (pxi > halfu() : U32), (pxi - halfu() : U32), (halfu() - pxi : U32))
  +dy = Bool.pick(U32, (pyi > halfu() : U32), (pyi - halfu() : U32), (halfu() - pyi : U32))
  ((dx < 1 : U32) && (dy < 5 : U32)) || ((dy < 1 : U32) && (dx < 5 : U32))

def paint(hair: Bool, +g: Game, +pxi: U32, +pyi: U32) -> U32:
  match hair:
    case True{}:
      rgb(255, 255, 255)
    case False{}:
      shade_px(g, pxi, pyi)

def pixel(+g: Game, +pxi: U32, +pyi: U32) -> U32:
  paint(cross_at(pxi, pyi), g, pxi, pyi)

# ---------- tile, straight-line ----------

def one4(same: Bool, +k0: U32, +k1: U32, +k2: U32, +k3: U32) -> Image:
  match same:
    case True{}:
      Pix{k0}
    case False{}:
      Qua{Pix{k0}, Pix{k1}, Pix{k2}, Pix{k3}}

def t2(+g: Game, +x: U32, +y: U32) -> Image:
  +x1 = (x + 1 : U32)
  +y1 = (y + 1 : U32)
  +k0 = pixel(g, x, y)
  +k1 = pixel(g, x1, y)
  +k2 = pixel(g, x, y1)
  +k3 = pixel(g, x1, y1)
  one4(U32.is_eq(k0, k1) && U32.is_eq(k1, k2) && U32.is_eq(k2, k3), k0, k1, k2, k3)

def t4(+g: Game, +x: U32, +y: U32) -> Image:
  +x1 = (x + 2 : U32)
  +y1 = (y + 2 : U32)
  Qua{t2(g, x, y), t2(g, x1, y), t2(g, x, y1), t2(g, x1, y1)}

# fork down to 4x4 tiles: see RESOLUTION above.
def fork(+k: Nat, +g: Game, +x: U32, +y: U32) -> Image:
  match k:
    case 0n:
      t4(g, x, y)
    case 1n+e:
      +h = U32.shln(4, e)
      +x1 = (x + h : U32)
      +y1 = (y + h : U32)
      p q r s = fork(e, g, x, y) fork(e, g, x1, y) fork(e, g, x, y1) fork(e, g, x1, y1)
      Qua{p, q, r, s}

def view(+g: Game) -> Image:
  fork!(7n, g, 0, 0)

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
# Packs two voxels into one word: 0 = nothing, else 1 + prev*32768 + hit.

def pk(+x: F32, +y: F32, +z: F32) -> U32:
  ((f2u(x) * 32 + f2u(y)) * 32 + f2u(z) : U32)

def pick(fuel: Nat, +w: World,
         +vx: F32, +vy: F32, +vz: F32,
         +sx: F32, +sy: F32, +sz: F32,
         +mx: F32, +my: F32, +mz: F32,
         +ex: F32, +ey: F32, +ez: F32,
         +prev: U32, +res: U32) -> U32:
  match fuel:
    case 0n:
      res
    case 1n+f:
      +take = solid(w, vx, vy, vz) && (res < 1 : U32)
      nres = Bool.pick(U32, take, (1 + prev * 32768 + pk(vx, vy, vz) : U32), res)
      +ux = (mx < my : F32) && (mx < mz : F32)
      +uy = Bool.pick(Bool, ux, False{}, (my < mz : F32))
      +nvx = Bool.pick(F32, ux, (vx + sx : F32), vx)
      nvy = Bool.pick(F32, uy, (vy + sy : F32), vy)
      +nvz = Bool.pick(F32, ux, vz, Bool.pick(F32, uy, vz, (vz + sz : F32)))
      nmx = Bool.pick(F32, ux, (mx + ex : F32), mx)
      nmy = Bool.pick(F32, uy, (my + ey : F32), my)
      nmz = Bool.pick(F32, ux, mz, Bool.pick(F32, uy, mz, (mz + ez : F32)))
      pick(f, w, nvx, nvy, nvz, sx, sy, sz, nmx, nmy, nmz, ex, ey, ez, pk(vx, vy, vz), nres)

def aim(+w: World, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32) -> U32:
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
  pick(40n, w, vx, vy, vz,
       Bool.pick(F32, px, 1.0, (0.0 - 1.0 : F32)),
       Bool.pick(F32, py, 1.0, (0.0 - 1.0 : F32)),
       Bool.pick(F32, pz, 1.0, (0.0 - 1.0 : F32)),
       (nx / ax : F32), (ny / ay : F32), (nz / az : F32),
       (1.0 / ax : F32), (1.0 / ay : F32), (1.0 / az : F32),
       0, 0)

# unpack: index -> x, y, z
def ix_x(+i: U32) -> U32: (i / 1024 : U32)
def ix_y(+i: U32) -> U32: (i / 32 % 32 : U32)
def ix_z(+i: U32) -> U32: (i % 32 : U32)

def apply_edit(act: Bool, w: World, +idx: U32, set: Bool) -> World:
  match act:
    case False{}:
      w
    case True{}:
      wmod(5n, w, ix_x(idx), ix_z(idx), ix_x(idx), ix_z(idx), U32.shln(1, U32.to_nat(ix_y(idx))), set)

# ---------- one tick ----------
# The player is 1.8 blocks tall with the eye at 1.6, so they stand in the
# block of `py - 1.6` and the one of `py + 0.2`. Walking tests those two
# per axis and stops at a wall (the feet test sits 0.05 up, so the block
# under the feet never counts). Gravity pulls `vy`; landing snaps the feet
# onto the block; space pushes off it. A block is never placed on the player.

def eye() -> F32: 1.6

def blocked(+w: World, +x: F32, +y: F32, +z: F32) -> Bool:
  solid(w, x, (y - 1.55 : F32), z) || solid(w, x, (y + 0.2 : F32), z)

def ax2(+held: U32, +negbit: U32, +posbit: U32) -> F32:
  (Bool.pick(F32, on(held, posbit), 1.0, 0.0)
   - Bool.pick(F32, on(held, negbit), 1.0, 0.0) : F32)

def step(g: Game) -> Game:
  G{+w, +px, +py, +pz, yaw, pit, vy, +held, +edge, mx, my} = g
  +nyaw = (yaw + 0.055 * ax2(held, 64, 128) : F32)
  +npit = F32.clamp((pit + 0.045 * ax2(held, 32, 16) : F32), (0.0 - 1.45 : F32), 1.45)
  +sy = F32.sin(nyaw)
  +cy = F32.cos(nyaw)
  +fw = ax2(held, 4, 1)
  +st = ax2(held, 2, 8)
  # walk, one axis at a time
  +tx = F32.clamp((px + 0.16 * (fw * sy + st * cy) : F32), 0.5, 31.5)
  +npx = Bool.pick(F32, blocked(w, tx, py, pz), px, tx)
  +tz = F32.clamp((pz + 0.16 * (fw * cy - st * sy) : F32), 0.5, 31.5)
  +npz = Bool.pick(F32, blocked(w, npx, py, tz), pz, tz)
  # fall, land, jump
  +vy1 = F32.max((vy - 0.012 : F32), (0.0 - 0.9 : F32))
  +ty = (py + vy1 : F32)
  +feet = (ty - eye() : F32)
  +land = (vy1 < 0.0 : F32) && solid(w, npx, feet, npz)
  +bump = (vy1 > 0.0 : F32) && solid(w, npx, (ty + 0.2 : F32), npz)
  +npy = F32.clamp(Bool.pick(F32, land, (floorf(feet) + 1.0 + eye() : F32),
                             Bool.pick(F32, bump, py, ty)), eye(), 31.5)
  +nvy = Bool.pick(F32, land && on(held, 8192), 0.2,
                   Bool.pick(F32, land || bump, 0.0, vy1))
  # what the crosshair is on
  +hit = aim(w, npx, npy, npz, look_x(nyaw, npit), look_y(npit), look_z(nyaw, npit))
  +got = (hit > 0 : U32)
  +at = ((hit - 1) / 32768 : U32)
  +onme = U32.is_eq(at, pk(npx, (npy - 1.55 : F32), npz)) || U32.is_eq(at, pk(npx, (npy + 0.2 : F32), npz))
  +brk = got && on(edge, 1024)
  +put = got && on(edge, 2048) && Bool.not(onme)
  +w1 = apply_edit(brk, w, ((hit - 1) % 32768 : U32), False{})
  +w2 = apply_edit(put, w1, at, True{})
  G{w2, npx, npy, npz, nyaw, npit, nvy, held, (edge .&. 4096 : U32), mx, my}

def alive(g: Game) -> IO(Maybe<Game>):
  G{w, px, py, pz, yaw, pit, vy, held, +edge, mx, my} = g
  Bool.pick(IO(Maybe<Game>), on(edge, 4096),
    IO.pure(Maybe<Game>, None{}),
    IO.pure(Maybe<Game>, Some{G{w, px, py, pz, yaw, pit, vy, held, 0, mx, my}}))

def tick(evs: List<Event>, g: Game) -> IO(Maybe<Game>):
  alive(step(feed(evs, g)))

def start() -> Game:
  G{WNone{}, 16.5, 22.0, 4.5, 0.0, (0.0 - 0.55 : F32), 0.0, 0, 0, 0, 0}

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("WASD move | space jump | drag to look | click break | right click place | J/L break/place | Esc quit")
    App.run(~Game, ~App{+g => (g, view(g)), tick}, "Bendcraft", 512, 512, start())
