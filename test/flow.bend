import Base
import ./lib.bend as Lib
import ../src/world.bend as World
import ../src/flow.bend as Flow
import ../src/player.bend as Player
import ../src/inventory.bend as Inventory
import ../src/util.bend as Util

# The flow without a window: cells of a void world (no terrain) built
# with edits, ticks run by hand, amounts read back. The world is linear,
# so a test asks it a list of questions in one pass (`query`) and reads
# the answers as a list. `bend test/flow.bend`.

def empty() -> World.World:
  World.W{[0 : U32^19n], World.Meta{Map.new(&2, World.Col), 0, 0, Nil{}, 0, 0}}

# ---------- building ----------

# a stone or water placed by the player's edit, which marks
def stone(w: World.World, +lx: U32, +y: U32, +lz: U32) -> World.World:
  World.edit(w, lx, lz, y, True{}, 2)

def water(w: World.World, +lx: U32, +y: U32, +lz: U32) -> World.World:
  World.edit(w, lx, lz, y, True{}, 8)

# n ticks from tick number `at`, with a budget
def ticks(n: Nat, +at: U32, +budget: Nat, w: World.World) -> World.World:
  match n:
    case 0n:
      w
    case 1n+k:
      ticks(k, (at + 1 : U32), budget, Flow.tick(w, Util.on(at, 1), budget))

# a floor of stone at y = 9 over [x, x + nx) x [z, z + nz)
def floor_z(n: Nat, w: World.World, +x: U32, +z: U32) -> World.World:
  match n:
    case 0n:
      w
    case 1n+k:
      floor_z(k, stone(w, x, 9, z), x, (z + 1 : U32))

def floor(n: Nat, w: World.World, +x: U32, +z: U32, +nz: Nat) -> World.World:
  match n:
    case 0n:
      w
    case 1n+k:
      floor(k, floor_z(nz, w, x, z), (x + 1 : U32), z, nz)

# a wall of stone from y = 10 to 15, n columns along z at x, or along x at z
def wall_y(n: Nat, w: World.World, +x: U32, +y: U32, +z: U32) -> World.World:
  match n:
    case 0n:
      w
    case 1n+k:
      wall_y(k, stone(w, x, y, z), x, (y + 1 : U32), z)

def wall_z(n: Nat, w: World.World, +x: U32, +z: U32) -> World.World:
  match n:
    case 0n:
      w
    case 1n+k:
      wall_z(k, wall_y(6n, w, x, 10, z), x, (z + 1 : U32))

def wall_x(n: Nat, w: World.World, +x: U32, +z: U32) -> World.World:
  match n:
    case 0n:
      w
    case 1n+k:
      wall_x(k, wall_y(6n, w, x, 10, z), (x + 1 : U32), z)

# a tick with every column's marks spent: the edits that built a world
# queued its columns, and a tick of dry ones drops them all
def settled(w: World.World) -> World.World:
  Flow.tick(w, False{}, 100000n)

# a basin: a floor of side n at (x, z) and walls around it, open above
def basin(+x: U32, +z: U32, +n: U32, +side: Nat) -> World.World:
  settled(wall_x(side, wall_x(side, wall_z(side, wall_z(side,
    floor(side, empty(), x, z, side),
    (x - 1 : U32), z), (x + n : U32), z), x, (z - 1 : U32)), x, (z + n : U32)))

# a shaft: a 1 x 1 basin, water at 15
def shaft() -> World.World:
  water(basin(64, 64, 1, 1n), 64, 15, 64)

def pool() -> World.World:
  water(basin(60, 60, 5, 5n), 62, 10, 62)

# three full cells in the shaft, 10 to 12
def three() -> World.World:
  water(water(water(basin(64, 64, 1, 1n), 64, 10, 64), 64, 11, 64), 64, 12, 64)

# ---------- asking ----------

# a question: the amount at a cell (At), the sum or the most over a box
# (Sum, Most: from (x, y, z), n cells a side, one less as a Nat), the
# marks of a column (Marks), the queue's length (Queued), the count of
# partial cells (Partials), the units that dried (Gone)
type Ask is Data:
  At{x: U32, y: U32, z: U32}
  Sum{x: U32, y: U32, z: U32, nx: Nat, ny: Nat, nz: Nat}
  Most{x: U32, y: U32, z: U32, nx: Nat, ny: Nat, nz: Nat}
  Marks{x: U32, z: U32}
  Queued{}
  Partials{}
  Gone{}

