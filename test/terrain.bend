import Base
import ../src/world.bend as World

# Rows of the terrain, to see the noise with your eyes: heights must roll
# along x as along z. A hash that is a product per axis made stripes here.

def row(n: Nat, +x: U32, +z: U32, +dx: U32, +dz: U32) -> String:
  match n:
    case 0n:
      ""
    case 1n+k:
      U32.show(World.terrain(x, z)) ++ " " ++ row(k, (x + dx : U32), (z + dz : U32), dx, dz)

def trees_z(n: Nat, +x: U32, +z: U32, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+k:
      trees_z(k, x, (z + 1 : U32), (acc + Bool.pick(U32, World.tree_at(x, z) && World.tree_ground(World.terrain(x, z)), 1, 0) : U32))

def trees(n: Nat, +x: U32, +z: U32, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+k:
      trees(k, (x + 1 : U32), z, trees_z(128n, x, z, acc))

def expect(ok: Bool, name: String) -> IO(Unit):
  match ok:
    case True{}: IO.print("ok " ++ name)
    case False{}: IO.die(Unit, 1, "failed " ++ name)

# Inspect the generated column, including neighbours' canopies. Below the
# water surface only the ground may be solid; every gap must be water.
def dry_roots(+h: U32, c: World.Col) -> Bool:
  World.Col{m, a, b, cc, d, water} = c
  +ground = (U32.shln(1, U32.to_nat(h)) - 1 : U32)
  U32.is_eq((m .&. 4095 : U32), (ground .&. 4095 : U32))
    && U32.is_eq(water, (4095 .&. U32.not(ground) : U32))

def scan(n: Nat, +i: U32, ok: Bool) -> Bool:
  match n:
    case 0n: ok
    case 1n+k:
      +x = (1048512 + i / 128 : U32)
      +z = (1048512 + i % 128 : U32)
      scan(k, (i + 1 : U32), ok && dry_roots(World.terrain(x, z), World.column(x, z)))

def no_tree(m: World.Masks) -> Bool:
  World.Masks{wood, leaf} = m
  U32.is_eq(wood, 0) && U32.is_eq(leaf, 0)

def shore_tree(c: World.Col) -> Bool:
  World.Col{m, a, b, cc, d, water} = c
  U32.is_eq((m .&. 258048 : U32), 258048) && U32.is_eq(water, 0)
    && U32.is_eq(World.nib_get(b, 12), 4) && U32.is_eq(World.nib_get(cc, 16), 5)

def old_tree(r: Array<U32> & World.Col) -> Bool:
  (ring, c) = r
  World.Col{m, a, b, cc, d, water} = c
  U32.is_eq(m, 511) && U32.is_eq(b, 4) && U32.is_eq(water, 3584)

# Existing edited columns are authoritative, even if the new generator
# would reject their submerged tree. Loading must not erase old builds.
def saved_tree(w: World.World) -> Bool:
  World.W{ring, edits, ox, oz} = w
  old_tree(World.get_col(ring, World.col_at(0, 1048543, 1048592)))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("along x at the start: " ++ row(40n, 1048576, 1048576, 1, 0))
    IO.print("along z at the start: " ++ row(40n, 1048576, 1048576, 0, 1))
    IO.print("along x near zero:    " ++ row(40n, 100, 100, 1, 0))
    IO.print("along z near zero:    " ++ row(40n, 100, 100, 0, 1))
    IO.print("trees in the start window: " ++ U32.show(trees(128n, 1048512, 1048512, 0)))
    expect(scan(16384n, 0, True{}), "generated start window has no submerged trees and fills their gaps with water")
    expect(World.tree_at(1048543, 1048592) && U32.is_eq(World.terrain(1048543, 1048592), 8)
      && no_tree(World.tree_here(1048543, 1048592, 0, False{}, World.Masks{0, 0}))
      && no_tree(World.tree_here(1048543, 1048592, 1, False{}, World.Masks{0, 0}))
      && no_tree(World.tree_here(1048543, 1048592, 2, False{}, World.Masks{0, 0})), "submerged tree contributes neither trunk nor canopy in neighbouring columns")
    expect(U32.is_eq(World.terrain(1048512, 1048515), 12) && shore_tree(World.column(1048512, 1048515)), "tree at the dry shoreline keeps its trunk and leaves")
    expect(saved_tree(World.load(World.W{[0 : U32^17n],
      Map.set(&2, World.Col, Map.new(&2, World.Col), "1048543,1048592", World.Col{511, 0, 4, 0, 0, 3584}),
      1048512, 1048512}, 1048543, 1048592)), "saved submerged wood survives generation changes")
    IO.pure(Unit, Unit{})
