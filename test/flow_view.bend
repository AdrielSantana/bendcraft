import Base
import ../src/player.bend as Player
import ../src/render.bend as Render
import ../src/world.bend as World
import ../src/flow.bend as Flow
import ../src/util.bend as Util
import ./sky.bend as Export

# The flow on the GPU: the lake west of the spawn breached into a pit dug
# beside it, seen from the pit's far rim as it fills, then settled; and
# the levels stair seen from the side at eye level, where a partial cell
# shows its plane and not a whole face. `make flow-view` renders and
# test/flow.py sheets them. Pictures, not numbers: look at them.

def dig(w: World.World, +lx: U32, +y: U32, +lz: U32) -> World.World:
  World.edit(w, lx, lz, y, False{}, 0)

# the pit: [x, x + n) x [z, z + n), heights 8 to 13
def pit_y(n: Nat, w: World.World, +x: U32, +y: U32, +z: U32) -> World.World:
  match n:
    case 0n: w
    case 1n+k: pit_y(k, dig(w, x, y, z), x, (y + 1 : U32), z)

def pit_z(n: Nat, w: World.World, +x: U32, +z: U32) -> World.World:
  match n:
    case 0n: w
    case 1n+k: pit_z(k, pit_y(6n, w, x, 8, z), x, (z + 1 : U32))

def hole(n: Nat, w: World.World, +x: U32, +z: U32, +side: Nat) -> World.World:
  match n:
    case 0n: w
    case 1n+k: hole(k, pit_z(side, w, x, z), (x + 1 : U32), z, side)

# the breach: the bank at x = 51, z = 66, heights 9 to 11
def breach(w: World.World) -> World.World:
  dig(dig(dig(w, 51, 9, 66), 51, 10, 66), 51, 11, 66)

def ticks(n: Nat, +at: U32, w: World.World) -> World.World:
  match n:
    case 0n: w
    case 1n+k: ticks(k, (at + 1 : U32), Flow.tick(w, Util.on(at, 1), Flow.budget()))

def dug(g: Player.Game) -> Player.Game:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag} = g
  Player.G{breach(hole(6n, w, 52, 61, 6n)), px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag}

def run(n: Nat, g: Player.Game) -> Player.Game:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag} = g
  Player.G{ticks(n, 0, w), px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag}

# from the pit's east rim, looking west and down into it
def rim(g: Player.Game) -> Player.Game:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag} = g
  Player.G{w, 59.5, 19.2, 63.5, (0.0 - 1.5707963 : F32), (0.0 - 0.62 : F32), vy, held, edge, mx, my, sel, res, 300000, bag}

# in the pit, at eye level with its water, looking west at the breach
def wading(g: Player.Game) -> Player.Game:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag} = g
  Player.G{w, 57.5, 10.9, 64.5, (0.0 - 1.5707963 : F32), (0.0 - 0.1 : F32), vy, held, edge, mx, my, sel, res, 300000, bag}

# the levels stair (test/water_view.bend) from the side, the eye a little
# over the lake's surface, looking north along the stair
def stair(n: Nat, w: World.World, +i: U32) -> World.World:
  match n:
    case 0n: w
    case 1n+k: stair(k, World.pour(w, (38 + i * 2 : U32), 11, 66, ((i + 1) * 32 : U32)), (i + 1 : U32))

def stair_side(g: Player.Game) -> Player.Game:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag} = g
  Player.G{stair(7n, w, 0), 44.5, 12.3, 70.5, 3.1415927, (0.0 - 0.12 : F32), vy, held, edge, mx, my, sel, res, 300000, bag}

def main() -> IO(Unit):
  do IO<Unit>:
    g : Player.Game = Player.start_at(Player.res_of(512, 288))
    a : Player.Game <- Export.save("build/flow-dug.tree", Player.view(rim(dug(g))))
    b : Player.Game <- Export.save("build/flow-filling.tree", Player.view(run(24n, a)))
    c : Player.Game <- Export.save("build/flow-wading.tree", Player.view(wading(b)))
    d : Player.Game <- Export.save("build/flow-settled.tree", Player.view(rim(run(400n, c))))
    e : Player.Game <- Export.save("build/flow-settled-wading.tree", Player.view(wading(d)))
    f : Player.Game <- Export.save("build/flow-stair-side.tree", Player.view(stair_side(Player.start_at(Player.res_of(512, 288)))))
    IO.pure(Unit, Unit{})
