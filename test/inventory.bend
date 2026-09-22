import Base
import ./lib.bend as Lib
import ../src/inventory.bend as Inventory
import ../src/player.bend as Player
import ../src/world.bend as World
import ../src/save.bend as Save
import ../src/render.bend as Render
import ../src/util.bend as Util

def counts(e: Inventory.Edit, +i: Nat, n: Nat, changed: Bool) -> Bool:
  Inventory.Edit{xs, did} = e
  Nat.is_eq(Inventory.count(xs, i), n) && Bool.not(Bool.xor(did, changed))

def same(a: List<&2, Nat>, b: List<&2, Nat>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case Nil{} Con{h, t}: False{}
    case Con{h, t} Nil{}: False{}
    case Con{h, t} Con{k, u}: Nat.is_eq(h, k) && same(t, u)

def bag(g: Player.Game) -> List<&2, Nat>:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, xs} = g
  xs

def empty_world() -> World.World:
  World.W{[0 : U32^18n], World.Meta{Map.new(&2, World.Col), 1048512, 1048512, Nil{}, 0, 0}}

# A sand cell, followed by a brick, is straight ahead. The selected type
# need not agree with either; a break must read the cell before clearing it.
def fixture(xs: List<&2, Nat>, sel: U32) -> Player.Game:
  Player.G{World.edit(World.edit(empty_world(), 64, 66, 10, True{}, 3), 64, 67, 10, True{}, 6),
    64.5, 10.5, 64.5, 0.0, 0.0, 0.0, 0, 0, 0, 0, sel, Player.res512(), 786432, xs}

def sand() -> List<&2, Nat>: [0n, 0n, 0n, 1n, 0n, 0n, 0n, 0n, 0n]

# the bucket's fixture: `a` units of water in the cell before the sand,
# `units` in the bucket, and the bucket chosen
def wet(+a: U32, units: Nat) -> Player.Game:
  Player.G{World.pour(World.edit(World.edit(empty_world(), 64, 66, 10, True{}, 3), 64, 67, 10, True{}, 6), 64, 10, 65, a),
    64.5, 10.5, 64.5, 0.0, 0.0, 0.0, 0, 0, 0, 0, 8, Player.res512(), 786432, List.set(&2, Nat, Inventory.empty(), 8n, units)}

def pail_of(g: Player.Game) -> Nat:
  Inventory.count(bag(g), 8n)

def snd(r: World.World & U32) -> U32:
  (w, v) = r
  v

def amount(g: Player.Game, +x: U32, +y: U32, +z: U32) -> U32:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, xs} = g
  snd(World.amount_at(w, x, y, z))

def selected(g: Player.Game) -> U32:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, xs} = g
  sel

def press(code: U32, g: Player.Game) -> Player.Game:
  Player.step(Player.feed([Key{code, True{}}], g))

def cell_type(ok: Bool, expected: U32, r: World.World & U32) -> Bool:
  (w, actual) = r
  ok && U32.is_eq(actual, expected)

def cell_solid(+idx: U32, ok: Bool, solid: Bool, kind: U32, r: World.World & Bool) -> Bool:
  (w, actual) = r
  cell_type(ok && Bool.not(Bool.xor(solid, actual)), kind, World.voxel(w, Player.ix_x(idx), Player.ix_y(idx), Player.ix_z(idx)))

def cell(g: Player.Game, xs: List<&2, Nat>, +idx: U32, solid: Bool, kind: U32) -> Bool:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, actual} = g
  cell_solid(idx, same(actual, xs), solid, kind,
    World.wsolid(w, Util.u2f(Player.ix_x(idx)), Util.u2f(Player.ix_y(idx)), Util.u2f(Player.ix_z(idx))))

def edited(r: World.World & List<&2, Nat>) -> Player.Game:
  (w, xs) = r
  Player.G{w, 64.5, 10.5, 64.5, 0.0, 0.0, 0.0, 0, 0, 0, 0, 0, Player.res512(), 786432, xs}

def world_of(g: Player.Game) -> World.World & List<&2, Nat>:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, xs} = g
  (w, xs)

def both() -> Player.Game:
  Player.step(Player.feed([Key{106, True{}}, Key{108, True{}}], fixture(Inventory.empty(), 3)))

