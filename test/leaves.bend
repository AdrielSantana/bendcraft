import Base
import ./lib.bend as Lib
import ../src/world.bend as World
import ../src/water.bend as Water
import ../src/render.bend as Render

def ring_of(w: World.World) -> Array<U32>:
  World.W{ring, meta} = w
  ring

# a leaf block at (64, 10, 64) with stone two blocks over it
def ring() -> Array<U32>:
  ring_of(World.edit(World.edit(World.W{[0 : U32^20n], World.Meta{Map.new(&2, World.Col), 0, 0, Nil{}, 0, 0}}, 64, 64, 10, True{}, 5), 64, 64, 12, True{}, 2))

def word(r: Array<U32> & U32) -> U32:
  (w, x) = r
  x

def glanced(r: Array<U32> & Render.Glance) -> F32:
  (w, g) = r
  Render.Glance{c, t} = g
  t

def rayed(r: Array<U32> & Render.Ray) -> F32:
  (w, hit) = r
  Render.Ray{code, t, rim, rim_end, tr} = hit
  t

# where a walk straight up from y 8.5, through the texel at (u, v) of the
# leaf's lower face, meets a block: 1.5 on the leaf, 3.5 on the stone;
# wind is the clock, 0 for still leaves
def up_glance(+u: F32, +v: F32, +open: U32, +wind: U32) -> F32:
  glanced(Render.run_glance(24n, ring(), 0, (64.0 + u : F32), 8.5, (64.0 + v : F32), 0.0, 1.0, 0.0, open, wind))

def up_ray(+u: F32, +v: F32, +leafy: Bool, +wind: U32) -> F32:
  rayed(Render.dda(~False{}, ~False{}, 60n, 0, 64.0, 8.0, 64.0, 1.0, 1.0, 1.0,
    ((1.0 - u) * 100000.0 : F32), 0.5, ((1.0 - v) * 100000.0 : F32), 100000.0, 1.0, 100000.0, 0.00001, 1.0, 0.00001, leafy, wind,
    1.0, 0, 0.0, (0.0 - 1.0 : F32), 0.0, 0, 256, Water.Trace{0.0, 0.0},
    Render.column_words(~False{}, ~False{}, ring(), World.col_at(0, 64, 64), 256, 8, 1.0, 0.5, 1.0)))

# Through each texel k = i + 8 j of the leaf's lower face, the eye's walk
# and a glance that sees the eye's gaps pass where the face's pattern is
# open, and walks that pierce nothing stop at the leaf; the count of open
# texels, and whether all agreed.
def texels(n: Nat, +k: U32, +open: U32, +ok: Bool) -> U32 & Bool:
  match n:
    case 0n:
      (open, ok)
    case 1n+m:
      +u = ((U32.to_f32((k % 8 : U32)) + 0.5) / 8.0 : F32)
      +v = ((U32.to_f32((k / 8 : U32)) + 0.5) / 8.0 : F32)
      +hole = Render.hole(1.0, u, v, Render.gaps())
      +met = Bool.pick(F32, hole, 3.5, 1.5)
      texels(m, (k + 1 : U32), (open + Bool.pick(U32, hole, 1, 0) : U32),
        ok && F32.is_eq(up_ray(u, v, True{}, 0), met) && F32.is_eq(up_glance(u, v, Render.gaps(), 0), met)
          && F32.is_eq(up_ray(u, v, False{}, 0), 1.5) && F32.is_eq(up_glance(u, v, 0, 0), 1.5))

# Through the same texels at a clock of the wind, the count whose walk
# goes otherwise than through still leaves, and whether the eye's walk
# and its glance agreed on each.
def blown(n: Nat, +k: U32, +wind: U32, +moved: U32, +ok: Bool) -> U32 & Bool:
  match n:
    case 0n:
      (moved, ok)
    case 1n+m:
      +u = ((U32.to_f32((k % 8 : U32)) + 0.5) / 8.0 : F32)
      +v = ((U32.to_f32((k / 8 : U32)) + 0.5) / 8.0 : F32)
      +met = up_glance(u, v, Render.gaps(), wind)
      blown(m, (k + 1 : U32), wind, (moved + Bool.pick(U32, F32.is_eq(met, up_glance(u, v, Render.gaps(), 0)), 0, 1) : U32),
        ok && F32.is_eq(up_ray(u, v, True{}, wind), met))

def swayed(r: U32 & Bool) -> Bool:
  (+moved, ok) = r
  ok && (moved > 0 : U32) && (moved < 64 : U32)

def agreed(r: U32 & Bool) -> Bool:
  (+open, ok) = r
  ok && (open > 10 : U32) && (open < 30 : U32)

def main() -> IO(Unit):
  do IO<Unit>:
    Lib.expect(U32.is_eq(word(Array.get(U32, ring(), World.leaf_at(World.col_at(0, 64, 64)))), 1024),
      "a column's leaf mask lies in the leaf plane: the leaf block's bit, not the stone's")
    Lib.expect(agreed(texels(64n, 0, 0, True{})),
      "the eye's walk and its glance pass a leaf block where its face's texel is open, about 30 in a hundred, and walks that pierce nothing stop at it")
    Lib.expect(swayed(blown(64n, 0, 154747, 0, True{})),
      "the wind moves a leaf block's open texels, the same for the eye's walk and its glance")
    Lib.expect(F32.is_eq(up_glance(0.3, 0.7, 100, 154747), 3.5),
      "a walk through every texel passes the leaf block and stops at the stone")
