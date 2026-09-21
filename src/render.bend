import Base
import ./util.bend as Util
import ./world.bend as World

# THE RENDER: a ray per pixel through the ring of columns, on the GPU.
#
# RESOLUTION is a runtime value: the camera carries the render's width and
# height, `frame` forks over 4x4 leaves in a square of 4 << k a side that
# covers the larger side, and what lies past the edge is one Pix with no
# ray. The window may be bigger than the render by a power of two: its
# shader stops at the first Pix it meets, so a coarser image scales up by
# itself.

def rgb(r: U32, g: U32, b: U32) -> U32:
  (r * 65536 + g * 256 + b : U32)

# value noise: a hash on a lattice, blended smoothly. The texture's hash
# is a product, fine at the eight tile coordinates; the terrain's mixes
# its bits, since a product is a ramp along each axis at any distance.
def h01(+i: U32, +j: U32) -> F32:
  (Util.u2f((U32.xor((i * 73856093 : U32), (j * 19349663 : U32)) / 256 % 256 : U32)) / 255.0 : F32)

def vnoise(+u: F32, +v: F32) -> F32:
  +i = Util.f2u(u)
  +j = Util.f2u(v)
  +fu = Util.smooth((u - Util.u2f(i) : F32))
  +fv = Util.smooth((v - Util.u2f(j) : F32))
  +a = h01(i, j)
  +b = h01((i + 1 : U32), j)
  +c = h01(i, (j + 1 : U32))
  +d = h01((i + 1 : U32), (j + 1 : U32))
  ((a * (1.0 - fu) + b * fu) * (1.0 - fv) + (c * (1.0 - fu) + d * fu) * fv : F32)

# ---------- looks ----------

# `U32.shln(a, n)` is O(n) -- a recursive shl per unit of n. So nothing here
# ever shifts by a variable: the DDA carries the mask 1<<y and moves it one
# bit per y step, and the type's nibble is picked with a select.

def scale(+c: U32, +k: F32) -> U32:
  F32.to_u32(F32.min((U32.to_f32(c) * k : F32), 255.0))

def dim(+c: U32, +k: F32) -> U32:
  +r = (c / 65536 : U32)
  +g = (c / 256 % 256 : U32)
  +b = (c % 256 : U32)
  rgb(scale(r, k), scale(g, k), scale(b, k))

def sky_at(+yq: U32, +rh: U32) -> U32:
  +g = (yq * 55 / rh : U32)
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
      Array.get(U32, w, World.col_at(base, x, z))
    case False{}:
      (w, old)

# the hit is a word: 0 none, else 1 + the face's axis; its look comes after
# the loop (a match, not the strict Bool.pick, so only a hit pays for it)
def hit(here: Bool, +axis: F32, +col: U32) -> U32:
  match here:
    case True{}:
      (1 + Util.f2u(axis) : U32)
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
      +here = World.inside(vx, vy, vz) && Util.on(bits, ymask) && (col < 1 : U32)
      +ncol = hit(here, axis, col)
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
          refetch(Bool.not(uy) && (ncol < 1 : U32), w, base, Util.f2u(nvx), Util.f2u(nvz), bits))

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
  F32.to_u32((Util.u2f(x) * (1.0 - f) + Util.u2f(y) * f : F32))

def mix(+a: U32, +b: U32, +f: F32) -> U32:
  rgb(lerp((a / 65536 : U32), (b / 65536 : U32), f),
      lerp((a / 256 % 256 : U32), (b / 256 % 256 : U32), f),
      lerp((a % 256 : U32), (b % 256 : U32), f))

# a tile of 8x8 texels, the same on every block: each texel is one of four
# shades, from a smooth noise sampled at its centre, so the shades come in
# patches, as pixel art does
def texture(+u: F32, +v: F32) -> F32:
  +i = (Util.u2f(Util.f2u((Util.fracf(u) * 8.0 : F32))) + 0.5 : F32)
  +j = (Util.u2f(Util.f2u((Util.fracf(v) * 8.0 : F32))) + 0.5 : F32)
  +n = (0.6 * vnoise((i * 0.55 : F32), (j * 0.55 : F32)) + 0.4 * vnoise((i * 1.3 + 5.0 : F32), (j * 1.3 + 9.0 : F32)) : F32)
  (0.76 + 0.12 * Util.u2f(Util.f2u((n * 3.99 : F32))) : F32)

