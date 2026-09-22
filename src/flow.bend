import Base
import ./util.bend as Util
import ./world.bend as World

# THE FLOW OF WATER: finite volume, in units of 1/255 of a cell.
#
# A cell holds 0 to 255 units (World.Levels). A tick steps the cells the
# world has marked (World.mark: a word of cells a column, a queue of the
# marked columns' slots, oldest first). For a cell holding a > 0 units:
# first down, the cell below, if not solid, takes min(a, 255 - b); then
# sideways, each of the four neighbours that is not solid and holds less
# takes floor((a - n) / 2), never more than what is left. Every transfer
# is one atomic move of k units from a cell to a neighbour, both
# rewritten at once on the current state: the volume is the same before
# and after, no cell goes over 255 or under 0, and no order of the cells
# can duplicate water. The order of the four sides alternates with the
# tick's parity, so the bias of a fixed order cancels over two ticks. A
# neighbour outside the ring is solid: the window's edge is closed, and
# a lake that reaches it holds. A tick steps at most `budget` columns;
# the rest wait their turn, so the host's work a tick is bounded
# whatever the lake. A cell that moved nothing drops out; a move marks
# the cell that lost water, the one above it and its four sides (they
# may now fill it) and the one that gained (it may pass it on).

# ---------- one transfer ----------

# what goes down: all that fits under, where under is not solid (256)
def down_take(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, (b < 256 : U32), U32.min(a, (World.full() - b : U32)), 0)

# what goes to a side: half the difference, floored, only where the
# neighbour holds less; a lone unit stays, two share
def side_take(+a: U32, +n: U32) -> U32:
  Bool.pick(U32, (n < a : U32), ((a - n) / 2 : U32), 0)

# k units from the cell, holding a, to a neighbour holding b
def move(w: World.World, +lx: U32, +y: U32, +lz: U32, +a: U32, +nx: U32, +ny: U32, +nz: U32, +b: U32, +k: U32) -> World.World:
  World.mark(World.mark_around(World.pour(World.pour(w, lx, y, lz, (a - k : U32)), nx, ny, nz, (b + k : U32)), lx, y, lz),
    nx, nz, U32.shln(1, U32.to_nat(ny)))

def move_if(some: Bool, w: World.World, +lx: U32, +y: U32, +lz: U32, +a: U32, +nx: U32, +ny: U32, +nz: U32, +b: U32, +k: U32) -> World.World:
  match some:
    case False{}:
      w
    case True{}:
      move(w, lx, y, lz, a, nx, ny, nz, b, k)

# ---------- one cell ----------

# the amount at a neighbour, or 256 where the flow cannot go: a solid
# cell, one under the world, one outside the ring
def probe_fin(+y: U32, +mask: U32, r: World.World & U32) -> World.World & U32:
  (w, a) = r
  (w, Bool.pick(U32, Util.on(mask, U32.shln(1, U32.to_nat(y))), 256, a))

def probe_mask(+lx: U32, +y: U32, +lz: U32, r: World.World & U32) -> World.World & U32:
  (w, mask) = r
  probe_fin(y, mask, World.amount_at(w, lx, y, lz))

def probe_in(ok: Bool, w: World.World, +lx: U32, +y: U32, +lz: U32) -> World.World & U32:
  match ok:
    case False{}:
      (w, 256)
    case True{}:
      probe_mask(lx, y, lz, World.word_at(w, lx, lz, 0))

def probe(w: World.World, +lx: U32, +y: U32, +lz: U32) -> World.World & U32:
  probe_in((lx < 128 : U32) && (lz < 128 : U32) && (y < 32 : U32), w, lx, y, lz)

# the sides in the tick's order: +x, -x, +z, -z on an even tick, the
# reverse on an odd one (a step of -1 wraps, and the probe says outside)
def side_x(+i: U32) -> U32:
  Bool.pick(U32, U32.is_eq(i, 0), 1, Bool.pick(U32, U32.is_eq(i, 1), 4294967295, 0))

def side_z(+i: U32) -> U32:
  Bool.pick(U32, U32.is_eq(i, 2), 1, Bool.pick(U32, U32.is_eq(i, 3), 4294967295, 0))

def side_of(+i: U32, +odd: Bool) -> U32:
  Bool.pick(U32, odd, (3 - i : U32), i)

