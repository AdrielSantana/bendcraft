import Base
import ./util.bend as Util
import ./world.bend as World
import ./day.bend as Day
import ./sky.bend as Sky
import ./inventory.bend as Inventory
import ./water.bend as Water
import ./clouds.bend as Clouds
import ./rain.bend as Rain
import ./wet.bend as Wet
import ./grass.bend as Grass
import ./lens.bend as Lens
import ./shafts.bend as Shafts
import ./torch.bend as Torch

# THE RENDER: a ray per pixel through the ring of columns, on the GPU.
#
# RESOLUTION is a runtime value: the camera carries the render's width and
# height, `frame` forks over 4x4 leaves in a square of 4 << k a side that
# covers the larger side, and what lies past the edge is one Pix with no
# ray. The window may be bigger than the render by a power of two: its
# shader stops at the first Pix it meets, so a coarser image scales up by
# itself.

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

# `U32.shln(a, n)` is O(n) -- a recursive shl per unit of n. So nothing here
# ever shifts by a variable: the DDA carries the mask 1<<y and moves it one
# bit per y step, and the type's nibble is picked with a select.

# ---------- DDA over the array ----------

# Only a step in x or z can change which column we are in, so the column is
# read once per crossing instead of once per voxel, and never again once
# this ray has found its block: its solid mask, and its leaf mask where
# the leaves' holes are asked for.
type Masks is Data:
  Masks{solid: U32, leaf: U32}

def masks_fin(+bits: U32, r: Array<U32> & U32) -> Array<U32> & Masks:
  (w, leaf) = r
  (w, Masks{bits, leaf})

def masks_of(leafy: Bool, +slot: U32, r: Array<U32> & U32) -> Array<U32> & Masks:
  match leafy:
    case False{}:
      (w, bits) = r
      (w, Masks{bits, 0})
    case True{}:
      (w, +bits) = r
      masks_fin(bits, Array.get(U32, w, World.leaf_at(slot)))

def refetch(need: Bool, +open: U32, w: Array<U32>, +base: U32, +x: U32, +z: U32, +bits: U32, +leaf: U32) -> Array<U32> & Masks:
  match need:
    case True{}:
      masks_of((open > 0 : U32), World.col_at(base, x, z), Array.get(U32, w, World.col_at(base, x, z)))
    case False{}:
      (w, Masks{bits, leaf})

# the hit is a word: 0 none, else 1 + the face's axis; its look comes after
# the loop (a match, not the strict Bool.pick, so only a hit pays for it)
def hit(here: Bool, +axis: F32, +col: U32) -> U32:
  match here:
    case True{}:
      (1 + Util.f2u(axis) : U32)
    case False{}:
      col

# The leaves' holes: a leaf block's face is an 8x8 tile of texels, as its
# texture is, and `open` in a hundred of them are open; a walk that enters
# a leaf block through an open one goes on through the block (pierced),
# so a canopy shows the sky and what stands behind it through its gaps.
# The texel is where the walk came into the cell, whose coordinates along
# the face come from the distances to the cell's next sides (m) and the
# walk's rate along each axis (a). The sun sees more gaps than the eye:
# under a canopy its ray enters three or four leaf blocks, and at the
# eye's 30 a tree's shadow held almost no fleck of light, at 55 it was
# lost among them.
def gaps() -> U32: 30

def sun_gaps(+fl: U32) -> U32: Bool.pick(U32, Util.on(fl, 8192), 40, 0)

def hole(+axis: F32, +a: F32, +b: F32, +open: U32) -> Bool:
  +i = Util.f2u(F32.min((a * 8.0 : F32), 7.0))
  +j = Util.f2u(F32.min((b * 8.0 : F32), 7.0))
  (Sky.star_hash((i + j * 8 + Util.f2u(axis) * 64 : U32), 4201) % 100 < open : U32)

def along(+s: F32, +m: F32, +t: F32, +a: F32) -> F32:
  Bool.pick(F32, (s > 0.0 : F32), (1.0 - (m - t) * a : F32), ((m - t) * a : F32))

# The wind sways the leaves: a leaf block's texels slide along the wind,
# and less up and across, with the gusts that push the grass
# (Grass.gusting), up to two texels, quivering at the block's own phase
# (Grass.quiver); wind is the clock, 0 for still leaves. The gusts run
# over the column's slot s, x·128 + z of the world whatever the window,
# so the sway never jumps as the window moves.
def wind_of(+fl: U32, +ck: U32) -> U32: Bool.pick(U32, Util.on(fl, 16384), ck, 0)

def swayed(moving: Bool, +wind: U32, +open: U32, +s: U32, +vy: F32, +axis: F32, +a: F32, +b: F32) -> Bool:
  match moving:
    case False{}:
      hole(axis, a, b, open)
    case True{}:
      +d = (Grass.gusting((U32.to_f32(s) * 0.0078125 : F32), wind, (1.7 * F32.sin((U32.to_f32((s % 128 : U32)) * 0.23 : F32)) : F32))
        * Grass.quiver(wind, (U32.to_f32((Sky.star_hash((s + Util.f2u(vy) * 16384 : U32), 4211) % 64 : U32)) * 0.015625 : F32)) * 0.2 : F32)
      hole(axis, Util.fracf((a - Bool.pick(F32, (axis < 0.5 : F32), 0.4, 1.0) * d : F32)), Util.fracf((b - Bool.pick(F32, (axis > 1.5 : F32), 0.4, 0.6) * d : F32)), open)

def pierced(on: Bool, +open: U32, +wind: U32, +base: U32, +vx: F32, +vy: F32, +vz: F32, +axis: F32, +t: F32,
            +mx: F32, +my: F32, +mz: F32, +sx: F32, +sy: F32, +sz: F32, +ax: F32, +ay: F32, +az: F32) -> Bool:
  match on:
    case False{}:
      False{}
    case True{}:
      +fy = along(sy, my, t, ay)
      swayed((wind > 0 : U32), wind, open, (World.col_at(base, Util.f2u(vx), Util.f2u(vz)) / 16 : U32), vy, axis,
        Bool.pick(F32, (axis < 0.5 : F32), fy, along(sx, mx, t, ax)), Bool.pick(F32, (axis > 1.5 : F32), fy, along(sz, mz, t, az)))

# The dry specialization keeps water loads out of the profile's off row.
# All specializations use this same loop and the same fixed fuel. With
# partial water in the window (~partial, bit 29 of the base), the column
# brings its partial mask too (slot + 15, the same cache line): bit y
# says the cell holds less than 255 units, so it is water only under
# its plane, and the loop clips the wet segment to it. Only such a cell,
# rare, reads its amount, as the ray enters it; the column then carries
# the clip as two distances, lo and hi, the wet segment being
# [max(t, lo), min(next, hi)). Without partial water the loop is the
# full-cell one, its segment [t, next), and the frame costs what it did.
# With the leaves' holes on, the column brings its leaf mask too
# (World.leaf_at).
type Column is Data:
  Column{solid: U32, water: U32, partial: U32, leaf: U32, lo: F32, hi: F32}

def inf() -> F32: 1000000000.0

# The plane of a partial cell is `frac` above the cell's floor, which a
# descending ray meets at my, and 1 - frac under its top, which a rising
# one meets at my; ey is the distance a unit of height costs. A level
# ray descends by the DDA's sign, its my huge, and the sign of my -
# frac * ey says which side of the plane it runs on. A descending ray
# is wet from the plane on (lo), a rising one up to it (hi). The plane
# entry of a descending ray is a top entry, as a top face's is
# (Water.crossed_top).
def plane_fin(bits: U32, wetbits: U32, partial: U32, leaf: U32, +y: U32, +sy: F32, +my: F32, +ey: F32, r: Array<U32> & U32) -> Array<U32> & Column:
  (w, word) = r
  +frac = (Util.u2f(World.byte_at(word, y)) / 255.0 : F32)
  +down = (sy < 0.0 : F32)
  +sp = (my - Bool.pick(F32, down, frac, (1.0 - frac : F32)) * ey : F32)
  (w, Column{bits, wetbits, partial, leaf, Bool.pick(F32, down, sp, (0.0 - inf() : F32)), Bool.pick(F32, down, inf(), sp)})

def plane_if(part: Bool, w: Array<U32>, bits: U32, wetbits: U32, partial: U32, leaf: U32, +slot: U32, +ymask: U32, +y: U32, +sy: F32, +my: F32, +ey: F32) -> Array<U32> & Column:
  match part:
    case False{}:
      (w, Column{bits, wetbits, partial, leaf, (0.0 - inf() : F32), inf()})
    case True{}:
      plane_fin(bits, wetbits, partial, leaf, y, sy, my, ey, Array.get(U32, w, (slot + 6 + y / 4 : U32)))

def with_plane(bits: U32, +wetbits: U32, +partial: U32, leaf: U32, +slot: U32, +ymask: U32, +y: U32, +sy: F32, +my: F32, +ey: F32, w: Array<U32>) -> Array<U32> & Column:
  plane_if(Util.on(partial, ymask) && Util.on(wetbits, ymask), w, bits, wetbits, partial, leaf, slot, ymask, y, sy, my, ey)

def partial_word_fin(bits: U32, water: U32, +slot: U32, +ymask: U32, +y: U32, +sy: F32, +my: F32, +ey: F32, r: Array<U32> & U32) -> Array<U32> & Column:
  (w, partial) = r
  with_plane(bits, water, partial, 0, slot, ymask, y, sy, my, ey, w)

def water_word_fin(partial: Bool, bits: U32, +slot: U32, +ymask: U32, +y: U32, +sy: F32, +my: F32, +ey: F32, r: Array<U32> & U32) -> Array<U32> & Column:
  match partial:
    case False{}:
      (w, water) = r
      (w, Column{bits, water, 0, 0, (0.0 - inf() : F32), inf()})
    case True{}:
      (w, water) = r
      partial_word_fin(bits, water, slot, ymask, y, sy, my, ey, Array.get(U32, w, (slot + 15 : U32)))

def water_word(on: Bool, partial: Bool, +slot: U32, +ymask: U32, +y: U32, +sy: F32, +my: F32, +ey: F32, r: Array<U32> & U32) -> Array<U32> & Column:
  match on:
    case False{}:
      (w, bits) = r
      (w, Column{bits, 0, 0, 0, (0.0 - inf() : F32), inf()})
    case True{}:
      (w, bits) = r
      water_word_fin(partial, bits, slot, ymask, y, sy, my, ey, Array.get(U32, w, (slot + 5 : U32)))

def leaf_fin(c: Column, r: Array<U32> & U32) -> Array<U32> & Column:
  Column{bits, wetbits, partialbits, old, lo, hi} = c
  (w, leaf) = r
  (w, Column{bits, wetbits, partialbits, leaf, lo, hi})

def leafed(leafy: Bool, +slot: U32, r: Array<U32> & Column) -> Array<U32> & Column:
  match leafy:
    case False{}:
      r
    case True{}:
      (w, c) = r
      leaf_fin(c, Array.get(U32, w, World.leaf_at(slot)))

# the column's words as the ray enters a cell of it
def column_words(~water: Bool, ~partial: Bool, leafy: Bool, w: Array<U32>, +slot: U32, +ymask: U32, +y: U32, +sy: F32, +my: F32, +ey: F32) -> Array<U32> & Column:
  leafed(leafy, slot, water_word(water, partial, slot, ymask, y, sy, my, ey, Array.get(U32, w, slot)))

# the same column, a cell on: with partial water, its plane if it is partial
def cell_on(partial: Bool, w: Array<U32>, bits: U32, +wetbits: U32, +partialbits: U32, leaf: U32, +slot: U32, +ymask: U32, +y: U32, +sy: F32, +my: F32, +ey: F32) -> Array<U32> & Column:
  match partial:
    case False{}:
      (w, Column{bits, wetbits, partialbits, leaf, (0.0 - inf() : F32), inf()})
    case True{}:
      with_plane(bits, wetbits, partialbits, leaf, slot, ymask, y, sy, my, ey, w)

# the step into the next cell: the words again only on a step in x or z
def step_in(~water: Bool, ~partial: Bool, need: Bool, +leafy: Bool, w: Array<U32>, +slot: U32, +ymask: U32, +y: U32, +sy: F32, +my: F32, +ey: F32,
            bits: U32, +wetbits: U32, +partialbits: U32, leaf: U32) -> Array<U32> & Column:
  match need:
    case True{}: column_words(~water, ~partial, leafy, w, slot, ymask, y, sy, my, ey)
    case False{}: cell_on(partial, w, bits, wetbits, partialbits, leaf, slot, ymask, y, sy, my, ey)

# the wet segment's ends: the cell's, clipped to its plane with partial water
# The water bit of the cell the ray just left rides in bit 7 of the step
# count, over the count's six bits and the top's, only while the window
# holds partial water (Water.crossed_top's from_water); the count and the
# top read past it (Water.steps, Water.top).
def came_wet(partial: Bool, +n: U32) -> Bool:
  match partial:
    case False{}: False{}
    case True{}: Util.on(n, 128)

def keep_wet(partial: Bool, +n: U32, +wet_here: Bool) -> U32:
  match partial:
    case False{}: n
    case True{}: ((n .&. 4294967167) .|. Bool.pick(U32, wet_here, 128, 0) : U32)

def seg_start(partial: Bool, +t: F32, +lo: F32) -> F32:
  match partial:
    case False{}: t
    case True{}: F32.max(t, lo)

def seg_end(partial: Bool, +next: F32, +hi: F32) -> F32:
  match partial:
    case False{}: next
    case True{}: F32.min(next, hi)

# rim: where the ray first came into air over a solid block low enough to
# meet its grass (Grass.top; under 0 none), and rim_end where it last
# left such air: the meadow's grass stands between (rimmed)
type Ray is Data:
  Ray{hit: U32, t: F32, rim: F32, rim_end: F32, water: Water.Trace}

# The hit word carries six step bits above the two face bits, then the
# first-water-top bit. Reflection needs no extra word through the DDA.
def dda_end(+col: U32, +n: U32, t: F32, rim: F32, rim_end: F32, tr: Water.Trace, r: Array<U32> & Column) -> Array<U32> & Ray:
  (w, bits) = r
  (w, Ray{(col + n * 4 : U32), t, rim, rim_end, tr})

