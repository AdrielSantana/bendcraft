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

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("along x at the start: " ++ row(40n, 1048576, 1048576, 1, 0))
    IO.print("along z at the start: " ++ row(40n, 1048576, 1048576, 0, 1))
    IO.print("along x near zero:    " ++ row(40n, 100, 100, 1, 0))
    IO.print("along z near zero:    " ++ row(40n, 100, 100, 0, 1))
    IO.pure(Unit, Unit{})
