import Base
import ./util.bend as Util
import ./sky.bend as Sky

# CLOUDS: cumulus in a slab over the world. A coverage over the ground's
# plane, a value noise of four octaves that repeats every 256 columns,
# raises each cloud's top from its flat base: a cloud is
# where the height in the slab is under the coverage. A sky pixel's ray
# marches the slab in 16 steps, each a coverage read and one more a few
# blocks towards the sun, which lights the side the sun sees, from the
# world's map of the coverage (map_at); the ground reads the coverage
# once, where the sun's line from it crosses the slab's middle. The
# clouds sit on the world's columns, not the window's: Cam.far holds the
# window's corner mod 256. The weather, 0 clear to 1
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

# the coverage's two broad octaves, and its two fine ones, whose mean is
# 0.115
def broad(+a: F32, +b: F32) -> F32:
  (0.5 * lattice(a, b, 0.03125, 8, 0) + 0.27 * lattice(a, b, 0.0625, 16, 101) : F32)

def fine(+a: F32, +b: F32) -> F32:
  (0.15 * lattice(a, b, 0.125, 32, 211) + 0.08 * lattice(a, b, 0.25, 64, 307) : F32)

# how high the clouds over a column reach in the slab, 0..1
def height(+n: F32, +b: F32) -> F32:
  F32.clamp(((n - b) * 3.5 : F32), 0.0, 1.0)

# how high the cloud over the column at (x, z), or a way (ax, az) from it,
# reaches in the slab, 0 in the open, from the broad octaves alone
def cover(+fm: U32, +ck: U32, +x: F32, +z: F32, +ax: F32, +az: F32) -> F32:
  height(broad(wrap((x + blown(fm, ck) + ax : F32)), wrap((z + corner_z(fm) + az : F32))), bias(weather(ck)))

# The map: the march's reads, filled at the world's birth, above the ring
# and the far map: a word a column of the clouds' columns (mod 256) holds
# the broad octaves' byte at its corner and at the three after it along x
# and z, so that one read is a cell to blend; the fine octaves' words are
# 2^16 further. A byte is 330 a unit: the broad reach 0.77.
def map_at(+x: U32, +z: U32) -> U32:
  (327680 + x % 256 * 256 + z % 256 : U32)

def byte(+v: F32) -> U32:
  F32.to_u32((v * 330.0 + 0.5 : F32))

def quad(+a: U32, +b: U32, +c: U32, +d: U32) -> U32:
  (a + b * 256 + c * 65536 + d * 16777216 : U32)

def broad_at(+x: U32, +z: U32) -> U32:
  byte(broad(U32.to_f32(x), U32.to_f32(z)))

def fine_at(+x: U32, +z: U32) -> U32:
  byte(fine(U32.to_f32(x), U32.to_f32(z)))

# a line of the map along z from z, each word's bytes at z handed on
# from the word before: the octaves repeat, so 256 reads as 0
def load_line(n: Nat, w: Array<U32>, +x: U32, +z: U32, +b0: U32, +b1: U32, +f0: U32, +f1: U32) -> Array<U32>:
  match n:
    case 0n:
      w
    case 1n+k:
      +b2 = broad_at(x, (z + 1 : U32))
      +b3 = broad_at((x + 1 : U32), (z + 1 : U32))
      +f2 = fine_at(x, (z + 1 : U32))
      +f3 = fine_at((x + 1 : U32), (z + 1 : U32))
      load_line(k, Array.set(U32, Array.set(U32, w, map_at(x, z), quad(b0, b1, b2, b3)), (map_at(x, z) + 65536 : U32), quad(f0, f1, f2, f3)),
        x, (z + 1 : U32), b2, b3, f2, f3)

def load(n: Nat, w: Array<U32>, +x: U32) -> Array<U32>:
  match n:
    case 0n:
      w
    case 1n+k:
      load(k, load_line(256n, w, x, 0, broad_at(x, 0), broad_at((x + 1 : U32), 0), fine_at(x, 0), fine_at((x + 1 : U32), 0)), (x + 1 : U32))

# a word's cell blended at (u, v), in the coverage's units
def blend(+word: U32, +u: F32, +v: F32) -> F32:
  +fu = (u - F32.floor(u) : F32)
  +fv = (v - F32.floor(v) : F32)
  +a = U32.to_f32((word % 256 : U32))
  +b = U32.to_f32((word / 256 % 256 : U32))
  +c = U32.to_f32((word / 65536 % 256 : U32))
  +d = U32.to_f32((word / 16777216 : U32))
  (((a + (b - a) * fu) * (1.0 - fv) + (c + (d - c) * fu) * fv) * 0.0030303030 : F32)

# a march step's reads at the clouds' (x, z): the broad octaves, the fine
# ones, and the broad a way (ax, az) towards the sun
type Cover is Data:
  Cover{n: F32, fine: F32, sun: F32}