# The loop walks its 60 steps whatever happens, the state frozen after the
# hit (t stops moving there): an exit at the hit (or on leaving the box)
# walked a third of the steps and made the frame slower, 15 -> 17 ms at
# 1470 x 796 and 28 -> 32 at 1920 x 1080 (2026-09-21, the same checksums),
# since the lanes of a SIMD group then leave the loop at different steps
# and the runtime's switch over segments runs them one case at a time.
# Uniform beats less. The mask moves one bit a step, never by a variable.
def dda(~water: Bool, ~partial: Bool, fuel: Nat, +base: U32,
        +vx: F32, +vy: F32, +vz: F32,
        +sx: F32, +sy: F32, +sz: F32,
        +mx: F32, +my: F32, +mz: F32,
        +ex: F32, +ey: F32, +ez: F32, +ax: F32, +ay: F32, +az: F32, +leafy: Bool, +wind: U32,
        +axis: F32, +col: U32, +t: F32, +rim: F32, +rim_end: F32, +n: U32, +ymask: U32, +tr: Water.Trace, r: Array<U32> & Column) -> Array<U32> & Ray:
  match fuel:
    case 0n:
      dda_end(col, n, t, rim, rim_end, tr, r)
    case 1n+f:
      (w, words) = r
      Column{+bits, +wetbits, +partialbits, +leafbits, +lo, +hi} = words
      +inside = World.inside(vx, vy, vz)
      +solid = inside && Util.on(bits, ymask) && (col < 1 : U32)
      +here = solid && Bool.not(pierced(solid && Util.on(leafbits, ymask), gaps(), wind, base, vx, vy, vz, axis, t, mx, my, mz, sx, sy, sz, ax, ay, az))
      +ncol = hit(here, axis, col)
      +ux = (mx < my : F32) && (mx < mz : F32)
      +uy = Bool.pick(Bool, ux, False{}, (my < mz : F32))
      +nvx = Bool.pick(F32, ux, (vx + sx : F32), vx)
      +nvy = Bool.pick(F32, uy, (vy + sy : F32), vy)
      +nvz = Bool.pick(F32, ux, vz, Bool.pick(F32, uy, vz, (vz + sz : F32)))
      nmx = Bool.pick(F32, ux, (mx + ex : F32), mx)
      +nmy = Bool.pick(F32, uy, (my + ey : F32), my)
      nmz = Bool.pick(F32, ux, mz, Bool.pick(F32, uy, mz, (mz + ez : F32)))
      naxis = Bool.pick(F32, ux, 0.0, Bool.pick(F32, uy, 1.0, 2.0))
      +nymask = Bool.pick(U32, uy,
        Bool.pick(U32, (sy > 0.0 : F32), U32.shl(ymask), U32.shr(ymask)), ymask)
      +nt = Bool.pick(F32, (ncol < 1 : U32), Bool.pick(F32, ux, mx, Bool.pick(F32, uy, my, mz)), t)
      +ws = seg_start(partial, t, lo)
      +we = seg_end(partial, nt, hi)
      +wet = inside && (ncol < 1 : U32) && Util.on(wetbits, ymask) && (ws < we : F32)
      nn = Water.crossed_top(water, wet, t, ws, we, axis, sy, tr, came_wet(partial, n),
        keep_wet(partial, Bool.pick(U32, (ncol < 1 : U32), (n + 1 : U32), n), inside && Util.on(wetbits, ymask)))
      +over = inside && (col < 1 : U32) && Bool.not(Util.on(bits, ymask)) && Util.on(bits, U32.shr(ymask))
        && Bool.pick(Bool, (sy > 0.0 : F32), ((my - t : F32) > ((1.0 - Grass.top()) * ey : F32) : F32), ((my - nt : F32) < (Grass.top() * ey : F32) : F32))
      dda(~water, ~partial, f, base, nvx, nvy, nvz, sx, sy, sz, nmx, nmy, nmz, ex, ey, ez, ax, ay, az, leafy, wind, naxis, ncol, nt,
          Bool.pick(F32, over && (rim < 0.0 : F32), t, rim), Bool.pick(F32, over, nt, rim_end), nn, nymask,
          Water.crossed(water, wet, ws, we, tr),
          step_in(~water, ~partial, Bool.not(uy) && (ncol < 1 : U32), leafy, w, World.col_at(base, Util.f2u(nvx), Util.f2u(nvz)), nymask, Util.f2u(nvy), sy, nmy, ey,
            bits, wetbits, partialbits, leafbits))

# The walk of a ray from p, t0 along it from its origin o (p = o + d t0):
# the eye's from the eye, the mirror's from the water's surface. Its
# crossings and its rim are distances from o.
def walk_from(~water: Bool, ~partial: Bool, fuel: Nat, w: Array<U32>, +base: U32, +fl: U32, +ck: U32,
              +px: F32, +py: F32, +pz: F32, +dx: F32, +dy: F32, +dz: F32, +t0: F32) -> Array<U32> & Ray:
  +vx = F32.floor(F32.max(px, 0.0))
  +vy = F32.floor(F32.max(py, 0.0))
  +vz = F32.floor(F32.max(pz, 0.0))
  +gx = (dx > 0.0 : F32)
  +gy = (dy > 0.0 : F32)
  +gz = (dz > 0.0 : F32)
  +ax = F32.max(Util.absf(dx), 0.00001)
  +ay = F32.max(Util.absf(dy), 0.00001)
  +az = F32.max(Util.absf(dz), 0.00001)
  +nx = Bool.pick(F32, gx, (vx + 1.0 - px : F32), (px - vx : F32))
  +ny = Bool.pick(F32, gy, (vy + 1.0 - py : F32), (py - vy : F32))
  +nz = Bool.pick(F32, gz, (vz + 1.0 - pz : F32), (pz - vz : F32))
  +sy = Bool.pick(F32, gy, 1.0, (0.0 - 1.0 : F32))
  +ymask = U32.shln(1, F32.to_nat(F32.max(py, 0.0)))
  dda(~water, ~partial, fuel, base, vx, vy, vz,
    Bool.pick(F32, gx, 1.0, (0.0 - 1.0 : F32)),
    sy,
    Bool.pick(F32, gz, 1.0, (0.0 - 1.0 : F32)),
    (t0 + nx / ax : F32), (t0 + ny / ay : F32), (t0 + nz / az : F32),
    (1.0 / ax : F32), (1.0 / ay : F32), (1.0 / az : F32), ax, ay, az, Util.on(fl, 4096), wind_of(fl, ck),
    1.0, 0, t0, (0.0 - 1.0 : F32), 0.0, 0, ymask, Water.Trace{0.0, 0.0},
    column_words(~water, ~partial, Util.on(fl, 4096), w, World.col_at(base, Util.f2u(vx), Util.f2u(vz)), ymask, Util.f2u(vy), sy, (t0 + ny / ay : F32), (1.0 / ay : F32)))

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
      Bool.pick(U32, U32.is_eq(what, 0), Bool.pick(U32, grass_side, Util.rgb(134, 96, 67), Util.rgb(117, 176, 73)), Util.rgb(134, 96, 67)),
      Bool.pick(U32, U32.is_eq(what, 2), Util.rgb(130, 130, 130), Util.rgb(219, 205, 150))),
    Bool.pick(U32, (what < 6 : U32),
      Bool.pick(U32, U32.is_eq(what, 4), Bool.pick(U32, side, Util.rgb(107, 76, 44), Util.rgb(160, 130, 80)), Util.rgb(58, 125, 42)),
      Bool.pick(U32, U32.is_eq(what, 6), Util.rgb(160, 70, 55), Bool.pick(U32, side, Util.rgb(210, 220, 230), Util.rgb(240, 245, 250)))))

# ---------- the glance: a walk over the solid bits ----------
# The shadow's walk and the mirror's, as the primary ray's without the
# water: the fuel's steps whatever happens, the state frozen at the hit,
# the column read once per crossing (refetch), the hit word as the
# primary's and t its distance.
type Glance is Data:
  Glance{col: U32, t: F32}

def glance_end(+col: U32, t: F32, r: Array<U32> & Masks) -> Array<U32> & Glance:
  (w, masks) = r
  (w, Glance{col, t})

def glance(fuel: Nat, +base: U32, +vx: F32, +vy: F32, +vz: F32, +sx: F32, +sy: F32, +sz: F32,
           +mx: F32, +my: F32, +mz: F32, +ex: F32, +ey: F32, +ez: F32, +ax: F32, +ay: F32, +az: F32, +open: U32, +wind: U32,
           +axis: F32, +col: U32, +t: F32, +ymask: U32, r: Array<U32> & Masks) -> Array<U32> & Glance:
  match fuel:
    case 0n:
      glance_end(col, t, r)
    case 1n+f:
      (w, masks) = r
      Masks{+bits, +leaf} = masks
      +solid = World.inside(vx, vy, vz) && Util.on(bits, ymask) && (col < 1 : U32)
      +here = solid && Bool.not(pierced(solid && Util.on(leaf, ymask), open, wind, base, vx, vy, vz, axis, t, mx, my, mz, sx, sy, sz, ax, ay, az))
      +ncol = hit(here, axis, col)
      +ux = (mx < my : F32) && (mx < mz : F32)
      +uy = Bool.pick(Bool, ux, False{}, (my < mz : F32))
      +nvx = Bool.pick(F32, ux, (vx + sx : F32), vx)
      +nvy = Bool.pick(F32, uy, (vy + sy : F32), vy)
      +nvz = Bool.pick(F32, ux, vz, Bool.pick(F32, uy, vz, (vz + sz : F32)))
      nmx = Bool.pick(F32, ux, (mx + ex : F32), mx)
      +nmy = Bool.pick(F32, uy, (my + ey : F32), my)
      nmz = Bool.pick(F32, ux, mz, Bool.pick(F32, uy, mz, (mz + ez : F32)))
      naxis = Bool.pick(F32, ux, 0.0, Bool.pick(F32, uy, 1.0, 2.0))
      nymask = Bool.pick(U32, uy, Bool.pick(U32, (sy > 0.0 : F32), U32.shl(ymask), U32.shr(ymask)), ymask)
      nt = Bool.pick(F32, (ncol < 1 : U32), Bool.pick(F32, ux, mx, Bool.pick(F32, uy, my, mz)), t)
      glance(f, base, nvx, nvy, nvz, sx, sy, sz, nmx, nmy, nmz, ex, ey, ez, ax, ay, az, open, wind, naxis, ncol, nt, nymask,
             refetch(Bool.not(uy) && (ncol < 1 : U32), open, w, base, Util.f2u(nvx), Util.f2u(nvz), bits, leaf))

def run_glance(fuel: Nat, w: Array<U32>, +base: U32, +ox: F32, +oy: F32, +oz: F32,
               +dx: F32, +dy: F32, +dz: F32, +open: U32, +wind: U32) -> Array<U32> & Glance:
  +vx = F32.floor(ox)
  +vy = F32.floor(oy)
  +vz = F32.floor(oz)
  +px = (dx > 0.0 : F32)
  +py = (dy > 0.0 : F32)
  +pz = (dz > 0.0 : F32)
  +ax = F32.max(Util.absf(dx), 0.00001)
  +ay = F32.max(Util.absf(dy), 0.00001)
  +az = F32.max(Util.absf(dz), 0.00001)
  +ex = (1.0 / ax : F32)
  +ey = (1.0 / ay : F32)
  +ez = (1.0 / az : F32)
  glance(fuel, base, vx, vy, vz,
         Bool.pick(F32, px, 1.0, (0.0 - 1.0 : F32)),
         Bool.pick(F32, py, 1.0, (0.0 - 1.0 : F32)),
         Bool.pick(F32, pz, 1.0, (0.0 - 1.0 : F32)),
         (Bool.pick(F32, px, (vx + 1.0 - ox : F32), (ox - vx : F32)) * ex : F32),
         (Bool.pick(F32, py, (vy + 1.0 - oy : F32), (oy - vy : F32)) * ey : F32),
         (Bool.pick(F32, pz, (vz + 1.0 - oz : F32), (oz - vz : F32)) * ez : F32), ex, ey, ez, ax, ay, az, open, wind,
         1.0, 0, 0.0, U32.shln(1, F32.to_nat(F32.max(oy, 0.0))),
         masks_of((open > 0 : U32), World.col_at(base, Util.f2u(vx), Util.f2u(vz)), Array.get(U32, w, World.col_at(base, Util.f2u(vx), Util.f2u(vz)))))

# ---------- the far walk: the columns beyond the window ----------
# A ray the window let go on continues over the far map (World.far_at),
# 128 steps at most: over a cell whose highest top it stays above, a
# step crosses the cell; else it crosses a column. It stops at its hit,
# at the map's edge, once it climbs over the world's top, and at its
# end: where the fog is whole for a pixel's ray (Sky.reach), where the
# window's shadow glance ends for a far block's shadow (shadow_if). So
# a lane of open sky walks a few steps or none; unlike the window's
# walk, the early stop measured faster, since the far walk's lanes part
# by kind, not by a few steps. A column is solid from the floor to its
# solid top (World.far_solid_top), and in its canopy's slab; the ray
# meets a side where it enters a column inside either, a top where it
# drops through one, the canopy's underside where it climbs into it. The
# sea over a column is not solid: with the water on, the walk adds the
# ray's path under its plane to the window's trace, as the window's walk
# does (Water.crossed), and stops where the water's fog is whole.
# The walk starts where the window's walk stopped, so the window's blocks
# show to there and the map's columns from there. It runs in the map's
# coordinates, the window's plus 64 and the corner's remainders plus
# 256, where a column and its cell are floors; a step moves the column
# by one on the axis it crossed, or past the cell's edge after a skip: a
# position found again from the distance would stay put where the ray
# runs along an axis, the float's step over a column being larger than
# the ray's. The hit: 1 an x side, 2 a top or an underside, 3 a z side,
# 0 nothing; with it the column's word. Only a sky pixel's lane pays for
# it: a tile of ground alone skips it.
type Far is Data:
  Far{hit: U32, word: U32, t: F32, water: Water.Trace}

def far_read(w: Array<U32>, +cx: F32, +cz: F32) -> Array<U32> & U32:
  Array.get(U32, w, World.far_at(Util.f2u(cx), Util.f2u(cz)))

def far_end(+hit: U32, +word: U32, t: F32, tr: Water.Trace, r: Array<U32> & U32) -> Array<U32> & Far:
  (w, x) = r
  (w, Far{hit, word, t, tr})

# the walk goes on while the ray is in the map (n columns a side, the
# window's 128 or the far map's 256) and can still meet a column that
# shows: a ray at or over 32, the top of the world, climbing, cannot, nor
# one past its end
def inside(+n: F32, +cx: F32, +cz: F32) -> Bool:
  (cx >= 0.0 : F32) && (cx < n : F32) && (cz >= 0.0 : F32) && (cz < n : F32)

def can_meet(+oy: F32, +dy: F32, +t: F32, +end: F32) -> Bool:
  Bool.not((dy >= 0.0 : F32) && ((oy + dy * t : F32) >= 32.0 : F32)) && (t < end : F32)

# the column a skip lands in along the axis it did not cross: the
# ray's, kept inside the cell it crossed, the float's error aside
def clamp4(+k: F32, +p: F32) -> F32:
  F32.clamp(F32.floor(p), k, (k + 3.0 : F32))