# grass green, dirt brown, stone grey; a grass block's side is dirt below
# the top quarter
# the colour of a block type: 0 grass (dirt on the sides under a green
# band), 1 dirt, 2 stone, 3 sand, 4 wood (rings on top), 5 leaves,
# 6 brick, 7 snow
def blockcol(+what: U32, +side: Bool, +yf: F32) -> U32:
  +grass_side = side && (yf <= 0.72 : F32)
  Bool.pick(U32, (what < 4 : U32),
    Bool.pick(U32, (what < 2 : U32),
      Bool.pick(U32, U32.is_eq(what, 0), Bool.pick(U32, grass_side, rgb(134, 96, 67), rgb(117, 176, 73)), rgb(134, 96, 67)),
      Bool.pick(U32, U32.is_eq(what, 2), rgb(130, 130, 130), rgb(219, 205, 150))),
    Bool.pick(U32, (what < 6 : U32),
      Bool.pick(U32, U32.is_eq(what, 4), Bool.pick(U32, side, rgb(107, 76, 44), rgb(160, 130, 80)), rgb(58, 125, 42)),
      Bool.pick(U32, U32.is_eq(what, 6), rgb(160, 70, 55), Bool.pick(U32, side, rgb(210, 220, 230), rgb(240, 245, 250)))))

# the sun: direction (0.48, 0.80, 0.36), so every step is +1 and the
# crossings advance by 1 / that component
def shadow_end(got: Bool, r: Array<U32> & U32) -> Array<U32> & Bool:
  (w, b) = r
  (w, got)

def shadow(fuel: Nat, +base: U32, +vx: F32, +vy: F32, +vz: F32, +mx: F32, +my: F32, +mz: F32,
           +ymask: U32, +got: Bool, r: Array<U32> & U32) -> Array<U32> & Bool:
  match fuel:
    case 0n:
      shadow_end(got, r)
    case 1n+f:
      (w, +bits) = r
      +here = got || (World.inside(vx, vy, vz) && Util.on(bits, ymask))
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
             refetch(Bool.not(uy) && Bool.not(here), w, base, Util.f2u(nvx), Util.f2u(nvz), bits))

def run_shadow(w: Array<U32>, +base: U32, +ox: F32, +oy: F32, +oz: F32) -> Array<U32> & Bool:
  +vx = Util.floorf(ox)
  +vy = Util.floorf(oy)
  +vz = Util.floorf(oz)
  shadow(24n, base, vx, vy, vz,
         ((vx + 1.0 - ox) * 2.0833 : F32), ((vy + 1.0 - oy) * 1.25 : F32), ((vz + 1.0 - oz) * 2.7778 : F32),
         U32.shln(1, F32.to_nat(F32.max(oy, 0.0))), False{},
         Array.get(U32, w, World.col_at(base, Util.f2u(vx), Util.f2u(vz))))

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
  Bool.pick(F32, s1 && s2, 0.4, (1.0 - 0.2 * Util.u2f(n) : F32))

def ao_fin(+v: U32, +col: U32, +f: F32, +sun: F32, +m: U32, +fu: F32, +fw: F32, r: Array<U32> & Bool) -> Array<U32> & U32:
  (w, s) = r
  +m8 = Bool.pick(U32, s, (m .|. 128 : U32), m)
  +pp = vao(Util.on(m8, 1), Util.on(m8, 4), Util.on(m8, 16))
  +mp = vao(Util.on(m8, 2), Util.on(m8, 4), Util.on(m8, 32))
  +pm = vao(Util.on(m8, 1), Util.on(m8, 8), Util.on(m8, 64))
  +mm = vao(Util.on(m8, 2), Util.on(m8, 8), Util.on(m8, 128))
  +ao = ((mm * (1.0 - fu) + pm * fu) * (1.0 - fw) + (mp * (1.0 - fu) + pp * fu) * fw : F32)
  (w, mix(dim(col, (ao * sun : F32)), v, (f * f : F32)))

