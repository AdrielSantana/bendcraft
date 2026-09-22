import Base
import ../src/world.bend as World
import ../src/flow.bend as Flow
import ../src/player.bend as Player
import ../src/util.bend as Util

# A lake drains: the world at the start, a shaft dug from the bed of the
# lake west of the spawn down into a cavern carved under it, then ticks
# of the flow on the host, timed; every ten, the ms a tick and the
# queue's length. `bend test/flow_bench.bend -o build/flow_bench &&
# ./build/flow_bench`. The budget is chosen here: a tick must stay well
# under a frame.

def dig(w: World.World, +lx: U32, +y: U32, +lz: U32) -> World.World:
  World.edit(w, lx, lz, y, False{}, 0)

# the cavern: [x, x + n) x [z, z + n) at heights 2, 3, 4
def carve_z(n: Nat, w: World.World, +x: U32, +z: U32) -> World.World:
  match n:
    case 0n:
      w
    case 1n+k:
      carve_z(k, dig(dig(dig(w, x, 2, z), x, 3, z), x, 4, z), x, (z + 1 : U32))

def carve(n: Nat, w: World.World, +x: U32, +z: U32, +side: Nat) -> World.World:
  match n:
    case 0n:
      w
    case 1n+k:
      carve(k, carve_z(side, w, x, z), (x + 1 : U32), z, side)

# the shafts: the columns [45, 45 + wide) x [66, 66 + wide) from height 5 to the bed
def shaft(n: Nat, w: World.World, +x: U32, +z: U32, +y: U32) -> World.World:
  match n:
    case 0n:
      w
    case 1n+k:
      shaft(k, dig(w, x, y, z), x, z, (y + 1 : U32))

def shafts_z(n: Nat, w: World.World, +x: U32, +z: U32) -> World.World:
  match n:
    case 0n:
      w
    case 1n+k:
      shafts_z(k, shaft(9n, w, x, z, 5), x, (z + 1 : U32))

def shafts(n: Nat, w: World.World, +x: U32, +z: U32, +wide: Nat) -> World.World:
  match n:
    case 0n:
      w
    case 1n+k:
      shafts(k, shafts_z(wide, w, x, z), (x + 1 : U32), z, wide)

def queued(w: World.World) -> World.World & Nat:
  World.W{ring, +meta} = w
  World.Meta{m, ox, oz, q, np, gone} = meta
  +n = List.length(&2, U32, q)
  (World.W{ring, meta}, n)

def world(g: Player.Game) -> World.World:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag} = g
  w

law run:
  for  n: Nat
  for  +at: U32
  for  +acc: Nat
  for  w: World.World
  IO(Unit)

@unsafe
def report(n: Nat, +at: U32, +acc: Nat, r: World.World & Nat) -> IO(Unit):
  (w, q) = r
  do IO<Unit>:
    IO.print("tick " ++ U32.show(at) ++ ": " ++ Nat.show(acc) ++ " ms the last ten, queue " ++ Nat.show(q))
    run(n, at, 0n, w)

# every tenth tick reports; the others go on
@unsafe
def run_fin(tenth: Bool, n: Nat, +at: U32, +acc: Nat, +t0: Nat, +t1: Nat, w: World.World) -> IO(Unit):
  match tenth:
    case True{}:
      report(n, (at + 1 : U32), (acc + (t1 - t0 : Nat) : Nat), queued(w))
    case False{}:
      run(n, (at + 1 : U32), (acc + (t1 - t0 : Nat) : Nat), w)

@unsafe
def run(n, at, acc, w):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+m:
      do IO<Unit>:
        t0 : Nat <- IO.now()
        w2 : World.World = Flow.tick(w, Util.on(at, 1), Flow.budget())
        t1 : Nat <- IO.now()
        run_fin(U32.is_eq((at % 10 : U32), 9), m, at, acc, t0, t1, w2)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("the lake at the spawn drains through one shaft at (45, 66) into a cavern of 16 x 16 x 3, budget " ++ Nat.show(Flow.budget()) ++ " columns a tick")
    run(200n, 0, 0n, shafts(1n, carve(16n, world(Player.start_at(Player.res512())), 38, 58, 16n), 45, 66, 1n))
    IO.print("through 4 x 4 shafts into a cavern of 48 x 48 x 3")
    run(300n, 0, 0n, shafts(4n, carve(48n, world(Player.start_at(Player.res512())), 20, 40, 48n), 45, 66, 4n))
