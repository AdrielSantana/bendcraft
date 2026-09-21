import Base
import ../src/world.bend as World
import ../src/water.bend as Water
import ../src/render.bend as Render
import ../src/player.bend as Player
import ../src/save.bend as Save
import ../src/inventory.bend as Inventory
import ../src/util.bend as Util

def expect(ok: Bool, name: String) -> IO(Unit):
  match ok:
    case True{}: IO.print("ok " ++ name)
    case False{}: IO.die(Unit, 1, "failed " ++ name)

def empty() -> World.World:
  World.W{[0 : U32^17n], Map.new(&2, World.Col), 0, 0}

def ray_ok(+axis: U32, +entry: F32, +depth: F32, +distance: F32, r: Array<U32> & Render.Ray) -> Bool:
  (w, hit) = r
  Render.Ray{code, t, Water.Trace{e, d}} = hit
  U32.is_eq((code % 4 : U32), (axis + 1 : U32)) && F32.is_eq(t, distance)
    && F32.is_eq(e, entry) && F32.is_eq(d, depth)

# One wet voxel, then a solid two cells beyond it. These rays test the
# real DDA in both signs of every axis, outside and inside the water.
def probe_w(~wet: Bool, +axis: U32, +pos: Bool, +under: Bool, +blocked: Bool, w: World.World) -> Bool:
  World.W{ring, m, ox, oz} = w
  +a = Bool.pick(F32, under, 64.0, Bool.pick(F32, pos, 61.0, 67.0))
  +x = Bool.pick(F32, U32.is_eq(axis, 0), a, 64.0)
  +y = Bool.pick(F32, U32.is_eq(axis, 1), (a - 54.0 : F32), 10.0)
  +z = Bool.pick(F32, U32.is_eq(axis, 2), a, 64.0)
  +sign = Bool.pick(F32, pos, 1.0, (0.0 - 1.0 : F32))
  +yes = Bool.pick(F32, wet, 1.0, 0.0)
  ray_ok(axis, Bool.pick(F32, wet && Bool.not(under) && Bool.not(blocked), 2.5, 0.0),
    Bool.pick(F32, blocked, 0.0, (yes * Bool.pick(F32, under, 0.5, 1.0) : F32)),
    Bool.pick(F32, blocked || under, 1.5, 4.5),
    Render.dda(~wet, 60n, 0, x, y, z, sign, sign, sign,
      Bool.pick(F32, U32.is_eq(axis, 0), 0.5, 50000.0),
      Bool.pick(F32, U32.is_eq(axis, 1), 0.5, 50000.0),
      Bool.pick(F32, U32.is_eq(axis, 2), 0.5, 50000.0),
      Bool.pick(F32, U32.is_eq(axis, 0), 1.0, 100000.0),
      Bool.pick(F32, U32.is_eq(axis, 1), 1.0, 100000.0),
      Bool.pick(F32, U32.is_eq(axis, 2), 1.0, 100000.0),
      1.0, 0, 0.0, 0, U32.shln(1, F32.to_nat(y)), Water.Trace{0.0, 0.0},
      Render.column_words(~wet, ring, World.col_at(0, Util.f2u(x), Util.f2u(z)))))

def probe(~wet: Bool, +axis: U32, +pos: Bool, under: Bool, +blocked: Bool) -> Bool:
  +offset = Bool.pick(U32, blocked, 1, 2)
  +a = Bool.pick(U32, pos, Bool.pick(U32, blocked, (64 - offset : U32), (64 + offset : U32)),
                                         Bool.pick(U32, blocked, (64 + offset : U32), (64 - offset : U32)))
  probe_w(~wet, axis, pos, under, blocked,
    World.edit(World.edit(empty(), 64, 64, 10, True{}, 8),
      Bool.pick(U32, U32.is_eq(axis, 0), a, 64),
      Bool.pick(U32, U32.is_eq(axis, 2), a, 64),
      Bool.pick(U32, U32.is_eq(axis, 1), (a - 54 : U32), 10), True{}, 2))

