import Base
import ./util.bend as Util
import ./world.bend as World
import ./day.bend as Day
import ./sky.bend as Sky
import ./inventory.bend as Inventory
import ./water.bend as Water

# THE RENDER: a ray per pixel through the ring of columns, on the GPU.
#
# RESOLUTION is a runtime value: the camera carries the render's width and
# height, `frame` forks over 4x4 leaves in a square of 4 << k a side that
# covers the larger side, and what lies past the edge is one Pix with no
# ray. The window may be bigger than the render by a power of two: its
# shader stops at the first Pix it meets, so a coarser image scales up by
# itself.

def rgb(r: U32, g: U32, b: U32) -> U32:
  Sky.rgb(r, g, b)

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

# The dry specialization keeps water loads out of the profile's off row.
# Both specializations use this same loop and the same fixed fuel.
type Column is Data:
  Column{solid: U32, water: U32}

def water_word_fin(bits: U32, r: Array<U32> & U32) -> Array<U32> & Column:
  (w, water) = r
  (w, Column{bits, water})

def water_word(on: Bool, +slot: U32, r: Array<U32> & U32) -> Array<U32> & Column:
  match on:
    case False{}:
      (w, bits) = r
      (w, Column{bits, 0})
    case True{}:
      (w, bits) = r
      water_word_fin(bits, Array.get(U32, w, (slot + 5 : U32)))

def column_words(~water: Bool, w: Array<U32>, +slot: U32) -> Array<U32> & Column:
  water_word(water, slot, Array.get(U32, w, slot))

def refetch_water(~water: Bool, need: Bool, w: Array<U32>, +base: U32, +x: U32, +z: U32,
                  old: Column) -> Array<U32> & Column:
  match need:
    case True{}: column_words(~water, w, World.col_at(base, x, z))
    case False{}: (w, old)

type Ray is Data:
  Ray{hit: U32, t: F32, water: Water.Trace}

# The hit word carries six step bits above the two face bits, then the
# first-water-top bit. Reflection needs no extra word through the DDA.
def dda_end(+col: U32, +n: U32, t: F32, tr: Water.Trace, r: Array<U32> & Column) -> Array<U32> & Ray:
  (w, bits) = r
  (w, Ray{(col + n * 4 : U32), t, tr})

# The loop walks its 60 steps whatever happens, the state frozen after the
# hit: an exit at the hit (or on leaving the box) walked a third of the
# steps and made the frame slower, 15 -> 17 ms at 1470 x 796 and 28 -> 32
# at 1920 x 1080 (2026-09-21, the same checksums), since the lanes of a
# SIMD group then leave the loop at different steps and the runtime's
# switch over segments runs them one case at a time. Uniform beats less.
def dda(~water: Bool, fuel: Nat, +base: U32,
        +vx: F32, +vy: F32, +vz: F32,
        +sx: F32, +sy: F32, +sz: F32,
        +mx: F32, +my: F32, +mz: F32,
        +ex: F32, +ey: F32, +ez: F32,
        +axis: F32, +col: U32, +t: F32, +n: U32, +ymask: U32, +tr: Water.Trace, r: Array<U32> & Column) -> Array<U32> & Ray:
  match fuel:
    case 0n:
      dda_end(col, n, t, tr, r)
    case 1n+f:
      (w, words) = r
      Column{+bits, +wetbits} = words
      +inside = World.inside(vx, vy, vz)
      +here = inside && Util.on(bits, ymask) && (col < 1 : U32)
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
      +nt = Bool.pick(F32, (ncol < 1 : U32), Bool.pick(F32, ux, mx, Bool.pick(F32, uy, my, mz)), t)
      # the steps before the hit, for the profile
      +wet = inside && (ncol < 1 : U32) && Util.on(wetbits, ymask)
      nn = Water.crossed_top(water, wet, t, nt, axis, sy, tr,
        Bool.pick(U32, (ncol < 1 : U32), (n + 1 : U32), n))
      dda(~water, f, base, nvx, nvy, nvz, sx, sy, sz, nmx, nmy, nmz, ex, ey, ez, naxis, ncol, nt, nn, nymask,
          Water.crossed(water, wet, t, nt, tr),
          refetch_water(~water, Bool.not(uy) && (ncol < 1 : U32), w, base, Util.f2u(nvx), Util.f2u(nvz), Column{bits, wetbits}))

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
# Distance haze and low mist blend into the atmosphere along the ray.

def mix(a: U32, b: U32, f: F32) -> U32:
  Sky.mix(a, b, f)

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

# The shadow uses the primary ray's signed steps and absolute reciprocals.
# Its fixed 24 steps keep neighbouring GPU lanes on the same loop.
def shadow_end(got: Bool, r: Array<U32> & U32) -> Array<U32> & Bool:
  (w, b) = r
  (w, got)

