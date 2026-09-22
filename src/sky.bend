import Base
import ./util.bend as Util

# Colours are functions of world ray direction and sun height, so turning
# the camera never drags the horizon or the stars along with the screen.
def daylight(+sy: F32) -> F32:
  Util.smooth(F32.clamp(((sy + 0.12) * 3.4 : F32), 0.0, 1.0))

def gradient(on: Bool, +dy: F32, +sy: F32) -> U32:
  match on:
    case False{}:
      Util.rgb(130, 170, 235)
    case True{}:
      +day = daylight(sy)
      +horizon = Util.mix(Util.rgb(18, 24, 44), Util.rgb(185, 212, 236), day)
      +zenith = Util.mix(Util.rgb(5, 9, 24), Util.rgb(65, 125, 206), day)
      Util.mix(horizon, zenith, F32.sqrt(F32.clamp(dy, 0.0, 1.0)))

def glow(on: Bool, +c: U32, +dx: F32, +dy: F32, +dz: F32,
         +sx: F32, +sy: F32, +sz: F32) -> U32:
  match on:
    case False{}:
      c
    case True{}:
      +h = F32.clamp((1.0 - Util.absf(dy) * 4.0 : F32), 0.0, 1.0)
      +warm = F32.clamp((1.0 - Util.absf(sy) * 3.0 : F32), 0.0, 1.0)
      +toward = F32.clamp((0.5 + 0.5 * (dx * sx + dz * sz) : F32), 0.0, 1.0)
      +colour = Util.mix(Util.rgb(90, 38, 58), Util.rgb(255, 153, 83), daylight(sy))
      Util.mix(c, colour, (h * h * warm * (0.18 + 0.72 * toward * toward) : F32))

# The fog samples this atmosphere alone, never a sun, moon or star disc.
def atmosphere(+fl: U32, +dx: F32, +dy: F32, +dz: F32, +sx: F32, +sy: F32, +sz: F32) -> U32:
  glow(Util.on(fl, 268435456), gradient(Util.on(fl, 67108864), dy, sy), dx, dy, dz, sx, sy, sz)

def sun(on: Bool, +c: U32, +dot: F32, +dy: F32, +sy: F32) -> U32:
  match on:
    case False{}:
      c
    case True{}:
      +disc = F32.clamp(((dot - 0.99935) * 16000.0 : F32), 0.0, 1.0)
      +above = F32.clamp((dy * 500.0 : F32), 0.0, 1.0)
      +colour = Util.mix(Util.rgb(255, 164, 83), Util.rgb(255, 247, 216), F32.clamp((sy * 2.0 : F32), 0.0, 1.0))
      Util.mix(c, colour, (disc * above : F32))

# A hash of a stereographic sky lattice gives fixed, sparse stars without
# a seam at an azimuth wrap. Jitter keeps the lattice out of the picture.
def star_hash(+i: U32, +j: U32) -> U32:
  +h = (i * 374761393 + j * 668265263 + 2246822519 : U32)
  +g = (U32.xor(h, (h / 8192 : U32)) * 1274126177 : U32)
  U32.xor(g, (g / 65536 : U32))

def stars(on: Bool, +c: U32, +dx: F32, +dy: F32, +dz: F32, +sy: F32) -> U32:
  match on:
    case False{}:
      c
    case True{}:
      +u = ((dx / (1.0 + F32.max(dy, 0.0)) + 1.0) * 110.0 : F32)
      +v = ((dz / (1.0 + F32.max(dy, 0.0)) + 1.0) * 110.0 : F32)
      +h = star_hash(Util.f2u(u), Util.f2u(v))
      +x = (Util.fracf(u) - (0.2 + 0.6 * U32.to_f32((h / 32 % 256 : U32)) / 255.0) : F32)
      +y = (Util.fracf(v) - (0.2 + 0.6 * U32.to_f32((h / 8192 % 256 : U32)) / 255.0) : F32)
      +spot = F32.clamp((1.0 - (x * x + y * y) * 32.0 : F32), 0.0, 1.0)
      +fade = (F32.clamp(((0.0 - sy - 0.08) * 4.0 : F32), 0.0, 1.0) * F32.clamp((dy * 8.0 : F32), 0.0, 1.0) : F32)
      +lit = Bool.pick(F32, U32.is_eq((h % 23 : U32), 0), (spot * fade : F32), 0.0)
      Util.mix(c, Util.rgb(210, 223, 245), lit)

def moon(on: Bool, +c: U32, +dot: F32, +dx: F32, +dy: F32, +dz: F32, +sy: F32) -> U32:
  match on:
    case False{}:
      c
    case True{}:
      +disc = F32.clamp(((0.0 - dot - 0.9989) * 12000.0 : F32), 0.0, 1.0)
      +above = F32.clamp((dy * 500.0 : F32), 0.0, 1.0)
      +night = F32.clamp(((0.0 - sy) * 5.0 : F32), 0.0, 1.0)
      +mark = star_hash(Util.f2u(((dx + 1.0) * 180.0 : F32)), Util.f2u(((dz + 1.0) * 180.0 : F32)))
      +colour = Util.mix(Util.rgb(153, 173, 196), Util.rgb(224, 231, 240), (U32.to_f32((mark % 256 : U32)) / 255.0 : F32))
      Util.mix(c, colour, (disc * above * night : F32))

def bodies(+fl: U32, +c: U32, +dx: F32, +dy: F32, +dz: F32, +sx: F32, +sy: F32, +sz: F32) -> U32:
  +dot = (dx * sx + dy * sy + dz * sz : F32)
  +field = stars(Util.on(fl, 536870912) && (sy < (0.0 - 0.08) : F32), c, dx, dy, dz, sy)
  +sunlit = sun(Util.on(fl, 134217728), field, dot, dy, sy)
  moon(Util.on(fl, 1073741824) && (sy < 0.0 : F32), sunlit, dot, dx, dy, dz, sy)

# The average endpoint density approximates a low mist layer. Its amount
# and distance haze compose as transmittances, staying in [0,1]. A 120-block
# fade hides the far walk's end: the walk stops there (Render.far).
def height_fog(on: Bool, +t: F32, +oy: F32, +hy: F32) -> F32:
  match on:
    case False{}:
      0.0
    case True{}:
      +low = (F32.clamp(((24.0 - oy) / 20.0 : F32), 0.0, 1.0) + F32.clamp(((24.0 - hy) / 20.0 : F32), 0.0, 1.0) : F32)
      F32.clamp((t * low / 90.0 : F32), 0.0, 1.0)

# the distance at which the fog is whole: a far walk ends there
def reach() -> F32: 120.0

def fog(+fl: U32, +t: F32, +oy: F32, +hy: F32) -> F32:
  +d = Bool.pick(F32, Util.on(fl, 8), F32.clamp((t / reach() : F32), 0.0, 1.0), 0.0)
  +h = height_fog(Util.on(fl, 2147483648), t, oy, hy)
  (1.0 - (1.0 - d * d) * (1.0 - h) : F32)