def restored(r: Player.Game & String) -> Player.Game:
  (g, s) = r
  Save.parse(String.lines(s), Player.res512())

def types(n: Nat) -> Bool:
  match n:
    case 0n: True{}
    case 1n+ +p:
      +kind = U32.from_nat(p)
      +expected = Inventory.edited(Inventory.edit(Inventory.empty(), p, False{}, True{}))
      w = World.edit(empty_world(), 64, 66, 10, True{}, kind)
      cell(edited(Player.edit_world(True{}, Player.pk_u(64, 10, 66), False{}, 0, (w, Inventory.empty()))),
        expected, Player.pk_u(64, 10, 66), False{}, 0) && types(p)

def still_playing(m: Maybe<Player.Game>) -> Bool:
  match m:
    case None{}: False{}
    case Some{g}: True{}

# Every display value is tested in every slot, including selection bits
# and adjacent occupied slots, before the view receives the two words.
def packing(n: Nat) -> Bool:
  match n:
    case 0n: True{}
    case 1n+ +p:
      +v = Inventory.display(p)
      +xs : List<&2, Nat> = [p, p, p, p, p, p, p, p, p]
      +lo = Inventory.hud_lo(7, xs)
      +hi = Inventory.hud_hi(xs)
      U32.is_eq((lo % 8 : U32), 7)
        && U32.is_eq(Inventory.hud_count(lo, hi, 0), v)
        && U32.is_eq(Inventory.hud_count(lo, hi, 1), v)
        && U32.is_eq(Inventory.hud_count(lo, hi, 2), v)
        && U32.is_eq(Inventory.hud_count(lo, hi, 3), v)
        && U32.is_eq(Inventory.hud_count(lo, hi, 4), v)
        && U32.is_eq(Inventory.hud_count(lo, hi, 5), v)
        && U32.is_eq(Inventory.hud_count(lo, hi, 6), v)
        && U32.is_eq(Inventory.hud_count(lo, hi, 7), v)
        && packing(p)

