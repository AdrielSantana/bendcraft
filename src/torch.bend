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
# block's, and the day fades it out (night).

# the hotbar's tenth slot, and the torch block's type
def slot() -> U32: 9

def reach() -> F32: 14.0

def held(+base: U32) -> Bool: Util.on(base, 67108864)

# the torches' look, bit 31: the light in the hand and the placed ones'
def lights(+base: U32) -> Bool: Util.on(base, 2147483648)

def chosen(+sel: U32) -> Bool: U32.is_eq((sel % 16 : U32), slot())

# the camera's base with the torch in hand when the choice is its slot
def in_hand(+base: U32, +sel: U32) -> U32:
  Bool.pick(U32, chosen(sel) && lights(base), (base .|. 67108864 : U32), base)

# how bright the flame burns at the clock ck: three waves a minute
# repeats whole, so the loop never jumps
def flicker(+ck: U32) -> F32:
  +s = (U32.to_f32((ck % 60000 : U32)) * 0.0062831853 : F32)
  (0.88 + 0.06 * F32.sin(s) + 0.04 * F32.sin((s * 2.5 : F32)) + 0.02 * F32.sin((s * 5.9 : F32)) : F32)

# how a torch's light falls t blocks away: near whole within a few,
# gone smoothly at reach()
def fall(+t: F32) -> F32:
  +f = (1.0 - F32.min((t * t * 0.0051020407 : F32), 1.0) : F32)
  (0.8 * f * f : F32)

# its light on a face t from the eye, which the ray meets at the cosine da
def light(+ck: U32, +t: F32, +da: F32) -> F32:
  (fall(t) * flicker(ck) * (0.55 + 0.45 * Util.absf(da)) : F32)

# a placed torch's light where the grid's level is l (World.light_at), as
# the hand's 14 - l blocks away
def glow(+l: F32) -> F32: fall((14.0 - l : F32))

# what the day leaves of the torches' light, the sun at height sy: all of
# it once the sun is 0.12 under the horizon, none from 0.17 over it, since
# a torch's warm red outshines the sun's white by its own
def night(+sy: F32) -> F32: (1.0 - Sky.daylight(sy) : F32)

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

# THE TORCH BLOCK, type 9: a stick of 2 by 10 texels of 16 standing in the
# middle of its cell, its top three the flame. It is not solid and casts
# no shadow; it rides the leaf plane (World.plane), and a walk that comes
# into its cell meets it where it crosses the stick's box.
def lo() -> F32: 0.4375
def hi() -> F32: 0.5625
def top() -> F32: 0.625

# how far on a ray of sign s and inverse rate e, at p on an axis of the
# cell (0 to 1), enters and leaves the slab from a to b
def enter(+s: F32, +p: F32, +a: F32, +b: F32, +e: F32) -> F32:
  (Bool.pick(F32, (s > 0.0 : F32), (a - p : F32), (p - b : F32)) * e : F32)

def leave(+s: F32, +p: F32, +a: F32, +b: F32, +e: F32) -> F32:
  (Bool.pick(F32, (s > 0.0 : F32), (b - p : F32), (p - a : F32)) * e : F32)

# how far on the ray from p in the cell meets the stick, under 0 for a miss
def stick(+sx: F32, +sy: F32, +sz: F32, +px: F32, +py: F32, +pz: F32, +ex: F32, +ey: F32, +ez: F32) -> F32:
  +a = F32.max(F32.max(enter(sx, px, lo(), hi(), ex), enter(sy, py, 0.0, top(), ey)), enter(sz, pz, lo(), hi(), ez))
  +b = F32.min(F32.min(leave(sx, px, lo(), hi(), ex), leave(sy, py, 0.0, top(), ey)), leave(sz, pz, lo(), hi(), ez))
  Bool.pick(F32, (a <= b : F32) && (b >= 0.0 : F32), F32.max(a, 0.0), (0.0 - 1.0 : F32))

def sign(+d: F32) -> F32: Bool.pick(F32, (d > 0.0 : F32), 1.0, (0.0 - 1.0 : F32))

def inverse(+d: F32) -> F32: (1.0 / F32.max(Util.absf(d), 0.00001) : F32)

# a texel of the flame's three rows, orange at its foot to white at its
# top, or of the stick, its second column darker
def texel(+row: U32, +column: U32) -> U32:
  Bool.pick(U32, (row >= 9 : U32), Util.rgb(255, 238, 160),
    Bool.pick(U32, U32.is_eq(row, 8), Util.rgb(255, 196, 80),
      Bool.pick(U32, U32.is_eq(row, 7), Util.rgb(240, 136, 36),
        Bool.pick(U32, U32.is_eq(column, 1), Util.rgb(84, 58, 30), Util.rgb(112, 80, 42)))))

# the torch seen along d where the ray meets its stick at p, at the clock
# ck: the stick brighter up to the flame, which flickers, a side shaded
# as a block's
def look(+ck: U32, +px: F32, +py: F32, +pz: F32, +dx: F32, +dy: F32, +dz: F32) -> U32:
  +qx = Util.fracf(px)
  +qy = Util.fracf(py)
  +qz = Util.fracf(pz)
  +ix = enter(sign(dx), qx, lo(), hi(), inverse(dx))
  +iy = enter(sign(dy), qy, 0.0, top(), inverse(dy))
  +iz = enter(sign(dz), qz, lo(), hi(), inverse(dz))
  +t = F32.max(F32.max(ix, iy), iz)
  +side = F32.is_eq(t, ix)
  +up = Bool.not(side) && F32.is_eq(t, iy)
  +row = Util.f2u(F32.clamp(((qy + dy * t) * 16.0 : F32), 0.0, 9.0))
  +across = Bool.pick(F32, side, (qz + dz * t : F32), (qx + dx * t : F32))
  +flame = (row >= 7 : U32)
  Util.dim(texel(row, Util.f2u(F32.clamp(((across - lo()) * 16.0 : F32), 0.0, 1.0))),
    Bool.pick(F32, flame, F32.min((flicker(ck) * 1.08 : F32), 1.0),
      (Bool.pick(F32, side, 0.8, Bool.pick(F32, up, 1.0, 0.7)) * (0.55 + 0.45 * Util.u2f(row) / 6.0) : F32)))

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
