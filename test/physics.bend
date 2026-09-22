import Base
import ../src/util.bend as Util
import ../src/world.bend as World
import ../src/render.bend as Render
import ../src/player.bend as Player

# The game without a window: synthetic events through `feed` and `step`,
# the state printed after each. `bend test/physics.bend` prints the lines;
# compare them with the ones in the README.

def ticks(n: Nat, g: Player.Game) -> Player.Game:
  match n:
    case 0n:
      g
    case 1n+m:
      ticks(m, Player.step(g))

def show_w(+px: F32, +py: F32, +pz: F32, +yaw: F32, +pit: F32, +vy: F32, +held: U32, +edge: U32, +mx: U32, +my: U32, +sel: U32, res: U32, clock: U32, bag: List<&2, Nat>,
           w: World.World) -> Player.Game & String:
  World.W{ring, m, +ox, +oz, q, np, made, gone} = w
  (Player.G{World.W{ring, m, ox, oz, q, np, made, gone}, px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag},
   "p=(" ++ F32.show(px) ++ ", " ++ F32.show(py) ++ ", " ++ F32.show(pz) ++ ") yaw=" ++ F32.show(yaw) ++ " pit=" ++ F32.show(pit) ++ " vy=" ++ F32.show(vy) ++ " held=" ++ U32.show(held) ++ " edge=" ++ U32.show(edge) ++ " sel=" ++ U32.show(sel) ++ " corner=" ++ U32.show(ox) ++ "," ++ U32.show(oz))

def show(g: Player.Game) -> Player.Game & String:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag} = g
  show_w(px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag, w)

def wcol_fin(m: Map<&2, World.Col>, ox: U32, oz: U32, q: List<&2, U32>, np: U32, made: U32, gone: U32, r: Array<U32> & U32) -> World.World & U32:
  (ring, c) = r
  (World.W{ring, m, ox, oz, q, np, made, gone}, c)

def wcol(w: World.World, +lx: U32, +lz: U32) -> World.World & U32:
  World.W{ring, m, +ox, +oz, q, np, made, gone} = w
  wcol_fin(m, ox, oz, q, np, made, gone, Array.get(U32, ring, World.col_at((ox * 128 + oz : U32), lx, lz)))

def target_typ(px: F32, py: F32, pz: F32, yaw: F32, pit: F32, vy: F32, held: U32, edge: U32, mx: U32, my: U32, sel: U32, res: U32, clock: U32, bag: List<&2, Nat>,
               +prev: U32, +got: U32, +h: U32, +c: U32, r: World.World & U32) -> Player.Game & String:
  (w, t) = r
  (Player.G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag},
   "hit=" ++ U32.show(got) ++ " prev=" ++ U32.show(prev) ++ " block=(" ++ U32.show(Player.ix_x(h)) ++ "," ++ U32.show(Player.ix_y(h)) ++ "," ++ U32.show(Player.ix_z(h)) ++ ") column=" ++ U32.show(c) ++ " type=" ++ U32.show(t))

def target_col(px: F32, py: F32, pz: F32, yaw: F32, pit: F32, vy: F32, held: U32, edge: U32, mx: U32, my: U32, sel: U32, res: U32, clock: U32, bag: List<&2, Nat>,
               +prev: U32, +got: U32, +h: U32, r: World.World & U32) -> Player.Game & String:
  (w, c) = r
  target_typ(px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag, prev, got, h, c,
             World.voxel(w, Player.ix_x(h), Player.ix_y(h), Player.ix_z(h)))

def target_ph(px: F32, py: F32, pz: F32, yaw: F32, pit: F32, vy: F32, held: U32, edge: U32, mx: U32, my: U32, sel: U32, res: U32, clock: U32, bag: List<&2, Nat>,
              w: World.World, ph: U32 & U32) -> Player.Game & String:
  (+prev, +got) = ph
  +h = (got - 1 : U32)
  target_col(px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag, prev, got, h, wcol(w, Player.ix_x(h), Player.ix_z(h)))

def target_hit(px: F32, py: F32, pz: F32, yaw: F32, pit: F32, vy: F32, held: U32, edge: U32, mx: U32, my: U32, sel: U32, res: U32, clock: U32, bag: List<&2, Nat>,
               r: World.World & (U32 & U32)) -> Player.Game & String:
  (w, ph) = r
  target_ph(px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag, w, ph)

def target(g: Player.Game) -> Player.Game & String:
  Player.G{w, +px, +py, +pz, +yaw, +pit, vy, held, edge, mx, my, sel, res, clock, bag} = g
  target_hit(px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag,
             Player.waim(w, px, py, pz, Render.look_x(yaw, pit), Render.look_y(pit), Render.look_z(yaw, pit)))