def shadow(fuel: Nat, +base: U32, +vx: F32, +vy: F32, +vz: F32, +sx: F32, +sy: F32, +sz: F32,
           +mx: F32, +my: F32, +mz: F32, +ex: F32, +ey: F32, +ez: F32,
           +ymask: U32, +got: Bool, r: Array<U32> & U32) -> Array<U32> & Bool:
  match fuel:
    case 0n:
      shadow_end(got, r)
    case 1n+f:
      (w, +bits) = r
      +here = got || (World.inside(vx, vy, vz) && Util.on(bits, ymask))
      +ux = (mx < my : F32) && (mx < mz : F32)
      +uy = Bool.pick(Bool, ux, False{}, (my < mz : F32))
      +nvx = Bool.pick(F32, ux, (vx + sx : F32), vx)
      nvy = Bool.pick(F32, uy, (vy + sy : F32), vy)
      +nvz = Bool.pick(F32, ux, vz, Bool.pick(F32, uy, vz, (vz + sz : F32)))
      nmx = Bool.pick(F32, ux, (mx + ex : F32), mx)
      nmy = Bool.pick(F32, uy, (my + ey : F32), my)
      nmz = Bool.pick(F32, ux, mz, Bool.pick(F32, uy, mz, (mz + ez : F32)))
      nymask = Bool.pick(U32, uy, Bool.pick(U32, (sy > 0.0 : F32), U32.shl(ymask), U32.shr(ymask)), ymask)
      shadow(f, base, nvx, nvy, nvz, sx, sy, sz, nmx, nmy, nmz, ex, ey, ez, nymask, here,
             refetch(Bool.not(uy) && Bool.not(here), w, base, Util.f2u(nvx), Util.f2u(nvz), bits))

def run_shadow(w: Array<U32>, +base: U32, +ox: F32, +oy: F32, +oz: F32,
               +lx: F32, +ly: F32, +lz: F32) -> Array<U32> & Bool:
  +vx = F32.floor(ox)
  +vy = F32.floor(oy)
  +vz = F32.floor(oz)
  +px = (lx > 0.0 : F32)
  +py = (ly > 0.0 : F32)
  +pz = (lz > 0.0 : F32)
  +ex = (1.0 / F32.max(Util.absf(lx), 0.00001) : F32)
  +ey = (1.0 / F32.max(Util.absf(ly), 0.00001) : F32)
  +ez = (1.0 / F32.max(Util.absf(lz), 0.00001) : F32)
  shadow(24n, base, vx, vy, vz,
         Bool.pick(F32, px, 1.0, (0.0 - 1.0 : F32)),
         Bool.pick(F32, py, 1.0, (0.0 - 1.0 : F32)),
         Bool.pick(F32, pz, 1.0, (0.0 - 1.0 : F32)),
         (Bool.pick(F32, px, (vx + 1.0 - ox : F32), (ox - vx : F32)) * ex : F32),
         (Bool.pick(F32, py, (vy + 1.0 - oy : F32), (oy - vy : F32)) * ey : F32),
         (Bool.pick(F32, pz, (vz + 1.0 - oz : F32), (oz - vz : F32)) * ez : F32), ex, ey, ez,
         U32.shln(1, F32.to_nat(F32.max(oy, 0.0))), False{},
         Array.get(U32, w, World.col_at(base, Util.f2u(vx), Util.f2u(vz))))

# a face turned away from the sun is in shadow without a ray; with the
# shadow flag off every face is lit
def shadow_if(on: Bool, sunny: Bool, w: Array<U32>, +base: U32, +ox: F32, +oy: F32, +oz: F32, +lx: F32, +ly: F32, +lz: F32) -> Array<U32> & Bool:
  match on:
    case False{}:
      (w, False{})
    case True{}:
      match sunny:
        case False{}:
          (w, True{})
        case True{}:
          run_shadow(w, base, ox, oy, oz, lx, ly, lz)

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
  (w, mix(dim(col, (ao * sun : F32)), v, f))

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

# after the sun: the first neighbour read, or none with the occlusion off
def after_sun(+v: U32, +col: U32, +f: F32, +base: U32, +ox: F32, +oy: F32, +oz: F32,
              +ux: F32, +uy: F32, +uz: F32, +ex: F32, +ey: F32, +ez: F32, +fu: F32, +fw: F32,
              aon: Bool, r: Array<U32> & Bool) -> Array<U32> & U32:
  match aon:
    case True{}:
      (w, dark) = r
      ao1(v, col, f, Bool.pick(F32, dark, 0.6, 1.0), base, ox, oy, oz, ux, uy, uz, ex, ey, ez, fu, fw,
          World.solid(w, base, (ox + ux : F32), (oy + uy : F32), (oz + uz : F32)))
    case False{}:
      (w, dark) = r
      (w, mix(dim(col, Bool.pick(F32, dark, 0.6, 1.0)), v, f))

