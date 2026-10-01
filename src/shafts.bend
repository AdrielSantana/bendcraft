import Base
import ./util.bend as Util
import ./sky.bend as Sky
import ./clouds.bend as Clouds

# THE SHAFTS: the sun's light in the haze (Cam's base bit 30). Eight
# points along the rays through a 4x4 tile's corners, out to 96 blocks and
# denser near the eye, are tested against the sun (Render.beams): how much
# of it reaches each, a nibble a point. A pixel weighs its tile's corners
# by its place into a profile, and the haze it looks through to what it
# met glows in the sun's colour where the sun reaches it, the far dimmed
# by the near, most towards the sun and as it sets: the shade of a canopy,
# a hill or a cloud cuts darker air out of it.

def reach() -> F32: 96.0

# where the i-th point's stretch of the ray starts
def edge(+i: U32) -> F32:
  (reach() * U32.to_f32((i * i : U32)) / 64.0 : F32)

# the i-th point, in the middle of its stretch
def at(+i: U32) -> F32:
  ((edge(i) + edge((i + 1 : U32))) * 0.5 : F32)

# the tile's four corners, a nibble a point, the first point the low one
type Beams is Data:
  Beams{tl: U32, tr: U32, bl: U32, br: U32}

def nib(+x: U32) -> F32: U32.to_f32((x % 16 : U32))

# the profile of the pixel (fx, fy) of its tile, in quarters
def weighed(n: Nat, +tl: U32, +tr: U32, +bl: U32, +br: U32, +fx: F32, +fy: F32, +q: U32, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+k:
      +top = (nib(tl) + (nib(tr) - nib(tl)) * fx : F32)
      +low = (nib(bl) + (nib(br) - nib(bl)) * fx : F32)
      weighed(k, (tl / 16 : U32), (tr / 16 : U32), (bl / 16 : U32), (br / 16 : U32), fx, fy, (q * 16 : U32),
        (acc + q * Util.near((top + (low - top) * fy : F32)) : U32))

def profile(b: Beams, +fx: F32, +fy: F32) -> U32:
  Beams{+tl, +tr, +bl, +br} = b
  weighed(8n, tl, tr, bl, br, fx, fy, 1, 0)

# the haze the eye sees to d, the far dimmed by the near
def depth(+d: F32) -> F32:
  (24.0 * (1.0 - F32.exp((0.0 - d / 24.0 : F32))) : F32)

# of it, the haze the sun reaches
def lit(n: Nat, +prof: U32, +d: F32, +i: U32, +s: F32) -> F32:
  match n:
    case 0n:
      s
    case 1n+k:
      lit(k, (prof / 16 : U32), d, (i + 1 : U32),
        (s + nib(prof) / 15.0 * (depth(F32.min(d, edge((i + 1 : U32)))) - depth(F32.min(d, edge(i)))) : F32))

# the haze scatters the sun's light forward: most towards it, some aside
def phase(+mu: F32) -> F32:
  (0.12 + 1.5 * F32.exp(((mu - 1.0) * 5.0 : F32)) : F32)

# the haze's light to d over c, k of it (the share of the pixel it lies
# over), in the body's colour (Sky.side: the sun, or the moon once it has
# set) and as bright; thicker as it sets, rising with it, and a heavy sky
# veils it
def glowed(on: Bool, +c: U32, +prof: U32, +d: F32, +k: F32, +ck: U32,
           +dx: F32, +dy: F32, +dz: F32, +lx: F32, +ly: F32, +lz: F32) -> U32:
  match on:
    case False{}:
      c
    case True{}:
      +sg = Sky.side(True{}, ly)
      +up = (sg * ly : F32)
      +a = (0.008 * k * lit(8n, prof, d, 0, 0.0) * phase((sg * (dx * lx + dy * ly + dz * lz) : F32))
        * F32.clamp((up * 10.0 : F32), 0.0, 1.0) * (2.5 - 1.5 * F32.clamp((up * 2.5 : F32), 0.0, 1.0))
        * (1.0 - Clouds.gloom(Clouds.weather(ck))) * Sky.strength(True{}, ly) * Bool.pick(F32, Sky.moonlit(ly), 2.0, 1.0) : F32)
      +s = Sky.body_colour(ly)
      Util.rgb(Util.screen((c / 65536 : U32), (a * U32.to_f32((s / 65536 : U32)) / 255.0 : F32)),
        Util.screen((c / 256 % 256 : U32), (a * U32.to_f32((s / 256 % 256 : U32)) / 255.0 : F32)),
        Util.screen((c % 256 : U32), (a * U32.to_f32((s % 256 : U32)) / 255.0 : F32)))

# the look is on while the sun or the moon is up, and not for the
# profile's counts
def on(+fl: U32, +base: U32, +ly: F32) -> Bool:
  Util.on(base, 1073741824) && Bool.not(Util.on(fl, 96)) && (Sky.up(Sky.moon_on(fl), ly) > 0.0 : F32)

def over(on: Bool, +prof: U32, +d: F32, +k: F32, +ck: U32, +dx: F32, +dy: F32, +dz: F32,
         +lx: F32, +ly: F32, +lz: F32, r: Array<U32> & U32) -> Array<U32> & U32:
  (w, +c) = r
  (w, glowed(on, c, prof, d, k, ck, dx, dy, dz, lx, ly, lz))

# how far a ray the window's walk let go on crosses the haze: to the
# clouds, or as far as the points reach
def open_air(+oy: F32, +dy: F32) -> F32:
  F32.min(reach(), ((Clouds.middle() - oy) / F32.max(dy, 0.001) : F32))
