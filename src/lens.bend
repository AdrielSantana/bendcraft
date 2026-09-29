import Base
import ./util.bend as Util
import ./sky.bend as Sky

# THE LENS: the sun in the camera (Cam.fl bit 19), over what a pixel shows,
# as much as the eye sees of the sun (seen, 0 to 1, Render.sighted). The
# glare is the sun's light spilled around it in the lens, over what stands
# before it too: a bright core, a glow and a wide veil. The flare is the
# lens's ghosts of the sun along the line from it through the screen's
# middle, soft hexagons in the coatings' colours, and a thin streak
# across it. Both are on the screen's coordinates as the ray is cast
# (Render.shade_px): the pixel's (u, v) and the sun's (su, sv).

def glare(+d: F32) -> F32:
  (0.8 * F32.exp(((d - 1.0) * 3000.0 : F32)) + 0.3 * F32.exp(((d - 1.0) * 80.0 : F32)) + 0.08 * F32.exp(((d - 1.0) * 6.0 : F32)) : F32)

# a ghost: a soft hexagon, the aperture's shape turned a little, of
# inradius radius at the point `at` of the way from the screen's middle to
# the sun, its rim a little brighter than its middle
def ghost(+u: F32, +v: F32, +su: F32, +sv: F32, +at: F32, +radius: F32, +k: F32) -> F32:
  +x = (u - su * at : F32)
  +y = (v - sv * at : F32)
  +ax = Util.absf((0.966 * x - 0.259 * y : F32))
  +ay = Util.absf((0.259 * x + 0.966 * y : F32))
  +d = (F32.max(ay, (0.866 * ax + 0.5 * ay : F32)) / radius : F32)
  (k * F32.clamp(((1.0 - d) * 5.0 : F32), 0.0, 1.0) * (0.55 + 0.45 * F32.min(d, 1.0)) : F32)

# a ghost of the colour (r, g, b), its red a little wider than its blue,
# so its rim splits as a lens's glass does
def hued(+u: F32, +v: F32, +su: F32, +sv: F32, +at: F32, +radius: F32, +k: F32, +r: F32, +g: F32, +b: F32) -> Sky.Tint:
  Sky.Tint{(r * ghost(u, v, su, sv, at, (radius * 1.05 : F32), k) : F32), (g * ghost(u, v, su, sv, at, radius, k) : F32),
    (b * ghost(u, v, su, sv, at, (radius * 0.95 : F32), k) : F32)}

def plus(a: Sky.Tint, b: Sky.Tint) -> Sky.Tint:
  Sky.Tint{+ar, +ag, +ab} = a
  Sky.Tint{+br, +bg, +bb} = b
  Sky.Tint{(ar + br : F32), (ag + bg : F32), (ab + bb : F32)}

def flare(+u: F32, +v: F32, +su: F32, +sv: F32) -> Sky.Tint:
  +streak = (0.28 * F32.exp((0.0 - Util.absf((v - sv : F32)) * 90.0 : F32)) * F32.exp((0.0 - Util.absf((u - su : F32)) * 1.2 : F32)) : F32)
  plus(plus(plus(hued(u, v, su, sv, 0.55, 0.035, 0.35, 1.0, 0.78, 0.47), hued(u, v, su, sv, (0.0 - 0.25 : F32), 0.06, 0.26, 0.55, 1.0, 0.75)),
    plus(hued(u, v, su, sv, (0.0 - 0.55 : F32), 0.13, 0.18, 0.63, 0.55, 1.0), hued(u, v, su, sv, (0.0 - 0.9 : F32), 0.05, 0.22, 1.0, 0.7, 0.35))),
    plus(hued(u, v, su, sv, (0.0 - 1.25 : F32), 0.22, 0.11, 0.47, 0.75, 1.0), Sky.Tint{streak, (0.85 * streak : F32), (0.6 * streak : F32)}))

# light a added over a channel c as a screen does: toward white, never past it
def screen(+c: U32, +a: F32) -> U32:
  F32.to_u32((U32.to_f32(c) + (255.0 - U32.to_f32(c)) * F32.clamp(a, 0.0, 1.0) : F32))

# the glare g in the sun's colour and the flare f, k of it, over c
def lit(+c: U32, +g: F32, +sun: U32, +k: F32, f: Sky.Tint) -> U32:
  Sky.Tint{+r, +gr, +b} = f
  Util.rgb(screen((c / 65536 : U32), (g * U32.to_f32((sun / 65536 : U32)) / 255.0 + k * r : F32)),
    screen((c / 256 % 256 : U32), (g * U32.to_f32((sun / 256 % 256 : U32)) / 255.0 + k * gr : F32)),
    screen((c % 256 : U32), (g * U32.to_f32((sun % 256 : U32)) / 255.0 + k * b : F32)))

# the sun's place on the screen from its direction l on the camera's
# forward f, right r and up e, as the ray is cast (d = f + 0.9 u r + 0.9 v e);
# a sun behind the eye or far off the screen shows no ghosts
def through(on: Bool, +c: U32, +seen: F32, +u: F32, +v: F32, +dx: F32, +dy: F32, +dz: F32,
            +fx: F32, +fy: F32, +fz: F32, +rx: F32, +rz: F32, +ex: F32, +ey: F32, +ez: F32,
            +lx: F32, +ly: F32, +lz: F32) -> U32:
  match on:
    case False{}:
      c
    case True{}:
      +lf = (lx * fx + ly * fy + lz * fz : F32)
      +k = (1.0 / (0.9 * F32.max(lf, 0.05)) : F32)
      +su = ((lx * rx + lz * rz) * k : F32)
      +sv = ((lx * ex + ly * ey + lz * ez) * k : F32)
      +near = Bool.pick(F32, (lf > 0.05 : F32), F32.clamp((1.5 - F32.sqrt((su * su + sv * sv : F32)) : F32), 0.0, 1.0), 0.0)
      lit(c, (seen * glare((dx * lx + dy * ly + dz * lz : F32)) : F32), Sky.sun_colour(ly), (seen * near : F32), flare(u, v, su, sv))