def tex_if(on: Bool, +u: F32, +wf: F32) -> F32:
  match on:
    case True{}:
      texture(u, wf)
    case False{}:
      1.0

# the type read: one word through the handle, then the look
def typed(+v: U32, +fl: U32, +base: U32, +hy: U32, +side: Bool, +yf: F32, +u: F32, +wf: F32, +tone: F32, +f: F32,
          +cx: F32, +cy: F32, +cz: F32, +ux: F32, +uz: F32, +ey: F32, +ez: F32, +fu: F32, +fw: F32,
          +lx: F32, +ly: F32, +lz: F32, +sunny: Bool, +sx: F32, +sy: F32, +sz: F32, r: Array<U32> & U32) -> Array<U32> & U32:
  (w, word) = r
  +what = World.nib_at(word, hy)
  +col = dim(blockcol(what, side, yf), (tone * tex_if(Util.on(fl, 4), u, wf) : F32))
  after_sun(v, col, f, base, cx, cy, cz, ux, 0.0, uz, 0.0, ey, ez, fu, fw, Util.on(fl, 2),
            shadow_if(Util.on(fl, 1), sunny, w, base, sx, sy, sz, lx, ly, lz))

def shade_go(sky: Bool, w: Array<U32>, +base: U32, +v: U32, +ox: F32, +oy: F32, +oz: F32,
             +dx: F32, +dy: F32, +dz: F32, +c: U32, +t: F32, +fl: U32, +lx: F32, +ly: F32, +lz: F32) -> Array<U32> & U32:
  match sky:
    case True{}:
      (w, Sky.bodies(fl, v, dx, dy, dz, lx, ly, lz))
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
      +tone = (Bool.pick(F32, ax, 0.8, Bool.pick(F32, ay, 1.0, 0.7)) * (0.18 + 0.82 * Sky.daylight(ly)) : F32)
      +f = Sky.fog(fl, t, oy, py)
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
      typed(v, fl, base, Util.f2u(hy), Bool.not(ay), Util.fracf(py), u, wf, tone, f,
            cx, cy, cz, ux, uz, ey, ez, fu, fw, lx, ly, lz,
            (ly > 0.0 : F32) && ((da * Bool.pick(F32, ax, lx, Bool.pick(F32, ay, ly, lz)) : F32) < 0.0 : F32),
            Bool.pick(F32, ax, (px + nudge : F32), px),
            Bool.pick(F32, ay, (py + nudge : F32), py),
            Bool.pick(F32, U32.is_eq(axis, 2), (pz + nudge : F32), pz),
            Array.get(U32, w, (World.col_at(base, Util.f2u(hx), Util.f2u(hz)) + 1 + Util.f2u(hy) / 8 : U32)))

# ---------- the mirror: the world seen in the water's top ----------
# A second walk, as the shadow is one: from where the ray met the water,
# along its mirrored direction, 32 steps whatever happens, solid bits
# alone. What it meets gets the block's colour, its texture and its face's
# tone, with no occlusion and no shadow ray: ripples and fog blur the rest,
# and it fades into the sky towards the end of the walk's reach.
# Only a pixel that shows a water top pays for it.

type Glance is Data:
  Glance{col: U32, t: F32}

def glance_end(+col: U32, t: F32, r: Array<U32> & U32) -> Array<U32> & Glance:
  (w, bits) = r
  (w, Glance{col, t})

def glance(fuel: Nat, +base: U32, +vx: F32, +vy: F32, +vz: F32, +sx: F32, +sy: F32, +sz: F32,
           +mx: F32, +my: F32, +mz: F32, +ex: F32, +ey: F32, +ez: F32,
           +axis: F32, +col: U32, +t: F32, +ymask: U32, r: Array<U32> & U32) -> Array<U32> & Glance:
  match fuel:
    case 0n:
      glance_end(col, t, r)
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
      nymask = Bool.pick(U32, uy, Bool.pick(U32, (sy > 0.0 : F32), U32.shl(ymask), U32.shr(ymask)), ymask)
      nt = Bool.pick(F32, (ncol < 1 : U32), Bool.pick(F32, ux, mx, Bool.pick(F32, uy, my, mz)), t)
      glance(f, base, nvx, nvy, nvz, sx, sy, sz, nmx, nmy, nmz, ex, ey, ez, naxis, ncol, nt, nymask,
             refetch(Bool.not(uy) && (ncol < 1 : U32), w, base, Util.f2u(nvx), Util.f2u(nvz), bits))