# a step from the column (cx, cz) the ray is in at t: the distances to
# the column's and the cell's far planes along x and z (ix, iz the
# inverse steps, px1, pz1 one where the step is positive)
def far(fuel: Nat, go: Bool, +bx: F32, +bz: F32, +fox: F32, +foz: F32, +dx: F32, +dz: F32, +ix: F32, +iz: F32, +px1: F32, +pz1: F32,
        +oy: F32, +dy: F32, +iy: F32, +end: F32, +t: F32, +on: Bool, +tr: Water.Trace, +ax: F32, +hit: U32, +hw: U32, +cx: F32, +cz: F32, r: Array<U32> & U32) -> Array<U32> & Far:
  match fuel:
    case 0n:
      far_end(hit, hw, t, tr, r)
    case 1n+f:
      match go:
        case False{}:
          far_end(hit, hw, t, tr, r)
        case True{}:
          (w, +word) = r
          +sea = World.far_sea(word)
          +run = Util.u2f(World.far_solid_top(word))
          +lb = Util.u2f((word / 1024 % 32 : U32))
          +lt = Util.u2f((word / 32768 % 32 : U32))
          +slab = (lt > lb : F32)
          +kx = (F32.floor((cx * 0.25 : F32)) * 4.0 : F32)
          +kz = (F32.floor((cz * 0.25 : F32)) * 4.0 : F32)
          +tcx = ((cx + px1 - fox) * ix : F32)
          +tcz = ((cz + pz1 - foz) * iz : F32)
          +tkx = ((kx + 4.0 * px1 - fox) * ix : F32)
          +tkz = ((kz + 4.0 * pz1 - foz) * iz : F32)
          +tc = F32.min(tcx, tcz)
          +tk = F32.min(tkx, tkz)
          +y0 = (oy + dy * t : F32)
          +y1 = (oy + dy * tc : F32)
          +skip = (F32.min(y0, (oy + dy * tk : F32)) >= Util.u2f((word / 1048576 % 32 : U32)) : F32)
          +side = Bool.not(skip) && ((y0 < run : F32) || (slab && (y0 >= lb : F32) && (y0 < lt : F32)))
          +roof = Bool.not(skip) && Bool.not(side) && slab && (y0 >= lt : F32) && (y1 < lt : F32)
          +top = Bool.not(skip) && Bool.not(side) && Bool.not(roof) && (y1 < run : F32)
          +under = Bool.not(skip) && Bool.not(side) && slab && (y0 < lb : F32) && (y1 >= lb : F32)
          +nhit = Bool.pick(U32, side, Bool.pick(U32, (ax > 1.5 : F32), 2, Bool.pick(U32, (ax > 0.5 : F32), 1, 3)), Bool.pick(U32, roof || top || under, 2, 0))
          +nt = Bool.pick(F32, skip, tk, Bool.pick(F32, side, t, Bool.pick(F32, roof, ((lt - oy) * iy : F32), Bool.pick(F32, top, ((run - oy) * iy : F32),
            Bool.pick(F32, under, ((lb - oy) * iy : F32), tc)))))
          +t12 = ((12.0 - oy) * iy : F32)
          +ws = Bool.pick(F32, (y0 < 12.0 : F32), t, t12)
          +wn = Bool.pick(F32, ((oy + dy * nt : F32) < 12.0 : F32), nt, t12)
          +ntr = Water.crossed(on, sea && (ws < wn : F32), ws, wn, tr)
          +ux = (tcx < tcz : F32)
          +uk = (tkx < tkz : F32)
          +ncx = Bool.pick(F32, skip, Bool.pick(F32, uk, (kx - 1.0 + 5.0 * px1 : F32), clamp4(kx, (fox + dx * tk : F32))),
            Bool.pick(F32, ux, (cx - 1.0 + 2.0 * px1 : F32), cx))
          +ncz = Bool.pick(F32, skip, Bool.pick(F32, uk, clamp4(kz, (foz + dz * tk : F32)), (kz - 1.0 + 5.0 * pz1 : F32)),
            Bool.pick(F32, ux, cz, (cz - 1.0 + 2.0 * pz1 : F32)))
          far(f, (nhit < 1 : U32) && inside(256.0, (ncx - bx : F32), (ncz - bz : F32)) && can_meet(oy, dy, nt, end) && Water.clear(ntr),
              bx, bz, fox, foz, dx, dz, ix, iz, px1, pz1, oy, dy, iy, end, nt, on, ntr, Bool.pick(F32, skip, Bool.pick(F32, uk, 1.0, 0.0), Bool.pick(F32, ux, 1.0, 0.0)), nhit, word, ncx, ncz, far_read(w, ncx, ncz))

# where a ray leaves the window's columns by a side: a walk in the window
# goes on over the far map from there, since past it the window holds
# nothing, and a block near the side would lose what lies beyond it
def window_exit(+ox: F32, +oz: F32, +dx: F32, +dz: F32) -> F32:
  +px = (dx > 0.0 : F32)
  +pz = (dz > 0.0 : F32)
  F32.min((Bool.pick(F32, px, (128.0 - ox : F32), (0.0 - ox : F32)) / Bool.pick(F32, px, F32.max(dx, 0.00001), F32.min(dx, (0.0 - 0.00001 : F32))) : F32),
    (Bool.pick(F32, pz, (128.0 - oz : F32), (0.0 - oz : F32)) / Bool.pick(F32, pz, F32.max(dz, 0.00001), F32.min(dz, (0.0 - 0.00001 : F32))) : F32))

# where a glance of the window reaches, blocks along the axes over its steps
def reach_of(+blocks: F32, +dx: F32, +dy: F32, +dz: F32) -> F32:
  (blocks / (Util.absf(dx) + Util.absf(dy) + Util.absf(dz)) : F32)

# how far a coordinate lies from the grid's nearest plane
def off_grid(+q: F32) -> F32:
  Util.absf((q - F32.floor((q + 0.5 : F32)) : F32))

# from the window's walk's end, a hair on: the map's coordinates of the
# eye and of the point's column. The window's walk ends on the plane it
# last crossed, into a cell it did not test: the far walk may start
# inside a block, and names the face it came in through by that plane
# (ax: 2 y, 1 x, 0 z), a top where the ray came down onto it
def run_far(fuel: Nat, w: Array<U32>, +fw: U32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, +t0: F32, +end: F32, +on: Bool, tr: Water.Trace) -> Array<U32> & Far:
  +t = (t0 + 0.001 : F32)
  +bx = Util.u2f((fw / 256 + 256 : U32))
  +bz = Util.u2f((fw % 256 + 256 : U32))
  +fox = (ox + 64.0 + bx : F32)
  +foz = (oz + 64.0 + bz : F32)
  +cx = F32.floor((fox + dx * (t + 0.002) : F32))
  +cz = F32.floor((foz + dz * (t + 0.002) : F32))
  +px1 = (dx > 0.0 : F32)
  +pz1 = (dz > 0.0 : F32)
  +ex = off_grid((fox + dx * t0 : F32))
  +ey = off_grid((oy + dy * t0 : F32))
  +ez = off_grid((foz + dz * t0 : F32))
  far(fuel, can_meet(oy, dy, t, end) && inside(256.0, (cx - bx : F32), (cz - bz : F32)), bx, bz, fox, foz, dx, dz,
      (1.0 / Bool.pick(F32, px1, F32.max(dx, 0.00001), F32.min(dx, (0.0 - 0.00001 : F32))) : F32),
      (1.0 / Bool.pick(F32, pz1, F32.max(dz, 0.00001), F32.min(dz, (0.0 - 0.00001 : F32))) : F32),
      Bool.pick(F32, px1, 1.0, 0.0), Bool.pick(F32, pz1, 1.0, 0.0), oy, dy, (1.0 / dy : F32), end, t, on, tr,
      Bool.pick(F32, (ey < F32.min(ex, ez) : F32), 2.0, Bool.pick(F32, (ex < ez : F32), 1.0, 0.0)), 0, 0, cx, cz, far_read(w, cx, cz))

# ---------- a face ----------
# The hit point p = o + d t lies on a face of the block h; the cell before
# the face, c, is air: the floor of p, except along the face's axis, where
# p sits on the boundary and c is the side the ray came from, h the other.
# u runs along z on an x face and along x otherwise, w along z on a y face
# and along y otherwise; the face's tone is 0.8 on x, 1.0 on top, 0.7 on
# z; da is the ray's step along the face's axis, so the face looks at the
# sun when the ray came against the sun's (`facing`).
type Face is Data:
  Face{px: F32, py: F32, pz: F32, ax: Bool, ay: Bool, hx: F32, hy: F32, hz: F32, cx: F32, cy: F32, cz: F32, da: F32, u: F32, wf: F32, tone: F32}

def face(+axis: U32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, +t: F32) -> Face:
  +px = (ox + dx * t : F32)
  +py = (oy + dy * t : F32)
  +pz = (oz + dz * t : F32)
  +ax = U32.is_eq(axis, 0)
  +ay = U32.is_eq(axis, 1)
  +az = U32.is_eq(axis, 2)
  +bx = F32.floor((px + 0.5 : F32))
  +by = F32.floor((py + 0.5 : F32))
  +bz = F32.floor((pz + 0.5 : F32))
  +cx = Bool.pick(F32, ax, Bool.pick(F32, (dx > 0.0 : F32), (bx - 1.0 : F32), bx), F32.floor(px))
  +cy = Bool.pick(F32, ay, Bool.pick(F32, (dy > 0.0 : F32), (by - 1.0 : F32), by), F32.floor(py))
  +cz = Bool.pick(F32, az, Bool.pick(F32, (dz > 0.0 : F32), (bz - 1.0 : F32), bz), F32.floor(pz))
  Face{px, py, pz, ax, ay,
       Bool.pick(F32, ax, Bool.pick(F32, (dx > 0.0 : F32), bx, (bx - 1.0 : F32)), cx),
       Bool.pick(F32, ay, Bool.pick(F32, (dy > 0.0 : F32), by, (by - 1.0 : F32)), cy),
       Bool.pick(F32, az, Bool.pick(F32, (dz > 0.0 : F32), bz, (bz - 1.0 : F32)), cz),
       cx, cy, cz, Bool.pick(F32, ax, dx, Bool.pick(F32, ay, dy, dz)),
       Bool.pick(F32, ax, pz, px), Bool.pick(F32, ay, pz, py), Bool.pick(F32, ax, 0.8, Bool.pick(F32, ay, 1.0, 0.7))}

# the cosine of the body's angle to the face's normal (l, the sun or the
# moon, Sky.side), 0 for a face turned from it or with it under the horizon
def facing(+da: F32, +ax: Bool, +ay: Bool, +lx: F32, +ly: F32, +lz: F32) -> F32:
  +l = Bool.pick(F32, ax, lx, Bool.pick(F32, ay, ly, lz))
  Bool.pick(F32, (ly > 0.0 : F32) && ((da * l : F32) < 0.0 : F32), Util.absf(l), 0.0)

# the word holding the type of the block h: one read through the handle
def type_word(w: Array<U32>, +base: U32, +hx: F32, +hy: F32, +hz: F32) -> Array<U32> & U32:
  Array.get(U32, w, (World.col_at(base, Util.f2u(hx), Util.f2u(hz)) + 1 + Util.f2u(hy) / 8 : U32))

# A block of the far map (distant) is shaded as the window's are: its
# type from its column's word (World.far_type), its occlusion's cells
# and its shadow's walk read from the far map, in the window's
# coordinates plus 64 and the corner's remainders (fm, Cam.far). A far
# cell is solid under its column's solid top (World.far_solid_top) and in
# its canopy.
def far_solid(+y: F32, r: Array<U32> & U32) -> Array<U32> & Bool:
  (w, +word) = r
  (w, (y < Util.u2f(World.far_solid_top(word)) : F32)
    || ((y >= Util.u2f((word / 1024 % 32 : U32)) : F32) && (y < Util.u2f((word / 32768 % 32 : U32)) : F32)))

def cell_solid(far: Bool, w: Array<U32>, +base: U32, +fm: U32, +x: F32, +y: F32, +z: F32) -> Array<U32> & Bool:
  match far:
    case False{}:
      World.solid(w, base, x, y, z)
    case True{}:
      far_solid(y, Array.get(U32, w, World.far_at(Util.f2u((x + 320.0 + Util.u2f((fm / 256 : U32)) : F32)),
        Util.f2u((z + 320.0 + Util.u2f((fm % 256 : U32)) : F32)))))

# a cell past the window's side is the far map's, for a block near it too
def solid_in(distant: Bool, w: Array<U32>, +base: U32, +fm: U32, +x: F32, +y: F32, +z: F32) -> Array<U32> & Bool:
  cell_solid(distant || Bool.not(inside(128.0, x, z)), w, base, fm, x, y, z)

# the word that holds the block's type: the window's, or the far column's own
def type_of(distant: Bool, w: Array<U32>, +base: U32, +word: U32, +hx: F32, +hy: F32, +hz: F32) -> Array<U32> & U32:
  match distant:
    case False{}:
      type_word(w, base, hx, hy, hz)
    case True{}:
      (w, word)

# the shadow: a glance of 24 steps towards the sun from a hair before the
# face, the far walk for a far block and past the window's side, to where
# the glance's 24 steps reach (21 over |lx| + |ly| + |lz|, as Water.reach counts faces); a face turned away
# from the sun is in shadow without a walk, and with the shadow flag off
# every face is lit
def far_shadow(r: Array<U32> & Far) -> Array<U32> & Bool:
  (w, fr) = r
  Far{hit, word, t, tr} = fr
  (w, (hit > 0 : U32))

def shadow_past(past: Bool, +c: U32, w: Array<U32>, +fm: U32, +ox: F32, +oy: F32, +oz: F32, +lx: F32, +ly: F32, +lz: F32) -> Array<U32> & Bool:
  match past:
    case False{}:
      (w, (c > 0 : U32))
    case True{}:
      far_shadow(run_far(24n, w, fm, ox, oy, oz, lx, ly, lz, window_exit(ox, oz, lx, lz), reach_of(21.0, lx, ly, lz), False{}, Water.Trace{0.0, 0.0}))

# a glance that met nothing ended past the window's side if its last
# crossing, at t, lies there
def shadow_fin(+fm: U32, +ox: F32, +oy: F32, +oz: F32, +lx: F32, +ly: F32, +lz: F32, r: Array<U32> & Glance) -> Array<U32> & Bool:
  (w, g) = r
  Glance{+c, +t} = g
  shadow_past((c < 1 : U32) && Bool.not(inside(128.0, (ox + lx * t : F32), (oz + lz * t : F32))), c, w, fm, ox, oy, oz, lx, ly, lz)

def shadow_if(on: Bool, sunny: Bool, distant: Bool, w: Array<U32>, +base: U32, +fm: U32,
              +ox: F32, +oy: F32, +oz: F32, +lx: F32, +ly: F32, +lz: F32, +open: U32, +wind: U32) -> Array<U32> & Bool:
  match on:
    case False{}:
      (w, False{})
    case True{}:
      match sunny:
        case False{}:
          (w, True{})
        case True{}:
          match distant:
            case False{}:
              shadow_fin(fm, ox, oy, oz, lx, ly, lz, run_glance(24n, w, base, ox, oy, oz, lx, ly, lz, open, wind))
            case True{}:
              far_shadow(run_far(24n, w, fm, ox, oy, oz, lx, ly, lz, 0.0, reach_of(21.0, lx, ly, lz), False{}, Water.Trace{0.0, 0.0}))