def main() -> IO(Unit):
  do IO<Unit>:
    Lib.expect(counts(Inventory.edit(Inventory.empty(), 7n, False{}, True{}), 7n, 1n, True{}), "collect into last slot")
    Lib.expect(counts(Inventory.edit(Inventory.empty(), 0n, True{}, False{}), 0n, 0n, False{}), "empty slot rejects placement")
    Lib.expect(counts(Inventory.edit([1n, 2n, 3n], 1n, True{}, False{}), 1n, 1n, True{}), "placement spends one")
    Lib.expect(counts(Inventory.edit([1n, 2n, 3n], 1n, False{}, True{}), 0n, 1n, True{}), "earlier slot is untouched")
    Lib.expect(counts(Inventory.edit([1n, 2n, 3n], 1n, False{}, True{}), 2n, 3n, True{}), "later slot is untouched")
    Lib.expect(counts(Inventory.edit([1n, 2n, 3n], 8n, False{}, True{}), 1n, 2n, False{}), "invalid slot rejects edit")
    Lib.expect(counts(Inventory.edit([1000n], 0n, False{}, True{}), 0n, 1001n, True{}), "counts exceed HUD range")
    Lib.expect(same(bag(Player.start()), Inventory.empty()), "new game starts empty")
    Lib.expect(cell(press(106, fixture(Inventory.empty(), 0)), sand(), Player.pk_u(64, 10, 66), False{}, 0), "break credits actual sand, not selected grass")
    Lib.expect(cell(press(108, fixture(Inventory.empty(), 3)), Inventory.empty(), Player.pk_u(64, 10, 65), False{}, 0), "empty inventory cannot create a block")
    Lib.expect(cell(press(108, fixture(sand(), 3)), Inventory.empty(), Player.pk_u(64, 10, 65), True{}, 3), "placement spends one sand and writes sand")
    Lib.expect(cell(Player.step(press(106, fixture(Inventory.empty(), 0))), sand(), Player.pk_u(64, 10, 67), True{}, 6), "held break does not collect the next block")
    Lib.expect(cell(edited(Player.edit_world(True{}, Player.pk_u(64, 10, 66), False{}, 0,
      world_of(press(106, fixture(Inventory.empty(), 0))))), sand(), Player.pk_u(64, 10, 66), False{}, 0), "breaking the same air twice gives one item")
    Lib.expect(cell(edited(Player.edit_world(True{}, Player.pk_u(64, 10, 66), True{}, 3,
      world_of(fixture(sand(), 3)))), sand(), Player.pk_u(64, 10, 66), True{}, 3), "occupied cell does not spend")
    Lib.expect(cell(edited(Player.edit_world(True{}, 524288, True{}, 3,
      world_of(fixture(sand(), 3)))), sand(), Player.pk_u(64, 10, 65), False{}, 0), "out of bounds placement does not spend")
    Lib.expect(cell(Player.step_edit(64.5, 10.5, 64.5, 0.0, 0.0, 0.0, 0, 2048, 0, 0, 3, Player.res512(), 786432, sand(),
      empty_world(), ((1 + Player.pk_u(64, 10, 64) : U32), (1 + Player.pk_u(64, 10, 66) : U32))),
      sand(), Player.pk_u(64, 10, 64), False{}, 0), "placement on player does not spend")
    Lib.expect(cell(both(), Inventory.empty(), Player.pk_u(64, 10, 65), True{}, 3), "same tick break can fund one placement")
    Lib.expect(cell(both(), Inventory.empty(), Player.pk_u(64, 10, 66), False{}, 0), "same tick funded placement removes source")
    Lib.expect(cell(restored(Save.text(both())), Inventory.empty(), Player.pk_u(64, 10, 65), True{}, 3), "save keeps world and depleted inventory together")
    Lib.expect(same(bag(restored(Save.text(fixture([0n, 1n, 9n, 10n, 99n, 100n, 1001n, 42n, 300n], 6)))),
      [0n, 1n, 9n, 10n, 99n, 100n, 1001n, 42n, 300n]), "save preserves all nine full counts, the bucket's units the ninth")
    Lib.expect(types(8n), "each block type is collected into its own slot")
    Lib.expect(cell(edited(Player.edit_world(True{}, Player.pk_u(64, 10, 66), True{}, 3,
      world_of(press(106, fixture(Inventory.empty(), 0))))), Inventory.empty(), Player.pk_u(64, 10, 66), True{}, 3), "break then replace restores cell type and count")
    Lib.expect(cell(Player.step_edit(64.5, 10.9, 64.5, 0.0, 0.0, 0.0, 0, 2048, 0, 0, 3, Player.res512(), 786432, sand(),
      empty_world(), ((1 + Player.pk_u(64, 10, 64) : U32), (1 + Player.pk_u(64, 10, 66) : U32))),
      sand(), Player.pk_u(64, 10, 64), False{}, 0), "placement between head and feet does not spend")
    Lib.expect(cell(Player.step_edit(64.5, 10.59, 64.5, 0.0, 0.0, 0.0, 0, 2048, 0, 0, 3, Player.res512(), 786432, sand(),
      empty_world(), ((1 + Player.pk_u(64, 8, 64) : U32), (1 + Player.pk_u(64, 10, 66) : U32))),
      sand(), Player.pk_u(64, 8, 64), False{}, 0), "placement at the bottom of the feet does not spend")
    Lib.expect(packing(102n), "all display counts read back in every slot")
    Lib.expect(U32.is_eq(Inventory.hud_pail(Inventory.empty()), 0) && U32.is_eq(Inventory.hud_pail(List.set(&2, Nat, Inventory.empty(), 8n, 254n)), 0)
      && U32.is_eq(Inventory.hud_pail(List.set(&2, Nat, Inventory.empty(), 8n, 255n)), 1) && U32.is_eq(Inventory.hud_pail(List.set(&2, Nat, Inventory.empty(), 8n, 25500n)), 100)
      && U32.is_eq(Render.stat_pail(Render.with_pail(Render.stat_of(999, 255), 100)), 100) && U32.is_eq(Render.stat_fps(Render.with_pail(Render.stat_of(999, 255), 100)), 255)
      && U32.is_eq(Render.stat_ms(Render.with_pail(Render.stat_of(999, 255), 100)), 999),
      "the HUD shows the bucket's full cells, 99+ at a hundred, above the readout's numbers")
    # the bucket, the ninth slot
    Lib.expect(U32.is_eq(selected(press(57, fixture(Inventory.empty(), 0))), 8), "9 chooses the bucket")
    Lib.expect(U32.is_eq(amount(press(106, wet(255, 0n)), 64, 10, 65), 0) && Nat.is_eq(pail_of(press(106, wet(255, 0n))), 255n)
      && cell(press(106, wet(255, 0n)), List.set(&2, Nat, Inventory.empty(), 8n, 255n), Player.pk_u(64, 10, 66), True{}, 3),
      "a click with the bucket takes the water cell before the sand whole, 255 units, and breaks no sand")
    Lib.expect(U32.is_eq(amount(press(106, wet(100, 20n)), 64, 10, 65), 0) && Nat.is_eq(pail_of(press(106, wet(100, 20n))), 120n),
      "a partial cell is worth its amount: a hundred units join the twenty")
    Lib.expect(U32.is_eq(amount(press(108, wet(0, 255n)), 64, 10, 65), 255) && Nat.is_eq(pail_of(press(108, wet(0, 255n))), 0n)
      && cell(press(108, wet(0, 255n)), Inventory.empty(), Player.pk_u(64, 10, 65), False{}, 8),
      "a right click with the bucket pours a full cell into the air before the sand, 255 units out, and places no block")
    Lib.expect(U32.is_eq(amount(press(108, wet(0, 254n)), 64, 10, 65), 0) && Nat.is_eq(pail_of(press(108, wet(0, 254n))), 254n)
      && U32.is_eq(amount(press(108, wet(200, 55n)), 64, 10, 65), 255) && Nat.is_eq(pail_of(press(108, wet(200, 55n))), 0n)
      && U32.is_eq(amount(press(108, wet(200, 54n)), 64, 10, 65), 200) && Nat.is_eq(pail_of(press(108, wet(200, 54n))), 54n),
      "a pour needs what the cell lacks: nothing from 254 into air; 55 fill a cell holding 200, 54 do not")
    Lib.expect(cell(press(106, fixture(sand(), 8)), sand(), Player.pk_u(64, 10, 66), True{}, 3)
      && cell(press(108, fixture(sand(), 8)), sand(), Player.pk_u(64, 10, 65), False{}, 0),
      "the bucket over dry ground breaks nothing and places nothing, and the sand count stays")
    Lib.expect(U32.is_eq(Render.hud_if(False{}, 0, 0, 0, 171, 269, 512, 288), 0), "HUD flag hides counts")
    saved : Player.Game <- Save.save_to("build/inventory-test.save", fixture([0n, 1n, 9n, 10n, 99n, 100n, 1001n, 42n, 300n], 6))
    loaded : Player.Game <- Save.load_from("build/inventory-test.save", Player.res512())
    Lib.expect(cell(loaded, [0n, 1n, 9n, 10n, 99n, 100n, 1001n, 42n, 300n], Player.pk_u(64, 10, 66), True{}, 3), "file roundtrip keeps counts and cell type")
    stale : Player.Game <- Save.save_to("build/inventory-key.save", fixture(Inventory.empty(), 0))
    playing : Maybe<Player.Game> <- Save.tick_to("build/inventory-key.save", [Key{106, True{}}, Key{112, True{}}], fixture(Inventory.empty(), 0))
    Lib.expect(still_playing(playing), "P saves without quitting")
    keyed : Player.Game <- Save.load_from("build/inventory-key.save", Player.res512())
    Lib.expect(cell(keyed, sand(), Player.pk_u(64, 10, 66), False{}, 0), "P saves the same tick's collection")
    previous : Player.Game <- Save.save_to("build/inventory-quit.save", fixture(sand(), 3))
    stopped : Maybe<Player.Game> <- Save.tick_to("build/inventory-quit.save", [Key{108, True{}}, Key{27, True{}}], fixture(sand(), 3))
    Lib.expect(Bool.not(still_playing(stopped)), "Esc saves and quits")
    quit : Player.Game <- Save.load_from("build/inventory-quit.save", Player.res512())
    Lib.expect(cell(quit, Inventory.empty(), Player.pk_u(64, 10, 65), True{}, 3), "Esc saves the same tick's placement")