# the sides, one probe ahead: r is the probe of side i, then side i + 1
# is probed on the world after the move
def sides(n: Nat, +lx: U32, +y: U32, +lz: U32, +a: U32, +i: U32, +odd: Bool, +nx: U32, +nz: U32, r: World.World & U32) -> World.World:
  match n:
    case 0n:
      (w, +b) = r
      move_if((side_take(a, b) > 0 : U32), w, lx, y, lz, a, nx, y, nz, b, side_take(a, b))
    case 1n+m:
      (w, +b) = r
      +k = side_take(a, b)
      +j = side_of((i + 1 : U32), odd)
      +nx2 = (lx + side_x(j) : U32)
      +nz2 = (lz + side_z(j) : U32)
      sides(m, lx, y, lz, (a - k : U32), (i + 1 : U32), odd, nx2, nz2,
        probe(move_if((k > 0 : U32), w, lx, y, lz, a, nx, y, nz, b, k), nx2, y, nz2))

# the sides only while something is left
def sides_if(some: Bool, w: World.World, +lx: U32, +y: U32, +lz: U32, +a: U32, +odd: Bool) -> World.World:
  match some:
    case False{}:
      w
    case True{}:
      +j = side_of(0, odd)
      +nx = (lx + side_x(j) : U32)
      +nz = (lz + side_z(j) : U32)
      sides(3n, lx, y, lz, a, 0, odd, nx, nz, probe(w, nx, y, nz))

def down_fin(+lx: U32, +y: U32, +lz: U32, +a: U32, +odd: Bool, r: World.World & U32) -> World.World:
  (w, +b) = r
  +k = down_take(a, b)
  sides_if((k < a : U32), move_if((k > 0 : U32), w, lx, y, lz, a, lx, (y - 1 : U32), lz, b, k), lx, y, lz, (a - k : U32), odd)

def cell_if(some: Bool, +lx: U32, +y: U32, +lz: U32, +a: U32, +odd: Bool, w: World.World) -> World.World:
  match some:
    case False{}:
      w
    case True{}:
      down_fin(lx, y, lz, a, odd, probe(w, lx, (y - 1 : U32), lz))

def cell_fin(+lx: U32, +y: U32, +lz: U32, +odd: Bool, r: World.World & U32) -> World.World:
  (w, +a) = r
  cell_if((a > 0 : U32), lx, y, lz, a, odd, w)

# ---------- a source ----------

# what a source holding a makes when it refills
def refilled(+a: U32) -> U32:
  (World.full() - a : U32)

# a source refills to full at the end of its step, and the world counts
# what it made; one that gave nothing made nothing
def refill_fin(+lx: U32, +y: U32, +lz: U32, r: World.World & U32) -> World.World:
  (w, +a) = r
  World.make(World.pour(w, lx, y, lz, World.full()), refilled(a))

# ---------- the sink ----------

# The model needs one: a spring's spill, with nothing to remove it, would
# spread as a film over every flat reach without end. Thin water dries: a
# cell resting on the ground (a solid under it, 256, or full water, 255)
# that holds under `thin` units at the end of its step loses them, and
# the world counts what went. Falling water never dries, and a lake at
# rest holds ten units a cell and more, so it is untouched.
def thin() -> U32: 4

def dries(+a: U32, +under: U32) -> Bool:
  (a > 0 : U32) && (a < thin() : U32) && (under >= 255 : U32)

def dry_if(gone: Bool, w: World.World, +lx: U32, +y: U32, +lz: U32, +a: U32) -> World.World:
  match gone:
    case False{}:
      w
    case True{}:
      World.dry(World.pour(w, lx, y, lz, 0), a)

def dry_go(+lx: U32, +y: U32, +lz: U32, +a: U32, r: World.World & U32) -> World.World:
  (w, +under) = r
  dry_if(dries(a, under), w, lx, y, lz, a)

# the probe under the cell only where the cell is thin
def dry_thin(thin_here: Bool, w: World.World, +lx: U32, +y: U32, +lz: U32, +a: U32) -> World.World:
  match thin_here:
    case False{}:
      w
    case True{}:
      dry_go(lx, y, lz, a, probe(w, lx, (y - 1 : U32), lz))

def dry_fin(+lx: U32, +y: U32, +lz: U32, r: World.World & U32) -> World.World:
  (w, +a) = r
  dry_thin((a > 0 : U32) && (a < thin() : U32), w, lx, y, lz, a)

# the end of a cell's step: a source refills, any other cell may dry
def settle_if(src: Bool, w: World.World, +lx: U32, +y: U32, +lz: U32) -> World.World:
  match src:
    case True{}:
      refill_fin(lx, y, lz, World.amount_at(w, lx, y, lz))
    case False{}:
      dry_fin(lx, y, lz, World.amount_at(w, lx, y, lz))

def settle(+lx: U32, +y: U32, +lz: U32, r: World.World & Bool) -> World.World:
  (w, src) = r
  settle_if(src, w, lx, y, lz)