def covered(+n: F32, +fine: F32, +su: F32, +sv: F32, r: Array<U32> & U32) -> Array<U32> & Cover:
  (w, +word) = r
  (w, Cover{n, fine, blend(word, su, sv)})

def covered_fine(+n: F32, +u: F32, +v: F32, +su: F32, +sv: F32, r: Array<U32> & U32) -> Array<U32> & Cover:
  (w, +word) = r
  covered(n, blend(word, u, v), su, sv, Array.get(U32, w, map_at(F32.to_u32(su), F32.to_u32(sv))))

def covered_broad(+u: F32, +v: F32, +su: F32, +sv: F32, +i: U32, r: Array<U32> & U32) -> Array<U32> & Cover:
  (w, +word) = r
  covered_fine(blend(word, u, v), u, v, su, sv, Array.get(U32, w, (i + 65536 : U32)))

def coverage(w: Array<U32>, +x: F32, +z: F32, +ax: F32, +az: F32) -> Array<U32> & Cover:
  +u = wrap(x)
  +v = wrap(z)
  +i = map_at(F32.to_u32(u), F32.to_u32(v))
  covered_broad(u, v, wrap((x + ax : F32)), wrap((z + az : F32)), i, Array.get(U32, w, i))

# what the ray still sees through (tr), and the light it met, weighed by
# what each step hid (w, wl)
type Puff is Data:
  Puff{tr: F32, w: F32, wl: F32}

# the density's ramp under a cloud's top, clamp(e, 0, 1): its
# antiderivative, and its mean along a step whose ends are a and b
def ramp(+e: F32) -> F32:
  +c = F32.clamp(e, 0.0, 1.0)
  (c * c * 0.5 + F32.max((e - 1.0 : F32), 0.0) : F32)

def span(+a: F32, +b: F32) -> F32:
  Bool.pick(F32, (Util.absf((b - a : F32)) < 0.001 : F32), F32.clamp((0.5 * (a + b) : F32), 0.0, 1.0), ((ramp(b) - ramp(a)) / (b - a) : F32))

# a step, a block up the slab (h in it): the cloud's density along it,
# its ramp (e) at the step's end and where it began (e0) averaged, since
# a flat ray's step spans many columns and one read of it showed the
# slab in layers; and its light at the end: what the cloud over it lets
# through from above, and more on the side the sun sees, where the cloud
# thins towards the sun (ax, az). The fine octaves fade as the step
# grows (detail): a step over many columns aliases them. The step reads
# the coverage (r) at its end, and the next one's.
def march(fuel: Nat, +x: F32, +h: F32, +z: F32, +sx: F32, +sz: F32, +ax: F32, +az: F32, +k: F32, +detail: F32, +b: F32,
          +tr: F32, +hid: F32, +wl: F32, +e0: F32, r: Array<U32> & Cover) -> Array<U32> & Puff:
  match fuel:
    case 0n:
      (w, cv) = r
      (w, Puff{tr, hid, wl})
    case 1n+f:
      (w, cv) = r
      Cover{+n, +fine, +sun} = cv
      +c = height((n + detail * (fine - 0.115) : F32), b)
      +e = ((c - h) * 12.0 : F32)
      +a = (1.0 - F32.exp((0.0 - span(e0, e) * k : F32)) : F32)
      +side = (height(n, b) - height(sun, b) : F32)
      +lit = F32.clamp((0.25 + 0.75 * F32.exp((F32.min((h - c : F32), 0.0) * 3.0 : F32)) + 1.2 * side : F32), 0.0, 1.0)
      +g = (tr * a : F32)
      march(f, (x + sx : F32), (h + per() : F32), (z + sz : F32), sx, sz, ax, az, k, detail, b, (tr - g : F32), (hid + g : F32), (wl + g * lit : F32), e,
        coverage(w, (x + sx : F32), (z + sz : F32), ax, az))

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

def marched(+v: U32, +sky: U32, +t0: F32, +wx: F32, +dx: F32, +dy: F32, +dz: F32, +lx: F32, +ly: F32, +lz: F32, r: Array<U32> & Puff) -> Array<U32> & U32:
  (w, p) = r
  (w, puffed(v, sky, t0, wx, dx, dy, dz, lx, ly, lz, p))

