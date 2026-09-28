import Base
import ./util.bend as Util
import ./sky.bend as Sky

# CLOUDS: cumulus in a slab over the world. A coverage over the ground's
# plane, a value noise of four octaves that repeats every 256 columns,
# raises each cloud's top from its flat base: a cloud is
# where the height in the slab is under the coverage. A sky pixel's ray
# marches the slab in 12 steps, each a coverage read and one more a few
# blocks towards the sun, which lights the side the sun sees; the ground
# reads the coverage once, where the sun's line from it crosses the
# slab's middle. The clouds sit on the world's columns, not the window's:
# Cam.far holds the window's corner mod 256. The weather, 0 clear to 1
# overcast, from the clock's days, sets how much of the sky they cover and
# how heavy they are, and greys the sky; the wind moves them along x.

def bottom() -> F32: 62.0

def top() -> F32: 78.0

# the slab's height's inverse, and its middle
def per() -> F32: 0.0625

def middle() -> F32: 70.0

# how grey a heavy sky is, and how much of the sun, the moon and the
# stars it veils
def gloom(+wx: F32) -> F32:
  (0.8 * F32.clamp(((wx - 0.3) * 1.4 : F32), 0.0, 1.0) : F32)

# how much light a block of cloud stops, heavier as the weather turns
def sigma(+wx: F32) -> F32: (0.35 + 0.65 * wx : F32)

# the coverage under which no cloud forms: lower, more sky covered
def bias(+wx: F32) -> F32: (0.52 - 0.3 * wx : F32)

def wrap(+x: F32) -> F32:
  (x - 256.0 * F32.floor((x * 0.00390625 : F32)) : F32)

# a lattice point's value in 0..1, by the stars' hash, which mixes its bits
def at(+i: U32, +j: U32) -> F32:
  (U32.to_f32((Sky.star_hash(i, j) % 1024 : U32)) * 0.0009775171 : F32)

# the weather, 0 clear to 1 overcast: a noise over half days, squared so
# that fair days are the most; it repeats with the clock's word, every
# 4096 days, and its seed makes the first day fair with some clouds
def weather(+t: U32) -> F32:
  +f = Util.smooth((U32.to_f32((t % 524288 : U32)) * 0.0000019073486 : F32))
  +v = (at((t / 524288 : U32), 45) * (1.0 - f) + at(((t / 524288 + 1) % 8192 : U32), 45) * f : F32)
  (v * v : F32)

# the window's corner in the world's columns, mod 256
def corner_x(+fm: U32) -> F32: U32.to_f32(((fm / 256 + 64) % 256 : U32))

def corner_z(+fm: U32) -> F32: U32.to_f32(((fm % 256 + 64) % 256 : U32))

# the corner in the clouds' columns: less the way the wind carried them
# along x, their 256 columns in a half day
def blown(+fm: U32, +t: U32) -> F32:
  (corner_x(fm) - U32.to_f32((t % 524288 : U32)) * 0.00048828125 : F32)

# value noise over cells of 1/k columns, n of them to the 256, so that it
# repeats with the columns; x and z in 0..256
def lattice(+x: F32, +z: F32, +k: F32, +n: U32, +seed: U32) -> F32:
  +u = (x * k : F32)
  +v = (z * k : F32)
  +fu = F32.floor(u)
  +fv = F32.floor(v)
  +i = F32.to_u32(fu)
  +j = F32.to_u32(fv)
  +i0 = (i % n + seed : U32)
  +i1 = ((i + 1) % n + seed : U32)
  +j0 = (j % n : U32)
  +j1 = ((j + 1) % n : U32)
  +su = Util.smooth((u - fu : F32))
  +sv = Util.smooth((v - fv : F32))
  ((at(i0, j0) * (1.0 - su) + at(i1, j0) * su) * (1.0 - sv) + (at(i0, j1) * (1.0 - su) + at(i1, j1) * su) * sv : F32)

# the coverage's two broad octaves, and its two fine ones around their mean
def broad(+a: F32, +b: F32) -> F32:
  (0.5 * lattice(a, b, 0.03125, 8, 0) + 0.27 * lattice(a, b, 0.0625, 16, 101) : F32)