# The eight cells around c along the face, one read each, as bits of m:
# 1 +u, 2 -u, 4 +w, 8 -w, 16 +u+w, 32 -u+w, 64 +u-w, 128 -u-w, the cell
# of bit i being c + su(i) u + sw(i) w. A vertex of the face is lit by its
# two sides and its corner: 3 steps of light, none when both sides are
# solid; the face blends its four vertices.
def su(+i: U32) -> F32:
  Bool.pick(F32, (i < 2 : U32) || (i >= 4 : U32), Bool.pick(F32, U32.is_eq((i % 2 : U32), 0), 1.0, (0.0 - 1.0 : F32)), 0.0)

def sw(+i: U32) -> F32:
  Bool.pick(F32, (i < 2 : U32), 0.0, Bool.pick(F32, U32.is_eq(i, 2) || U32.is_eq(i, 4) || U32.is_eq(i, 5), 1.0, (0.0 - 1.0 : F32)))

def vao(+s1: Bool, +s2: Bool, c: Bool) -> F32:
  +n = (Bool.pick(U32, s1, 1, 0) + Bool.pick(U32, s2, 1, 0) + Bool.pick(U32, c, 1, 0) : U32)
  Bool.pick(F32, s1 && s2, 0.4, (1.0 - 0.2 * Util.u2f(n) : F32))

def ao_fin(held: Bool, +v: U32, +col: U32, +f: F32, +sun: F32, +tint: Sky.Tint, +lamp: F32, +m: U32, +fu: F32, +fw: F32, r: Array<U32> & Bool) -> Array<U32> & U32:
  (w, s) = r
  +m8 = Bool.pick(U32, s, (m .|. 128 : U32), m)
  +pp = vao(Util.on(m8, 1), Util.on(m8, 4), Util.on(m8, 16))
  +mp = vao(Util.on(m8, 2), Util.on(m8, 4), Util.on(m8, 32))
  +pm = vao(Util.on(m8, 1), Util.on(m8, 8), Util.on(m8, 64))
  +mm = vao(Util.on(m8, 2), Util.on(m8, 8), Util.on(m8, 128))
  +ao = ((mm * (1.0 - fu) + pm * fu) * (1.0 - fw) + (mp * (1.0 - fu) + pp * fu) * fw : F32)
  (w, Util.mix(Torch.lit(held, col, (ao * sun : F32), tint, (ao * lamp : F32)), v, f))

def ao(n: Nat, +distant: Bool, +v: U32, +col: U32, +f: F32, +sun: F32, +tint: Sky.Tint, +lamp: F32, +base: U32, +fm: U32, +m: U32, +bit: U32, +i: U32,
       +ox: F32, +oy: F32, +oz: F32, +ux: F32, +uy: F32, +uz: F32, +ex: F32, +ey: F32, +ez: F32, +fu: F32, +fw: F32,
       r: Array<U32> & Bool) -> Array<U32> & U32:
  match n:
    case 0n:
      ao_fin(Torch.held(base), v, col, f, sun, tint, lamp, m, fu, fw, r)
    case 1n+k:
      (w, s) = r
      +j = (i + 1 : U32)
      +sj = su(j)
      +wj = sw(j)
      ao(k, distant, v, col, f, sun, tint, lamp, base, fm, Bool.pick(U32, s, (m .|. bit : U32), m), (bit * 2 : U32), j, ox, oy, oz, ux, uy, uz, ex, ey, ez, fu, fw,
         solid_in(distant, w, base, fm, (ox + sj * ux + wj * ex : F32), (oy + sj * uy + wj * ey : F32), (oz + sj * uz + wj * ez : F32)))

# after the sun: the first neighbour read, or none with the occlusion off;
# the sun the face takes and the light's colour from it (hue, bit 17)
def after_sun(+distant: Bool, +v: U32, +col: U32, +f: F32, +base: U32, +fm: U32, +ox: F32, +oy: F32, +oz: F32,
              +ux: F32, +uy: F32, +uz: F32, +ex: F32, +ey: F32, +ez: F32, +fu: F32, +fw: F32, +lit: F32,
              +hue: Bool, +ndl: F32, +ly: F32, +lamp: F32, aon: Bool, r: Array<U32> & Bool) -> Array<U32> & U32:
  match aon:
    case True{}:
      (w, +dark) = r
      +sun = Sky.sunned(hue, dark, lit, ndl)
      ao(7n, distant, v, col, f, sun, Sky.light(hue, sun, ly), lamp, base, fm, 0, 1, 0, ox, oy, oz, ux, uy, uz, ex, ey, ez, fu, fw,
         solid_in(distant, w, base, fm, (ox + ux : F32), (oy + uy : F32), (oz + uz : F32)))
    case False{}:
      (w, +dark) = r
      +sun = Sky.sunned(hue, dark, lit, ndl)
      (w, Util.mix(Torch.lit(Torch.held(base), col, sun, Sky.light(hue, sun, ly), lamp), v, f))

def tex_if(on: Bool, +u: F32, +wf: F32) -> F32:
  match on:
    case True{}:
      texture(u, wf)
    case False{}:
      1.0

# ---------- the mirror: the world seen in the water's top ----------
# A glance from where the ray met the water or a puddle, along its
# mirrored direction, 32 steps. What it meets gets the block's colour, its
# texture and its face's tone, with no occlusion and no shadow ray:
# ripples and fog blur the rest, and it fades into the sky towards the end
# of the walk's reach. Only a pixel that shows a water top or a puddle
# pays for it. The mirror shows the world where its ray met a block,
# fogged into the sky behind it, and that sky alone where it met none: the
# same arithmetic as before the world was in it, so a miss is the same
# byte.

# a block's colour, lit by tone and textured by tex, but for a grass top
# with the meadow on: the meadow seen from afar at (x, z), t from the eye
def meadow_top(meadow: Bool, +fm: U32, +x: F32, +z: F32, +t: F32, +c: U32, +tone: F32, +tex: F32) -> U32:
  match meadow:
    case True{}:
      Util.dim(Grass.afar(fm, x, z, t), tone)
    case False{}:
      Util.dim(c, (tone * tex : F32))

# The meadow the ray passed from its rim (Ray) to what it met
# (src/grass.bend), lit where it met the blades or else the floor under
# them: in the sun or the shadow of what stands between, fogged and wet
# as there, the fog seen from the eye at height eye; a torch in hand lights
# them as it lights a face it meets square.
def rim_lit(+base: U32, +fw: U32, +ck: U32, +fl: U32, +eye: F32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, +v: U32,
            +lx: F32, +ly: F32, +lz: F32, +c: U32, +at: F32, lw: Grass.Meadow, r: Array<U32> & Bool) -> Array<U32> & U32:
  (w, +dark) = r
  +sg = Sky.side(Sky.moon_on(fl), ly)
  +sun = Bool.pick(F32, dark, 0.6, Clouds.shade(Util.on(fl, 256), fw, ck, (ox + dx * at : F32), (oy + dy * at : F32), (oz + dz * at : F32), (sg * lx : F32), (sg * ly : F32), (sg * lz : F32)))
  +level = Sky.level(Sky.moon_on(fl), ly)
  (w, Grass.over(c, v, Sky.fog(fl, at, eye, (oy + dy * at : F32)), sun,
    Torch.lamp(Torch.held(base), Sky.light(Util.on(fl, 131072), sun, ly), Torch.over(Torch.held(base), ck, at, 1.0, (level * 0.8 : F32))), level,
    Wet.wetness(Util.on(fl, 1024), ck), Grass.dryness(fw, (ox + dx * at : F32), (oz + dz * at : F32)), dx, dy, dz, (sg * lx : F32), (sg * ly : F32), (sg * lz : F32), lw))

def rim_seen(seen: Bool, +base: U32, +fw: U32, +ck: U32, +fl: U32, +eye: F32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, +v: U32,
             +lx: F32, +ly: F32, +lz: F32, +c: U32, +at: F32, lw: Grass.Meadow, w: Array<U32>) -> Array<U32> & U32:
  match seen:
    case False{}:
      (w, c)
    case True{}:
      +sg = Sky.side(Sky.moon_on(fl), ly)
      rim_lit(base, fw, ck, fl, eye, ox, oy, oz, dx, dy, dz, v, lx, ly, lz, c, at, lw,
        shadow_if(Util.on(fl, 1), ((sg * ly : F32) > 0.0 : F32), False{}, w, base, fw, (ox + dx * at : F32), (oy + dy * at : F32), (oz + dz * at : F32), (sg * lx : F32), (sg * ly : F32), (sg * lz : F32), sun_gaps(fl), wind_of(fl, ck)))

# the blades take the sun's shafts in the air before them (sh, Shafts)
def rim_met(+base: U32, +fw: U32, +ck: U32, +fl: U32, +eye: F32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, +v: U32,
            +lx: F32, +ly: F32, +lz: F32, +c: U32, +t1: F32, +sh: U32, r: Array<U32> & Grass.Meadow) -> Array<U32> & U32:
  (w, lw) = r
  Grass.Meadow{+tr, +n, +lit, +s, +head, +heart, +t, +hue, +low} = lw
  +at = ((t + 0.001 * t1) / (n + 0.001) : F32)
  Shafts.over(Shafts.on(fl, base, ly), sh, at, (1.0 - tr : F32), ck, dx, dy, dz, lx, ly, lz,
    rim_seen((tr < 0.999 : F32) || (low > 0.0 : F32), base, fw, ck, fl, eye, ox, oy, oz, dx, dy, dz, v, lx, ly, lz, c, at,
      Grass.Meadow{tr, n, lit, s, head, heart, t, hue, low}, w))

def rimmed(on: Bool, +base: U32, +fw: U32, +ck: U32, +fl: U32, +eye: F32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
           +rim: F32, +t1: F32, +v: U32, +lx: F32, +ly: F32, +lz: F32, +sh: U32, r: Array<U32> & U32) -> Array<U32> & U32:
  match on:
    case False{}:
      r
    case True{}:
      (w, +c) = r
      rim_met(base, fw, ck, fl, eye, ox, oy, oz, dx, dy, dz, v, lx, ly, lz, c, t1, sh, Grass.march(w, base, fw, ck, ox, oy, oz, dx, dy, dz, rim, t1))

# the block the mirror's ray met: its type's colour, the texture (a grass
# top the meadow seen from afar), the face's tone, darker when the face
# is turned from the sun; over far water the ray walks the far map, to
# the walk's reach
def glance_fin(+distant: Bool, +sky: U32, +fl: U32, +fm: U32, +hy: U32, +side: Bool, +yf: F32, +u: F32, +wf: F32, +x: F32, +z: F32, +t: F32,
               +tone: F32, +tint: Sky.Tint, +f: F32, r: Array<U32> & U32) -> Array<U32> & U32:
  (w, +word) = r
  +what = Bool.pick(U32, distant, World.far_type(word, hy), World.nib_at(word, hy))
  (w, Util.mix(Sky.tinted(meadow_top(Util.on(fl, 2048) && U32.is_eq(what, 0) && Bool.not(side), fm, x, z, t, blockcol(what, side, yf), tone, tex_if(Util.on(fl, 4), u, wf)), tint),
    sky, f))

def glance_face(+distant: Bool, +word: U32, +sky: U32, +fl: U32, +base: U32, +fm: U32, +dx: F32, +dy: F32, +dz: F32,
                +far: F32, +eye: F32, +lx: F32, +ly: F32, +lz: F32, +t: F32, w: Array<U32>, fc: Face) -> Array<U32> & U32:
  Face{+px, +py, +pz, +ax, +ay, +hx, +hy, +hz, cx, cy, cz, +da, u, wf, +tone} = fc
  +sg = Sky.side(Sky.moon_on(fl), ly)
  +ndl = facing(da, ax, ay, (sg * lx : F32), (sg * ly : F32), (sg * lz : F32))
  +sun = Sky.sunned(Util.on(fl, 131072), (ndl <= 0.0 : F32), 1.0, ndl)
  glance_fin(distant, sky, fl, fm, Util.f2u(hy), Bool.not(ay), Util.fracf(py), u, wf, px, pz, t,
    (tone * Sky.level(Sky.moon_on(fl), ly) * sun : F32), Sky.light(Util.on(fl, 131072), sun, ly),
    F32.max(Sky.fog(fl, t, eye, py), Water.reach((t - far : F32), dx, dy, dz)),
    type_of(distant, w, base, word, hx, hy, hz))

def glance_look(got: Bool, +distant: Bool, +word: U32, +sky: U32, +fl: U32, +base: U32, +fm: U32,
                +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
                +far: F32, +eye: F32, +lx: F32, +ly: F32, +lz: F32, +c: U32, +t: F32, w: Array<U32>) -> Array<U32> & U32:
  match got:
    case False{}:
      (w, sky)
    case True{}:
      glance_face(distant, word, sky, fl, base, fm, dx, dy, dz, far, eye, lx, ly, lz, t, w, face((c - 1 : U32), ox, oy, oz, dx, dy, dz, t))

def far_glance_open(+sky: U32, +fl: U32, +base: U32, +fm: U32,
                    +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
                    +far: F32, +eye: F32, +lx: F32, +ly: F32, +lz: F32, r: Array<U32> & Far) -> Array<U32> & U32:
  (w, fr) = r
  Far{+hit, word, t, tr} = fr
  glance_look((hit > 0 : U32), True{}, word, sky, fl, base, fm, ox, oy, oz, dx, dy, dz, far, eye, lx, ly, lz, hit, t, w)

# The mirror's ray: the eye's own seen in the water, from the eye's image
# o under it, walked from the surface on, far along it, so its distances
# are the eye's and the meadow, the fog and a pixel's width read them as
# the eye's ray's. Past the window's side the far walk takes it on.
def glance_past(past: Bool, +sky: U32, +fl: U32, +base: U32, +fm: U32,
                +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
                +far: F32, +eye: F32, +lx: F32, +ly: F32, +lz: F32, +c: U32, +t: F32, w: Array<U32>) -> Array<U32> & U32:
  match past:
    case False{}:
      glance_look((c > 0 : U32), False{}, 0, sky, fl, base, fm, ox, oy, oz, dx, dy, dz, far, eye, lx, ly, lz, c, t, w)
    case True{}:
      far_glance_open(sky, fl, base, fm, ox, oy, oz, dx, dy, dz, far, eye, lx, ly, lz,
        run_far(32n, w, fm, ox, oy, oz, dx, dy, dz, (far + window_exit((ox + dx * far : F32), (oz + dz * far : F32), dx, dz) : F32),
          (far + reach_of(28.0, dx, dy, dz) : F32), False{}, Water.Trace{0.0, 0.0}))