def run_glance(w: Array<U32>, +base: U32, +ox: F32, +oy: F32, +oz: F32,
               +dx: F32, +dy: F32, +dz: F32) -> Array<U32> & Glance:
  +vx = F32.floor(ox)
  +vy = F32.floor(oy)
  +vz = F32.floor(oz)
  +px = (dx > 0.0 : F32)
  +py = (dy > 0.0 : F32)
  +pz = (dz > 0.0 : F32)
  +ex = (1.0 / F32.max(Util.absf(dx), 0.00001) : F32)
  +ey = (1.0 / F32.max(Util.absf(dy), 0.00001) : F32)
  +ez = (1.0 / F32.max(Util.absf(dz), 0.00001) : F32)
  glance(32n, base, vx, vy, vz,
         Bool.pick(F32, px, 1.0, (0.0 - 1.0 : F32)),
         Bool.pick(F32, py, 1.0, (0.0 - 1.0 : F32)),
         Bool.pick(F32, pz, 1.0, (0.0 - 1.0 : F32)),
         (Bool.pick(F32, px, (vx + 1.0 - ox : F32), (ox - vx : F32)) * ex : F32),
         (Bool.pick(F32, py, (vy + 1.0 - oy : F32), (oy - vy : F32)) * ey : F32),
         (Bool.pick(F32, pz, (vz + 1.0 - oz : F32), (oz - vz : F32)) * ez : F32), ex, ey, ez,
         1.0, 0, 0.0, U32.shln(1, F32.to_nat(F32.max(oy, 0.0))),
         Array.get(U32, w, World.col_at(base, Util.f2u(vx), Util.f2u(vz))))

# the block the mirror's ray met: its type's colour, the texture, the
# face's tone, darker when the face is turned from the sun
def glance_fin(bottom: U32, m: Water.Reflection, +fl: U32, +hy: U32, side: Bool, yf: F32, u: F32, wf: F32,
               tone: F32, f: F32, r: Array<U32> & U32) -> Array<U32> & Water.Mirror:
  (w, word) = r
  (w, Water.Mirror{bottom, m, True{}, dim(blockcol(World.nib_at(word, hy), side, yf),
    (tone * tex_if(Util.on(fl, 4), u, wf) : F32)), f})

def glance_look(got: Bool, bottom: U32, m: Water.Reflection, +fl: U32, +base: U32,
                +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
                +far: F32, +eye: F32, +lx: F32, +ly: F32, +lz: F32, +c: U32, +t: F32, w: Array<U32>) -> Array<U32> & Water.Mirror:
  match got:
    case False{}:
      (w, Water.Mirror{bottom, m, False{}, 0, 1.0})
    case True{}:
      +axis = (c - 1 : U32)
      +px = (ox + dx * t : F32)
      +py = (oy + dy * t : F32)
      +pz = (oz + dz * t : F32)
      +ax = U32.is_eq(axis, 0)
      +ay = U32.is_eq(axis, 1)
      +bx = Util.floorf((px + 0.5 : F32))
      +by = Util.floorf((py + 0.5 : F32))
      +bz = Util.floorf((pz + 0.5 : F32))
      +hx = Bool.pick(F32, ax, Bool.pick(F32, (dx > 0.0 : F32), bx, (bx - 1.0 : F32)), Util.floorf(px))
      +hy = Bool.pick(F32, ay, Bool.pick(F32, (dy > 0.0 : F32), by, (by - 1.0 : F32)), Util.floorf(py))
      +hz = Bool.pick(F32, U32.is_eq(axis, 2), Bool.pick(F32, (dz > 0.0 : F32), bz, (bz - 1.0 : F32)), Util.floorf(pz))
      +da = Bool.pick(F32, ax, dx, Bool.pick(F32, ay, dy, dz))
      +lit = (ly > 0.0 : F32) && ((da * Bool.pick(F32, ax, lx, Bool.pick(F32, ay, ly, lz)) : F32) < 0.0 : F32)
      glance_fin(bottom, m, fl, Util.f2u(hy), Bool.not(ay), Util.fracf(py),
        Bool.pick(F32, ax, pz, px), Bool.pick(F32, ay, pz, py),
        (Bool.pick(F32, ax, 0.8, Bool.pick(F32, ay, 1.0, 0.7)) * (0.18 + 0.82 * Sky.daylight(ly)) * Bool.pick(F32, lit, 1.0, 0.6) : F32),
        F32.max(Sky.fog(fl, (far + t : F32), eye, py), Water.reach(t, dx, dy, dz)),
        Array.get(U32, w, (World.col_at(base, Util.f2u(hx), Util.f2u(hz)) + 1 + Util.f2u(hy) / 8 : U32)))

def glance_open(bottom: U32, m: Water.Reflection, +fl: U32, +base: U32,
                +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
                +far: F32, +eye: F32, +lx: F32, +ly: F32, +lz: F32, r: Array<U32> & Glance) -> Array<U32> & Water.Mirror:
  (w, g) = r
  Glance{+c, t} = g
  glance_look((c > 0 : U32), bottom, m, fl, base, ox, oy, oz, dx, dy, dz, far, eye, lx, ly, lz, c, t, w)

