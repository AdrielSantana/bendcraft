import Base
import ./lib.bend as Lib
import ../src/world.bend as World
import ../src/grass.bend as Grass
import ../src/meadow.bend as Meadow

# A plateau of 51 by 51 columns whose top block is at 9, grass or stone,
# with the meadow's map loaded.
def plateau(n: Nat, w: Array<U32>, +i: U32, +stone: U32) -> Array<U32>:
  match n:
    case 0n:
      w
    case 1n+k:
      +col = World.col_at(0, (40 + i / 51 : U32), (40 + i % 51 : U32))
      plateau(k, Array.set(U32, Array.set(U32, w, col, 512), (col + 2 : U32), stone), (i + 1 : U32), stone)

def meadow(+stone: U32) -> Array<U32>:
  Meadow.load(256n, plateau(2601n, [0 : U32^20n], 0, stone), 0)

# the map's words along a diagonal of columns against the words they hold
def mapped(n: Nat, +x: U32, +ok: Bool, r: Array<U32> & U32) -> Bool:
  match n:
    case 0n:
      ok
    case 1n+k:
      (w, +word) = r
      +nx = (x + 37 : U32)
      mapped(k, nx, ok && U32.is_eq(word, Meadow.word_at((x % 256 : U32), (x * 3 % 256 : U32))), Array.get(U32, w, Meadow.map_at(nx, (nx * 3 : U32))))

def seen(r: Array<U32> & Grass.Meadow) -> Grass.Meadow:
  (w, m) = r
  m

# what a ray along z from (64.5, y, 40.5) sees of the grass over 20 blocks
def along(+y: F32, w: Array<U32>) -> Grass.Meadow:
  seen(Grass.march(w, 0, 0, 0, 64.5, y, 40.5, 0.0, 0.0, 1.0, 0.0, 20.0))

def clear(m: Grass.Meadow) -> Bool:
  Grass.Meadow{tr, n, lit, s, head, heart, t, hue, low} = m
  F32.is_eq(tr, 1.0) && F32.is_eq(n, 0.0) && F32.is_eq(low, 0.0)

def hidden(m: Grass.Meadow) -> Bool:
  Grass.Meadow{tr, n, lit, s, head, heart, t, hue, low} = m
  (tr < 0.5 : F32)

def met(m: Grass.Meadow) -> Bool:
  Grass.Meadow{tr, n, lit, s, head, heart, t, hue, low} = m
  (tr < 1.0 : F32) || (low > 0.0 : F32)

# a ray down onto the floor from half a block over it
def down(w: Array<U32>) -> Bool:
  met(seen(Grass.march(w, 0, 0, 0, 64.3, 10.5, 64.6, 0.1961161, (0.0 - 0.9805807 : F32), 0.0, 0.0, 0.5099020)))

def main() -> IO(Unit):
  do IO<Unit>:
    Lib.expect(mapped(40n, 0, True{}, Array.get(U32, meadow(0), Meadow.map_at(0, 0))),
      "the meadow's map holds each column's word, at its coordinates mod 256")
    Lib.expect(hidden(along(10.2, meadow(0))) && clear(along((10.0 + Grass.top() + 0.01 : F32), meadow(0))),
      "a ray through the grass's height is hidden by its blades, and one a hair over top() meets none")
    Lib.expect(clear(along(10.2, meadow(572662306))), "a stone top grows no grass")
    Lib.expect(down(meadow(0)) && Bool.not(down(meadow(572662306))),
      "a ray down onto a grass top meets its blades or the shade at their feet, and onto stone neither")