# the mirror's walk: what it met, and the meadow it passed over (bit 16),
# without the blades' shadows or the shafts in the air
def mirror_open(+sky: U32, +fl: U32, +base: U32, +fm: U32, +ck: U32,
                +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
                +far: F32, +eye: F32, +lx: F32, +ly: F32, +lz: F32, r: Array<U32> & Ray) -> Array<U32> & U32:
  (w, ray) = r
  Ray{+code, +t, +rim, +rim_end, tr} = ray
  +c = (code % 4 : U32)
  rimmed(Util.on(fl, 2048) && Util.on(fl, 65536) && (rim >= 0.0 : F32), (base .&. 3221225471 : U32), fm, ck, (fl .&. 4294967294 : U32), eye, ox, oy, oz, dx, dy, dz,
    rim, F32.min(t, rim_end), sky, lx, ly, lz, 0,
    glance_past((c < 1 : U32) && Bool.not(inside(128.0, (ox + dx * t : F32), (oz + dz * t : F32))), sky, fl, base, fm,
      ox, oy, oz, dx, dy, dz, far, eye, lx, ly, lz, c, t, w))

def mirror_walk(distant: Bool, +sky: U32, +fl: U32, +base: U32, +fm: U32, +ck: U32, +px: F32, +py: F32, +pz: F32,
                +rx: F32, +ry: F32, +rz: F32, +far: F32, +eye: F32, +lx: F32, +ly: F32, +lz: F32, w: Array<U32>) -> Array<U32> & U32:
  match distant:
    case False{}:
      mirror_open(sky, fl, base, fm, ck, (px - rx * far : F32), (py - ry * far : F32), (pz - rz * far : F32), rx, ry, rz, far, eye, lx, ly, lz,
        walk_from(~False{}, ~False{}, 32n, w, base, fl, ck, px, py, pz, rx, ry, rz, far))
    case True{}:
      far_glance_open(sky, fl, base, fm, (px - rx * far : F32), (py - ry * far : F32), (pz - rz * far : F32), rx, ry, rz, far, eye, lx, ly, lz,
        run_far(32n, w, fm, (px - rx * far : F32), (py - ry * far : F32), (pz - rz * far : F32), rx, ry, rz, far, (far + reach_of(28.0, rx, ry, rz) : F32),
          False{}, Water.Trace{0.0, 0.0}))

def framed(bottom: U32, m: Water.Reflection, r: Array<U32> & U32) -> Array<U32> & Water.Mirror:
  (w, colour) = r
  (w, Water.Mirror{bottom, m, colour})

# the world in the mirror is a look of its own (bit 27 of the camera's
# base); its walk starts a hair over the water, in the air the ray came through
def mirror_world(world: Bool, +distant: Bool, +fm: U32, +ck: U32, +fl: U32, +base: U32, +px: F32, +py: F32, +pz: F32,
                 +far: F32, +eye: F32, +lx: F32, +ly: F32, +lz: F32, +m: Water.Reflection, +sky: U32,
                 r: Array<U32> & U32) -> Array<U32> & Water.Mirror:
  match world:
    case False{}:
      (w, bottom) = r
      (w, Water.Mirror{bottom, m, sky})
    case True{}:
      Water.Reflection{+rx, +ry, +rz, cosine} = m
      (w, bottom) = r
      framed(bottom, m, mirror_walk(distant, sky, fl, base, fm, ck, px, (py + 0.01 : F32), pz, rx, ry, rz, far, eye, lx, ly, lz, w))

# the sky behind the mirror at p, along its ray m
def behind(world: Bool, +distant: Bool, +fm: U32, +ck: U32, +fl: U32, +base: U32, +px: F32, +py: F32, +pz: F32,
           +far: F32, +eye: F32, +lx: F32, +ly: F32, +lz: F32, m: Water.Reflection, r: Array<U32> & U32) -> Array<U32> & Water.Mirror:
  Water.Reflection{+rx, +ry, +rz, +cosine} = m
  mirror_world(world, distant, fm, ck, fl, base, px, py, pz, far, eye, lx, ly, lz, Water.Reflection{rx, ry, rz, cosine},
    Clouds.mirrored(fl, fm, ck, px, py, pz, rx, ry, rz, lx, ly, lz), r)

# the water's top at p under the rain, whose rings reach it only where no
# block of its column (mask) is over its cell, as the wet reaches a face
def sheltered(+distant: Bool, +fm: U32, +ck: U32, +rain: F32, +fl: U32, +base: U32, +px: F32, +py: F32, +pz: F32,
              +dx: F32, +dy: F32, +dz: F32, +entry: F32, +oy: F32, +lx: F32, +ly: F32, +lz: F32, +bottom: U32,
              r: Array<U32> & U32) -> Array<U32> & Water.Mirror:
  (w, mask) = r
  behind(Water.mirror_on(base), distant, fm, ck, fl, base, px, py, pz, entry, oy, lx, ly, lz,
    Water.reflected(Water.ripples_on(fl), base, ck, Wet.reached(distant, rain, F32.floor((py - 0.01 : F32)), mask), px, pz, entry, dx, dy, dz),
    (w, bottom))

def mirrored(go: Bool, +distant: Bool, +fm: U32, +ck: U32, +rain: F32, +fl: U32, +base: U32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
             +entry: F32, +lx: F32, +ly: F32, +lz: F32, r: Array<U32> & U32) -> Array<U32> & Water.Mirror:
  match go:
    case False{}:
      (w, bottom) = r
      (w, Water.Mirror{bottom, Water.flat(dx, dy, dz), 0})
    case True{}:
      (w, bottom) = r
      +px = (ox + dx * entry : F32)
      +pz = (oz + dz * entry : F32)
      sheltered(distant, fm, ck, rain, fl, base, px, (oy + dy * entry : F32), pz, dx, dy, dz, entry, oy, lx, ly, lz, bottom,
        Array.get(U32, w, World.col_at(base, Util.f2u(px), Util.f2u(pz))))

# ---------- the wet: what the rain leaves on a face (src/wet.bend) ----------
# The air cell's column tells whether the rain reaches the face; a
# puddle's mirror walks the world as the lake's does, with the world in
# the mirror (bit 27 of the base), and any other face mirrors the sky.

def sheened(+v: U32, +f: F32, +soak: F32, +pud: F32, r: Array<U32> & Water.Mirror) -> Array<U32> & U32:
  (w, mi) = r
  Water.Mirror{c, m, shown} = mi
  Water.Reflection{x, y, z, cosine} = m
  (w, Wet.sheen(c, v, f, soak, pud, cosine, shown))

# its mirror stands where the ray met a puddle, and in the air cell's
# middle for the sky alone; the rain's rings fade over 32 blocks, as the
# lake's ripples do
def soaked(+distant: Bool, +wet: F32, +base: U32, +fm: U32, +ck: U32, +cx: F32, +cy: F32, +cz: F32, +puddly: Bool, +x: F32, +z: F32,
           +t: F32, +oy: F32, m: Water.Reflection, +v: U32, +f: F32, +fl: U32, +lx: F32, +ly: F32, +lz: F32, +c: U32,
           r: Array<U32> & U32) -> Array<U32> & U32:
  (w, mask) = r
  +soak = Wet.reached(distant, wet, cy, mask)
  +pud = Bool.pick(F32, puddly, Wet.puddle(fm, x, z, soak), 0.0)
  sheened(v, f, soak, pud,
    behind((pud > 0.0 : F32) && Water.mirror_on(base), distant, fm, ck, fl, base,
      Bool.pick(F32, puddly, x, (cx + 0.5 : F32)), Bool.pick(F32, puddly, cy, (cy + 0.5 : F32)), Bool.pick(F32, puddly, z, (cz + 0.5 : F32)),
      t, oy, lx, ly, lz,
      Wet.mirror_of(puddly, base, ck, Rain.falling(Util.on(fl, 512), ck), x, z, (0.15 * pud * (1.0 - F32.clamp((t / 32.0 : F32), 0.0, 1.0)) : F32), m),
      (w, c)))

# the face soaked, or as it was in a dry world, whose air is not read
def soak(on: Bool, +distant: Bool, +wet: F32, +base: U32, +fm: U32, +ck: U32, +cx: F32, +cy: F32, +cz: F32, +puddly: Bool,
         +x: F32, +z: F32, +t: F32, +oy: F32, m: Water.Reflection, +v: U32, +f: F32, +fl: U32, +lx: F32, +ly: F32, +lz: F32,
         r: Array<U32> & U32) -> Array<U32> & U32:
  match on:
    case False{}:
      r
    case True{}:
      (w, c) = r
      soaked(distant, wet, base, fm, ck, cx, cy, cz, puddly, x, z, t, oy, m, v, f, fl, lx, ly, lz, c,
        Array.get(U32, w, World.col_at(base, Util.f2u(cx), Util.f2u(cz))))

def facing_up(m: Water.Reflection) -> Bool:
  Water.Reflection{x, y, z, cosine} = m
  (y > 0.0 : F32)

# the type read: one word through the handle, then the look, soaked in
# a wet world; the ground's tops (grass, dirt, stone, sand, brick) hold
# puddles
def typed(+distant: Bool, +v: U32, +fl: U32, +base: U32, +fm: U32, +ck: U32, +hy: U32, +side: Bool, +yf: F32, +u: F32, +wf: F32, +tone: F32, +f: F32,
          +cx: F32, +cy: F32, +cz: F32, +ux: F32, +uz: F32, +ey: F32, +ez: F32, +fu: F32, +fw: F32,
          +lx: F32, +ly: F32, +lz: F32, +ndl: F32, +sx: F32, +sy: F32, +sz: F32, +t: F32, +oy: F32, +lamp: F32, +m: Water.Reflection,
          r: Array<U32> & U32) -> Array<U32> & U32:
  (w, +word) = r
  +sg = Sky.side(Sky.moon_on(fl), ly)
  +what = Bool.pick(U32, distant, World.far_type(word, hy), World.nib_at(word, hy))
  +col = meadow_top(Util.on(fl, 2048) && U32.is_eq(what, 0) && Bool.not(side), fm, sx, sz, t, blockcol(what, side, yf), tone, tex_if(Util.on(fl, 4), u, wf))
  +wet = Wet.wetness(Util.on(fl, 1024), ck)
  soak((wet > 0.0 : F32), distant, wet, base, fm, ck, cx, cy, cz,
    Bool.not(side) && ((what < 4 : U32) || U32.is_eq(what, 6)) && facing_up(m), u, wf, t, oy, m, v, f, fl, lx, ly, lz,
    after_sun(distant, v, col, f, base, fm, cx, cy, cz, ux, 0.0, uz, 0.0, ey, ez, fu, fw,
              Clouds.shade(Util.on(fl, 256), fm, ck, sx, sy, sz, (sg * lx : F32), (sg * ly : F32), (sg * lz : F32)), Util.on(fl, 131072), ndl, ly, lamp, Util.on(fl, 2),
              shadow_if(Util.on(fl, 1), (ndl > 0.0 : F32), distant, w, base, fm, sx, sy, sz, (sg * lx : F32), (sg * ly : F32), (sg * lz : F32), sun_gaps(fl), wind_of(fl, ck))))

# the look of the block behind the face: its unit steps of u and w in
# space, where on the face for the blend of the four vertices, the
# shadow ray's start a hair before the face, in c, and the ray mirrored
# by the face, with how flat it meets it
def shade_face(+distant: Bool, w: Array<U32>, +base: U32, +fm: U32, +ck: U32, +word: U32, +v: U32, +oy: F32, +t: F32, +fl: U32,
               +dx: F32, +dy: F32, +dz: F32, +lx: F32, +ly: F32, +lz: F32, fc: Face) -> Array<U32> & U32:
  Face{+px, +py, +pz, +ax, +ay, +hx, +hy, +hz, +cx, +cy, +cz, +da, +u, +wf, +tone} = fc
  +nudge = Bool.pick(F32, (da > 0.0 : F32), (0.0 - 0.01 : F32), 0.01)
  +sg = Sky.side(Sky.moon_on(fl), ly)
  +level = Sky.level(Sky.moon_on(fl), ly)
  typed(distant, v, fl, base, fm, ck, Util.f2u(hy), Bool.not(ay), Util.fracf(py), u, wf, (tone * level : F32), Sky.fog(fl, t, oy, py),
        cx, cy, cz, Bool.pick(F32, ax, 0.0, 1.0), Bool.pick(F32, ax, 1.0, 0.0), Bool.pick(F32, ay, 0.0, 1.0), Bool.pick(F32, ay, 1.0, 0.0),
        Util.fracf(u), Util.fracf(wf), lx, ly, lz, facing(da, ax, ay, (sg * lx : F32), (sg * ly : F32), (sg * lz : F32)),
        Bool.pick(F32, ax, (px + nudge : F32), px),
        Bool.pick(F32, ay, (py + nudge : F32), py),
        Bool.pick(F32, Bool.not(ax) && Bool.not(ay), (pz + nudge : F32), pz),
        t, oy, Torch.over(Torch.held(base), ck, t, da, level), Water.Reflection{Bool.pick(F32, ax, (0.0 - dx : F32), dx), Bool.pick(F32, ay, (0.0 - dy : F32), dy),
          Bool.pick(F32, Bool.not(ax) && Bool.not(ay), (0.0 - dz : F32), dz), Util.absf(da)},
        type_of(distant, w, base, word, hx, hy, hz))

def shade_go(sky: Bool, +distant: Bool, +word: U32, w: Array<U32>, +base: U32, +fw: U32, +ck: U32, +v: U32, +ox: F32, +oy: F32, +oz: F32,
             +dx: F32, +dy: F32, +dz: F32, +c: U32, +t: F32, +fl: U32, +lx: F32, +ly: F32, +lz: F32) -> Array<U32> & U32:
  match sky:
    case True{}:
      Clouds.above(w, fl, fw, ck, v, ox, oy, oz, dx, dy, dz, lx, ly, lz)
    case False{}:
      shade_face(distant, w, base, fw, ck, word, v, oy, t, fl, dx, dy, dz, lx, ly, lz, face((c - 1 : U32), ox, oy, oz, dx, dy, dz, t))