# a sky pixel's clouds, over the sky it shows with its heavens, marched
# from the slab's bottom, whose first read ends no step (e0 far under the
# ramp); a ray too flat to reach the slab near enough has faded before it
def over(on: Bool, w: Array<U32>, +fm: U32, +ck: U32, +v: U32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
         +lx: F32, +ly: F32, +lz: F32, +sky: U32) -> Array<U32> & U32:
  match on:
    case False{}:
      (w, sky)
    case True{}:
      +wx = weather(ck)
      +up = F32.max(dy, 0.02)
      +t0 = ((bottom() - oy) / up : F32)
      +dt = (1.0 / up : F32)
      +x = (ox + blown(fm, ck) + dx * t0 : F32)
      +z = (oz + corner_z(fm) + dz * t0 : F32)
      +ax = (lx * 5.0 : F32)
      +az = (lz * 5.0 : F32)
      marched(v, sky, t0, wx, dx, dy, dz, lx, ly, lz,
        march(17n, x, 0.0, z, (dx * dt : F32), (dz * dt : F32), ax, az, (dt * sigma(wx) : F32),
          F32.clamp((1.6 - dt * 0.15 : F32), 0.0, 1.0), bias(wx), 1.0, 0.0, 0.0, (0.0 - 1000000.0 : F32), coverage(w, x, z, ax, az)))

# the share of the sun's light the cloud over (x, y, z) lets through along
# the sun's line, through its whole height
def through(on: Bool, +fm: U32, +ck: U32, +x: F32, +y: F32, +z: F32, +lx: F32, +ly: F32, +lz: F32) -> F32:
  match on:
    case False{}:
      1.0
    case True{}:
      +wx = weather(ck)
      +slant = F32.max(ly, 0.3)
      +t = ((middle() - y) / F32.max(ly, 0.05) : F32)
      +c = cover(fm, ck, x, z, (lx * t : F32), (lz * t : F32))
      F32.exp((0.0 - sigma(wx) * c * (top() - bottom()) * 0.25 / slant : F32))

# the sun's light on the ground under the clouds, over the light a block's
# shadow leaves: a thin cloud dims it a little, a heavy one more than a
# block does
def shade(on: Bool, +fm: U32, +ck: U32, +x: F32, +y: F32, +z: F32, +lx: F32, +ly: F32, +lz: F32) -> F32:
  (0.55 + 0.45 * through(on, fm, ck, x, y, z, lx, ly, lz) : F32)

# the share of the sun the clouds leave an eye at (x, y, z): what the
# cloud on its line lets through, as much as the sky shows that cloud (it
# fades into the haze from 180 blocks), under a heavy sky's veil
def unveiled(on: Bool, +fm: U32, +ck: U32, +x: F32, +y: F32, +z: F32, +lx: F32, +ly: F32, +lz: F32) -> F32:
  match on:
    case False{}:
      1.0
    case True{}:
      +t = ((middle() - y) / F32.max(ly, 0.02) : F32)
      +fade = (1.0 - Util.smooth(F32.clamp(((t - 180.0) * 0.004 : F32), 0.0, 1.0)) : F32)
      ((1.0 - (1.0 - through(True{}, fm, ck, x, y, z, lx, ly, lz)) * fade) * (1.0 - gloom(weather(ck))) : F32)

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
def above(w: Array<U32>, +fl: U32, +fm: U32, +ck: U32, +v: U32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
          +lx: F32, +ly: F32, +lz: F32) -> Array<U32> & U32:
  over(Util.on(fl, 128), w, fm, ck, v, ox, oy, oz, dx, dy, dz, lx, ly, lz, heavens(Util.on(fl, 128), fl, ck, v, dx, dy, dz, lx, ly, lz))

# the clouds a mirror at (ox, oy, oz) shows along (dx, dy, dz), over the
# sky it shows: one read of their broad coverage where the ray crosses
# the slab's middle, through the cloud's height along the ray and lit
# halfway, in place of the sixteen steps a sky pixel marches
def glimpsed(on: Bool, +fm: U32, +ck: U32, +v: U32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
             +lx: F32, +ly: F32, +lz: F32, +sky: U32) -> U32:
  match on:
    case False{}:
      sky
    case True{}:
      +wx = weather(ck)
      +up = F32.max(dy, 0.02)
      +t0 = ((middle() - oy) / up : F32)
      +tr = F32.exp((0.0 - sigma(wx) * cover(fm, ck, ox, oz, (dx * t0 : F32), (dz * t0 : F32)) * (top() - bottom()) / up : F32))
      puffed(v, sky, t0, wx, dx, dy, dz, lx, ly, lz, Puff{tr, (1.0 - tr : F32), (0.6 * (1.0 - tr) : F32)})

# what a mirror at (ox, oy, oz) shows of the sky along (dx, dy, dz): the
# sky, its heavens and a glimpse of the clouds
def mirrored(+fl: U32, +fm: U32, +ck: U32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, +lx: F32, +ly: F32, +lz: F32) -> U32:
  +s = sky(fl, ck, dx, dy, dz, lx, ly, lz)
  glimpsed(Util.on(fl, 128), fm, ck, s, ox, oy, oz, dx, dy, dz, lx, ly, lz, heavens(Util.on(fl, 128), fl, ck, s, dx, dy, dz, lx, ly, lz))