def combine(+summing: Bool, +acc: U32, +v: U32) -> U32:
  Bool.pick(U32, summing, (acc + v : U32), U32.max(acc, v))

# the cells of a row along z, one read ahead of the recursion
def row(n: Nat, +summing: Bool, +x: U32, +y: U32, +z: U32, +acc: U32, r: World.World & U32) -> World.World & U32:
  match n:
    case 0n:
      (w, v) = r
      (w, combine(summing, acc, v))
    case 1n+k:
      (w, v) = r
      row(k, summing, x, y, (z + 1 : U32), combine(summing, acc, v), World.amount_at(w, x, y, (z + 1 : U32)))

def rows(n: Nat, +summing: Bool, +x: U32, +y: U32, +z: U32, +nz: Nat, +acc: U32, r: World.World & U32) -> World.World & U32:
  match n:
    case 0n:
      (w, v) = r
      (w, combine(summing, acc, v))
    case 1n+k:
      (w, v) = r
      rows(k, summing, (x + 1 : U32), y, z, nz, combine(summing, acc, v),
        row(nz, summing, (x + 1 : U32), y, z, 0, World.amount_at(w, (x + 1 : U32), y, z)))

def layers(n: Nat, +summing: Bool, +x: U32, +y: U32, +z: U32, +nx: Nat, +nz: Nat, +acc: U32, r: World.World & U32) -> World.World & U32:
  match n:
    case 0n:
      (w, v) = r
      (w, combine(summing, acc, v))
    case 1n+k:
      (w, v) = r
      layers(k, summing, x, (y + 1 : U32), z, nx, nz, combine(summing, acc, v),
        rows(nx, summing, x, (y + 1 : U32), z, nz, 0, row(nz, summing, x, (y + 1 : U32), z, 0, World.amount_at(w, x, (y + 1 : U32), z))))

def box(w: World.World, +summing: Bool, +x: U32, +y: U32, +z: U32, +nx: Nat, +ny: Nat, +nz: Nat) -> World.World & U32:
  layers(ny, summing, x, y, z, nx, nz, 0, rows(nx, summing, x, y, z, nz, 0, row(nz, summing, x, y, z, 0, World.amount_at(w, x, y, z))))

def queued(w: World.World) -> World.World & U32:
  World.W{ring, meta} = w
  World.Meta{m, ox, oz, q, np, gone} = meta
  +n = U32.from_nat(List.length(&2, U32, q))
  (World.W{ring, World.Meta{m, ox, oz, Nil{}, np, gone}}, n)

def partials(w: World.World) -> World.World & U32:
  World.W{ring, +meta} = w
  World.Meta{m, ox, oz, q, np, gone} = meta
  (World.W{ring, meta}, np)

def gone(w: World.World) -> World.World & U32:
  World.W{ring, +meta} = w
  World.Meta{m, ox, oz, q, np, gone} = meta
  (World.W{ring, meta}, gone)

def measure(w: World.World, q: Ask) -> World.World & U32:
  match q:
    case At{x, y, z}:
      World.amount_at(w, x, y, z)
    case Sum{x, y, z, nx, ny, nz}:
      box(w, True{}, x, y, z, nx, ny, nz)
    case Most{x, y, z, nx, ny, nz}:
      box(w, False{}, x, y, z, nx, ny, nz)
    case Marks{x, z}:
      World.word_at(w, x, z, 14)
    case Queued{}:
      queued(w)
    case Partials{}:
      partials(w)
    case Gone{}:
      gone(w)

# the answers in the questions' order, one measure ahead
def answers(qs: List<&2, Ask>, acc: List<&2, U32>, r: World.World & U32) -> List<&2, U32>:
  match qs:
    case Nil{}:
      (w, v) = r
      List.reverse(&2, U32, v <> acc)
    case Con{q, rest}:
      (w, v) = r
      answers(rest, v <> acc, measure(w, q))

def query(w: World.World, qs: List<&2, Ask>) -> List<&2, U32>:
  match qs:
    case Nil{}:
      Nil{}
    case Con{q, rest}:
      answers(rest, Nil{}, measure(w, q))

def same(xs: List<&2, U32>, ys: List<&2, U32>) -> Bool:
  match xs ys:
    case Nil{} Nil{}:
      True{}
    case Nil{} Con{h, t}:
      False{}
    case Con{h, t} Nil{}:
      False{}
    case Con{h, t} Con{k, u}:
      U32.is_eq(h, k) && same(t, u)

