import Base
import ./lib.bend as Lib
import ../src/player.bend as Player
import ../src/world.bend as World
import ../src/save.bend as Save
import ../src/inventory.bend as Inventory
import ../src/torch.bend as Torch

def empty() -> World.World:
  World.W{[0 : U32^20n], World.Meta{Map.new(&2, World.Col), 0, 0, Nil{}, 0, 0}}

def put(w: World.World, +x: U32, +y: U32, +z: U32, +what: U32) -> World.World:
  World.edit(w, x, z, y, True{}, what)

# a torch at (64, 10, 64) on stone
def one() -> World.World:
  put(put(empty(), 64, 9, 64, 2), 64, 10, 64, 9)

def level_fin(r: World.World & U32) -> U32:
  (w, l) = r
  l

def level(w: World.World, +x: U32, +y: U32, +z: U32) -> U32:
  level_fin(World.light(w, x, y, z))

# the torch walled in on its other five sides
def walled() -> World.World:
  put(put(put(put(put(one(), 65, 10, 64, 2), 63, 10, 64, 2), 64, 10, 65, 2), 64, 10, 63, 2), 64, 11, 64, 2)

# the player's world with a torch on the ground at local (70, 72), the
# window gone 80 columns east and back when away
def far_fin(+h: U32, w: World.World, away: Bool) -> World.World & U32:
  match away:
    case False{}:
      (put(w, 70, h, 72, 9), h)
    case True{}:
      (World.follow(80n, True{}, False{}, World.follow(80n, True{}, True{}, put(w, 70, h, 72, 9))), h)

def ground(away: Bool, g: Player.Game) -> World.World & U32:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, sel, res, clock, bag} = g
  far_fin(World.terrain(1048582, 1048584), w, away)

# the level of a cell as the next byte of acc
def more(+acc: U32, r: World.World & U32) -> World.World & U32:
  (w, +l) = r
  (w, (acc * 256 + l : U32))

def ask(r: World.World & U32, +x: U32, +y: U32, +z: U32) -> World.World & U32:
  (w, +acc) = r
  more(acc, World.light(w, x, y, z))

def around_fin(r: World.World & U32) -> U32:
  (w, +h) = r
  level_fin(ask(ask(ask(ask((w, 0), 70, h, 72), 73, (h + 1 : U32), 72), 70, (h + 4 : U32), 70), 66, h, 72))

# the light of four cells around the torch, a byte each
def around(away: Bool) -> U32:
  around_fin(ground(away, Player.start_at(Player.res512())))

def restored(r: Player.Game & String) -> Player.Game:
  (g, s) = r
  Save.parse(String.lines(s), Player.res512())

def loaded(g: Player.Game) -> U32:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, sel, res, clock, bag} = g
  level(w, 64, 10, 64)

def main() -> IO(Unit):
  do IO<Unit>:
    Lib.expect(U32.is_eq(level(one(), 64, 10, 64), 14) && U32.is_eq(level(one(), 65, 10, 64), 13) && U32.is_eq(level(one(), 64, 11, 64), 13),
      "a torch's cell holds 14 and its open neighbours 13")
    Lib.expect(U32.is_eq(level(one(), 70, 10, 64), 8) && U32.is_eq(level(one(), 60, 12, 62), 6) && U32.is_eq(level(one(), 64, 10, 77), 1)
      && U32.is_eq(level(one(), 64, 10, 78), 0), "in the open the light is one less a step, gone 14 steps away")
    Lib.expect(U32.is_eq(level(one(), 64, 9, 64), 0) && U32.is_eq(level(one(), 64, 8, 64), 10), "a solid cell holds none, and the light goes around it")
    Lib.expect(U32.is_eq(level(walled(), 64, 10, 64), 14) && U32.is_eq(level(walled(), 66, 10, 64), 0) && U32.is_eq(level(walled(), 64, 12, 64), 0),
      "a torch walled in lights nothing past its walls")
    Lib.expect(U32.is_eq(level(put(one(), 65, 10, 64, 2), 66, 10, 64), 10) && U32.is_eq(level(put(one(), 65, 10, 64, 2), 65, 10, 64), 0),
      "a block placed in the light darkens what it hides, which the light reaches around it")
    Lib.expect(U32.is_eq(level(World.edit(one(), 64, 64, 10, False{}, 0), 64, 10, 64), 0) && U32.is_eq(level(World.edit(one(), 64, 64, 10, False{}, 0), 66, 10, 64), 0),
      "a torch taken takes its light")
    Lib.expect(U32.is_eq(level(World.edit(one(), 64, 64, 9, False{}, 0), 65, 10, 64), 0), "the break under a torch takes its light")
    Lib.expect(U32.is_eq(level(World.pour(one(), 64, 10, 64, 255), 64, 10, 64), 0) && U32.is_eq(level(World.pour(one(), 64, 10, 64, 255), 65, 10, 64), 0),
      "water on a torch puts out its light")
    Lib.expect(U32.is_eq(level(put(put(one(), 72, 10, 64, 9), 72, 9, 64, 2), 68, 10, 64), 10) && U32.is_eq(level(put(put(one(), 72, 10, 64, 9), 72, 9, 64, 2), 69, 10, 64), 11)
      && U32.is_eq(level(World.edit(put(put(one(), 72, 10, 64, 9), 72, 9, 64, 2), 72, 64, 10, False{}, 0), 69, 10, 64), 9),
      "a cell holds the most any torch brings it, and the other's once one is taken")
    Lib.expect(U32.is_eq(level(put(one(), 78, 20, 64, 2), 70, 10, 64), 8) && U32.is_eq(level(put(one(), 78, 20, 64, 2), 77, 10, 64), 1),
      "an edit past a torch's reach keeps its light")
    Lib.expect(U32.is_eq(around(True{}), around(False{})) && U32.is_eq((around(False{}) / 16777216 : U32), 14),
      "the window gone past a torch and back finds its light as it was")
    Lib.expect(U32.is_eq(loaded(restored(Save.text(Player.G{one(), 64.5, 11.0, 66.5, 0.0, 0.0, 0.0, 0, 0, 0, Player.res512(), 786432, Inventory.empty()}))), 14),
      "a saved torch lights the world it loads into")
    Lib.expect(F32.is_eq(Torch.night((0.0 - 0.2 : F32)), 1.0) && F32.is_eq(Torch.night(0.3), 0.0) && (Torch.night(0.0) > 0.0 : F32) && (Torch.night(0.0) < 1.0 : F32)
      && (Torch.glow(13.0) > Torch.glow(7.0) : F32) && F32.is_eq(Torch.glow(0.0), 0.0),
      "the torches' light is whole at night, gone by day, and brighter the higher the level")