def axes(n: Nat, +i: U32) -> IO(Unit):
  match n:
    case 0n: IO.pure(Unit, Unit{})
    case 1n+k:
      do IO<Unit>:
        expect(probe(~True{}, i, True{}, False{}, False{}) && probe(~True{}, i, False{}, False{}, False{}), "wet DDA both signs, axis " ++ U32.show(i))
        expect(probe(~True{}, i, True{}, True{}, False{}) && probe(~True{}, i, False{}, True{}, False{}), "submerged DDA, axis " ++ U32.show(i))
        expect(probe(~True{}, i, True{}, False{}, True{}) && probe(~True{}, i, False{}, False{}, True{}), "water behind solid is hidden, axis " ++ U32.show(i))
        expect(probe(~False{}, i, True{}, False{}, False{}) && probe(~False{}, i, False{}, False{}, False{}), "water flag removes wet intervals, axis " ++ U32.show(i))
        axes(k, (i + 1 : U32))

def solid(r: World.World & Bool) -> Bool:
  (w, b) = r
  b

def material(r: World.World & U32) -> U32:
  (w, what) = r
  what

def col(r: Array<U32> & World.Col) -> World.Col:
  (w, c) = r
  c

def same_masks(c: World.Col, +solid: U32, +water: U32) -> Bool:
  World.Col{m, a, b, cc, d, w} = c
  U32.is_eq(m, solid) && U32.is_eq(w, water)

def saved_col(g: Player.Game) -> World.Col:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag} = g
  World.W{ring, m, ox, oz} = w
  col(World.get_col(ring, World.col_at(0, 64, 64)))

def restored(r: Player.Game & String) -> World.Col:
  (g, text) = r
  saved_col(Save.parse(String.lines(text), Player.res512()))

def fixture(w: World.World) -> Player.Game:
  Player.G{w, 64.5, 14.0, 64.5, 0.0, 0.0, 0.0, 0, 0, 0, 0, 0, Player.res512(), 154747, Inventory.empty()}

def placed(r: World.World & List<&2, Nat>) -> Bool:
  (w, bag) = r
  World.W{ring, m, ox, oz} = w
  (Nat.is_eq(Inventory.count(bag, 6n), 0n)) && same_masks(col(World.get_col(ring, World.col_at(0, 64, 64))), 1024, 0)

def picked(r: World.World & (U32 & U32)) -> Bool:
  (w, pair) = r
  (prev, hit) = pair
  U32.is_eq(prev, (1 + 64 * 4096 + 10 * 128 + 64 : U32))
    && U32.is_eq(hit, (1 + 64 * 4096 + 9 * 128 + 64 : U32))

def shadow(r: Array<U32> & Bool) -> Bool:
  (w, hit) = r
  hit

# A horizontal strip lets a real ray either stay wet until the DDA limit
# or leave water after half a block and meet a distant wall in air.
def pool(n: Nat, w: World.World, +x: U32, +wet_until: U32) -> World.World:
  match n:
    case 0n: w
    case 1n+k:
      pool(k, World.edit(w, x, 64, 10, (x < wet_until : U32), 8), (x + 1 : U32), wet_until)

def pixel(r: Array<U32> & U32) -> U32:
  (w, c) = r
  c

def fog_ray_w(+fl: U32, w: World.World) -> U32:
  World.W{ring, m, ox, oz} = w
  pixel(Render.run_water(Util.on(fl, 2097152), ring, 0, 1.5, 10.5, 64.5,
    1.0, 0.0, 0.0, Render.rgb(100, 140, 180), fl, 0.48, 0.8, 0.36))

def fog_ray(fl: U32, wet_until: U32, wall: U32) -> U32:
  fog_ray_w(fl, World.edit(pool(128n, empty(), 0, wet_until), wall, 64, 10, True{}, 2))