def nth(xs: List<&2, U32>, i: Nat) -> U32:
  match xs:
    case Nil{}:
      4294967295
    case Con{h, t}:
      match i:
        case 0n:
          h
        case 1n+j:
          nth(t, j)

def show_all(xs: List<&2, U32>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{h, t}:
      " " ++ U32.show(h) ++ show_all(t)

# the bucket used at a cell with `units` in it: the world after, and the
# units it holds then; `told` puts those units before the world's answers
def pailed(r: World.World & List<&2, Nat>) -> World.World & U32:
  (w, bag) = r
  (w, U32.from_nat(Inventory.count(bag, 8n)))

def bucket(put: Bool, +x: U32, +y: U32, +z: U32, units: Nat, w: World.World) -> World.World & U32:
  pailed(Player.pail(True{}, put, Player.pk_u(x, y, z), (w, List.set(&2, Nat, Inventory.empty(), 8n, units))))

def told(qs: List<&2, Ask>, r: World.World & U32) -> List<&2, U32>:
  (w, u) = r
  u <> query(w, qs)

def fst(r: World.World & U32) -> World.World:
  (w, u) = r
  w

# a whole basin of side 5 at (60, 60): its floor's layer, all its layers
def over(+x: U32, +y: U32, +z: U32) -> Ask:
  Sum{x, y, z, 4n, 21n, 4n}

def layer(+x: U32, +y: U32, +z: U32) -> Ask:
  Most{x, y, z, 4n, 0n, 4n}

# ---------- the arithmetic ----------

def due_ok() -> Bool:
  U32.is_eq(Flow.due(0, 255), 0) && U32.is_eq(Flow.due(0, 256), 1) && U32.is_eq(Flow.due(255, 1), 1)
    && U32.is_eq(Flow.due(1048575, 1), 1) && U32.is_eq(Flow.due(0, 10000), 2)

# the slot of a local column decodes at the game's origin and after shifts
def decode_ok(+ox: U32, +oz: U32, +lx: U32, +lz: U32) -> Bool:
  +slot = World.col_at((ox * 128 + oz : U32), lx, lz)
  +lz2 = Flow.lz_of(slot, oz)
  U32.is_eq(lz2, lz) && U32.is_eq(Flow.lx_of(slot, ox, oz, lz2), lx)

# the world of a game advanced by ms from a clock at zero
def world_of(g: Player.Game) -> World.World:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag} = g
  w

def advanced(+ms: U32, w: World.World) -> World.World:
  world_of(Player.advance(Player.G{w, 64.5, 30.0, 64.5, 0.0, 0.0, 0.0, 0, 0, 0, 0, 0, Player.res512(), 0, Nil{}}, ms))