def ao7(+v: U32, +col: U32, +f: F32, +sun: F32, +base: U32, +m: U32, +ox: F32, +oy: F32, +oz: F32,
        +ux: F32, +uy: F32, +uz: F32, +ex: F32, +ey: F32, +ez: F32, +fu: F32, +fw: F32,
        r: Array<U32> & Bool) -> Array<U32> & U32:
  (w, s) = r
  ao_fin(v, col, f, sun, Bool.pick(U32, s, (m .|. 64 : U32), m), fu, fw,
         World.solid(w, base, (ox - ux - ex : F32), (oy - uy - ey : F32), (oz - uz - ez : F32)))

def ao6(+v: U32, +col: U32, +f: F32, +sun: F32, +base: U32, +m: U32, +ox: F32, +oy: F32, +oz: F32,
        +ux: F32, +uy: F32, +uz: F32, +ex: F32, +ey: F32, +ez: F32, +fu: F32, +fw: F32,
        r: Array<U32> & Bool) -> Array<U32> & U32:
  (w, s) = r
  ao7(v, col, f, sun, base, Bool.pick(U32, s, (m .|. 32 : U32), m), ox, oy, oz, ux, uy, uz, ex, ey, ez, fu, fw,
      World.solid(w, base, (ox + ux - ex : F32), (oy + uy - ey : F32), (oz + uz - ez : F32)))

def ao5(+v: U32, +col: U32, +f: F32, +sun: F32, +base: U32, +m: U32, +ox: F32, +oy: F32, +oz: F32,
        +ux: F32, +uy: F32, +uz: F32, +ex: F32, +ey: F32, +ez: F32, +fu: F32, +fw: F32,
        r: Array<U32> & Bool) -> Array<U32> & U32:
  (w, s) = r
  ao6(v, col, f, sun, base, Bool.pick(U32, s, (m .|. 16 : U32), m), ox, oy, oz, ux, uy, uz, ex, ey, ez, fu, fw,
      World.solid(w, base, (ox - ux + ex : F32), (oy - uy + ey : F32), (oz - uz + ez : F32)))

def ao4(+v: U32, +col: U32, +f: F32, +sun: F32, +base: U32, +m: U32, +ox: F32, +oy: F32, +oz: F32,
        +ux: F32, +uy: F32, +uz: F32, +ex: F32, +ey: F32, +ez: F32, +fu: F32, +fw: F32,
        r: Array<U32> & Bool) -> Array<U32> & U32:
  (w, s) = r
  ao5(v, col, f, sun, base, Bool.pick(U32, s, (m .|. 8 : U32), m), ox, oy, oz, ux, uy, uz, ex, ey, ez, fu, fw,
      World.solid(w, base, (ox + ux + ex : F32), (oy + uy + ey : F32), (oz + uz + ez : F32)))

def ao3(+v: U32, +col: U32, +f: F32, +sun: F32, +base: U32, +m: U32, +ox: F32, +oy: F32, +oz: F32,
        +ux: F32, +uy: F32, +uz: F32, +ex: F32, +ey: F32, +ez: F32, +fu: F32, +fw: F32,
        r: Array<U32> & Bool) -> Array<U32> & U32:
  (w, s) = r
  ao4(v, col, f, sun, base, Bool.pick(U32, s, (m .|. 4 : U32), m), ox, oy, oz, ux, uy, uz, ex, ey, ez, fu, fw,
      World.solid(w, base, (ox - ex : F32), (oy - ey : F32), (oz - ez : F32)))

def ao2(+v: U32, +col: U32, +f: F32, +sun: F32, +base: U32, +m: U32, +ox: F32, +oy: F32, +oz: F32,
        +ux: F32, +uy: F32, +uz: F32, +ex: F32, +ey: F32, +ez: F32, +fu: F32, +fw: F32,
        r: Array<U32> & Bool) -> Array<U32> & U32:
  (w, s) = r
  ao3(v, col, f, sun, base, Bool.pick(U32, s, (m .|. 2 : U32), m), ox, oy, oz, ux, uy, uz, ex, ey, ez, fu, fw,
      World.solid(w, base, (ox + ex : F32), (oy + ey : F32), (oz + ez : F32)))