# the world in the mirror is a look of its own (bit 27 of the camera's base)
def mirror_world(world: Bool, +fl: U32, +base: U32, +px: F32, +py: F32, +pz: F32,
                 +far: F32, +eye: F32, +lx: F32, +ly: F32, +lz: F32, +m: Water.Reflection,
                 r: Array<U32> & U32) -> Array<U32> & Water.Mirror:
  match world:
    case False{}:
      (w, bottom) = r
      (w, Water.Mirror{bottom, m, False{}, 0, 1.0})
    case True{}:
      Water.Reflection{+rx, +ry, +rz, cosine} = m
      (w, bottom) = r
      # the walk starts a hair over the water, in the air the ray came through
      glance_open(bottom, m, fl, base, px, (py + 0.01 : F32), pz, rx, ry, rz, far, eye, lx, ly, lz,
        run_glance(w, base, px, (py + 0.01 : F32), pz, rx, ry, rz))

def mirrored(go: Bool, +fl: U32, +base: U32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
             +entry: F32, +lx: F32, +ly: F32, +lz: F32, r: Array<U32> & U32) -> Array<U32> & Water.Mirror:
  match go:
    case False{}:
      (w, bottom) = r
      (w, Water.Mirror{bottom, Water.flat(dx, dy, dz), False{}, 0, 1.0})
    case True{}:
      mirror_world(Water.mirror_on(base), fl, base, (ox + dx * entry : F32), (oy + dy * entry : F32), (oz + dz * entry : F32),
        entry, oy, lx, ly, lz,
        Water.reflected(Water.ripples_on(fl), base, (ox + dx * entry : F32), (oz + dz * entry : F32), entry, dx, dy, dz), r)

# the profile's pixels: the steps to the hit (flag 32), or 1 on a hit (64)
def shade_mode(steps: Bool, hits: Bool, sky: Bool, w: Array<U32>, +base: U32, +v: U32,
               +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
               +c: U32, +t: F32, +n: U32, +fl: U32, +lx: F32, +ly: F32, +lz: F32) -> Array<U32> & U32:
  match steps:
    case True{}:
      (w, n)
    case False{}:
      match hits:
        case True{}:
          (w, Bool.pick(U32, sky, 0, 1))
        case False{}:
          shade_go(sky, w, base, v, ox, oy, oz, dx, dy, dz, c, t, fl, lx, ly, lz)

def shade(+v: U32, +fl: U32, +lx: F32, +ly: F32, +lz: F32, w: Array<U32>, +base: U32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
          ct: Ray) -> Array<U32> & U32:
  Ray{+c, +t, +tr} = ct
  Water.Trace{+entry, depth} = tr
  +wet = (depth > 0.0 : F32) && Bool.not(Util.on(fl, 96))
  +ground_flags = Bool.pick(U32, wet, (fl .&. 2147483639 : U32), fl)
  +hitw = (c % 4 : U32)
  Water.shade(wet, fl, v, oy, dy, lx, ly, lz, Water.top(c), t, (hitw > 0 : U32), tr,
    mirrored(wet && Water.top(c) && Water.reflection_on(fl), fl, base, ox, oy, oz, dx, dy, dz, entry, lx, ly, lz, shade_mode(Util.on(fl, 32), Util.on(fl, 64), (hitw < 1 : U32), w, base, v, ox, oy, oz, dx, dy, dz, hitw, t, Water.steps(c), ground_flags, lx, ly, lz)))

def finish(+v: U32, +fl: U32, +lx: F32, +ly: F32, +lz: F32, +base: U32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
           r: Array<U32> & Ray) -> Array<U32> & U32:
  (w, ct) = r
  shade(v, fl, lx, ly, lz, w, base, ox, oy, oz, dx, dy, dz, ct)

def run_dda(~water: Bool, w: Array<U32>, +base: U32, +ox: F32, +oy: F32, +oz: F32,
            +dx: F32, +dy: F32, +dz: F32, +v: U32, +fl: U32, +lx: F32, +ly: F32, +lz: F32) -> Array<U32> & U32:
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
  finish(v, fl, lx, ly, lz, base, ox, oy, oz, dx, dy, dz, dda(~water, 60n, base, vx, vy, vz,
           Bool.pick(F32, px, 1.0, (0.0 - 1.0 : F32)),
           Bool.pick(F32, py, 1.0, (0.0 - 1.0 : F32)),
           Bool.pick(F32, pz, 1.0, (0.0 - 1.0 : F32)),
           (nx / ax : F32), (ny / ay : F32), (nz / az : F32),
           (1.0 / ax : F32), (1.0 / ay : F32), (1.0 / az : F32),
           1.0, 0, 0.0, 0, U32.shln(1, F32.to_nat(F32.max(oy, 0.0))), Water.Trace{0.0, 0.0},
           column_words(~water, w, World.col_at(base, Util.f2u(vx), Util.f2u(vz)))))

