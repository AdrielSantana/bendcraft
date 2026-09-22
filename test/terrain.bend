import Base
import ./lib.bend as Lib
import ../src/world.bend as World
import ../src/util.bend as Util
import ../src/render.bend as Render
import ../src/sky.bend as Sky
import ../src/day.bend as Day

# Rows of the terrain, to see the noise with your eyes: heights must roll
# along x as along z. A hash that is a product per axis made stripes here.

def row(n: Nat, +x: U32, +z: U32, +dx: U32, +dz: U32) -> String:
  match n:
    case 0n:
      ""
    case 1n+k:
      U32.show(World.terrain(x, z)) ++ " " ++ row(k, (x + dx : U32), (z + dz : U32), dx, dz)

def trees_z(n: Nat, +x: U32, +z: U32, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+k:
      trees_z(k, x, (z + 1 : U32), (acc + Bool.pick(U32, World.tree_at(x, z) && World.tree_ground(World.terrain(x, z)), 1, 0) : U32))

def trees(n: Nat, +x: U32, +z: U32, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+k:
      trees(k, (x + 1 : U32), z, trees_z(128n, x, z, acc))

# Inspect the generated column, including neighbours' canopies. Below the
# water surface only the ground may be solid; every gap must be water.
def dry_roots(+h: U32, c: World.Col) -> Bool:
  World.Col{m, a, b, cc, d, water, lv} = c
  +ground = (U32.shln(1, U32.to_nat(h)) - 1 : U32)
  U32.is_eq((m .&. 4095 : U32), (ground .&. 4095 : U32))
    && U32.is_eq(water, (4095 .&. U32.not(ground) : U32))

# Read the packed surface material, rather than repeating tnib's rule.
def lake_floor(+h: U32, c: World.Col) -> Bool:
  World.Col{m, a, b, cc, d, water, lv} = c
  (h >= 12 : U32) || U32.is_eq(World.nib_get(Bool.pick(U32, (h <= 8 : U32), a, b), (h - 1 : U32)),
    Bool.pick(U32, (h <= 6 : U32), 3, 1))

def scan(n: Nat, +i: U32, ok: Bool) -> Bool:
  match n:
    case 0n: ok
    case 1n+k:
      +x = (1048512 + i / 128 : U32)
      +z = (1048512 + i % 128 : U32)
      +h = World.terrain(x, z)
      +c = World.column(x, z)
      scan(k, (i + 1 : U32), ok && dry_roots(h, c) && lake_floor(h, c))

def no_tree(m: World.Masks) -> Bool:
  World.Masks{wood, leaf} = m
  U32.is_eq(wood, 0) && U32.is_eq(leaf, 0)

def shore_tree(c: World.Col) -> Bool:
  World.Col{m, a, b, cc, d, water, lv} = c
  U32.is_eq((m .&. 258048 : U32), 258048) && U32.is_eq(water, 0)
    && U32.is_eq(World.nib_get(b, 12), 4) && U32.is_eq(World.nib_get(cc, 16), 5)

def old_tree(r: Array<U32> & World.Col) -> Bool:
  (ring, c) = r
  World.Col{m, a, b, cc, d, water, lv} = c
  U32.is_eq(m, 511) && U32.is_eq(b, 4) && U32.is_eq(water, 3584)

# Existing edited columns are authoritative, even if the new generator
# would reject their submerged tree. Loading must not erase old builds.
def saved_tree(w: World.World) -> Bool:
  World.W{ring, meta} = w
  old_tree(World.get_col(ring, World.col_at(0, 1048543, 1048592)))

# the far map: the start's columns and the line a move brings into view
def start() -> World.World:
  World.load_world(World.W{[0 : U32^19n], World.Meta{Map.new(&2, World.Col), 1048512, 1048512, Nil{}, 0, 0}}, 1048512, 1048512)

def far_read(r: Array<U32> & U32) -> U32:
  (ring, word) = r
  word

def far_of(w: World.World, +x: U32, +z: U32) -> U32:
  World.W{ring, meta} = w
  far_read(Array.get(U32, ring, World.far_at(x, z)))

# the highest top of the cell of column (x, z), from the noise
def cell_of(n: Nat, +x: U32, +z: U32, +i: U32, +best: U32) -> U32:
  match n:
    case 0n:
      best
    case 1n+k:
      cell_of(k, x, z, (i + 1 : U32), U32.max(best, World.far_top(World.far_col((x - x % 4 + i / 4 : U32), (z - z % 4 + i % 4 : U32)))))

# the map's word for (x, z) is the column's, with its cell's top
def far_is(w: World.World, +x: U32, +z: U32) -> Bool:
  +word = far_of(w, x, z)
  U32.is_eq((word % 1048576 : U32), World.far_col(x, z)) && U32.is_eq((word / 1048576 : U32), cell_of(16n, x, z, 0, 0))

# at the map's edge a cell's slots also hold columns from across the
# map: the column is exact, and its cell's top covers it
def far_covers(w: World.World, +x: U32, +z: U32) -> Bool:
  +word = far_of(w, x, z)
  U32.is_eq((word % 1048576 : U32), World.far_col(x, z)) && ((word / 1048576 : U32) >= World.far_top(World.far_col(x, z)) : U32)

# the far word against the window's own column, block by block: the
# window's block is 32 for air, 8 for water, its type else; the far
# word's the same from its run, its canopy and far_type
def agree_col(n: Nat, +y: U32, +m: U32, +a: U32, +b: U32, +cc: U32, +d: U32, +water: U32, +far: U32, ok: Bool) -> Bool:
  match n:
    case 0n:
      ok
    case 1n+k:
      +bit = U32.shln(1, U32.to_nat(y))
      +tw = Bool.pick(U32, (y < 16 : U32), Bool.pick(U32, (y < 8 : U32), a, b), Bool.pick(U32, (y < 24 : U32), cc, d))
      +near = Bool.pick(U32, Util.on(water, bit), 8, Bool.pick(U32, Util.on(m, bit), World.nib_at(tw, y), 32))
      +solid = (y < far / 32 % 32 : U32) || ((y >= far / 1024 % 32 : U32) && (y < far / 32768 % 32 : U32))
      agree_col(k, (y + 1 : U32), m, a, b, cc, d, water, far, ok && U32.is_eq(near, Bool.pick(U32, solid, World.far_type(far, y), 32)))

def agree(+far: U32, c: World.Col) -> U32:
  World.Col{+m, +a, +b, +cc, +d, +water, lv} = c
  Bool.pick(U32, agree_col(32n, 0, m, a, b, cc, d, water, far, True{}), 0, 1)

# the columns of the window at (x, z) whose far word disagrees
def disagree(n: Nat, +x: U32, +z: U32, +i: U32, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+k:
      +cx = (x + i / 128 : U32)
      +cz = (z + i % 128 : U32)
      disagree(k, x, z, (i + 1 : U32), (acc + agree(World.far_col(cx, cz), World.column(cx, cz)) : U32))

# the far look against the window's: rays from the start's eye, each
# shaded by the window's walk and look, then by the far walk's from the
# eye over the far map, with the game's looks and the mirror but the
# ripples, which are gone past 32 blocks where the far walk begins; the
# count of rays whose colours part by more than 4 a channel
def apart(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, (a > b : U32), (a - b : U32), (b - a : U32))

def part(+a: U32, +b: U32) -> U32:
  U32.max(U32.max(apart((a / 65536 : U32), (b / 65536 : U32)), apart((a / 256 % 256 : U32), (b / 256 % 256 : U32))), apart((a % 256 : U32), (b % 256 : U32)))

def looks() -> U32: (Render.looks() .&. U32.not(1048576) : U32)

def eye_base() -> U32: ((1048512 * 128 + 1048512 : U32) .&. 16383 .|. 134217728 : U32)

def eye_far() -> U32: (World.far_corner(1048512) % 256 * 256 + World.far_corner(1048512) % 256 : U32)

def far_then(+acc: U32, +near: U32, r: Array<U32> & U32) -> Array<U32> & U32:
  (ring, +far) = r
  (ring, (acc + Bool.pick(U32, (part(near, far) > 4 : U32), 1, 0) : U32))

def near_then(+acc: U32, +dx: F32, +dy: F32, +dz: F32, +v: U32, +lx: F32, +ly: F32, +lz: F32, r: Array<U32> & U32) -> Array<U32> & U32:
  (ring, +near) = r
  far_then(acc, near, Render.far_fin(eye_base(), eye_far(), looks(), v, 64.5, 30.0, 64.5, dx, dy, dz, lx, ly, lz, Sky.bodies(looks(), v, dx, dy, dz, lx, ly, lz),
    Render.run_far(128n, ring, eye_far(), 64.5, 30.0, 64.5, dx, dy, dz, 0.0, Sky.reach())))

def look_both(ring: Array<U32>, +acc: U32, +dx: F32, +dy: F32, +dz: F32, +lx: F32, +ly: F32, +lz: F32) -> Array<U32> & U32:
  +v = Sky.atmosphere(looks(), dx, dy, dz, lx, ly, lz)
  near_then(acc, dx, dy, dz, v, lx, ly, lz, Render.clipped(ring, eye_base(), eye_far(), 64.5, 30.0, 64.5, dx, dy, dz, v, looks(), lx, ly, lz))

# ray i: 24 headings, eight pitches from 0.08 to 0.5 down
def look_ray(ring: Array<U32>, +acc: U32, +yaw: F32, +pit: F32) -> Array<U32> & U32:
  look_both(ring, acc, (F32.cos(pit) * F32.sin(yaw) : F32), F32.sin(pit), (F32.cos(pit) * F32.cos(yaw) : F32),
    Day.sun_x(Day.morning()), Day.sun_y(Day.morning()), Day.sun_z(Day.morning()))

def parted(n: Nat, +i: U32, r: Array<U32> & U32) -> U32:
  match n:
    case 0n:
      (ring, +acc) = r
      acc
    case 1n+k:
      (ring, +acc) = r
      parted(k, (i + 1 : U32), look_ray(ring, acc, (Util.u2f((i / 8 : U32)) * 0.2618 : F32), (0.0 - 0.08 - Util.u2f((i % 8 : U32)) * 0.06 : F32)))

def parted_in(w: World.World) -> U32:
  World.W{ring, meta} = w
  parted(192n, 0, (ring, 0))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("along x at the start: " ++ row(40n, 1048576, 1048576, 1, 0))
    IO.print("along z at the start: " ++ row(40n, 1048576, 1048576, 0, 1))
    IO.print("along x near zero:    " ++ row(40n, 100, 100, 1, 0))
    IO.print("along z near zero:    " ++ row(40n, 100, 100, 0, 1))
    IO.print("trees in the start window: " ++ U32.show(trees(128n, 1048512, 1048512, 0)))
    Lib.expect(scan(16384n, 0, True{}), "generated start window has no submerged trees or grass, and fills gaps with water")
    Lib.expect(World.tree_at(1048543, 1048592) && U32.is_eq(World.terrain(1048543, 1048592), 8)
      && no_tree(World.tree_here(1048543, 1048592, 0, False{}, World.Masks{0, 0}))
      && no_tree(World.tree_here(1048543, 1048592, 1, False{}, World.Masks{0, 0}))
      && no_tree(World.tree_here(1048543, 1048592, 2, False{}, World.Masks{0, 0})), "submerged tree contributes neither trunk nor canopy in neighbouring columns")
    Lib.expect(U32.is_eq(World.terrain(1048512, 1048515), 12) && shore_tree(World.column(1048512, 1048515)), "tree at the dry shoreline keeps its trunk and leaves")
    Lib.expect(far_is(start(), 1048448, 1048448) && far_is(start(), 1048703, 1048703) && far_is(start(), 1048576, 1048576),
      "the far map holds the start's columns, 64 around the window on each side, each with its cell's highest top")
    Lib.expect(far_covers(World.follow(1n, True{}, True{}, start()), 1048704, 1048500)
      && far_covers(World.follow(1n, True{}, False{}, start()), 1048447, 1048500)
      && far_covers(World.follow(1n, False{}, True{}, start()), 1048500, 1048704)
      && far_covers(World.follow(1n, False{}, False{}, start()), 1048500, 1048447)
      && far_is(World.follow(4n, True{}, True{}, start()), 1048707, 1048500)
      && far_is(World.follow(4n, True{}, False{}, start()), 1048444, 1048500)
      && far_is(World.follow(4n, False{}, True{}, start()), 1048500, 1048707)
      && far_is(World.follow(4n, False{}, False{}, start()), 1048500, 1048444),
      "a move of a column loads the far map's line that came into view, on either axis, either way, under its cell's top; four moves, and the new line's cell is whole and its top exact")
    Lib.expect(U32.is_eq(disagree(16384n, 1048512, 1048512, 0, 0), 14),
      "the far map agrees with the window's own columns, block by block, in all but 14 of the start window's 16384: a canopy's leaves inside a slope are the slope's, and two canopies at two heights fill the gap between them")
    Lib.expect(U32.is_eq(parted_in(start()), 3),
      "the far look is the window's: of 192 rays from the start's eye, all but three steep looks at a lake's bed are the same colour within 4 a channel over the far map")
    Lib.expect(saved_tree(World.load(World.W{[0 : U32^19n],
      World.Meta{Map.set(&2, World.Col, Map.new(&2, World.Col), "1048543,1048592", World.col6(511, 0, 4, 0, 0, 3584)),
      1048512, 1048512, Nil{}, 0, 0}}, 1048543, 1048592)), "saved submerged wood survives generation changes")
    IO.pure(Unit, Unit{})