def ao1(+v: U32, +col: U32, +f: F32, +sun: F32, +base: U32, +ox: F32, +oy: F32, +oz: F32,
        +ux: F32, +uy: F32, +uz: F32, +ex: F32, +ey: F32, +ez: F32, +fu: F32, +fw: F32,
        r: Array<U32> & Bool) -> Array<U32> & U32:
  (w, s) = r
  ao2(v, col, f, sun, base, Bool.pick(U32, s, 1, 0), ox, oy, oz, ux, uy, uz, ex, ey, ez, fu, fw,
      World.solid(w, base, (ox - ux : F32), (oy - uy : F32), (oz - uz : F32)))

# after the sun: the first neighbour read
def after_sun(+v: U32, +col: U32, +f: F32, +base: U32, +ox: F32, +oy: F32, +oz: F32,
              +ux: F32, +uy: F32, +uz: F32, +ex: F32, +ey: F32, +ez: F32, +fu: F32, +fw: F32,
              r: Array<U32> & Bool) -> Array<U32> & U32:
  (w, dark) = r
  ao1(v, col, f, Bool.pick(F32, dark, 0.6, 1.0), base, ox, oy, oz, ux, uy, uz, ex, ey, ez, fu, fw,
      World.solid(w, base, (ox + ux : F32), (oy + uy : F32), (oz + uz : F32)))

# the type read: one word through the handle, then the look
def typed(+v: U32, +base: U32, +hy: U32, +side: Bool, +yf: F32, +u: F32, +wf: F32, +tone: F32, +f: F32,
          +cx: F32, +cy: F32, +cz: F32, +ux: F32, +uz: F32, +ey: F32, +ez: F32, +fu: F32, +fw: F32,
          +sunny: Bool, +sx: F32, +sy: F32, +sz: F32, r: Array<U32> & U32) -> Array<U32> & U32:
  (w, word) = r
  +what = World.nib_at(word, hy)
  +col = dim(blockcol(what, side, yf), (tone * texture(u, wf) : F32))
  after_sun(v, col, f, base, cx, cy, cz, ux, 0.0, uz, 0.0, ey, ez, fu, fw,
            shadow_if(sunny, w, base, sx, sy, sz))

