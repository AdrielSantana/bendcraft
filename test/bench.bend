import Base
import ../src/world.bend as World
import ../src/player.bend as Player

# The frame without a window: five frames with the camera turning 0.01 rad
# a frame, a checksum of the image per frame, the time of the `!` and of
# the checksum walk apart. Once on the untouched world, once with 300
# blocks placed. `bend test/bench.bend -o build/bench && ./build/bench`;
# the checksums must not change between builds that change nothing visible.

def total(+k: Nat, img: Image) -> U32:
  match k:
    case 0n:
      match img:
        case Pix{c}:
          c
        case Qua{tl, tr, bl, br}:
          0
    case 1n+j:
      match img:
        case Pix{c}:
          c
        case Qua{tl, tr, bl, br}:
          a b c d = total(j, tl) total(j, tr) total(j, bl) total(j, br)
          (a + b + c + d : U32)

def turn(g: Player.Game) -> Player.Game:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my} = g
  Player.G{w, px, py, pz, (yaw + 0.01 : F32), pit, vy, held, edge, mx, my}

law bench:
  for  n: Nat
  for  g: Player.Game
  IO(Unit)

@unsafe
def bench_fin(n: Nat, +t0: Nat, +t1: Nat, r: Player.Game & Image) -> IO(Unit):
  (g, img) = r
  do IO<Unit>:
    +sum : U32 = total(9n, img)
    t2 : Nat <- IO.now()
    IO.print("gpu=" ++ Nat.show((t1 - t0 : Nat)) ++ " walk=" ++ Nat.show((t2 - t1 : Nat)) ++ " checksum=" ++ U32.show(sum))
    bench(n, turn(g))

@unsafe
def bench(n, g):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+m:
      do IO<Unit>:
        t0 : Nat <- IO.now()
        r : Player.Game & Image = Player.view(g)
        t1 : Nat <- IO.now()
        bench_fin(m, t0, t1, r)

def build(n: Nat, w: World.World, +i: U32) -> World.World:
  match n:
    case 0n:
      w
    case 1n+m:
      build(m, World.edit(w, (56 + i % 16 : U32), (70 + i / 16 % 12 : U32), U32.shln(1, U32.to_nat((19 + i % 2 : U32))), True{}), (i + 1 : U32))

def edited(n: Nat, g: Player.Game) -> Player.Game:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my} = g
  Player.G{build(n, w, 0), px, py, pz, yaw, pit, vy, held, edge, mx, my}

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("untouched")
    bench(5n, Player.start())
    IO.print("built 300")
    bench(5n, edited(300n, Player.start()))