def say(tag: String, r: Player.Game & String) -> IO(Player.Game):
  (g, s) = r
  do IO<Player.Game>:
    IO.print(tag ++ s)
    IO.pure(Player.Game, g)

def one(e: Event) -> List<Event>:
  Con{e, Nil{}}

# an edit survives its column leaving the ring and coming back: the bit
# and the type
def persist_typ(+c: U32, r: World.World & U32) -> String:
  (w, t) = r
  "column 64,64 after 130 shifts away and back = " ++ U32.show(c) ++ " (bit 20 = 1048576 must be set), type at 20 = " ++ U32.show(t) ++ " (must be 6, brick)"

def persist_fin(r: World.World & U32) -> String:
  (w, c) = r
  persist_typ(c, World.voxel(w, 64, 20, 64))

def persist(g: Player.Game) -> String:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag} = g
  persist_fin(wcol(World.follow_z(130n, False{}, World.follow_z(130n, True{}, World.edit(w, 64, 64, 20, True{}, 6))), 64, 64))

# Keep the historical physics scenario's one sand placement funded. The
# inventory tests exercise the real empty start and rejected placements.
def supplied(g: Player.Game) -> Player.Game:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag} = g
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, [0n, 0n, 0n, 1n, 0n, 0n, 0n, 0n]}

# the player set down in the lake west of the spawn (local 45.5, 66.5 at
# the start's corner: full water at heights 8 to 11, the surface at 12),
# the eye half a block over the surface, facing +z
def dunk(g: Player.Game) -> Player.Game:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag} = g
  Player.G{w, 45.5, 12.5, 66.5, 0.0, 0.0, 0.0, held, edge, mx, my, sel, res, clock, bag}

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("terrain at the corner: " ++ U32.show(World.terrain(1048512, 1048512)) ++ " " ++ U32.show(World.terrain(1048576, 1048576)) ++ " " ++ U32.show(World.terrain(1048600, 1048530)))
    g0 : Player.Game <- say("start      ", show(supplied(Player.start())))
    g1 : Player.Game <- say("fall       ", show(ticks(200n, g0)))
    g2 : Player.Game <- say("jump 1     ", show(Player.step(Player.feed(one(Key{32, True{}}), g1))))
    g3 : Player.Game <- say("jump 17    ", show(ticks(16n, Player.feed(one(Key{32, False{}}), g2))))
    g4 : Player.Game <- say("landed     ", show(ticks(60n, g3)))
    g5 : Player.Game <- say("drag       ", show(Player.step(Player.feed(Con{Mouse{256, 256, 0, True{}}, Con{Move{356, 256}, Con{Move{356, 306}, one(Mouse{356, 306, 0, False{}})}}}, g4))))
    g6 : Player.Game <- say("aim        ", target(g5))
    g7 : Player.Game <- say("click      ", show(Player.step(Player.feed(Con{Mouse{256, 256, 0, True{}}, one(Mouse{256, 256, 0, False{}})}, g6))))
    g8 : Player.Game <- say("aim        ", target(g7))
    g9 : Player.Game <- say("key 4      ", show(Player.step(Player.feed(Con{Key{52, True{}}, one(Key{52, False{}})}, g8))))
    g9b : Player.Game <- say("right      ", show(Player.step(Player.feed(one(Mouse{256, 256, 1, True{}}), g9))))
    g10 : Player.Game <- say("aim        ", target(g9b))
    g11 : Player.Game <- say("walk W 30  ", show(ticks(30n, Player.feed(one(Key{119, True{}}), g10))))
    g12 : Player.Game <- say("walk W 300 ", show(ticks(300n, g11)))
    g13 : Player.Game <- say("walk S 600 ", show(ticks(600n, Player.feed(Con{Key{119, False{}}, one(Key{115, True{}})}, g12))))
    IO.print(persist(g13))
    s0 : Player.Game <- say("dunk       ", show(dunk(Player.start())))
    s1 : Player.Game <- say("sink 60    ", show(ticks(60n, s0)))
    s2 : Player.Game <- say("on the bed ", show(ticks(340n, s1)))
    s3 : Player.Game <- say("swim up 60 ", show(ticks(60n, Player.feed(one(Key{32, True{}}), s2))))
    s4 : Player.Game <- say("bob 200    ", show(ticks(140n, s3)))
    s5 : Player.Game <- say("stroke 60  ", show(ticks(60n, Player.feed(Con{Key{32, False{}}, one(Key{119, True{}})}, s4))))
    s6 : Player.Game <- say("back 300   ", show(ticks(300n, Player.feed(Con{Key{119, False{}}, one(Key{115, True{}})}, s5))))
    IO.pure(Unit, Unit{})