def shade_go(sky: Bool, w: Array<U32>, +base: U32, +v: U32, +ox: F32, +oy: F32, +oz: F32,
             +dx: F32, +dy: F32, +dz: F32, +c: U32, +t: F32) -> Array<U32> & U32:
  match sky:
    case True{}:
      (w, v)
    case False{}:
      +axis = (c - 1 : U32)
      +px = (ox + dx * t : F32)
      +py = (oy + dy * t : F32)
      +pz = (oz + dz * t : F32)
      # the face's coordinates: u along z on an x face and along x otherwise,
      # w along z on a y face and along y otherwise
      +ax = U32.is_eq(axis, 0)
      +ay = U32.is_eq(axis, 1)
      +u = Bool.pick(F32, ax, pz, px)
      +wf = Bool.pick(F32, ay, pz, py)
      +tone = Bool.pick(F32, ax, 0.8, Bool.pick(F32, ay, 1.0, 0.7))
      +f = F32.min((t / 48.0 : F32), 1.0)
      # O, the air cell before the face: floor of p, except along the face's
      # axis, where p sits on the boundary and O is the side the ray came from
      +bx = Util.floorf((px + 0.5 : F32))
      +by = Util.floorf((py + 0.5 : F32))
      +bz = Util.floorf((pz + 0.5 : F32))
      +cx = Bool.pick(F32, ax, Bool.pick(F32, (dx > 0.0 : F32), (bx - 1.0 : F32), bx), Util.floorf(px))
      +cy = Bool.pick(F32, ay, Bool.pick(F32, (dy > 0.0 : F32), (by - 1.0 : F32), by), Util.floorf(py))
      +cz = Bool.pick(F32, U32.is_eq(axis, 2), Bool.pick(F32, (dz > 0.0 : F32), (bz - 1.0 : F32), bz), Util.floorf(pz))
      # the block itself is on the other side of the face
      +hx = Bool.pick(F32, ax, Bool.pick(F32, (dx > 0.0 : F32), bx, (bx - 1.0 : F32)), cx)
      +hy = Bool.pick(F32, ay, Bool.pick(F32, (dy > 0.0 : F32), by, (by - 1.0 : F32)), cy)
      +hz = Bool.pick(F32, U32.is_eq(axis, 2), Bool.pick(F32, (dz > 0.0 : F32), bz, (bz - 1.0 : F32)), cz)
      # the unit steps of u and w in space
      +ux = Bool.pick(F32, ax, 0.0, 1.0)
      +uz = Bool.pick(F32, ax, 1.0, 0.0)
      +ey = Bool.pick(F32, ay, 0.0, 1.0)
      +ez = Bool.pick(F32, ay, 1.0, 0.0)
      # where on the face, for the blend of the four vertices
      +fu = Util.fracf(u)
      +fw = Util.fracf(wf)
      # the face looks at the sun when the ray came against that axis; the
      # shadow ray starts a hair before the face, in O
      +da = Bool.pick(F32, ax, dx, Bool.pick(F32, ay, dy, dz))
      +nudge = Bool.pick(F32, (da > 0.0 : F32), (0.0 - 0.01 : F32), 0.01)
      typed(v, base, Util.f2u(hy), Bool.not(ay), Util.fracf(py), u, wf, tone, f,
            cx, cy, cz, ux, uz, ey, ez, fu, fw, (da < 0.0 : F32),
            Bool.pick(F32, ax, (px + nudge : F32), px),
            Bool.pick(F32, ay, (py + nudge : F32), py),
            Bool.pick(F32, U32.is_eq(axis, 2), (pz + nudge : F32), pz),
            Array.get(U32, w, (World.col_at(base, Util.f2u(hx), Util.f2u(hz)) + 1 + Util.f2u(hy) / 8 : U32)))

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
  +vx = Util.floorf(F32.max(ox, 0.0))
  +vy = Util.floorf(F32.max(oy, 0.0))
  +vz = Util.floorf(F32.max(oz, 0.0))
  +px = (dx > 0.0 : F32)
  +py = (dy > 0.0 : F32)
  +pz = (dz > 0.0 : F32)
  +ax = F32.max(Util.absf(dx), 0.00001)
  +ay = F32.max(Util.absf(dy), 0.00001)
  +az = F32.max(Util.absf(dz), 0.00001)
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
           Array.get(U32, w, World.col_at(base, Util.f2u(vx), Util.f2u(vz)))))

# A ray that misses the loaded box reads the world zero times.
def shoot(go: Bool, w: Array<U32>, +base: U32, +ox: F32, +oy: F32, +oz: F32,
          +dx: F32, +dy: F32, +dz: F32, +v: U32) -> Array<U32> & U32:
  match go:
    case False{}:
      (w, v)
    case True{}:
      run_dda(w, base, ox, oy, oz, dx, dy, dz, v)

def clipped(w: Array<U32>, +base: U32, +ox: F32, +oy: F32, +oz: F32,
            +dx: F32, +dy: F32, +dz: F32, +v: U32) -> Array<U32> & U32:
  +rx = (1.0 / F32.max(Util.absf(dx), 0.00001) * Bool.pick(F32, (dx > 0.0 : F32), 1.0, (0.0 - 1.0 : F32)) : F32)
  +ry = (1.0 / F32.max(Util.absf(dy), 0.00001) * Bool.pick(F32, (dy > 0.0 : F32), 1.0, (0.0 - 1.0 : F32)) : F32)
  +rz = (1.0 / F32.max(Util.absf(dz), 0.00001) * Bool.pick(F32, (dz > 0.0 : F32), 1.0, (0.0 - 1.0 : F32)) : F32)
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
# `v` down the leaf is the row's sky colour, ready for the fog.
type Cam is Data:
  Cam{px: F32, py: F32, pz: F32, yaw: F32, pit: F32, base: U32, sel: U32, rw: U32, rh: U32}

def look_x(+yaw: F32, +pit: F32) -> F32: (F32.cos(pit) * F32.sin(yaw) : F32)
def look_y(+pit: F32) -> F32: F32.sin(pit)
def look_z(+yaw: F32, +pit: F32) -> F32: (F32.cos(pit) * F32.cos(yaw) : F32)