def main() -> IO(Unit):
  do IO<Unit>:
    Lib.expect(due_ok(), "a tick every 256 ms of the clock, across its wrap, at most two a frame")
    Lib.expect(decode_ok(1048512, 1048512, 5, 100) && decode_ok(1048512, 1048512, 0, 0) && decode_ok(1048512, 1048512, 127, 127)
      && decode_ok(1048530, 1048499, 64, 64) && decode_ok(0, 0, 3, 4) && decode_ok(1048512, 1048600, 127, 40),
      "a queued slot decodes to its local column at any origin")
    Lib.expect(U32.is_eq(World.fits(255, 0), 255) && U32.is_eq(World.fits(255, 100), 155) && U32.is_eq(World.fits(3, 5), 3)
      && U32.is_eq(World.fits(255, 255), 0) && U32.is_eq(World.fits(255, 256), 0),
      "a cell takes what fits, nothing into a solid")
    Lib.expect(U32.is_eq(Flow.side_take(255, 0), 127) && U32.is_eq(Flow.side_take(255, 1), 127) && U32.is_eq(Flow.side_take(2, 0), 1) && U32.is_eq(Flow.side_take(1, 0), 0)
      && U32.is_eq(Flow.side_take(5, 4), 0) && U32.is_eq(Flow.side_take(4, 5), 0) && U32.is_eq(Flow.side_take(255, 256), 0),
      "a side takes half the difference, floored, only from more")
    # marks
    Lib.expect(same(query(water(empty(), 64, 15, 64),
        Marks{64, 64} <> Marks{65, 64} <> Marks{63, 64} <> Marks{64, 65} <> Marks{64, 63} <> Queued{} <> Nil{}),
      98304 <> 32768 <> 32768 <> 32768 <> 32768 <> 5 <> Nil{}),
      "an edit marks the cell, the one above and the four sides, queuing five columns once")
    Lib.expect(same(query(water(water(empty(), 64, 15, 64), 64, 15, 64), Queued{} <> Nil{}), 5 <> Nil{}),
      "a second mark on a marked column does not queue it again")
    Lib.expect(same(query(water(empty(), 0, 15, 0), Queued{} <> Nil{}), 3 <> Nil{}),
      "at the ring's corner, two sides are outside and not marked")
    # the still lake: an unmarked world does not change
    Lib.expect(same(query(ticks(3n, 0, Flow.budget(), World.pour(empty(), 64, 12, 64, 255)), At{64, 12, 64} <> At{64, 11, 64} <> Queued{} <> Nil{}),
      255 <> 0 <> 0 <> Nil{}), "water nobody marked stays, over the void")
    # a column drains
    Lib.expect(same(query(ticks(1n, 0, Flow.budget(), shaft()), At{64, 15, 64} <> At{64, 14, 64} <> Marks{64, 64} <> Queued{} <> Nil{}),
      0 <> 255 <> 114688 <> 5 <> Nil{}),
      "a full cell over air falls a cell a tick, and the cell it left, the one above and the one that gained are marked")
    Lib.expect(same(query(ticks(5n, 0, Flow.budget(), shaft()), At{64, 10, 64} <> Sum{64, 10, 64, 0n, 21n, 0n} <> Nil{}), 255 <> 255 <> Nil{}),
      "five ticks on, it rests on the floor, all 255 units")
    Lib.expect(same(query(ticks(8n, 0, Flow.budget(), shaft()), At{64, 10, 64} <> Queued{} <> Nil{}), 255 <> 0 <> Nil{}),
      "and there it stays, off the queue")
    # a pool spreads and settles
    Lib.expect(same(query(ticks(1n, 0, Flow.budget(), pool()),
        over(60, 10, 60) <> At{62, 10, 62} <> At{63, 10, 62} <> At{61, 10, 62} <> At{62, 10, 63} <> At{62, 10, 61} <> Nil{}),
      255 <> 16 <> 127 <> 64 <> 32 <> 16 <> Nil{}),
      "a full cell on a floor spreads to its sides, in the tick's order, halving what is left")
    Lib.expect(same(query(ticks(1n, 1, Flow.budget(), pool()), At{62, 10, 61} <> At{62, 10, 63} <> At{61, 10, 62} <> At{63, 10, 62} <> Nil{}),
      127 <> 64 <> 32 <> 16 <> Nil{}), "an odd tick takes the sides in the reverse order")
    Lib.expect(same(query(ticks(40n, 0, Flow.budget(), pool()), over(60, 10, 60) <> Gone{} <> Queued{} <> Nil{}), 249 <> 6 <> 0 <> Nil{})
      && (nth(query(ticks(40n, 0, Flow.budget(), pool()), layer(60, 10, 60) <> Nil{}), 0n) < 14 : U32),
      "forty ticks on, the units lie flat over the basin, no cell over thirteen (a level lake is 10 a cell), the queue empty; six of the 255 dried at the spread's thin edge")
    Lib.expect(same(query(ticks(41n, 0, Flow.budget(), pool()), over(60, 10, 60) <> Nil{}), 249 <> Nil{}), "a tick more changes nothing")
    Lib.expect(same(query(ticks(60n, 0, Flow.budget(), water(water(pool(), 62, 11, 62), 62, 12, 62)),
        over(60, 10, 60) <> layer(60, 11, 60) <> Gone{} <> Nil{}), 764 <> 0 <> 1 <> Nil{}),
      "three cells of water over the floor spread to one layer, a unit dried")
    # a wall holds
    Lib.expect(same(query(ticks(40n, 0, Flow.budget(), water(wall_z(5n, basin(60, 60, 5, 5n), 62, 60), 61, 10, 62)),
        over(60, 10, 60) <> Sum{63, 10, 60, 1n, 21n, 4n} <> Nil{}), 255 <> 0 <> Nil{}),
      "a wall across the basin keeps the water on its side")
    # the ring's edge holds: a floor at the corner, walls inward only
    Lib.expect(same(query(ticks(40n, 0, Flow.budget(), water(settled(wall_x(3n, wall_z(3n, floor(3n, empty(), 0, 0, 3n), 3, 0), 0, 3)), 0, 10, 0)),
        Sum{0, 10, 0, 2n, 21n, 2n} <> Sum{125, 0, 125, 2n, 31n, 2n} <> Nil{}), 255 <> 0 <> Nil{}),
      "water at the ring's corner spreads inward only, the edge closed, and none wraps to the far corner")
    # the budget
    Lib.expect(same(query(ticks(200n, 0, 2n, pool()), over(60, 10, 60) <> Gone{} <> Queued{} <> Nil{}), 249 <> 6 <> 0 <> Nil{}),
      "two columns a tick, the same pool settles the same, nothing lost or made but the six that dried")
    # the load marks
    Lib.expect(same(query(World.load(World.W{[0 : U32^19n], World.Meta{Map.set(&2, World.Col, Map.new(&2, World.Col), "50,50",
          World.col6(1023, 0, 0, 0, 0, 3072)), 0, 0, Nil{}, 0, 0}}, 50, 50),
        Marks{50, 50} <> Marks{51, 50} <> Marks{50, 49} <> Queued{} <> Nil{}), 3072 <> 4294967295 <> 4294967295 <> 5 <> Nil{}),
      "a saved column loads marked where it is wet, its sides marked whole")
    Lib.expect(same(query(water(basin(60, 60, 5, 5n), 62, 10, 62), Partials{} <> Nil{}), 0 <> Nil{})
      && same(query(ticks(1n, 0, Flow.budget(), pool()), Partials{} <> Nil{}), 5 <> Nil{})
      && same(query(ticks(40n, 0, Flow.budget(), pool()), Partials{} <> Nil{}), 25 <> Nil{})
      && same(query(World.shift_x(True{}, ticks(40n, 0, Flow.budget(), pool())), Partials{} <> Nil{}), 25 <> Nil{})
      && same(query(World.load(ticks(40n, 0, Flow.budget(), pool()), 62, 62), Partials{} <> Nil{}), 25 <> Nil{}),
      "the world counts its partial cells: none placed, five after the first spread, all twenty-five settled, the same after a shift and a reload")
    Lib.expect(U32.is_eq(World.partial_mask(World.Levels{3, 0, 0, 0, 0, 0, 0, 0}), 1) && U32.is_eq(World.partial_mask(World.Levels{255, 0, 0, 0, 0, 0, 0, 0}), 0)
      && U32.is_eq(World.partial_mask(World.Levels{256, 0, 0, 0, 0, 0, 0, 0}), 2) && U32.is_eq(World.partial_mask(World.Levels{4278190080, 0, 0, 0, 0, 0, 0, 0}), 0)
      && U32.is_eq(World.partial_mask(World.Levels{4294967295, 4294967295, 4294967295, 4294967295, 4294967295, 4294967295, 4294967295, 4294967295}), 0)
      && U32.is_eq(World.partial_mask(World.Levels{16843009, 16843009, 16843009, 16843009, 16843009, 16843009, 16843009, 16843009}), 4294967295)
      && U32.is_eq(World.partial_mask(World.Levels{2155905152, 2155905152, 2155905152, 2155905152, 2155905152, 2155905152, 2155905152, 2155905152}), 4294967295)
      && U32.is_eq(World.partial_mask(World.Levels{0, 1879048192, 0, 117440512, 0, 0, 0, 0}), 32896)
      && U32.is_eq(World.partial_mask(World.Levels{0, 0, 0, 0, 0, 0, 0, 4261412864}), 2147483648)
      && U32.is_eq(World.partial_mask(World.full_levels(1056)), 0),
      "the partial mask has a bit where a byte holds one to 254")
    # the bucket: units move between a cell and the bucket, none made or lost
    Lib.expect(same(told(At{62, 10, 62} <> over(60, 10, 60) <> Gone{} <> Queued{} <> Nil{}, bucket(False{}, 62, 10, 62, 0n, ticks(40n, 0, Flow.budget(), pool()))),
        10 <> 0 <> 239 <> 6 <> 5 <> Nil{})
      && same(told(At{62, 10, 62} <> over(60, 10, 60) <> Gone{} <> Nil{}, bucket(False{}, 62, 10, 62, 10n, ticks(80n, 0, Flow.budget(), fst(bucket(False{}, 62, 10, 62, 0n, ticks(40n, 0, Flow.budget(), pool())))))),
        19 <> 0 <> 230 <> 6 <> Nil{}),
      "the bucket takes the settled pool's middle cell whole: ten units in the bucket, the cell empty and its neighbourhood queued, 239 + 10 + 6 the 255 placed; eighty ticks on the pool has filled the gap to nine and dried nothing more, and taken again with the ten still held: 19 in the bucket, 230 in the basin, 6 gone, the ledger holds")
    Lib.expect(same(told(At{62, 10, 62} <> Nil{}, bucket(True{}, 62, 10, 62, 255n, basin(60, 60, 5, 5n))), 0 <> 255 <> Nil{})
      && same(told(At{62, 10, 62} <> Nil{}, bucket(True{}, 62, 10, 62, 254n, basin(60, 60, 5, 5n))), 254 <> 0 <> Nil{})
      && same(told(At{62, 10, 62} <> Nil{}, bucket(True{}, 62, 10, 62, 55n, World.pour(basin(60, 60, 5, 5n), 62, 10, 62, 200))), 0 <> 255 <> Nil{})
      && same(told(At{62, 10, 62} <> Nil{}, bucket(True{}, 62, 10, 62, 54n, World.pour(basin(60, 60, 5, 5n), 62, 10, 62, 200))), 54 <> 200 <> Nil{})
      && same(told(At{59, 10, 62} <> Nil{}, bucket(True{}, 59, 10, 62, 255n, basin(60, 60, 5, 5n))), 255 <> 0 <> Nil{})
      && same(told(Nil{}, bucket(False{}, 59, 10, 62, 7n, basin(60, 60, 5, 5n))), 7 <> Nil{})
      && same(told(Nil{}, bucket(False{}, 200, 10, 62, 7n, basin(60, 60, 5, 5n))), 7 <> Nil{}),
      "a pour is a full cell: 255 from the bucket into air, nothing from 254; into a cell holding 200 it pours the 55 the cell lacks, nothing from 54; nothing into a wall, nothing out of one or from outside the window")
    Lib.expect(same(query(ticks(40n, 0, Flow.budget(), fst(bucket(True{}, 62, 10, 62, 255n, basin(60, 60, 5, 5n)))), over(60, 10, 60) <> Gone{} <> Nil{}), 249 <> 6 <> Nil{}),
      "a cell poured from the bucket is the pool: forty ticks on, the basin holds 249 and dried 6, as the placed cell did")
    Lib.expect(same(told(Sum{64, 10, 64, 0n, 21n, 0n} <> At{64, 12, 64} <> Nil{}, bucket(False{}, 64, 12, 64, 0n, three())), 255 <> 510 <> 0 <> Nil{})
      && same(told(Sum{64, 10, 64, 0n, 21n, 0n} <> Gone{} <> Nil{}, bucket(True{}, 64, 13, 64, 300n, fst(bucket(False{}, 64, 12, 64, 0n, three())))), 45 <> 765 <> 0 <> Nil{})
      && same(query(ticks(10n, 0, Flow.budget(), fst(bucket(True{}, 64, 13, 64, 300n, fst(bucket(False{}, 64, 12, 64, 0n, three()))))),
          At{64, 12, 64} <> At{64, 13, 64} <> Sum{64, 10, 64, 0n, 21n, 0n} <> Gone{} <> Nil{}), 255 <> 0 <> 765 <> 0 <> Nil{}),
      "the shaft's top cell into the bucket and a cell of it poured back above the gap: the shaft, the bucket and the dried sum to 765 throughout, and the poured cell falls into the gap")
    # the sink: thin water on the ground dries
    Lib.expect(same(query(ticks(1n, 0, Flow.budget(), World.mark_around(World.pour(basin(60, 60, 5, 5n), 62, 10, 62, 3), 62, 10, 62)),
        At{62, 10, 62} <> At{63, 10, 62} <> Gone{} <> Nil{}), 0 <> 1 <> 1 <> Nil{})
      && same(query(ticks(3n, 0, Flow.budget(), World.mark_around(World.pour(basin(60, 60, 5, 5n), 62, 10, 62, 3), 62, 10, 62)),
        over(60, 10, 60) <> Gone{} <> Queued{} <> Nil{}), 0 <> 3 <> 0 <> Nil{})
      && same(query(ticks(3n, 0, Flow.budget(), World.mark_around(World.pour(basin(60, 60, 5, 5n), 62, 10, 62, 4), 62, 10, 62)),
        over(60, 10, 60) <> Gone{} <> Nil{}), 0 <> 4 <> Nil{}),
      "a film of three units on the floor shares two out and dries the rest; the two dry at their turn: three gone, the floor dry; four units go the same way")
    Lib.expect(same(query(ticks(1n, 0, Flow.budget(), World.mark_around(World.pour(basin(64, 64, 1, 1n), 64, 15, 64, 3), 64, 15, 64)),
        At{64, 15, 64} <> At{64, 14, 64} <> Gone{} <> Nil{}), 0 <> 3 <> 0 <> Nil{})
      && same(query(ticks(8n, 0, Flow.budget(), World.mark_around(World.pour(basin(64, 64, 1, 1n), 64, 15, 64, 3), 64, 15, 64)),
        At{64, 10, 64} <> Gone{} <> Nil{}), 0 <> 3 <> Nil{}),
      "three units falling down a shaft never dry; landed on the floor they do")
    Lib.expect(same(query(ticks(1n, 0, Flow.budget(), World.mark_around(World.pour(water(basin(64, 64, 1, 1n), 64, 10, 64), 64, 11, 64, 3), 64, 11, 64)),
        At{64, 11, 64} <> At{64, 10, 64} <> Gone{} <> Nil{}), 0 <> 255 <> 3 <> Nil{}),
      "three units resting on full water dry too, the water under them whole")
    # a solid placed in water shoves the water up
    Lib.expect(same(query(stone(ticks(40n, 0, Flow.budget(), pool()), 62, 10, 62), At{62, 11, 62} <> At{62, 10, 62} <> over(60, 10, 60) <> Gone{} <> Queued{} <> Nil{}),
        10 <> 0 <> 249 <> 6 <> 5 <> Nil{})
      && same(query(ticks(40n, 0, Flow.budget(), stone(ticks(40n, 0, Flow.budget(), pool()), 62, 10, 62)), over(60, 10, 60) <> layer(60, 11, 60) <> Gone{} <> Nil{}),
        248 <> 0 <> 7 <> Nil{}),
      "a stone placed in the settled pool lifts its cell's ten units onto itself, the basin keeps them and the flow takes them from there, a unit drying as they spread")
    Lib.expect(same(query(stone(three(), 64, 10, 64), At{64, 10, 64} <> At{64, 11, 64} <> At{64, 12, 64} <> At{64, 13, 64} <> Sum{64, 10, 64, 0n, 21n, 0n} <> Gone{} <> Nil{}),
        0 <> 255 <> 255 <> 255 <> 765 <> 0 <> Nil{})
      && same(query(stone(three(), 64, 11, 64), At{64, 12, 64} <> At{64, 13, 64} <> Sum{64, 10, 64, 0n, 21n, 0n} <> Nil{}), 255 <> 255 <> 765 <> Nil{})
      && same(query(stone(World.pour(basin(64, 64, 1, 1n), 64, 10, 64, 100), 64, 10, 64), At{64, 11, 64} <> Gone{} <> Nil{}), 100 <> 0 <> Nil{}),
      "a stone at the bottom of three full cells shoves a cell of water past them to the first with room; in the middle the same; a half cell's hundred go up as they are")
    Lib.expect(same(query(stone(stone(three(), 64, 13, 64), 64, 10, 64), At{64, 13, 64} <> Sum{64, 10, 64, 0n, 21n, 0n} <> Gone{} <> Nil{}), 0 <> 510 <> 255 <> Nil{})
      && same(query(stone(ticks(40n, 0, Flow.budget(), pool()), 62, 12, 62), over(60, 10, 60) <> Gone{} <> Nil{}), 249 <> 6 <> Nil{}),
      "under a ceiling the shoved water has nowhere to go and is gone, counted; a stone placed in the air shoves nothing")
    # the game's clock drives the ticks (Player.advance)
    Lib.expect(same(query(advanced(100, shaft()), At{64, 15, 64} <> At{64, 14, 64} <> Nil{}), 255 <> 0 <> Nil{})
      && same(query(advanced(300, shaft()), At{64, 15, 64} <> At{64, 14, 64} <> Nil{}), 0 <> 255 <> Nil{})
      && same(query(advanced(2000, shaft()), At{64, 13, 64} <> Nil{}), 255 <> Nil{}),
      "the game's clock runs the flow: none in 100 ms, one tick in 300, two at most a frame however long the stall")