def run_water(on: Bool, w: Array<U32>, +base: U32, +ox: F32, +oy: F32, +oz: F32,
              +dx: F32, +dy: F32, +dz: F32, +v: U32, +fl: U32, +lx: F32, +ly: F32, +lz: F32) -> Array<U32> & U32:
  match on:
    case False{}: run_dda(~False{}, w, base, ox, oy, oz, dx, dy, dz, v, fl, lx, ly, lz)
    case True{}: run_dda(~True{}, w, base, ox, oy, oz, dx, dy, dz, v, fl, lx, ly, lz)

# A ray that misses the loaded box reads the world zero times (and counts
# no step and no hit under the profile's flags).
def shoot(go: Bool, w: Array<U32>, +base: U32, +ox: F32, +oy: F32, +oz: F32,
          +dx: F32, +dy: F32, +dz: F32, +v: U32, +fl: U32, +lx: F32, +ly: F32, +lz: F32) -> Array<U32> & U32:
  match go:
    case False{}:
      (w, Bool.pick(U32, ((fl .&. 96) < 1 : U32), Sky.bodies(fl, v, dx, dy, dz, lx, ly, lz), 0))
    case True{}:
      run_water(Util.on(fl, 2097152), w, base, ox, oy, oz, dx, dy, dz, v, fl, lx, ly, lz)

def clipped(w: Array<U32>, +base: U32, +ox: F32, +oy: F32, +oz: F32,
            +dx: F32, +dy: F32, +dz: F32, +v: U32, +fl: U32, +lx: F32, +ly: F32, +lz: F32) -> Array<U32> & U32:
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
  shoot((tin < tout : F32), w, base, (ox + dx * s : F32), (oy + dy * s : F32), (oz + dz * s : F32), dx, dy, dz, v, fl, lx, ly, lz)

# ---------- the player ----------

# The camera is Data, shared down the fork; the world is the array, threaded.
# `v` down the leaf is the ray's atmospheric colour, ready for the fog. `fl` is the
# flags: 1 shadow, 2 occlusion, 4 texture, 8 fog, 16 HUD (the game passes
# Render.looks()); 32 makes the pixel the ray's steps to its hit, 64 makes it 1 on a
# hit and 0 on sky: `make profile` renders with each and prints what costs
# what. Bits 7..19 hold the readout, with four FPS bits in items and one in
# base's bit 31; bit 20 enables ripples. Bits 21..24
# hold water (21), water fog (22), Fresnel (23) and sky reflection (24). Bits 25..31 enable the day cycle, sky
# gradient, sun disc, horizon glow, stars, moon and height fog, respectively.
# sel holds selection in its low three bits, then four seven-bit counts;
# items holds the other four and the high FPS bits. Counts are capped for the HUD.
# base keeps the ring's low 14 bits, a 13-bit ripple clock and one FPS bit.
type Cam is Data:
  Cam{px: F32, py: F32, pz: F32, yaw: F32, pit: F32, base: U32, sel: U32, items: U32, fl: U32, rw: U32, rh: U32, lx: F32, ly: F32, lz: F32}

# Bit 25 selects the clock's sun; disabled, the profile uses the old sun.
def looks() -> U32: 4293918751

# the looks that ride in the camera's base, bits 27..30: 27 the world in
# the water's mirror; 28..30 are spare
def looks_base() -> U32: 134217728

def camera(px: F32, py: F32, pz: F32, yaw: F32, pit: F32, base: U32, more: U32, sel: U32, items: U32,
           +fl: U32, rw: U32, rh: U32, +clock: U32) -> Cam:
  +cycle = Util.on(fl, 33554432)
  Cam{px, py, pz, yaw, pit, Water.with_looks(Water.frame_base(base, clock), more), sel, items, fl, rw, rh,
      Bool.pick(F32, cycle, Day.sun_x(clock), 0.48),
      Bool.pick(F32, cycle, Day.sun_y(clock), 0.8),
      Bool.pick(F32, cycle, Day.sun_z(clock), 0.36)}

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
  Cam{ox, oy, oz, yaw, pit, base, sel, items, +fl, +rw, +rh, +lx, +ly, +lz} = cam
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
  clipped(w, base, ox, oy, oz, (dx / n : F32), (dy / n : F32), (dz / n : F32), Sky.atmosphere(fl, (dx / n : F32), (dy / n : F32), (dz / n : F32), lx, ly, lz), fl, lx, ly, lz)

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

