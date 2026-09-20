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
      trees_z(k, x, (z + 1 : U32), (acc + Bool.pick(U32, World.tree_at(x, z) && (World.terrain(x, z) >= 7 : U32) && (World.terrain(x, z) <= 24 : U32), 1, 0) : U32))

def trees(n: Nat, +x: U32, +z: U32, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+k:
      trees(k, (x + 1 : U32), z, trees_z(128n, x, z, acc))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("along x at the start: " ++ row(40n, 1048576, 1048576, 1, 0))
    IO.print("along z at the start: " ++ row(40n, 1048576, 1048576, 0, 1))
    IO.print("along x near zero:    " ++ row(40n, 100, 100, 1, 0))
    IO.print("along z near zero:    " ++ row(40n, 100, 100, 0, 1))
    IO.print("trees in the start window: " ++ U32.show(trees(128n, 1048512, 1048512, 0)))
    IO.pure(Unit, Unit{})