def norm3(+x: F32, +y: F32, +z: F32) -> F32:
  F32.sqrt((x * x + y * y + z * z : F32))

# the screen in the camera's units: the height spans -1..1, the width by
# its aspect
def p2f(+p: U32, +size: U32, +rh: U32) -> F32:
  ((U32.to_f32((p * 2 : U32)) - U32.to_f32(size)) / U32.to_f32(rh) : F32)

def shade_px(+cam: Cam, w: Array<U32>, +pxi: U32, +pyi: U32) -> Array<U32> & U32:
  Cam{ox, oy, oz, yaw, pit, base, sel, +rw, +rh} = cam
  +u = p2f(pxi, rw, rh)
  +v = p2f(pyi, rh, rh)
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
  clipped(w, base, ox, oy, oz, (dx / n : F32), (dy / n : F32), (dz / n : F32), sky_at(band(pyi), rh))

# a crosshair straight over the middle
def cross_at(+pxi: U32, +pyi: U32, +rw: U32, +rh: U32) -> Bool:
  +hx = (rw / 2 : U32)
  +hy = (rh / 2 : U32)
  +dx = Bool.pick(U32, (pxi > hx : U32), (pxi - hx : U32), (hx - pxi : U32))
  +dy = Bool.pick(U32, (pyi > hy : U32), (pyi - hy : U32), (hy - pyi : U32))
  ((dx < 1 : U32) && (dy < 5 : U32)) || ((dy < 1 : U32) && (dx < 5 : U32))

# the hotbar: the eight block types in a row along the bottom, 20 px each
# 4 apart, the chosen one framed in white
def slot_at(+pxi: U32, +pyi: U32, +rw: U32, +rh: U32) -> U32:
  +x0 = (rw / 2 - 94 : U32)
  +y0 = (rh - 30 : U32)
  +inx = (pxi >= x0 : U32) && (pxi < (x0 + 188 : U32) : U32)
  +iny = (pyi >= y0 : U32) && (pyi < (y0 + 20 : U32) : U32)
  +inslot = ((pxi - x0) % 24 < 20 : U32)
  Bool.pick(U32, inx && iny && inslot, ((pxi - x0) / 24 + 1 : U32), 0)

def slot_col(+sel: U32, +slot: U32, +pxi: U32, +pyi: U32, +rw: U32, +rh: U32) -> U32:
  +i = (slot - 1 : U32)
  +lx = ((pxi - (rw / 2 - 94)) % 24 : U32)
  +ly = (pyi - (rh - 30) : U32)
  +border = (lx < 2 : U32) || (lx >= 18 : U32) || (ly < 2 : U32) || (ly >= 18 : U32)
  Bool.pick(U32, border, Bool.pick(U32, U32.is_eq(i, sel), rgb(255, 255, 255), rgb(40, 40, 40)),
            blockcol(i, False{}, 1.0))

# what lies over the scene at this pixel: 0 nothing, else 1 + the colour
def hud(+sel: U32, +pxi: U32, +pyi: U32, +rw: U32, +rh: U32) -> U32:
  +slot = slot_at(pxi, pyi, rw, rh)
  Bool.pick(U32, cross_at(pxi, pyi, rw, rh), (1 + rgb(255, 255, 255) : U32),
    Bool.pick(U32, (slot > 0 : U32), (1 + slot_col(sel, slot, pxi, pyi, rw, rh) : U32), 0))

def hud_of(+cam: Cam, +pxi: U32, +pyi: U32) -> U32:
  Cam{ox, oy, oz, yaw, pit, base, sel, rw, rh} = cam
  hud(sel, pxi, pyi, rw, rh)

def paint(over: Bool, +code: U32, +cam: Cam, w: Array<U32>, +pxi: U32, +pyi: U32) -> Array<U32> & U32:
  match over:
    case True{}:
      (w, (code - 1 : U32))
    case False{}:
      shade_px(cam, w, pxi, pyi)

def pixel(+cam: Cam, w: Array<U32>, +pxi: U32, +pyi: U32) -> Array<U32> & U32:
  +code = hud_of(cam, pxi, pyi)
  paint((code > 0 : U32), code, cam, w, pxi, pyi)

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