# ---------- the readout: the `!`'s milliseconds and the frames a second ----------
# The two numbers ride in the flags above the looks (main.bend measures
# them): bits 7..16 the tenths of a millisecond, to 99.9, bits 17..19 the
# low three FPS bits, base's bit 31 the next and items' bits 28..31 the
# high four. This leaves fl bit 20 for ripples. Zeros hide the readout.
# "16.4 MS  60 FPS" in the top left
# corner, glyphs of 3 x 5 drawn 2 px a dot, a bit a dot from the top left:
# 0-9, then . blank M F P and + (S is the 5). The GPU never shifts by a variable,
# so a row and a dot are picked by a division and a mask.

def stat_flags(+fl: U32, +ms10: U32, +fps: U32) -> U32:
  ((fl .&. 4293918847) + 128 * (U32.min(ms10, 999) + 1024 * (U32.min(fps, 255) % 8)) : U32)

def stat_base(base: U32, fps: U32) -> U32:
  ((base .&. 2147483647) .|. (U32.min(fps, 255) / 8 % 2 * 2147483648) : U32)

def stat_items(+items: U32, +fps: U32) -> U32:
  ((items .&. 268435455) + (U32.min(fps, 255) / 16) * 268435456 : U32)

def stat_ms(+fl: U32) -> U32: (fl / 128 % 1024 : U32)
def stat_fps(fl: U32, items: U32, base: U32) -> U32:
  (fl / 131072 % 8 + 8 * (base / 2147483648) + 16 * (items / 268435456) : U32)

def stat_on(fl: U32, items: U32, base: U32) -> Bool:
  Util.on(fl, 1048448) || (items / 268435456 > 0 : U32) || Util.on(base, 2147483648)

def glyph(+i: U32) -> U32:
  Bool.pick(U32, U32.is_eq(i, 0), 31599,
    Bool.pick(U32, U32.is_eq(i, 1), 29850,
    Bool.pick(U32, U32.is_eq(i, 2), 29671,
    Bool.pick(U32, U32.is_eq(i, 3), 31207,
    Bool.pick(U32, U32.is_eq(i, 4), 18925,
    Bool.pick(U32, U32.is_eq(i, 5), 31183,
    Bool.pick(U32, U32.is_eq(i, 6), 31695,
    Bool.pick(U32, U32.is_eq(i, 7), 18727,
    Bool.pick(U32, U32.is_eq(i, 8), 31727,
    Bool.pick(U32, U32.is_eq(i, 9), 31215,
    Bool.pick(U32, U32.is_eq(i, 10), 8192,
    Bool.pick(U32, U32.is_eq(i, 11), 0,
    Bool.pick(U32, U32.is_eq(i, 12), 23549,
    Bool.pick(U32, U32.is_eq(i, 13), 4815,
    Bool.pick(U32, U32.is_eq(i, 14), 5103,
    Bool.pick(U32, U32.is_eq(i, 15), 1488,
    0))))))))))))))))

def stat_cell(+c: U32, +ms: U32, +fps: U32) -> U32:
  Bool.pick(U32, U32.is_eq(c, 0), Bool.pick(U32, (ms < 100 : U32), 11, (ms / 100 : U32)),
    Bool.pick(U32, U32.is_eq(c, 1), (ms / 10 % 10 : U32),
    Bool.pick(U32, U32.is_eq(c, 2), 10,
    Bool.pick(U32, U32.is_eq(c, 3), (ms % 10 : U32),
    Bool.pick(U32, U32.is_eq(c, 4), 11,
    Bool.pick(U32, U32.is_eq(c, 5), 12,
    Bool.pick(U32, U32.is_eq(c, 6), 5,
    Bool.pick(U32, U32.is_eq(c, 7), 11,
    Bool.pick(U32, U32.is_eq(c, 8), Bool.pick(U32, (fps < 100 : U32), 11, (fps / 100 : U32)),
    Bool.pick(U32, U32.is_eq(c, 9), Bool.pick(U32, (fps < 10 : U32), 11, (fps / 10 % 10 : U32)),
    Bool.pick(U32, U32.is_eq(c, 10), (fps % 10 : U32),
    Bool.pick(U32, U32.is_eq(c, 11), 11,
    Bool.pick(U32, U32.is_eq(c, 12), 13,
    Bool.pick(U32, U32.is_eq(c, 13), 14,
    Bool.pick(U32, U32.is_eq(c, 14), 5,
    11)))))))))))))))

def row_div(+r: U32) -> U32:
  Bool.pick(U32, U32.is_eq(r, 0), 1, Bool.pick(U32, U32.is_eq(r, 1), 8, Bool.pick(U32, U32.is_eq(r, 2), 64,
    Bool.pick(U32, U32.is_eq(r, 3), 512, 4096))))

def dot_bit(+d: U32) -> U32:
  Bool.pick(U32, U32.is_eq(d, 0), 1, Bool.pick(U32, U32.is_eq(d, 1), 2, Bool.pick(U32, U32.is_eq(d, 2), 4, 0)))

