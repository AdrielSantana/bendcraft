import Base
import ../src/world.bend as World
import ../src/player.bend as Player
import ../src/save.bend as Save

# Save and load without a window: place a brick, walk a bit, save to a
# file under build/, load it back, and print what came back: the position
# and the brick.

def ticks(n: Nat, g: Player.Game) -> Player.Game:
  match n:
    case 0n:
      g
    case 1n+m:
      ticks(m, Player.step(g))

def one(e: Event) -> List<Event>:
  Con{e, Nil{}}

def spot_fin(+px: F32, +py: F32, +pz: F32, +yaw: F32, +pit: F32, +sel: U32, res: U32, clock: U32, bag: List<&2, Nat>, w: World.World) -> Player.Game & String:
  World.W{ring, m, +ox, +oz} = w
  (Player.G{World.W{ring, m, ox, oz}, px, py, pz, yaw, pit, 0.0, 0, 0, 0, 0, sel, res, clock, bag},
   "p=(" ++ F32.show(px) ++ ", " ++ F32.show(py) ++ ", " ++ F32.show(pz) ++ ") yaw=" ++ F32.show(yaw) ++ " pit=" ++ F32.show(pit) ++ " sel=" ++ U32.show(sel) ++ " corner=" ++ U32.show(ox) ++ "," ++ U32.show(oz))

def spot(g: Player.Game) -> Player.Game & String:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag} = g
  spot_fin(px, py, pz, yaw, pit, sel, res, clock, bag, w)

# the brick sits at world column (1048572, 1048572): local (60, 60) at
# the start, (60, 55) once the walk has moved the corner five columns
def brick_fin(px: F32, py: F32, pz: F32, yaw: F32, pit: F32, vy: F32, held: U32, edge: U32, mx: U32, my: U32, sel: U32, res: U32, clock: U32, bag: List<&2, Nat>,
              +lz: U32, r: World.World & U32) -> Player.Game & String:
  (w, t) = r
  (Player.G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag}, "type at local (60, 25, " ++ U32.show(lz) ++ ") = " ++ U32.show(t) ++ " (6 is brick)")

def brick(g: Player.Game, +lz: U32) -> Player.Game & String:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag} = g
  brick_fin(px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag, lz, World.voxel(w, 60, 25, lz))

def place(g: Player.Game) -> Player.Game:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag} = g
  Player.G{World.edit(w, 60, 60, 25, True{}, 6), px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag}

def say(tag: String, r: Player.Game & String) -> IO(Player.Game):
  (g, s) = r
  do IO<Player.Game>:
    IO.print(tag ++ s)
    IO.pure(Player.Game, g)

def main() -> IO(Unit):
  do IO<Unit>:
    g0 : Player.Game <- say("start   ", spot(ticks(200n, Player.feed(one(Key{55, True{}}), Player.start()))))
    g1 : Player.Game <- say("placed  ", brick(place(g0), 60))
    g2a : Player.Game <- say("walked  ", spot(ticks(40n, Player.feed(one(Key{119, True{}}), g1))))
    g2 : Player.Game <- say("walked  ", brick(g2a, 55))
    g3 : Player.Game <- Save.save_to("build/test.save", g2)
    g4 : Player.Game <- Save.load_from("build/test.save", Player.res512())
    g5 : Player.Game <- say("loaded  ", spot(g4))
    g6 : Player.Game <- say("loaded  ", brick(g5, 55))
    g7 : Player.Game <- Save.load_from("build/no_such_file.save", Player.res512())
    g8 : Player.Game <- say("missing ", spot(g7))
    IO.pure(Unit, Unit{})