# the tree of a frame: see fork below
def pair(l: Array<U32> & Image, r: Array<U32> & Image) -> Array<U32> & Image:
  (wl, p) = l
  (wr, q) = r
  (Array.join(U32, wl, wr), Qua{p, q, Pix{0}, Pix{0}})

def solo(l: Array<U32> & Image) -> Array<U32> & Image:
  (wl, p) = l
  (wl, Qua{p, Pix{0}, Pix{0}, Pix{0}})

def merge_fin(p: Image, q: Image, j: Image) -> Image:
  match j:
    case Qua{r, s, c, d}:
      Qua{p, q, r, s}
    case Pix{z}:
      Qua{p, q, Pix{0}, Pix{0}}

def merge(i: Image, j: Image) -> Image:
  match i:
    case Qua{p, q, a, b}:
      merge_fin(p, q, j)
    case Pix{c}:
      Pix{c}

def quad2(t: Array<U32> & Image, b: Array<U32> & Image) -> Array<U32> & Image:
  (wt, i) = t
  (wb, j) = b
  (Array.join(U32, wt, wb), merge(i, j))

def top(t: Array<U32> & Image) -> Array<U32> & Image:
  (wt, i) = t
  (wt, merge(i, Pix{0}))

# The tree of a frame is binary: a node at f = 2k is a square of 2h = 4 * 2^k
# pixels and splits into its top and bottom rows, a row (f odd) into its left
# and right squares of half h. A node exists only if its corner is inside
# the render, and v says whether its second half is: a node with one half
# inside runs that half in place, without a fork. The shape is for the GPU
# runtime, which grows a frontier of tasks two-way a turn until its 128
# lanes a group hold one each, then runs each task on its lane to the end:
# a two-way tree fills the frontier with tasks of one size, and a half
# that never becomes a task never skews it. The four-way tree, pruned,
# left some lanes 64 leaves and took 110-150 ms on a 1470 x 796 frame
# where this takes 16; unpruned it took 46.
@unsafe
def fork(+f: Nat, +wide: Bool, v: Bool, +cam: Cam, +w: Array<U32>, +rw: U32, +rh: U32, +h: U32, +x: U32, +y: U32) -> Array<U32> & Image:
  match f:
    case 0n:
      t4(cam, w, x, y)
    case 1n+g:
      match wide:
        case True{}:
          match v:
            case True{}:
              +h2 = (h / 2 : U32)
              +vy = ((y + h2 : U32) < rh : U32)
              l r = fork(g, False{}, vy, cam, w, rw, rh, h2, x, y) fork(g, False{}, vy, cam, w, rw, rh, h2, (x + h : U32), y)
              pair(l, r)
            case False{}:
              +h2 = (h / 2 : U32)
              solo(fork(g, False{}, ((y + h2 : U32) < rh : U32), cam, w, rw, rh, h2, x, y))
        case False{}:
          match v:
            case True{}:
              +vx = ((x + h : U32) < rw : U32)
              t b = fork(g, True{}, vx, cam, w, rw, rh, h, x, y) fork(g, True{}, vx, cam, w, rw, rh, h, x, (y + h : U32))
              quad2(t, b)
            case False{}:
              top(fork(g, True{}, ((x + h : U32) < rw : U32), cam, w, rw, rh, h, x, y))

# the levels of fork that cover the larger side with 4x4 leaves
def depth_at(fuel: Nat, +side: U32, +m: U32, +k: U32) -> U32:
  match fuel:
    case 0n:
      k
    case 1n+f:
      Bool.pick(U32, (side >= m : U32), k, depth_at(f, (side * 2 : U32), m, (k + 1 : U32)))

def depth(+rw: U32, +rh: U32) -> Nat:
  U32.to_nat(depth_at(12n, 4, U32.max(rw, rh), 0))

# the frame: one `!` over the lane cube, the camera shared as Data and the
# ring as the array both sides may read
@unsafe
def frame(+cam: Cam, +ring: Array<U32>, +rw: U32, +rh: U32) -> Array<U32> & Image:
  +d = depth(rw, rh)
  +h = U32.shln(2, d)
  fork!((d + d : Nat), False{}, (h < rh : U32), cam, ring, rw, rh, h, 0, 0)