def stat_px(inside: Bool, +fl: U32, items: U32, base: U32, +pxi: U32, +pyi: U32) -> U32:
  match inside:
    case False{}:
      0
    case True{}:
      +lx = (pxi - 4 : U32)
      +ly = (pyi - 4 : U32)
      +intext = (pxi >= 4 : U32) && (pxi < 124 : U32) && (pyi >= 4 : U32) && (pyi < 14 : U32)
      +g = glyph(stat_cell((lx / 8 : U32), stat_ms(fl), stat_fps(fl, items, base)))
      +row = (g / row_div((ly / 2 : U32)) % 8 : U32)
      +lit = intext && Util.on(row, dot_bit((lx % 8 / 2 : U32)))
      Bool.pick(U32, lit, (1 + rgb(255, 255, 255) : U32), (1 + rgb(16, 16, 24) : U32))

# Counts share the HUD flag. Only pixels inside a slot decode them; the
# host list never reaches a lane. A dark strip keeps each digit legible.
def count_glyph(+n: U32, +cell: U32) -> U32:
  +v = U32.min(n, 99)
  Bool.pick(U32, U32.is_eq(cell, 0), Bool.pick(U32, (v < 10 : U32), 11, (v / 10 : U32)),
    Bool.pick(U32, U32.is_eq(cell, 1), (v % 10 : U32), Bool.pick(U32, (n > 99 : U32), 15, 11)))

def count_col(+n: U32, +lx: U32, +ly: U32) -> U32:
  +g = glyph(count_glyph(n, ((lx - 5) / 4 : U32)))
  +row = (g / row_div((ly - 11 : U32)) % 8 : U32)
  +lit = (lx >= 5 : U32) && (lx < 16 : U32) && (ly >= 11 : U32) && (ly < 16 : U32)
    && Util.on(row, dot_bit(((lx - 5) % 4 : U32)))
  Bool.pick(U32, lit, Bool.pick(U32, U32.is_eq(n, 0), rgb(144, 144, 152), rgb(255, 255, 255)), rgb(16, 16, 24))

def slot_col(+sel: U32, items: U32, +slot: U32, +pxi: U32, +pyi: U32, +rw: U32, +rh: U32) -> U32:
  +i = (slot - 1 : U32)
  +lx = ((pxi - (rw / 2 - 94)) % 24 : U32)
  +ly = (pyi - (rh - 30) : U32)
  +border = (lx < 2 : U32) || (lx >= 18 : U32) || (ly < 2 : U32) || (ly >= 18 : U32)
  +label = (lx >= 4 : U32) && (lx < 18 : U32) && (ly >= 10 : U32) && (ly < 17 : U32)
  Bool.pick(U32, border, Bool.pick(U32, U32.is_eq(i, (sel % 8 : U32)), rgb(255, 255, 255), rgb(40, 40, 40)),
    Bool.pick(U32, label, count_col(Inventory.hud_count(sel, items, i), lx, ly), blockcol(i, False{}, 1.0)))

def slot_px(inside: Bool, sel: U32, items: U32, slot: U32, pxi: U32, pyi: U32, rw: U32, rh: U32) -> U32:
  match inside:
    case False{}: 0
    case True{}: (1 + slot_col(sel, items, slot, pxi, pyi, rw, rh) : U32)

# what lies over the scene at this pixel: 0 nothing, else 1 + the colour
def hud(+sel: U32, +items: U32, +base: U32, +fl: U32, +pxi: U32, +pyi: U32, +rw: U32, +rh: U32) -> U32:
  +slot = slot_at(pxi, pyi, rw, rh)
  +stat = stat_px(stat_on(fl, items, base) && (pxi < 128 : U32) && (pyi < 18 : U32), fl, items, base, pxi, pyi)
  Bool.pick(U32, (stat > 0 : U32), stat,
    Bool.pick(U32, cross_at(pxi, pyi, rw, rh), (1 + rgb(255, 255, 255) : U32),
      slot_px((slot > 0 : U32), sel, items, slot, pxi, pyi, rw, rh)))

def hud_if(on: Bool, +sel: U32, items: U32, base: U32, +fl: U32, +pxi: U32, +pyi: U32, +rw: U32, +rh: U32) -> U32:
  match on:
    case True{}:
      hud(sel, items, base, fl, pxi, pyi, rw, rh)
    case False{}:
      0

def hud_of(+cam: Cam, +pxi: U32, +pyi: U32) -> U32:
  Cam{ox, oy, oz, yaw, pit, base, sel, items, +fl, rw, rh, lx, ly, lz} = cam
  hud_if(Util.on(fl, 16), sel, items, base, fl, pxi, pyi, rw, rh)

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