def fine(+a: F32, +b: F32) -> F32:
  (0.15 * lattice(a, b, 0.125, 32, 211) + 0.08 * lattice(a, b, 0.25, 64, 307) - 0.115 : F32)

# how high the clouds over a column reach in the slab, 0..1
def height(+n: F32, +b: F32) -> F32:
  F32.clamp(((n - b) * 3.5 : F32), 0.0, 1.0)

# the broad octaves alone: the light's read towards the sun, and the shadow
def rough(+x: F32, +z: F32, +b: F32) -> F32:
  height(broad(wrap(x), wrap(z)), b)

# how high the cloud over the column at (x, z), or a way (ax, az) from it,
# reaches in the slab, 0 in the open
def cover(+fm: U32, +ck: U32, +x: F32, +z: F32, +ax: F32, +az: F32) -> F32:
  rough((x + blown(fm, ck) + ax : F32), (z + corner_z(fm) + az : F32), bias(weather(ck)))

# what the ray still sees through (tr), and the light it met, weighed by
# what each step hid (w, wl)
type Puff is Data:
  Puff{tr: F32, w: F32, wl: F32}

# a step: the cloud's density where the ray is, and its light: what the
# cloud over it lets through from above, and more on the side the sun
# sees, where the cloud thins towards the sun. The fine octaves fade as
# the step grows (detail): a step over many columns aliases them.
def march(fuel: Nat, +x: F32, +y: F32, +z: F32, +sx: F32, +sy: F32, +sz: F32, +lx: F32, +lz: F32, +k: F32, +detail: F32, +b: F32,
          +tr: F32, +w: F32, +wl: F32) -> Puff:
  match fuel:
    case 0n:
      Puff{tr, w, wl}
    case 1n+f:
      +h = ((y - bottom()) * per() : F32)
      +u = wrap(x)
      +v = wrap(z)
      +n = broad(u, v)
      +c = height((n + detail * fine(u, v) : F32), b)
      +d = F32.clamp(((c - h) * 12.0 + 0.5 : F32), 0.0, 1.0)
      +a = (1.0 - F32.exp((0.0 - d * k : F32)) : F32)
      +side = (height(n, b) - rough((x + lx * 5.0 : F32), (z + lz * 5.0 : F32), b) : F32)
      +lit = F32.clamp((0.25 + 0.75 * F32.exp((F32.min((h - c : F32), 0.0) * 3.0 : F32)) + 1.2 * side : F32), 0.0, 1.0)
      +g = (tr * a : F32)
      march(f, (x + sx : F32), (y + sy : F32), (z + sz : F32), sx, sy, sz, lx, lz, k, detail, b, (tr - g : F32), (w + g : F32), (wl + g * lit : F32))

# the clouds' colour over the sky: white to the sun by day, rose and gold
# at its rising and setting, grey-blue under the moon, greyer as the
# weather turns; far clouds fade into the horizon's haze
def puffed(+v: U32, +sky: U32, +t0: F32, +wx: F32, +dx: F32, +dy: F32, +dz: F32, +lx: F32, +ly: F32, +lz: F32, p: Puff) -> U32:
  Puff{+tr, +w, +wl} = p
  +day = Sky.daylight(ly)
  +warm = F32.clamp((1.0 - Util.absf(ly) * 3.0 : F32), 0.0, 1.0)
  +toward = F32.clamp((dx * lx + dy * ly + dz * lz : F32), 0.0, 1.0)
  +bright = Util.mix(Util.mix(Util.mix(Util.rgb(58, 66, 92), Util.rgb(255, 253, 248), day),
    Util.mix(Util.rgb(120, 62, 96), Util.rgb(255, 176, 118), day), (warm * 0.8 : F32)), Util.rgb(150, 156, 166), (wx * 0.45 : F32))
  +dark = Util.mix(Util.mix(Util.rgb(20, 24, 38), Util.rgb(104, 114, 138), day), Util.rgb(40, 44, 54), (wx * 0.6 : F32))
  +light = F32.clamp((wl / F32.max(w, 0.0001) + 0.3 * toward * toward : F32), 0.0, 1.0)
  +fade = (1.0 - Util.smooth(F32.clamp(((t0 - 180.0) * 0.004 : F32), 0.0, 1.0)) : F32)
  Util.mix(sky, Util.mix(Util.mix(dark, bright, light), v, F32.clamp((t0 * 0.0018 : F32), 0.0, 0.6)), ((1.0 - tr) * fade : F32))