# the profile's pixels: the steps to the hit (flag 32), or 1 on a hit (64)
def shade_mode(steps: Bool, hits: Bool, sky: Bool, +distant: Bool, +word: U32, w: Array<U32>, +base: U32, +fw: U32, +ck: U32, +v: U32,
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
          shade_go(sky, distant, word, w, base, fw, ck, v, ox, oy, oz, dx, dy, dz, c, t, fl, lx, ly, lz)

# the water over the bed: the wet path's height for an eye in the air,
# whole for a submerged one (its path starts at the eye, not the surface)
def thickness(+entry: F32, +depth: F32, +dy: F32) -> F32:
  Bool.pick(F32, (entry > 0.0 : F32), (depth * Util.absf(dy) : F32), 9.0)

# the bed's light under the water: the caustic, on a block a wet ray met,
# a look of its own (bit 28 of the camera's base). At night its factor is
# 1.0 (Sky.daylight is 0 from 0.12 under the horizon), and the sun's
# height is the same for every pixel, so skipping it there costs no
# divergence and changes no byte.
def bed(on: Bool, +base: U32, +ck: U32, +x: F32, +z: F32, +drop: F32, +dy: F32, +ly: F32, +thick: F32, r: Array<U32> & U32) -> Array<U32> & U32:
  match on:
    case False{}: r
    case True{}:
      (w, c) = r
      (w, Util.dim(c, Water.caustic(base, ck, x, z, drop, dy, ly, thick)))

# ---------- the surface seen from under the water ----------
# A ray from a submerged eye that leaves the water up, with the look on
# (Cam.fl bit 15), shows the surface where it leaves, not what its straight
# walk met: Snell's window, the world out of the water along the bent ray
# as the lake's mirror walks it (`behind`), the rain falling in it, and
# past the window the underside's mirror, the world under the water seen
# in it. Fresnel weighs the two, a mirror at the window's edge. A ray
# that met a block under the water has a wet path its hit's distance long,
# less a rounding of its sum: it left the water only 0.01 short of the hit.
def rises(+fl: U32, +dy: F32, +t: F32, +entry: F32, +depth: F32) -> Bool:
  Util.on(fl, 32768) && (depth > 0.0 : F32) && (entry <= 0.0 : F32) && (dy > 0.0 : F32) && ((depth + 0.01 : F32) < t : F32)

def shown(r: Array<U32> & Water.Mirror) -> Array<U32> & U32:
  (w, m) = r
  Water.Mirror{bottom, x, colour} = m
  (w, colour)

def weighed(+f: F32, +ink: U32, r: Array<U32> & U32) -> Array<U32> & U32:
  (w, c) = r
  (w, Util.mix(c, ink, f))

# the underside's mirror: a glance down from the surface, what it met
# lit as deep as it lies and fogged by the water it went through, the
# deep water's colour where it met nothing
def under_lit(+light: F32, +fog: F32, +ink: U32, r: Array<U32> & U32) -> Array<U32> & U32:
  (w, c) = r
  (w, Util.mix(Util.dim(c, light), ink, fog))

def underside(+fl: U32, +base: U32, +fm: U32, +px: F32, +py: F32, +pz: F32, +rx: F32, +ry: F32, +rz: F32,
              +lx: F32, +ly: F32, +lz: F32, r: Array<U32> & Glance) -> Array<U32> & U32:
  (w, g) = r
  Glance{+c, +t} = g
  +down = Water.drop((py + ry * t : F32))
  +ink = Water.colour(ly)
  under_lit(Water.light(down), Water.opacity(False{}, t), Water.ink_at(ink, ly, down),
    glance_look((c > 0 : U32), False{}, 0, ink, (fl .&. 2147483639 : U32), base, fm, px, py, pz, rx, ry, rz, 0.0, py, lx, ly, lz, c, t, w))

def window(inside: Bool, +fm: U32, +ck: U32, +rain: F32, +fl: U32, +base: U32, +px: F32, +py: F32, +pz: F32,
           +lx: F32, +ly: F32, +lz: F32, +tx: F32, +ty: F32, +tz: F32, +ct: F32, r: Array<U32> & U32) -> Array<U32> & U32:
  match inside:
    case False{}:
      r
    case True{}:
      (w, +mirror) = r
      weighed(Water.fresnel(Water.fresnel_on(fl), ct), mirror,
        Rain.fall((rain > 0.0 : F32), rain, ck, fm, base, px, py, pz, tx, ty, tz, 12.0, ly,
          shown(behind(Water.mirror_on(base), False{}, fm, ck, fl, base, px, py, pz, 0.0, py, lx, ly, lz,
            Water.Reflection{tx, ty, tz, ct}, (w, 0)))))

def looked_out(+fm: U32, +ck: U32, +rain: F32, +fl: U32, +base: U32, +px: F32, +py: F32, +pz: F32,
               +lx: F32, +ly: F32, +lz: F32, u: Water.Underside, w: Array<U32>) -> Array<U32> & U32:
  Water.Underside{+tx, +ty, +tz, +ct, +rx, +ry, +rz} = u
  window((ct > 0.0 : F32), fm, ck, rain, fl, base, px, py, pz, lx, ly, lz, tx, ty, tz, ct,
    underside(fl, base, fm, px, py, pz, rx, ry, rz, lx, ly, lz, run_glance(24n, w, base, px, (py - 0.01 : F32), pz, rx, ry, rz, 0, 0)))

# the rain's rings reach the surface where no block of its column (mask)
# is over it, as over the lake
def surfaced(+fm: U32, +ck: U32, +rain: F32, +fl: U32, +base: U32, +px: F32, +py: F32, +pz: F32,
             +dx: F32, +dy: F32, +dz: F32, +depth: F32, +lx: F32, +ly: F32, +lz: F32, r: Array<U32> & U32) -> Array<U32> & U32:
  (w, mask) = r
  looked_out(fm, ck, rain, fl, base, px, py, pz, lx, ly, lz,
    Water.refracted(Water.ripples_on(fl), base, ck, Wet.reached(False{}, rain, F32.floor((py - 0.01 : F32)), mask), px, pz, depth, dx, dy, dz), w)

# what the ray showed past its water: the surface over a submerged eye,
# or what its walk met
def beyond(out: Bool, +rain: F32, +fl: U32, +depth: F32, steps: Bool, hits: Bool, sky: Bool, +distant: Bool, +word: U32, w: Array<U32>,
           +base: U32, +fw: U32, +ck: U32, +v: U32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
           +c: U32, +t: F32, +n: U32, +gl: U32, +lx: F32, +ly: F32, +lz: F32) -> Array<U32> & U32:
  match out:
    case False{}:
      shade_mode(steps, hits, sky, distant, word, w, base, fw, ck, v, ox, oy, oz, dx, dy, dz, c, t, n, gl, lx, ly, lz)
    case True{}:
      +px = (ox + dx * depth : F32)
      +pz = (oz + dz * depth : F32)
      surfaced(fw, ck, rain, fl, base, px, (oy + dy * depth : F32), pz, dx, dy, dz, depth, lx, ly, lz,
        Array.get(U32, w, World.col_at(base, Util.f2u(px), Util.f2u(pz))))

# What the ray met, under the water it went through: the window's hit or
# the far walk's (distant), the water's surface met by either, and its
# mirror walked where the surface was met.
def seen(+distant: Bool, +mirror_far: Bool, +word: U32, +hitw: U32, +n: U32, +top: Bool, +v: U32, +fl: U32, +lx: F32, +ly: F32, +lz: F32,
         +base: U32, +fw: U32, +ck: U32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, +t: F32, tr: Water.Trace, w: Array<U32>) -> Array<U32> & U32:
  Water.Trace{+entry, +depth} = tr
  +wet = (depth > 0.0 : F32) && Bool.not(Util.on(fl, 96))
  +out = wet && rises(fl, dy, t, entry, depth)
  +ground_flags = Bool.pick(U32, wet, (fl .&. 2147482615 : U32), fl)
  +rain = Rain.falling(Util.on(fl, 512), ck)
  Rain.fall((rain > 0.0 : F32), rain, ck, fw, base, ox, oy, oz, dx, dy, dz, Bool.pick(F32, wet, entry, t), ly,
  Water.shade(wet, fl, v, Torch.ink(Torch.held(base), Water.colour(ly), Water.colour(1.0), Torch.over(Torch.held(base), ck, entry, 1.0, 1.0)), oy, dy, ly, top, t, (hitw > 0 : U32) && Bool.not(out), Water.Trace{entry, depth},
    mirrored(wet && top && Water.reflection_on(fl), mirror_far, fw, ck, rain, fl, base, ox, oy, oz, dx, dy, dz, entry, lx, ly, lz,
      bed(wet && (hitw > 0 : U32) && Water.caustic_on(base) && (ly > (0.0 - 0.12 : F32) : F32), base, ck, (ox + dx * t : F32), (oz + dz * t : F32), Water.drop((oy + dy * t : F32)), dy, ly, thickness(entry, depth, dy),
        beyond(out, rain, fl, depth, Util.on(fl, 32), Util.on(fl, 64), (hitw < 1 : U32), distant, word, w, base, fw, ck, v, ox, oy, oz, dx, dy, dz, hitw, t, n, ground_flags, lx, ly, lz)))))

# the far walk's hit, under the water the window's walk and its own
# crossed; the surface is the far walk's where the window's walk stayed
# dry. A miss's distance is the window's end (t0): the far walk's says
# nothing, and the water's ink is read at it.
def from_far(+c: U32, +near_wet: Bool, +t0: F32, +v: U32, +fl: U32, +lx: F32, +ly: F32, +lz: F32, +base: U32, +fw: U32, +ck: U32,
             +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, r: Array<U32> & Far) -> Array<U32> & U32:
  (w, fr) = r
  Far{+hit, +word, +t, tr} = fr
  seen(True{}, Bool.not(near_wet), word, hit, Water.steps(c), Water.top(c) || Bool.not(near_wet), v, fl, lx, ly, lz,
    base, fw, ck, ox, oy, oz, dx, dy, dz, Bool.pick(F32, (hit > 0 : U32), t, t0), tr, w)

# the profile's renders stay in the window, and so does the surface over
# a submerged eye; a ray the window's walk let go on walks the far map
def after_walk(near: Bool, +c: U32, +v: U32, +fl: U32, +lx: F32, +ly: F32, +lz: F32, +base: U32, +fw: U32, +ck: U32,
               +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, +t: F32, +entry: F32, +depth: F32, w: Array<U32>) -> Array<U32> & U32:
  match near:
    case True{}:
      seen(False{}, False{}, 0, (c % 4 : U32), Water.steps(c), Water.top(c), v, fl, lx, ly, lz, base, fw, ck, ox, oy, oz, dx, dy, dz, t, Water.Trace{entry, depth}, w)
    case False{}:
      from_far(c, (depth > 0.0 : F32), t, v, fl, lx, ly, lz, base, fw, ck, ox, oy, oz, dx, dy, dz,
        run_far(128n, w, fw, ox, oy, oz, dx, dy, dz, F32.min(t, window_exit(ox, oz, dx, dz)), Sky.reach(), Util.on(fl, 2097152), Water.Trace{entry, depth}))

# The grass stands from the rim to its end, what the ray met or the
# water it went into, which hides what it holds.
# The shafts (sh, Shafts) lie over the air the ray crossed to what it met,
# or to its water, or as far as they reach where the window's walk let it
# go on.
def shade_fin(+v: U32, +fl: U32, +lx: F32, +ly: F32, +lz: F32, +base: U32, +fw: U32, +ck: U32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
              +c: U32, +t: F32, +rim: F32, +rim_end: F32, +sh: U32, w: Array<U32>, tr: Water.Trace) -> Array<U32> & U32:
  Water.Trace{+entry, +depth} = tr
  rimmed(Util.on(fl, 2048) && (rim >= 0.0 : F32),
    base, fw, ck, fl, oy, ox, oy, oz, dx, dy, dz, rim, F32.min(F32.min(t, rim_end), Bool.pick(F32, (depth > 0.0 : F32), entry, t)), v, lx, ly, lz, sh,
    Shafts.over(Shafts.on(fl, base, ly), sh, Bool.pick(F32, (depth > 0.0 : F32), entry, Bool.pick(F32, ((c % 4 : U32) > 0 : U32), t, Shafts.open_air(oy, dy))), 1.0,
      ck, dx, dy, dz, lx, ly, lz,
      after_walk(((c % 4 : U32) > 0 : U32) || Util.on(fl, 96) || rises(fl, dy, t, entry, depth), c, v, fl, lx, ly, lz, base, fw, ck, ox, oy, oz, dx, dy, dz, t, entry, depth, w)))

def shade(+v: U32, +fl: U32, +lx: F32, +ly: F32, +lz: F32, w: Array<U32>, +base: U32, +fw: U32, +ck: U32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
          +sh: U32, ct: Ray) -> Array<U32> & U32:
  Ray{+c, +t, +rim, +rim_end, tr} = ct
  shade_fin(v, fl, lx, ly, lz, base, fw, ck, ox, oy, oz, dx, dy, dz, c, t, rim, rim_end, sh, w, tr)

def finish(+v: U32, +fl: U32, +lx: F32, +ly: F32, +lz: F32, +base: U32, +fw: U32, +ck: U32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
           +sh: U32, r: Array<U32> & Ray) -> Array<U32> & U32:
  (w, ct) = r
  shade(v, fl, lx, ly, lz, w, base, fw, ck, ox, oy, oz, dx, dy, dz, sh, ct)

def run_dda(~water: Bool, ~partial: Bool, w: Array<U32>, +base: U32, +fw: U32, +ck: U32, +ox: F32, +oy: F32, +oz: F32,
            +dx: F32, +dy: F32, +dz: F32, +v: U32, +fl: U32, +lx: F32, +ly: F32, +lz: F32, +sh: U32) -> Array<U32> & U32:
  finish(v, fl, lx, ly, lz, base, fw, ck, ox, oy, oz, dx, dy, dz, sh, walk_from(~water, ~partial, 60n, w, base, fl, ck, ox, oy, oz, dx, dy, dz, 0.0))

def run_partial(part: Bool, w: Array<U32>, +base: U32, +fw: U32, +ck: U32, +ox: F32, +oy: F32, +oz: F32,
                +dx: F32, +dy: F32, +dz: F32, +v: U32, +fl: U32, +lx: F32, +ly: F32, +lz: F32, +sh: U32) -> Array<U32> & U32:
  match part:
    case False{}: run_dda(~True{}, ~False{}, w, base, fw, ck, ox, oy, oz, dx, dy, dz, v, fl, lx, ly, lz, sh)
    case True{}: run_dda(~True{}, ~True{}, w, base, fw, ck, ox, oy, oz, dx, dy, dz, v, fl, lx, ly, lz, sh)

def run_water(on: Bool, w: Array<U32>, +base: U32, +fw: U32, +ck: U32, +ox: F32, +oy: F32, +oz: F32,
              +dx: F32, +dy: F32, +dz: F32, +v: U32, +fl: U32, +lx: F32, +ly: F32, +lz: F32, +sh: U32) -> Array<U32> & U32:
  match on:
    case False{}: run_dda(~False{}, ~False{}, w, base, fw, ck, ox, oy, oz, dx, dy, dz, v, fl, lx, ly, lz, sh)
    case True{}: run_partial(Util.on(base, 536870912), w, base, fw, ck, ox, oy, oz, dx, dy, dz, v, fl, lx, ly, lz, sh)

def blank(+counts: Bool, r: Array<U32> & U32) -> Array<U32> & U32:
  (w, c) = r
  (w, Bool.pick(U32, counts, 0, c))

# A ray that misses the loaded box reads the world zero times but for the
# clouds' map (and counts no step and no hit under the profile's flags).
def shoot(go: Bool, w: Array<U32>, +base: U32, +fw: U32, +ck: U32, +ox: F32, +oy: F32, +oz: F32,
          +dx: F32, +dy: F32, +dz: F32, +v: U32, +fl: U32, +lx: F32, +ly: F32, +lz: F32, +sh: U32) -> Array<U32> & U32:
  match go:
    case False{}:
      blank(((fl .&. 96) > 0 : U32), Clouds.above(w, fl, fw, ck, v, ox, oy, oz, dx, dy, dz, lx, ly, lz))
    case True{}:
      run_water(Util.on(fl, 2097152), w, base, fw, ck, ox, oy, oz, dx, dy, dz, v, fl, lx, ly, lz, sh)

def clipped(w: Array<U32>, +base: U32, +fw: U32, +ck: U32, +ox: F32, +oy: F32, +oz: F32,
            +dx: F32, +dy: F32, +dz: F32, +v: U32, +fl: U32, +lx: F32, +ly: F32, +lz: F32, +sh: U32) -> Array<U32> & U32:
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
  shoot((tin < tout : F32), w, base, fw, ck, (ox + dx * s : F32), (oy + dy * s : F32), (oz + dz * s : F32), dx, dy, dz, v, fl, lx, ly, lz, sh)

# ---------- the player ----------

# The camera is Data, shared down the fork; the world is the array, threaded.
# `v` down the leaf is the ray's atmospheric colour, ready for the fog. `fl` is the
# flags: 1 shadow, 2 occlusion, 4 texture, 8 fog, 16 HUD (the game passes
# Render.looks()); 32 makes the pixel the ray's steps to its hit, 64 makes it 1 on a
# hit and 0 on sky: `make profile` renders with each and prints what costs
# what. Bit 7 is the clouds, 8 their shadows, 9 the rain, 10 the wet, 11 the meadow, 12 the leaves' holes, 13 the sun through them,
# 14 the leaves in the wind, 15 the surface from under the water, 16 the meadow in the
# mirrors, 17 the light's colour, 18 the sun's halo, 19 the lens; bit 20 enables ripples. Bits 21..24
# hold water (21), water fog (22), Fresnel (23) and sky reflection (24). Bits 25..31 enable the day cycle, sky
# gradient, sun disc, horizon glow, stars, moon and height fog, respectively.
# sel holds selection in its low four bits, then four seven-bit counts;
# items holds the other four. Counts are capped for the HUD. stat holds
# the readout's numbers and the bucket's full cells (stat_of, with_pail).
# base keeps the ring's low 14 bits; far the far map's base
# (World.far_cam); clock the game's, whose days the weather follows and
# whose milliseconds the ripples; seen how much of the sun, or the moon,
# the eye sees (sighted), for the lens.
type Cam is Data:
  Cam{px: F32, py: F32, pz: F32, yaw: F32, pit: F32, base: U32, far: U32, sel: U32, items: U32, stat: U32, fl: U32, rw: U32, rh: U32, lx: F32, ly: F32, lz: F32, clock: U32, seen: F32}

# Bit 25 selects the clock's sun; disabled, the profile uses the old sun.
def looks() -> U32: 4294967199

# the looks that ride in the camera's base, bits 27..31: 27 the world in
# the water's mirror, 28 the caustic on its bed; 29 says the window holds
# a cell of partial water, so the rays clip to planes (Frame.view_w
# sets it from the world's count); 30 the sun's light in the haze
# (Shafts); 31 the torches' light (Torch), whose bit 26 says the eye
# holds one
def looks_base() -> U32: 3623878656

def with_partial(+more: U32, some: Bool) -> U32:
  Bool.pick(U32, some, (more .|. 536870912 : U32), more)

def camera(px: F32, py: F32, pz: F32, yaw: F32, pit: F32, base: U32, far: U32, more: U32, +sel: U32, items: U32, stat: U32,
           +fl: U32, rw: U32, rh: U32, +clock: U32) -> Cam:
  +cycle = Util.on(fl, 33554432)
  Cam{px, py, pz, yaw, pit, Torch.in_hand(Water.with_looks(base, more), sel), far, sel, items, stat, fl, rw, rh,
      Bool.pick(F32, cycle, Day.sun_x(clock), 0.48),
      Bool.pick(F32, cycle, Day.sun_y(clock), 0.8),
      Bool.pick(F32, cycle, Day.sun_z(clock), 0.36), clock, 0.0}

# ---------- the sun as the eye sees it ----------
# How much of the sun, or of the moon once it has set (Sky.side), the eye
# sees, for the lens (src/lens.bend), found on the host once a frame:
# thirteen rays from the eye, to the body's middle and to two rings of six
# points within its disc, each walked as a pixel's ray is, through the
# window, the leaves' gaps and the water, and on over the far map; a ray
# that meets a block or water hides its share, so the body fades in steps
# of a thirteenth as it goes behind an edge. The clouds the sky shows on
# its line dim what is left (Clouds.unveiled), and it sets and rises
# (Sky.strength).
def wet_path(tr: Water.Trace) -> Bool:
  Water.Trace{entry, +depth} = tr
  (depth > 0.0 : F32)

def clear_far(r: Array<U32> & Far) -> Array<U32> & F32:
  (w, fr) = r
  Far{+hit, word, t, tr} = fr
  (w, Bool.pick(F32, (hit > 0 : U32), 0.0, 1.0))

def clear_past(met: Bool, w: Array<U32>, +fw: U32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, +t: F32) -> Array<U32> & F32:
  match met:
    case True{}:
      (w, 0.0)
    case False{}:
      clear_far(run_far(128n, w, fw, ox, oy, oz, dx, dy, dz, F32.min(t, window_exit(ox, oz, dx, dz)), Sky.reach(), False{}, Water.Trace{0.0, 0.0}))

def clear_ray(+fw: U32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, r: Array<U32> & Ray) -> Array<U32> & F32:
  (w, ray) = r
  Ray{+code, +t, rim, rim_end, tr} = ray
  clear_past(((code % 4 : U32) > 0 : U32) || wet_path(tr), w, fw, ox, oy, oz, dx, dy, dz, t)

def added(+sum: F32, r: Array<U32> & F32) -> Array<U32> & F32:
  (w, +s) = r
  (w, (sum + s : F32))

# the ray to the body's middle (i 0), then to six points 0.013 off it and
# six 0.027 off it between them, along a and b across its line; the disc
# is 0.036 across its middle, the moon's 0.047
def body_rays(n: Nat, +base: U32, +fw: U32, +fl: U32, +ck: U32, +ox: F32, +oy: F32, +oz: F32, +lx: F32, +ly: F32, +lz: F32,
              +ax: F32, +az: F32, +bx: F32, +by: F32, +bz: F32, +i: U32, r: Array<U32> & F32) -> Array<U32> & F32:
  match n:
    case 0n:
      r
    case 1n+k:
      (w, +sum) = r
      +ring = Bool.pick(F32, (i < 1 : U32), 0.0, Bool.pick(F32, (i < 7 : U32), 0.013, 0.027))
      +angle = (U32.to_f32(i) * 1.0471976 + Bool.pick(F32, (i < 7 : U32), 0.0, 0.5235988) : F32)
      +sa = (ring * F32.cos(angle) : F32)
      +sb = (ring * F32.sin(angle) : F32)
      +dx = (lx + sa * ax + sb * bx : F32)
      +dy = (ly + sb * by : F32)
      +dz = (lz + sa * az + sb * bz : F32)
      body_rays(k, base, fw, fl, ck, ox, oy, oz, lx, ly, lz, ax, az, bx, by, bz, (i + 1 : U32),
        added(sum, clear_ray(fw, ox, oy, oz, dx, dy, dz, walk_from(~True{}, ~False{}, 60n, w, base, fl, ck, ox, oy, oz, dx, dy, dz, 0.0))))

def seen_of(+fl: U32, +fw: U32, +ck: U32, +ox: F32, +oy: F32, +oz: F32, +lx: F32, +ly: F32, +lz: F32, +k: F32, r: Array<U32> & F32) -> Array<U32> & F32:
  (w, +rays) = r
  (w, (rays / 13.0 * Clouds.unveiled(Util.on(fl, 128), fw, ck, ox, oy, oz, lx, ly, lz) * k : F32))

# the body l, as bright as k
def sight(on: Bool, w: Array<U32>, +base: U32, +fw: U32, +fl: U32, +ck: U32, +ox: F32, +oy: F32, +oz: F32, +lx: F32, +ly: F32, +lz: F32, +k: F32) -> Array<U32> & F32:
  match on:
    case False{}:
      (w, 0.0)
    case True{}:
      +al = F32.max(F32.sqrt((lx * lx + lz * lz : F32)), 0.0001)
      +ax = (lz / al : F32)
      +az = ((0.0 - lx) / al : F32)
      seen_of(fl, fw, ck, ox, oy, oz, lx, ly, lz, k,
        body_rays(13n, base, fw, fl, ck, ox, oy, oz, lx, ly, lz, ax, az, (0.0 - az * ly : F32), (az * lx - ax * lz : F32), (ax * ly : F32), 0, (w, 0.0)))

def with_seen(cam: Cam, +s: F32) -> Cam:
  Cam{px, py, pz, yaw, pit, base, far, sel, items, stat, fl, rw, rh, lx, ly, lz, clock, seen} = cam
  Cam{px, py, pz, yaw, pit, base, far, sel, items, stat, fl, rw, rh, lx, ly, lz, clock, s}

def seen_into(+cam: Cam, r: Array<U32> & F32) -> Array<U32> & Cam:
  (w, +s) = r
  (w, with_seen(cam, s))

# the camera with the sun or the moon it sees, the lens on (Cam.fl bit 19)
def sighted(w: Array<U32>, +cam: Cam) -> Array<U32> & Cam:
  Cam{+px, +py, +pz, yaw, pit, +base, +far, sel, items, stat, +fl, rw, rh, +lx, +ly, +lz, +clock, seen} = cam
  +s = Sky.side(Sky.moon_on(fl), ly)
  seen_into(cam, sight(Util.on(fl, 524288), w, base, far, fl, clock, px, py, pz, (s * lx : F32), (s * ly : F32), (s * lz : F32), Sky.strength(Sky.moon_on(fl), ly)))

def look_x(+yaw: F32, +pit: F32) -> F32: (F32.cos(pit) * F32.sin(yaw) : F32)
def look_y(+pit: F32) -> F32: F32.sin(pit)
def look_z(+yaw: F32, +pit: F32) -> F32: (F32.cos(pit) * F32.cos(yaw) : F32)

def norm3(+x: F32, +y: F32, +z: F32) -> F32:
  F32.sqrt((x * x + y * y + z * z : F32))

# the screen in the camera's units: the height spans -1..1, the width by
# its aspect
def p2f(+p: U32, +size: U32, +rh: U32) -> F32:
  ((U32.to_f32((p * 2 : U32)) - U32.to_f32(size)) / U32.to_f32(rh) : F32)

# the eye's ray through the screen's point (u, v), normalised, with the
# camera's forward f, its level right r (f across the world's up) and its
# up e (r across f), which the lens reads
type Aim is Data:
  Aim{dx: F32, dy: F32, dz: F32, fx: F32, fy: F32, fz: F32, rx: F32, rz: F32, ex: F32, ey: F32, ez: F32}

def aim(+yaw: F32, +pit: F32, +u: F32, +v: F32) -> Aim:
  +fx = look_x(yaw, pit)
  +fy = look_y(pit)
  +fz = look_z(yaw, pit)
  +rl = F32.max(norm3(fz, 0.0, (0.0 - fx : F32)), 0.00001)
  +rx = (fz / rl : F32)
  +rz = ((0.0 - fx) / rl : F32)
  +ex = (0.0 - rz * fy : F32)
  +ey = (rz * fx - rx * fz : F32)
  +ez = (rx * fy : F32)
  +dx = (fx + 0.9 * u * rx + 0.9 * v * ex : F32)
  +dy = (fy + 0.9 * v * ey : F32)
  +dz = (fz + 0.9 * u * rz + 0.9 * v * ez : F32)
  +n = F32.max(norm3(dx, dy, dz), 0.00001)
  Aim{(dx / n : F32), (dy / n : F32), (dz / n : F32), fx, fy, fz, rx, rz, ex, ey, ez}

def lensed(on: Bool, +seen: F32, +u: F32, +v: F32, +dx: F32, +dy: F32, +dz: F32, +fx: F32, +fy: F32, +fz: F32,
           +rx: F32, +rz: F32, +ex: F32, +ey: F32, +ez: F32, +lx: F32, +ly: F32, +lz: F32, r: Array<U32> & U32) -> Array<U32> & U32:
  (w, +c) = r
  (w, Lens.through(on, c, seen, u, v, dx, dy, dz, fx, fy, fz, rx, rz, ex, ey, ez, lx, ly, lz))

def shade_aim(+ox: F32, +oy: F32, +oz: F32, +base: U32, +far: U32, +fl: U32, +lx: F32, +ly: F32, +lz: F32, +ck: U32, +seen: F32,
              +u: F32, +v: F32, +prof: U32, w: Array<U32>, a: Aim) -> Array<U32> & U32:
  Aim{+dx, +dy, +dz, +fx, +fy, +fz, +rx, +rz, +ex, +ey, +ez} = a
  lensed(Util.on(fl, 524288), seen, u, v, dx, dy, dz, fx, fy, fz, rx, rz, ex, ey, ez, lx, ly, lz,
    clipped(w, base, far, ck, ox, oy, oz, dx, dy, dz, Clouds.sky(fl, ck, dx, dy, dz, lx, ly, lz), fl, lx, ly, lz, prof))

# sh holds the tile's shafts (beams), which the pixel weighs by its place
def shade_px(+cam: Cam, w: Array<U32>, +pxi: U32, +pyi: U32, +sh: Shafts.Beams) -> Array<U32> & U32:
  Cam{ox, oy, oz, yaw, pit, base, far, sel, items, stat, +fl, +rw, +rh, +lx, +ly, +lz, +ck, +seen} = cam
  +u = p2f(pxi, rw, rh)
  +v = p2f(pyi, rh, rh)
  shade_aim(ox, oy, oz, base, far, fl, lx, ly, lz, ck, seen, u, v,
    Shafts.profile(sh, (U32.to_f32((pxi % 4 : U32)) * 0.25 : F32), (U32.to_f32((pyi % 4 : U32)) * 0.25 : F32)), w, aim(yaw, pit, u, v))

# a crosshair straight over the middle
def cross_at(+pxi: U32, +pyi: U32, +rw: U32, +rh: U32) -> Bool:
  +hx = (rw / 2 : U32)
  +hy = (rh / 2 : U32)
  +dx = Bool.pick(U32, (pxi > hx : U32), (pxi - hx : U32), (hx - pxi : U32))
  +dy = Bool.pick(U32, (pyi > hy : U32), (pyi - hy : U32), (hy - pyi : U32))
  ((dx < 1 : U32) && (dy < 5 : U32)) || ((dy < 1 : U32) && (dx < 5 : U32))

# the hotbar: the eight block types, the bucket and the torch in a row
# along the bottom, 20 px each 4 apart, the chosen one framed in white
def slot_at(+pxi: U32, +pyi: U32, +rw: U32, +rh: U32) -> U32:
  +x0 = (rw / 2 - 118 : U32)
  +y0 = (rh - 30 : U32)
  +inx = (pxi >= x0 : U32) && (pxi < (x0 + 236 : U32) : U32)
  +iny = (pyi >= y0 : U32) && (pyi < (y0 + 20 : U32) : U32)
  +inslot = ((pxi - x0) % 24 < 20 : U32)
  Bool.pick(U32, inx && iny && inslot, ((pxi - x0) / 24 + 1 : U32), 0)

# ---------- the readout: the `!`'s milliseconds and the frames a second ----------
# The two numbers ride in the camera's stat word (main.bend measures
# them): bits 0..9 the tenths of a millisecond, to 99.9, bits 10..17 the
# frames a second, to 255; bits 18..24 hold the bucket's full cells, the
# hotbar's ninth count. Zeros hide the readout. "16.4 MS  60 FPS" in
# the top left corner, glyphs of 3 x 5 drawn 2 px a dot, a bit a dot from
# the top left: 0-9, then . blank M F P and + (S is the 5). The GPU never
# shifts by a variable, so a row and a dot are picked by a division and a
# mask.

def stat_of(+ms10: U32, +fps: U32) -> U32:
  (U32.min(ms10, 999) + 1024 * U32.min(fps, 255) : U32)

def stat_ms(+stat: U32) -> U32: (stat % 1024 : U32)
def stat_fps(+stat: U32) -> U32: (stat / 1024 % 256 : U32)

# the numbers' eighteen bits
def stat_on(+stat: U32) -> Bool: (stat % 262144 > 0 : U32)

def with_pail(+stat: U32, +cells: U32) -> U32: (stat + 262144 * cells : U32)
def stat_pail(+stat: U32) -> U32: (stat / 262144 % 128 : U32)

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

def stat_px(inside: Bool, +stat: U32, +pxi: U32, +pyi: U32) -> U32:
  match inside:
    case False{}:
      0
    case True{}:
      +lx = (pxi - 4 : U32)
      +ly = (pyi - 4 : U32)
      +intext = (pxi >= 4 : U32) && (pxi < 124 : U32) && (pyi >= 4 : U32) && (pyi < 14 : U32)
      +g = glyph(stat_cell((lx / 8 : U32), stat_ms(stat), stat_fps(stat)))
      +row = (g / row_div((ly / 2 : U32)) % 8 : U32)
      +lit = intext && Util.on(row, dot_bit((lx % 8 / 2 : U32)))
      Bool.pick(U32, lit, (1 + Util.rgb(255, 255, 255) : U32), (1 + Util.rgb(16, 16, 24) : U32))

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
  Bool.pick(U32, lit, Bool.pick(U32, U32.is_eq(n, 0), Util.rgb(144, 144, 152), Util.rgb(255, 255, 255)), Util.rgb(16, 16, 24))

# the bucket's swatch is the water's blue, its count the full cells it
# holds; the torch's is a torch, with no count
def slot_col(+sel: U32, items: U32, +stat: U32, +slot: U32, +pxi: U32, +pyi: U32, +rw: U32, +rh: U32) -> U32:
  +i = (slot - 1 : U32)
  +lx = ((pxi - (rw / 2 - 118)) % 24 : U32)
  +ly = (pyi - (rh - 30) : U32)
  +border = (lx < 2 : U32) || (lx >= 18 : U32) || (ly < 2 : U32) || (ly >= 18 : U32)
  +label = (lx >= 4 : U32) && (lx < 18 : U32) && (ly >= 10 : U32) && (ly < 17 : U32)
  Bool.pick(U32, border, Bool.pick(U32, U32.is_eq(i, (sel % 16 : U32)), Util.rgb(255, 255, 255), Util.rgb(40, 40, 40)),
    Bool.pick(U32, U32.is_eq(i, Torch.slot()), Torch.icon((lx - 2 : U32), (ly - 2 : U32)),
      Bool.pick(U32, label, count_col(Bool.pick(U32, U32.is_eq(i, 8), stat_pail(stat), Inventory.hud_count(sel, items, i)), lx, ly),
        Bool.pick(U32, U32.is_eq(i, 8), Util.rgb(46, 110, 160), blockcol(i, False{}, 1.0)))))

def slot_px(inside: Bool, sel: U32, items: U32, stat: U32, slot: U32, pxi: U32, pyi: U32, rw: U32, rh: U32) -> U32:
  match inside:
    case False{}: 0
    case True{}: (1 + slot_col(sel, items, stat, slot, pxi, pyi, rw, rh) : U32)

# what lies over the scene at this pixel: 0 nothing, else 1 + the colour;
# the torch chosen stands in the hand
def hud(+sel: U32, +items: U32, +stat: U32, +ck: U32, +pxi: U32, +pyi: U32, +rw: U32, +rh: U32) -> U32:
  +slot = slot_at(pxi, pyi, rw, rh)
  +text = stat_px(stat_on(stat) && (pxi < 128 : U32) && (pyi < 18 : U32), stat, pxi, pyi)
  +hand = Torch.in_view(Torch.chosen(sel), ck, pxi, pyi, rw, rh)
  Bool.pick(U32, (text > 0 : U32), text,
    Bool.pick(U32, cross_at(pxi, pyi, rw, rh), (1 + Util.rgb(255, 255, 255) : U32),
      Bool.pick(U32, (hand > 0 : U32), hand,
        slot_px((slot > 0 : U32), sel, items, stat, slot, pxi, pyi, rw, rh))))

def hud_if(on: Bool, +sel: U32, items: U32, +stat: U32, +ck: U32, +pxi: U32, +pyi: U32, +rw: U32, +rh: U32) -> U32:
  match on:
    case True{}:
      hud(sel, items, stat, ck, pxi, pyi, rw, rh)
    case False{}:
      0

def hud_of(+cam: Cam, +pxi: U32, +pyi: U32) -> U32:
  Cam{ox, oy, oz, yaw, pit, base, far, sel, items, stat, +fl, rw, rh, lx, ly, lz, ck, seen} = cam
  hud_if(Util.on(fl, 16), sel, items, stat, ck, pxi, pyi, rw, rh)

def paint(over: Bool, +code: U32, +cam: Cam, w: Array<U32>, +pxi: U32, +pyi: U32, +sh: Shafts.Beams) -> Array<U32> & U32:
  match over:
    case True{}:
      (w, (code - 1 : U32))
    case False{}:
      shade_px(cam, w, pxi, pyi, sh)

def pixel(+cam: Cam, w: Array<U32>, +pxi: U32, +pyi: U32, +sh: Shafts.Beams) -> Array<U32> & U32:
  +code = hud_of(cam, pxi, pyi)
  paint((code > 0 : U32), code, cam, w, pxi, pyi, sh)

# ---------- the sun's shafts in the air ----------
# The tile's shafts (src/shafts.bend): along the rays through its four
# corners, how much of the sun reaches each of eight points (Shafts.at):
# the clouds' shadow, and within the window's reach a glance of 16 steps
# towards the sun, the leaves' gaps and their wind as the ground's shadow
# sees them; a nibble a point. A point inside a block, past the corner
# ray's hit, counts as lit: a pixel beside it looks past the block, and
# a shadow there would ring the block's outline.
def clear(r: Array<U32> & Glance) -> Array<U32> & F32:
  (w, g) = r
  Glance{+c, +t} = g
  (w, Bool.pick(F32, (c < 1 : U32) || (t <= 0.0 : F32), 1.0, 0.0))

def sunlit(near: Bool, w: Array<U32>, +base: U32, +open: U32, +wind: U32, +x: F32, +y: F32, +z: F32,
           +lx: F32, +ly: F32, +lz: F32) -> Array<U32> & F32:
  match near:
    case False{}:
      (w, 1.0)
    case True{}:
      clear(run_glance(16n, w, base, x, y, z, lx, ly, lz, open, wind))

def beamed(+q: U32, +bits: U32, +cloud: F32, r: Array<U32> & F32) -> Array<U32> & U32:
  (w, +sun) = r
  (w, (bits + q * F32.to_u32((sun * cloud * 15.0 + 0.5 : F32)) : U32))

def beam(n: Nat, +base: U32, +fm: U32, +ck: U32, +clouds: Bool, +open: U32, +wind: U32, +ox: F32, +oy: F32, +oz: F32,
         +dx: F32, +dy: F32, +dz: F32, +lx: F32, +ly: F32, +lz: F32, +i: U32, +q: U32, r: Array<U32> & U32) -> Array<U32> & U32:
  match n:
    case 0n:
      r
    case 1n+k:
      (w, +bits) = r
      +t = Shafts.at(i)
      +x = (ox + dx * t : F32)
      +y = (oy + dy * t : F32)
      +z = (oz + dz * t : F32)
      beam(k, base, fm, ck, clouds, open, wind, ox, oy, oz, dx, dy, dz, lx, ly, lz, (i + 1 : U32), (q * 16 : U32),
        beamed(q, bits, Clouds.through(clouds && (y < Clouds.middle() : F32), fm, ck, x, y, z, lx, ly, lz),
          sunlit((i < 6 : U32), w, base, open, wind, x, y, z, lx, ly, lz)))

def beam_aim(+base: U32, +fm: U32, +ck: U32, +clouds: Bool, +open: U32, +wind: U32, +ox: F32, +oy: F32, +oz: F32,
             +lx: F32, +ly: F32, +lz: F32, w: Array<U32>, a: Aim) -> Array<U32> & U32:
  Aim{+dx, +dy, +dz, fx, fy, fz, rx, rz, ex, ey, ez} = a
  +sg = Sky.side(True{}, ly)
  beam(8n, base, fm, ck, clouds, open, wind, ox, oy, oz, dx, dy, dz, (sg * lx : F32), (sg * ly : F32), (sg * lz : F32), 0, 1, (w, 0))

def corner(+cam: Cam, w: Array<U32>, +cx: U32, +cy: U32) -> Array<U32> & U32:
  Cam{ox, oy, oz, yaw, pit, base, far, sel, items, stat, +fl, +rw, +rh, lx, ly, lz, +ck, seen} = cam
  beam_aim(base, far, ck, Util.on(fl, 256), sun_gaps(fl), wind_of(fl, ck), ox, oy, oz, lx, ly, lz, w, aim(yaw, pit, p2f(cx, rw, rh), p2f(cy, rh, rh)))

def beams_fin(+a: U32, +b: U32, +c: U32, r: Array<U32> & U32) -> Array<U32> & Shafts.Beams:
  (w, +d) = r
  (w, Shafts.Beams{a, b, c, d})

def beams_c(+cam: Cam, +x: U32, +y: U32, +a: U32, +b: U32, r: Array<U32> & U32) -> Array<U32> & Shafts.Beams:
  (w, +c) = r
  beams_fin(a, b, c, corner(cam, w, (x + 4 : U32), (y + 4 : U32)))

def beams_b(+cam: Cam, +x: U32, +y: U32, +a: U32, r: Array<U32> & U32) -> Array<U32> & Shafts.Beams:
  (w, +b) = r
  beams_c(cam, x, y, a, b, corner(cam, w, x, (y + 4 : U32)))

def beams_a(+cam: Cam, +x: U32, +y: U32, r: Array<U32> & U32) -> Array<U32> & Shafts.Beams:
  (w, +a) = r
  beams_b(cam, x, y, a, corner(cam, w, (x + 4 : U32), y))

def beams_if(on: Bool, +cam: Cam, w: Array<U32>, +x: U32, +y: U32) -> Array<U32> & Shafts.Beams:
  match on:
    case False{}:
      (w, Shafts.Beams{0, 0, 0, 0})
    case True{}:
      beams_a(cam, x, y, corner(cam, w, x, y))

# the shafts of the tile at (x, y)
def beams(+cam: Cam, w: Array<U32>, +x: U32, +y: U32) -> Array<U32> & Shafts.Beams:
  Cam{ox, oy, oz, yaw, pit, +base, far, sel, items, stat, +fl, rw, rh, lx, +ly, lz, ck, seen} = cam
  beams_if(Shafts.on(fl, base, ly), cam, w, x, y)

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

def t2c(+cam: Cam, +x: U32, +y: U32, +sh: Shafts.Beams, +k0: U32, +k1: U32, r: Array<U32> & U32) -> Array<U32> & Image:
  (w, k2) = r
  t2d(k0, k1, k2, pixel(cam, w, (x + 1 : U32), (y + 1 : U32), sh))

def t2b(+cam: Cam, +x: U32, +y: U32, +sh: Shafts.Beams, +k0: U32, r: Array<U32> & U32) -> Array<U32> & Image:
  (w, k1) = r
  t2c(cam, x, y, sh, k0, k1, pixel(cam, w, x, (y + 1 : U32), sh))

def t2a(+cam: Cam, +x: U32, +y: U32, +sh: Shafts.Beams, r: Array<U32> & U32) -> Array<U32> & Image:
  (w, k0) = r
  t2b(cam, x, y, sh, k0, pixel(cam, w, (x + 1 : U32), y, sh))

def t2(+cam: Cam, w: Array<U32>, +x: U32, +y: U32, +sh: Shafts.Beams) -> Array<U32> & Image:
  t2a(cam, x, y, sh, pixel(cam, w, x, y, sh))

def t4d(a: Image, b: Image, c: Image, r: Array<U32> & Image) -> Array<U32> & Image:
  (w, d) = r
  (w, Qua{a, b, c, d})

def t4c(+cam: Cam, +x: U32, +y: U32, +sh: Shafts.Beams, a: Image, b: Image, r: Array<U32> & Image) -> Array<U32> & Image:
  (w, c) = r
  t4d(a, b, c, t2(cam, w, (x + 2 : U32), (y + 2 : U32), sh))

def t4b(+cam: Cam, +x: U32, +y: U32, +sh: Shafts.Beams, a: Image, r: Array<U32> & Image) -> Array<U32> & Image:
  (w, b) = r
  t4c(cam, x, y, sh, a, b, t2(cam, w, x, (y + 2 : U32), sh))

def t4a(+cam: Cam, +x: U32, +y: U32, +sh: Shafts.Beams, r: Array<U32> & Image) -> Array<U32> & Image:
  (w, a) = r
  t4b(cam, x, y, sh, a, t2(cam, w, (x + 2 : U32), y, sh))

def t4s(+cam: Cam, +x: U32, +y: U32, r: Array<U32> & Shafts.Beams) -> Array<U32> & Image:
  (w, +sh) = r
  t4a(cam, x, y, sh, t2(cam, w, x, y, sh))

def t4(+cam: Cam, w: Array<U32>, +x: U32, +y: U32) -> Array<U32> & Image:
  t4s(cam, x, y, beams(cam, w, x, y))
