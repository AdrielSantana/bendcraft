import Base
import ./util.bend as Util
import ./sky.bend as Sky

# THE TORCH: the hotbar's tenth slot, key 0, infinite for now. In the
# eye's hand (bit 26 of the camera's base, from the choice, with the
# torches' look on, bit 31) it lights what lies within reach() of the eye
# in a warm light that flickers. The light stands at the eye, so every
# point the eye sees it reaches, and no shadow is walked. A lit colour
# takes the brighter of its own light and the torch's, channel by
# channel, as Minecraft takes the brighter of the sky's light and a
# block's: the day hides it.

def slot() -> U32: 9

def reach() -> F32: 14.0

def held(+base: U32) -> Bool: Util.on(base, 67108864)

def chosen(+sel: U32) -> Bool: U32.is_eq((sel % 16 : U32), slot())

# the camera's base with the torch in hand when the choice is its slot
def in_hand(+base: U32, +sel: U32) -> U32:
  Bool.pick(U32, chosen(sel) && Util.on(base, 2147483648), (base .|. 67108864 : U32), base)

# how bright the flame burns at the clock ck: three waves a minute
# repeats whole, so the loop never jumps
def flicker(+ck: U32) -> F32:
  +s = (U32.to_f32((ck % 60000 : U32)) * 0.0062831853 : F32)
  (0.88 + 0.06 * F32.sin(s) + 0.04 * F32.sin((s * 2.5 : F32)) + 0.02 * F32.sin((s * 5.9 : F32)) : F32)

# its light on a face t from the eye, which the ray meets at the cosine
# da: near the day's within a few blocks, gone smoothly at reach()
def light(+ck: U32, +t: F32, +da: F32) -> F32:
  +f = (1.0 - F32.min((t * t * 0.0051020407 : F32), 1.0) : F32)
  (0.8 * flicker(ck) * f * f * (0.55 + 0.45 * Util.absf(da)) : F32)

# the same over a surface of level l, none out of the hand
def over(held: Bool, +ck: U32, +t: F32, +da: F32, +l: F32) -> F32:
  match held:
    case False{}:
      0.0
    case True{}:
      (light(ck, t, da) / l : F32)

# the brighter, channel by channel, of a light and the torch's k
def brighter(+r: F32, +g: F32, +b: F32, +k: F32) -> Sky.Tint:
  Sky.Tint{F32.max(r, (1.35 * k : F32)), F32.max(g, (0.92 * k : F32)), F32.max(b, (0.52 * k : F32))}

# a colour c in the day's level under its light a·tint, and the torch's k,
# its light over that level, in one rounding
def lit(held: Bool, +c: U32, +a: F32, tint: Sky.Tint, +k: F32) -> U32:
  match held:
    case False{}:
      Sky.tinted(Util.dim(c, a), tint)
    case True{}:
      Sky.Tint{+r, +g, +b} = tint
      Sky.tinted(c, brighter((r * a : F32), (g * a : F32), (b * a : F32), k))

# the light's colour for a surface whose own light is its level: the
# meadow's blades
def lamp(held: Bool, tint: Sky.Tint, +k: F32) -> Sky.Tint:
  match held:
    case False{}:
      tint
    case True{}:
      Sky.Tint{+r, +g, +b} = tint
      brighter(r, g, b, k)

# the water's colour ink with the torch's light k on it, as it lights the
# day's water, day
def ink(held: Bool, +ink: U32, +day: U32, +k: F32) -> U32:
  match held:
    case False{}:
      ink
    case True{}:
      +lit = Sky.tinted(day, brighter(0.0, 0.0, 0.0, k))
      Util.rgb(U32.max((ink / 65536 : U32), (lit / 65536 : U32)), U32.max((ink / 256 % 256 : U32), (lit / 256 % 256 : U32)), U32.max((ink % 256 : U32), (lit % 256 : U32)))

# the torch in the tenth slot's swatch, 16 px a side from its corner
def icon(+lx: U32, +ly: U32) -> U32:
  +stick = (lx >= 7 : U32) && (lx < 9 : U32) && (ly >= 7 : U32)
  +flame = (lx >= 6 : U32) && (lx < 10 : U32) && (ly >= 2 : U32) && (ly < 7 : U32)
  +core = (lx >= 7 : U32) && (lx < 9 : U32) && (ly >= 4 : U32) && (ly < 7 : U32)
  Bool.pick(U32, core, Util.rgb(255, 236, 150),
    Bool.pick(U32, flame, Util.rgb(240, 140, 40),
      Bool.pick(U32, stick, Util.rgb(107, 76, 40), Util.rgb(52, 52, 58))))

# the torch in the hand, over the bottom right corner: a texel a 144th of
# the window's height, a stick 2 wide under a flame of 4 x 5 whose top
# flickers; 0 where the scene shows, else 1 + the colour
def sprite(inside: Bool, +ck: U32, +tx: U32, +ty: U32) -> U32:
  match inside:
    case False{}:
      0
    case True{}:
      +high = (flicker(ck) > 0.9 : F32)
      +mid = (tx >= 2 : U32) && (tx < 4 : U32)
      +core = mid && (((ty >= 2 : U32) && (ty < 5 : U32)) || U32.is_eq(ty, Bool.pick(U32, high, 0, 1)))
      +flame = (tx >= 1 : U32) && (tx < 5 : U32) && (ty >= Bool.pick(U32, high, 1, 2) : U32) && (ty < 6 : U32)
      Bool.pick(U32, core, (1 + Util.rgb(255, 238, 160) : U32),
        Bool.pick(U32, flame, (1 + Util.rgb(240, 136, 36) : U32),
          Bool.pick(U32, mid && (ty >= 6 : U32), (1 + Bool.pick(U32, U32.is_eq(tx, 3), Util.rgb(84, 58, 30), Util.rgb(112, 80, 42)) : U32), 0)))

def in_view(chosen: Bool, +ck: U32, +pxi: U32, +pyi: U32, +rw: U32, +rh: U32) -> U32:
  match chosen:
    case False{}:
      0
    case True{}:
      +u = U32.max((rh / 144 : U32), 2)
      +x0 = (rw - 18 * u : U32)
      +y0 = (rh - 22 * u : U32)
      sprite((pxi >= x0 : U32) && (pyi >= y0 : U32) && ((pxi - x0) / u < 6 : U32), ck, ((pxi - x0) / u : U32), ((pyi - y0) / u : U32))
