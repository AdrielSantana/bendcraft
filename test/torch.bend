import Base
import ./lib.bend as Lib
import ../src/inventory.bend as Inventory
import ../src/player.bend as Player
import ../src/world.bend as World
import ../src/render.bend as Render
import ../src/save.bend as Save
import ../src/torch.bend as Torch
import ../src/util.bend as Util

def empty() -> World.World:
  World.W{[0 : U32^20n], World.Meta{Map.new(&2, World.Col), 0, 0, Nil{}, 0, 0}}

# stone at (64, 9, 65) with a torch on it, and stone two cells behind
def lit() -> World.World:
  World.edit(World.edit(World.edit(empty(), 64, 65, 9, True{}, 2), 64, 65, 10, True{}, 9), 64, 67, 10, True{}, 2)

def kind(r: World.World & U32) -> U32:
  (w, k) = r
  k

def solid(r: World.World & Bool) -> Bool:
  (w, s) = r
  s

def plane_fin(r: Array<U32> & U32) -> U32:
  (ring, word) = r
  word

def plane(w: World.World) -> U32:
  World.W{ring, meta} = w
  plane_fin(Array.get(U32, ring, World.leaf_at(World.col_at(0, 64, 65))))

# what a walk from (x, 10.3, 63.5) along z meets: its code and distance
def walked_fin(r: Array<U32> & Render.Ray) -> U32 & F32:
  (ring, ray) = r
  Render.Ray{code, t, rim, rim_end, tr} = ray
  (code, t)

def walked_in(+x: F32, w: World.World) -> U32 & F32:
  World.W{ring, meta} = w
  walked_fin(Render.walk_from(~False{}, ~False{}, 60n, ring, 0, 0, 0, x, 10.3, 63.5, 0.0, 0.0, 1.0, 0.0))

def walked(+x: F32) -> U32 & F32:
  walked_in(x, lit())

def met(r: U32 & F32) -> Bool:
  (+code, +t) = r
  Util.on(code, 1024) && U32.is_eq((code % 4 : U32), 3) && F32.is_eq(t, 1.9375)

def passed(r: U32 & F32) -> Bool:
  (+code, +t) = r
  Bool.not(Util.on(code, 1024)) && U32.is_eq((code % 4 : U32), 3) && F32.is_eq(t, 3.5)

# the player at (64.5, 10.5, 64.5) looking along z at the sand two cells
# on, stone under the cell before it
def fixture(+sel: U32) -> Player.Game:
  Player.G{World.edit(World.edit(empty(), 64, 66, 10, True{}, 3), 64, 65, 9, True{}, 2),
    64.5, 10.5, 64.5, 0.0, 0.0, 0.0, 0, 0, sel, Player.res512(), 786432, Inventory.empty()}

def press(code: U32, g: Player.Game) -> Player.Game:
  Player.step(Player.feed([Key{code, True{}}], g))

def cell(g: Player.Game, +x: U32, +y: U32, +z: U32) -> U32:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, sel, res, clock, bag} = g
  kind(World.voxel(w, x, y, z))

def spent(g: Player.Game) -> Bool:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, sel, res, clock, +bag} = g
  Bool.not(Nat.is_eq(Inventory.count(bag, 2n), 0n) && Nat.is_eq(Inventory.count(bag, 3n), 0n))

def restored(r: Player.Game & String) -> Player.Game:
  (g, s) = r
  Save.parse(String.lines(s), Player.res512())

def main() -> IO(Unit):
  do IO<Unit>:
    Lib.expect(U32.is_eq(kind(World.voxel(lit(), 64, 10, 65)), 9) && Bool.not(solid(World.wsolid(lit(), 64.5, 10.5, 65.5)))
      && U32.is_eq(plane(lit()), 1024), "a torch stands in its cell, not solid, on the leaf plane")
    Lib.expect(U32.is_eq(kind(World.voxel(World.edit(lit(), 64, 65, 9, False{}, 0), 64, 10, 65)), 0)
      && U32.is_eq(plane(World.edit(lit(), 64, 65, 9, False{}, 0)), 0), "the block under a torch broken takes it")
    Lib.expect(U32.is_eq(kind(World.voxel(World.pour(lit(), 64, 10, 65, 255), 64, 10, 65)), 8)
      && U32.is_eq(kind(World.voxel(World.pour(World.pour(lit(), 64, 10, 65, 255), 64, 10, 65, 0), 64, 10, 65)), 0)
      && U32.is_eq(plane(World.pour(lit(), 64, 10, 65, 255)), 0), "water puts a torch out, and it does not come back when the water goes")
    Lib.expect(met(walked(64.5)), "a walk at the stick meets it at its side, inside the torch's cell, marked a torch's")
    Lib.expect(passed(walked(64.2)) && passed(walked(64.8)), "a walk beside the stick goes through the torch's cell to the stone behind")
    Lib.expect(U32.is_eq(cell(press(108, fixture(9)), 64, 10, 65), 9) && Bool.not(spent(press(108, fixture(9)))),
      "the torch in hand stands one on the block under the cell before the face, for nothing")
    Lib.expect(U32.is_eq(cell(press(108, fixture(9)), 64, 10, 64), 0)
      && U32.is_eq(cell(press(108, Player.G{World.edit(empty(), 64, 66, 10, True{}, 3), 64.5, 10.5, 64.5, 0.0, 0.0, 0.0, 0, 0, 9, Player.res512(), 786432, Inventory.empty()}), 64, 10, 65), 0),
      "no torch stands on air")
    Lib.expect(U32.is_eq(cell(press(106, press(108, fixture(9))), 64, 10, 65), 0) && U32.is_eq(cell(press(106, press(108, fixture(9))), 64, 10, 66), 3)
      && Bool.not(spent(press(106, press(108, fixture(9))))), "a click on the torch takes it, not the sand behind, and gives nothing")
    Lib.expect(U32.is_eq(cell(restored(Save.text(press(108, fixture(9)))), 64, 10, 65), 9), "a torch saves and loads")
    Lib.expect((Torch.look(0, 64.5, 10.55, 65.4375, 0.0, 0.0, 1.0) > Torch.look(0, 64.5, 10.1, 65.4375, 0.0, 0.0, 1.0) : U32)
      && U32.is_ne(Torch.look(0, 64.45, 10.1, 65.4375, 0.0, 0.0, 1.0), Torch.look(0, 64.55, 10.1, 65.4375, 0.0, 0.0, 1.0)),
      "a torch's flame is brighter than the stick's foot, whose two texels differ")