# a sky pixel's clouds, over the sky it shows with its heavens; a ray too
# flat to reach the slab near enough has faded before it
def over(on: Bool, +fm: U32, +ck: U32, +v: U32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
         +lx: F32, +ly: F32, +lz: F32, +sky: U32) -> U32:
  match on:
    case False{}:
      sky
    case True{}:
      +wx = weather(ck)
      +up = F32.max(dy, 0.02)
      +t0 = ((bottom() - oy) / up : F32)
      +dt = ((top() - bottom()) / up * 0.0833333 : F32)
      +s = (t0 + 0.5 * dt : F32)
      puffed(v, sky, t0, wx, dx, dy, dz, lx, ly, lz,
        march(12n, (ox + blown(fm, ck) + dx * s : F32), (oy + up * s : F32), (oz + corner_z(fm) + dz * s : F32),
          (dx * dt : F32), (up * dt : F32), (dz * dt : F32), lx, lz, (dt * sigma(wx) : F32), F32.clamp((1.6 - dt * 0.15 : F32), 0.0, 1.0), bias(wx), 1.0, 0.0, 0.0))

# the sun's light on the ground under the clouds: what the cloud over it
# lets through along the sun's line, through its whole height, over the
# light a block's shadow leaves: a thin cloud dims it a little, a heavy
# one more than a block does
def shade(on: Bool, +fm: U32, +ck: U32, +x: F32, +y: F32, +z: F32, +lx: F32, +ly: F32, +lz: F32) -> F32:
  match on:
    case False{}:
      1.0
    case True{}:
      +wx = weather(ck)
      +slant = F32.max(ly, 0.3)
      +t = ((middle() - y) / F32.max(ly, 0.05) : F32)
      +c = cover(fm, ck, x, z, (lx * t : F32), (lz * t : F32))
      (0.55 + 0.45 * F32.exp((0.0 - sigma(wx) * c * (top() - bottom()) * 0.25 / slant : F32)) : F32)

# the sky and its fog under the weather: a heavy one greys them, by day
# and by night
def overcast(on: Bool, +ck: U32, +ly: F32, +c: U32) -> U32:
  match on:
    case False{}:
      c
    case True{}:
      Util.mix(c, Util.mix(Util.rgb(24, 26, 32), Util.rgb(158, 164, 172), Sky.daylight(ly)), gloom(weather(ck)))

# the sky seen along (dx, dy, dz), and the fog's colour that way
def sky(+fl: U32, +ck: U32, +dx: F32, +dy: F32, +dz: F32, +lx: F32, +ly: F32, +lz: F32) -> U32:
  overcast(Util.on(fl, 128), ck, ly, Sky.atmosphere(fl, dx, dy, dz, lx, ly, lz))

# the sun, the moon and the stars on the sky s along (dx, dy, dz), which
# a heavy sky veils
def heavens(on: Bool, +fl: U32, +ck: U32, +s: U32, +dx: F32, +dy: F32, +dz: F32, +lx: F32, +ly: F32, +lz: F32) -> U32:
  match on:
    case False{}:
      Sky.bodies(fl, s, dx, dy, dz, lx, ly, lz)
    case True{}:
      Util.mix(Sky.bodies(fl, s, dx, dy, dz, lx, ly, lz), s, gloom(weather(ck)))

# what a sky pixel shows: v, the sky that way, with its heavens and clouds
def above(+fl: U32, +fm: U32, +ck: U32, +v: U32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
          +lx: F32, +ly: F32, +lz: F32) -> U32:
  over(Util.on(fl, 128), fm, ck, v, ox, oy, oz, dx, dy, dz, lx, ly, lz, heavens(Util.on(fl, 128), fl, ck, v, dx, dy, dz, lx, ly, lz))

# what a mirror shows of the sky along (dx, dy, dz): the sky and its
# heavens, without the clouds' march
def mirrored(+fl: U32, +ck: U32, +dx: F32, +dy: F32, +dz: F32, +lx: F32, +ly: F32, +lz: F32) -> U32:
  heavens(Util.on(fl, 128), fl, ck, sky(fl, ck, dx, dy, dz, lx, ly, lz), dx, dy, dz, lx, ly, lz)