def main() -> IO(Unit):
  do IO<Unit>:
    axes(3n, 0)
    expect(U32.is_eq(fog_ray(2097160, 2, 40), Render.rgb(100, 140, 180)), "distance fog survives starting in water and exiting to air")
    expect(U32.is_eq(fog_ray_w(6291464, World.edit(pool(88n, empty(), 40, 128), 56, 64, 10, True{}, 2)),
      Render.rgb(100, 140, 180)), "distant water stays hidden by foreground air fog")
    expect(U32.is_eq(fog_ray(6291464, 128, 40), Water.colour(0.8))
      && U32.is_eq(fog_ray(6291464, 128, 100), Water.colour(0.8)), "underwater wall and ray limit converge to the same fog colour")
    expect(U32.is_ne(fog_ray(2097160, 128, 40), Water.colour(0.8)), "water fog has its own flag")
    expect(U32.is_eq(fog_ray(4194312, 128, 40), Render.rgb(100, 140, 180)), "water off keeps ordinary fog")
    expect(U32.is_eq(Water.fog(True{}, 123, 456, 456, 0.0, 0.0), 123)
      && U32.is_eq(Water.fog(True{}, 123, 456, 456, 0.0, 24.0), 456)
      && U32.is_eq(Water.fog(True{}, 123, 456, 456, 0.0, 80.0), 456)
      && U32.is_eq(Water.fog(False{}, 123, 456, 456, 0.0, 80.0), 123), "wet fog bounds and disable")
    expect(picked(Player.waim(World.edit(World.edit(empty(), 64, 64, 9, True{}, 2), 64, 64, 10, True{}, 8),
      64.5, 12.5, 64.5, 0.0, (0.0 - 1.0 : F32), 0.0)), "picking traverses water and finds the bottom")
    expect(Bool.not(shadow(Render.run_shadow(World.put_col([0 : U32^17n], World.col_at(0, 64, 64), World.Col{0, 0, 0, 0, 0, 1024}),
      0, 64.5, 12.5, 64.5, 0.0, (0.0 - 1.0 : F32), 0.0))), "water casts no solid shadow")
    expect(U32.is_eq(material(World.voxel(World.shift_xn(World.shift_xp(World.edit(empty(), 0, 64, 10, True{}, 8))), 0, 10, 64)), 8), "ring reload keeps edited water")
    expect(Bool.not(solid(World.wsolid(World.edit(empty(), 64, 64, 10, True{}, 8), 64.0, 10.0, 64.0))), "water is not a collision")
    expect(U32.is_eq(material(World.voxel(World.edit(empty(), 64, 64, 10, True{}, 8), 64, 10, 64)), 8), "water material reads back")
    expect(placed(Player.edit_world(True{}, (64 * 4096 + 10 * 128 + 64 : U32), True{}, 6,
      (World.edit(empty(), 64, 64, 10, True{}, 8), [0n, 0n, 0n, 0n, 0n, 0n, 1n, 0n]))), "placing spends one brick and displaces water")
    expect(same_masks(restored(Save.text(fixture(World.edit(empty(), 64, 64, 10, True{}, 8)))), 0, 1024), "save restores the water mask")
    expect(same_masks(restored(Save.text(fixture(World.edit(World.edit(empty(), 64, 64, 10, True{}, 8), 64, 64, 10, True{}, 6)))), 1024, 0), "save preserves displacement")
    expect(same_masks(col(World.get_col(World.put_col([0 : U32^17n], World.col_at(0, 64, 64), World.Col{256, 1, 2, 3, 4, 3584}), World.col_at(0, 64, 64))), 256, 3584), "column storage keeps both masks")
    expect(U32.is_eq(Save.water_of([], "0,0", 0), World.flood(World.terrain(0, 0), 0)), "old saves restore natural water")
    expect(U32.is_eq(Save.water_of(["0"], "0,0", 0), 0), "explicit dry edits stay dry")
    expect(U32.is_eq(Save.water_of(["1024"], "0,0", 1024), 0), "loaded solids displace overlapping water")