# the step of one cell: down, then the sides, then the refill or the drying
def step(w: World.World, +lx: U32, +y: U32, +lz: U32, +odd: Bool) -> World.World:
  settle(lx, y, lz, World.source_at(cell_fin(lx, y, lz, odd, World.amount_at(w, lx, y, lz)), lx, y, lz))

# ---------- one column ----------

# the marked cells of a column, from the bottom up: a cell that drains
# makes room for the one above it in the same tick, so a column falls
# whole rather than opening a gap a tick
def step_if(some: Bool, w: World.World, +lx: U32, +y: U32, +lz: U32, +odd: Bool) -> World.World:
  match some:
    case False{}:
      w
    case True{}:
      step(w, lx, y, lz, odd)

# (the fuel is the first parameter: the recursion descends on it)
def column(n: Nat, done: Bool, +y: U32, +bits: U32, +lx: U32, +lz: U32, +odd: Bool, w: World.World) -> World.World:
  match n:
    case 0n:
      w
    case 1n+m:
      match done:
        case True{}:
          w
        case False{}:
          column(m, U32.is_eq((bits / 2 : U32), 0), (y + 1 : U32), (bits / 2 : U32), lx, lz, odd, step_if(Util.on(bits, 1), w, lx, y, lz, odd))

# the local column of a queued slot: the slot is ((X * 128 + Z) * 16)
# mod 2^18 for the world column (X, Z) = (ox + lx, oz + lz), and the
# carry of Z into the slot's high part is what the extra term undoes
def lz_of(+slot: U32, +oz: U32) -> U32:
  ((slot / 16 - oz) % 128 : U32)

def lx_of(+slot: U32, +ox: U32, +oz: U32, +lz: U32) -> U32:
  ((slot / 2048 - (oz + lz) / 128 - ox) % 128 : U32)

# the column at the slot: its marks read and cleared, its cells stepped
def slot_fin(m: Map<&2, World.Col>, +ox: U32, +oz: U32, q: List<&2, U32>, np: U32, made: U32, gone: U32, +slot: U32, +odd: Bool, r: Array<U32> & U32) -> World.World:
  (ring, +bits) = r
  +lz = lz_of(slot, oz)
  column(32n, U32.is_eq(bits, 0), 0, bits, lx_of(slot, ox, oz, lz), lz, odd, World.W{Array.set(U32, ring, (slot + 14 : U32), 0), m, ox, oz, q, np, made, gone})

def step_slot(w: World.World, +slot: U32, +odd: Bool) -> World.World:
  World.W{ring, m, +ox, +oz, q, np, made, gone} = w
  slot_fin(m, ox, oz, q, np, made, gone, slot, odd, Array.get(U32, ring, (slot + 14 : U32)))

# ---------- one tick ----------

# The queue leaves the world for the tick, so the marks the tick makes
# queue afresh; what the budget did not reach goes back in front of them,
# and the tick's marks behind, oldest first.
def rejoin(rest: List<&2, U32>, w: World.World) -> World.World:
  World.W{ring, m, ox, oz, q, np, made, gone} = w
  World.W{ring, m, ox, oz, List.append(&2, U32, rest, List.reverse(&2, U32, q)), np, made, gone}

def tick_go(budget: Nat, q: List<&2, U32>, +odd: Bool, w: World.World) -> World.World:
  match budget:
    case 0n:
      rejoin(q, w)
    case 1n+k:
      match q:
        case Nil{}:
          rejoin(Nil{}, w)
        case Con{slot, rest}:
          tick_go(k, rest, odd, step_slot(w, slot, odd))

def tick(w: World.World, +odd: Bool, +budget: Nat) -> World.World:
  World.W{ring, m, ox, oz, q, np, made, gone} = w
  tick_go(budget, q, odd, World.W{ring, m, ox, oz, Nil{}, np, made, gone})

# the columns a tick steps at most
def budget() -> Nat: 256n

# A tick every 256 ms of the day's clock, 4096 a turn, so the grid holds
# across the clock's wrap; the parity is the tick's number. After a
# stall, at most two a frame: the water catches up at that pace.
def period() -> U32: 256

def ticks(n: Nat, +at: U32, w: World.World) -> World.World:
  match n:
    case 0n:
      w
    case 1n+k:
      ticks(k, (at + 1 : U32), tick(w, Util.on(at, 1), budget()))

def due(+clock: U32, +ms: U32) -> U32:
  U32.min(((clock + ms) / period() - clock / period() : U32), 2)

def advance(w: World.World, +clock: U32, +ms: U32) -> World.World:
  ticks(U32.to_nat(due(clock, ms)), (clock / period() : U32), w)
