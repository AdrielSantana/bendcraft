import Base
import ../src/world.bend as World
import ../src/water.bend as Water
import ../src/render.bend as Render
import ../src/player.bend as Player
import ../src/save.bend as Save
import ../src/inventory.bend as Inventory
import ../src/util.bend as Util
import ../src/sky.bend as Sky

def near(a: F32, b: F32, epsilon: F32) -> Bool:
  (F32.abs((a - b : F32)) <= epsilon : F32)

def expect(ok: Bool, name: String) -> IO(Unit):
  match ok:
    case True{}: IO.print("ok " ++ name)
    case False{}: IO.die(Unit, 1, "failed " ++ name)

def empty() -> World.World:
  World.W{[0 : U32^18n], Map.new(&2, World.Col), 0, 0, Nil{}, 0}

def ray_ok(+axis: U32, top: Bool, +entry: F32, +depth: F32, +distance: F32, r: Array<U32> & Render.Ray) -> Bool:
  (w, hit) = r
  Render.Ray{+code, t, Water.Trace{e, d}} = hit
  U32.is_eq((code % 4 : U32), (axis + 1 : U32)) && F32.is_eq(t, distance)
    && F32.is_eq(e, entry) && F32.is_eq(d, depth) && Bool.not(Bool.xor(Water.top(code), top))

# One wet voxel, then a solid two cells beyond it. These rays test the
# real DDA in both signs of every axis, outside and inside the water.
def probe_w(~wet: Bool, +axis: U32, +pos: Bool, +under: Bool, +blocked: Bool, w: World.World) -> Bool:
  World.W{ring, m, ox, oz, q, np} = w
  +a = Bool.pick(F32, under, 64.0, Bool.pick(F32, pos, 61.0, 67.0))
  +x = Bool.pick(F32, U32.is_eq(axis, 0), a, 64.0)
  +y = Bool.pick(F32, U32.is_eq(axis, 1), (a - 54.0 : F32), 10.0)
  +z = Bool.pick(F32, U32.is_eq(axis, 2), a, 64.0)
  +sign = Bool.pick(F32, pos, 1.0, (0.0 - 1.0 : F32))
  +yes = Bool.pick(F32, wet, 1.0, 0.0)
  ray_ok(axis, wet && U32.is_eq(axis, 1) && Bool.not(pos) && Bool.not(under) && Bool.not(blocked),
    Bool.pick(F32, wet && Bool.not(under) && Bool.not(blocked), 2.5, 0.0),
    Bool.pick(F32, blocked, 0.0, (yes * Bool.pick(F32, under, 0.5, 1.0) : F32)),
    Bool.pick(F32, blocked || under, 1.5, 4.5),
    Render.dda(~wet, ~wet, 60n, 0, x, y, z, sign, sign, sign,
      Bool.pick(F32, U32.is_eq(axis, 0), 0.5, 50000.0),
      Bool.pick(F32, U32.is_eq(axis, 1), 0.5, 50000.0),
      Bool.pick(F32, U32.is_eq(axis, 2), 0.5, 50000.0),
      Bool.pick(F32, U32.is_eq(axis, 0), 1.0, 100000.0),
      Bool.pick(F32, U32.is_eq(axis, 1), 1.0, 100000.0),
      Bool.pick(F32, U32.is_eq(axis, 2), 1.0, 100000.0),
      1.0, 0, 0.0, 0, U32.shln(1, F32.to_nat(y)), Water.Trace{0.0, 0.0},
      Render.column_words(~wet, ~wet, ring, World.col_at(0, Util.f2u(x), Util.f2u(z)), U32.shln(1, F32.to_nat(y)), Util.f2u(y), sign,
        Bool.pick(F32, U32.is_eq(axis, 1), 0.5, 50000.0), Bool.pick(F32, U32.is_eq(axis, 1), 1.0, 100000.0))))

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

# the ring alone after a column is written into it
def ring_of(r: Array<U32> & U32) -> Array<U32>:
  (w, np) = r
  w

def same_masks(c: World.Col, +solid: U32, +water: U32) -> Bool:
  World.Col{m, a, b, cc, d, w, lv} = c
  U32.is_eq(m, solid) && U32.is_eq(w, water)

def same_levels(a: World.Levels, b: World.Levels) -> Bool:
  World.Levels{a0, a1, a2, a3, a4, a5, a6, a7} = a
  World.Levels{b0, b1, b2, b3, b4, b5, b6, b7} = b
  U32.is_eq(a0, b0) && U32.is_eq(a1, b1) && U32.is_eq(a2, b2) && U32.is_eq(a3, b3)
    && U32.is_eq(a4, b4) && U32.is_eq(a5, b5) && U32.is_eq(a6, b6) && U32.is_eq(a7, b7)

def saved_col(g: Player.Game) -> World.Col:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag} = g
  World.W{ring, m, ox, oz, q, np} = w
  col(World.get_col(ring, World.col_at(0, 64, 64)))

def restored(r: Player.Game & String) -> World.Col:
  (g, text) = r
  saved_col(Save.parse(String.lines(text), Player.res512()))

def fixture(w: World.World) -> Player.Game:
  Player.G{w, 64.5, 14.0, 64.5, 0.0, 0.0, 0.0, 0, 0, 0, 0, 0, Player.res512(), 154747, Inventory.empty()}

def placed(r: World.World & List<&2, Nat>) -> Bool:
  (w, bag) = r
  World.W{ring, m, ox, oz, q, np} = w
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

def snd(r: World.World & U32) -> U32:
  (w, v) = r
  v

def amount(w: World.World, +lx: U32, +y: U32, +lz: U32) -> U32:
  snd(World.amount_at(w, lx, y, lz))

def voxel_of(w: World.World, +lx: U32, +y: U32, +lz: U32) -> U32:
  snd(World.voxel(w, lx, y, lz))

# One cell of `a` units at (64, 10, 64). A ray along an axis from
# (x, y, z), or sloping down 1 in 4 along x (`level` false): its trace.
def trace_of(r: Array<U32> & Render.Ray) -> Render.Ray:
  (w, hit) = r
  hit

def partial_trace_w(+level: Bool, +x: F32, +y: F32, +z: F32, +axis: U32, w: World.World) -> Render.Ray:
  World.W{ring, m, ox, oz, q, np} = w
  +vy = Util.floorf(y)
  +move_x = Bool.pick(Bool, level, U32.is_eq(axis, 0), True{})
  +move_y = Bool.pick(Bool, level, U32.is_eq(axis, 1), True{})
  +move_z = level && U32.is_eq(axis, 2)
  +ay = Bool.pick(F32, level, 1.0, 0.25)
  trace_of(Render.dda(~True{}, ~True{}, 60n, 0, Util.floorf(x), vy, Util.floorf(z), 1.0, (0.0 - 1.0 : F32), 1.0,
    Bool.pick(F32, move_x, (Util.floorf(x) + 1.0 - x : F32), 50000.0),
    Bool.pick(F32, move_y, ((y - vy) / ay : F32), ((y - vy) / 0.00001 : F32)),
    Bool.pick(F32, move_z, (Util.floorf(z) + 1.0 - z : F32), 50000.0),
    Bool.pick(F32, move_x, 1.0, 100000.0),
    Bool.pick(F32, move_y, (1.0 / ay : F32), 100000.0),
    Bool.pick(F32, move_z, 1.0, 100000.0),
    1.0, 0, 0.0, 0, U32.shln(1, F32.to_nat(vy)), Water.Trace{0.0, 0.0},
    Render.column_words(~True{}, ~True{}, ring, World.col_at(0, Util.f2u(x), Util.f2u(z)), U32.shln(1, F32.to_nat(vy)), Util.f2u(vy), (0.0 - 1.0 : F32),
      Bool.pick(F32, move_y, ((y - vy) / ay : F32), ((y - vy) / 0.00001 : F32)), Bool.pick(F32, move_y, (1.0 / ay : F32), 100000.0))))

def partial_trace(+level: Bool, +a: U32, +x: F32, +y: F32, +z: F32, +axis: U32) -> Render.Ray:
  partial_trace_w(level, x, y, z, axis, World.pour(pool(1n, empty(), 64, 128), 64, 10, 64, a))

def ray_matches(+entry: F32, +depth: F32, top: Bool, ray: Render.Ray) -> Bool:
  Render.Ray{code, t, Water.Trace{e, d}} = ray
  near(e, entry, 0.0001) && near(d, depth, 0.0001) && Bool.not(Bool.xor(Water.top(code), top))

def partial_ok(+level: Bool, +a: U32, +x: F32, +y: F32, +z: F32, +axis: U32, +along: Bool, +entry: F32, +depth: F32, top: Bool) -> Bool:
  ray_matches(entry, depth, top, partial_trace(level, a, x, y, z, axis))

# a stone at 9 under a water cell at 10, the surface ray's pool
def surface_pool() -> World.World:
  World.edit(World.edit(empty(), 64, 64, 9, True{}, 2), 64, 64, 10, True{}, 8)

def pixel(r: Array<U32> & U32) -> U32:
  (w, c) = r
  c

def fog_ray_w(+fl: U32, w: World.World) -> U32:
  World.W{ring, m, ox, oz, q, np} = w
  pixel(Render.run_water(Util.on(fl, 2097152), ring, 0, 1.5, 10.5, 64.5,
    1.0, 0.0, 0.0, Render.rgb(100, 140, 180), fl, 0.48, 0.8, 0.36))

def fog_ray(fl: U32, wet_until: U32, wall: U32) -> U32:
  fog_ray_w(fl, World.edit(pool(128n, empty(), 0, wet_until), wall, 64, 10, True{}, 2))

# The same shallow wet path sees either a wall beyond the air fog or sky.
# It rises through the water surface before reaching either background.
def emerged_ray_w(+fl: U32, +sun_y: F32, w: World.World) -> U32:
  World.W{ring, m, ox, oz, q, np} = w
  pixel(Render.run_water(Util.on(fl, 2097152), ring, 0, 1.5, 10.5, 64.5,
    0.99277389, 0.12, 0.0, Sky.gradient(True{}, 0.12, sun_y), fl, 0.48, sun_y, 0.36))

def emerged_wall(fl: U32, sun_y: F32, wall: U32, w: World.World) -> U32:
  World.W{ring, m, ox, oz, q, np} = w
  emerged_ray_w(fl, sun_y, World.put_fin(m, ox, oz, q, World.put_col(ring, World.col_at(0, wall, 64),
    World.col6(4294967295, 572662306, 572662306, 572662306, 572662306, 0), np)))

def emerged_ray(fl: U32, sun_y: F32, wall: U32) -> U32:
  emerged_wall(fl, sun_y, wall, pool(128n, empty(), 0, 128))

def no_silhouette(+fl: U32, +sun_y: F32) -> Bool:
  +sky = emerged_ray(fl, sun_y, 100)
  U32.is_eq(emerged_ray(fl, sun_y, 40), sky)
    && U32.is_ne(emerged_ray(fl, sun_y, 12), sky)

# Water at an arbitrary edited height, not the natural sea plane. The
# ray can enter its top, begin submerged, or hit the bank before water.
# the base carries the window's partial-water bit, as Player.view_w sets it
def surface_ray_w(+fl: U32, +under: Bool, w: World.World) -> U32:
  World.W{ring, m, ox, oz, q, +np} = w
  pixel(Render.run_water(Util.on(fl, 2097152), ring, Render.with_partial(0, (np > 0 : U32)), 64.5, Bool.pick(F32, under, 10.5, 14.5), 64.5,
    0.0, (0.0 - 1.0 : F32), 0.0, Sky.rgb(130, 170, 235), fl, 0.48, 0.8, 0.36))

def surface_ray(fl: U32, under: Bool, blocked: Bool) -> U32:
  surface_ray_w(fl, under, World.edit(World.edit(World.edit(empty(), 64, 64, 9, True{}, 2),
    64, 64, 10, True{}, 8), 64, 64, 12, blocked, 2))

def far_surface_w(w: World.World) -> U32:
  World.W{ring, m, ox, oz, q, np} = w
  pixel(Render.run_water(True{}, ring, 0, 1.5, 15.5, 64.5,
    0.9949874, (0.0 - 0.1 : F32), 0.0, Sky.rgb(100, 140, 180), Render.looks(), 0.48, 0.8, 0.36))

def main() -> IO(Unit):
  do IO<Unit>:
    axes(3n, 0)
    expect(F32.is_eq(Water.fresnel(True{}, 1.0), 0.02) && F32.is_eq(Water.fresnel(True{}, 0.0), 1.0)
      && (Water.fresnel(True{}, 0.5) > 0.142 : F32) && (Water.fresnel(True{}, 0.5) < 0.143 : F32)
      && F32.is_eq(Water.fresnel(False{}, 0.0), 0.02), "Fresnel grows toward grazing angles; off keeps normal reflectance")
    expect(near(Water.opacity(True{}, 0.0), 0.12, 0.0001) && near(Water.opacity(True{}, 1.0), 0.5171, 0.001)
      && (Water.opacity(True{}, 4.0) > 0.84 : F32) && (Water.opacity(True{}, 60.0) < 1.0 : F32)
      && near(Water.opacity(False{}, 4.0), 0.54, 0.0001) && (Water.opacity(False{}, 4.0) < Water.opacity(True{}, 4.0) : F32), "water is dense seen from the air and clear for an eye under it")
    expect(U32.is_eq(Water.ink_at(Water.colour(0.8), 0.8, 0.0), Water.colour(0.8))
      && U32.is_eq(Water.ink_at(Water.colour(0.8), 0.8, 6.0), Water.deep(0.8))
      && U32.is_eq(Water.ink_at(Water.colour(0.8), 0.8, 20.0), Water.deep(0.8))
      && (Water.deep(0.8) < Water.colour(0.8) : U32) && (Water.deep((0.0 - 0.5 : F32)) < Water.colour((0.0 - 0.5 : F32)) : U32),
      "the water's colour darkens with the depth under the surface, by day and by night")
    expect(near(Water.lit_path(3.0, (0.0 - 1.0 : F32)), 6.0, 0.0001) && near(Water.lit_path(3.0, 0.0), 3.0, 0.0001)
      && near(Water.lit_path(3.0, 0.5), 3.0, 0.0001), "the bed's light went down before it came up the ray")
    expect((Water.caustic(4000000, 60.4, 66.7, 0.0, (0.0 - 1.0 : F32), 0.9, 1.0) >= 0.5 : F32)
      && (Water.caustic(4000000, 60.4, 66.7, 0.0, (0.0 - 1.0 : F32), 0.9, 1.0) <= 2.1 : F32)
      && Bool.not(near(Water.caustic(4000000, 60.4, 66.7, 0.0, (0.0 - 1.0 : F32), 0.9, 1.0), Water.caustic(4000000, 61.1, 66.2, 0.0, (0.0 - 1.0 : F32), 0.9, 1.0), 0.001)),
      "the caustic brightens and darkens the bed within bounds, and differs from point to point")
    expect(F32.is_eq(Water.caustic(4000000, 60.4, 66.7, 6.0, (0.0 - 1.0 : F32), 0.9, 1.0), 1.0)
      && F32.is_eq(Water.caustic(4000000, 60.4, 66.7, 0.0, (0.0 - 1.0 : F32), (0.0 - 0.5 : F32), 1.0), 1.0)
      && F32.is_eq(Water.caustic(4000000, 60.4, 66.7, 0.0, 0.1, 0.9, 1.0), 1.0),
      "the caustic is gone six blocks down, at night, and looking along or up through the surface")
    expect(near(Water.caustic(Water.frame_base(4000000, 700), 60.4, 66.7, 1.0, (0.0 - 0.7 : F32), 0.9, 1.0),
        Water.caustic(Water.frame_base((4000000 + 128 : U32), 700), 59.4, 66.7, 1.0, (0.0 - 0.7 : F32), 0.9, 1.0), 0.0001)
      && near(Water.caustic(Water.frame_base(4000000, 700), 60.4, 66.7, 1.0, (0.0 - 0.7 : F32), 0.9, 1.0),
        Water.caustic(Water.frame_base((4000000 + 1 : U32), 700), 60.4, 65.7, 1.0, (0.0 - 0.7 : F32), 0.9, 1.0), 0.0001),
      "a ring shift along either axis cannot drag the caustic")
    expect(F32.is_eq(Water.caustic(4000000, 60.4, 66.7, 0.0, (0.0 - 1.0 : F32), 0.9, 0.0), 1.0)
      && near((Water.caustic(4000000, 60.4, 66.7, 0.0, (0.0 - 1.0 : F32), 0.9, 0.45) - 1.0 : F32),
        ((Water.caustic(4000000, 60.4, 66.7, 0.0, (0.0 - 1.0 : F32), 0.9, 0.9) - 1.0) / 2.0 : F32), 0.0001)
      && F32.is_eq(Water.caustic(4000000, 60.4, 66.7, 0.0, (0.0 - 1.0 : F32), 0.9, 0.9), Water.caustic(4000000, 60.4, 66.7, 0.0, (0.0 - 1.0 : F32), 0.9, 3.0))
      && F32.is_eq(Render.thickness(2.0, 1.5, (0.0 - 0.5 : F32)), 0.75) && F32.is_eq(Render.thickness(0.0, 0.2, (0.0 - 0.5 : F32)), 9.0),
      "the caustic grows with the water over the bed: none under no water, half under half a block, whole from nine tenths; a submerged eye's bed counts as deep")
    expect(partial_ok(True{}, 102, 64.5, 14.5, 64.5, 1, False{}, 4.1, 0.4, True{})
      && partial_ok(True{}, 255, 64.5, 14.5, 64.5, 1, False{}, 3.5, 1.0, True{})
      && partial_ok(True{}, 255, 64.5, 10.25, 62.5, 2, True{}, 1.5, 1.0, False{})
      && partial_ok(True{}, 102, 64.5, 10.25, 62.5, 2, True{}, 1.5, 1.0, False{})
      && partial_ok(True{}, 102, 64.5, 10.75, 62.5, 2, True{}, 0.0, 0.0, False{}),
      "the DDA's wet segment: a full cell's is what it was; a cell four tenths full starts down at its plane from above, is whole from the side under the plane, and is none over it")
    expect(partial_ok(False{}, 102, 63.5, 10.95, 64.5, 0, True{}, 0.0, 0.0, False{})
      && partial_ok(False{}, 255, 63.5, 10.95, 64.5, 0, True{}, 0.5, 1.0, False{})
      && partial_ok(False{}, 204, 63.5, 10.95, 64.5, 0, True{}, 0.6, 0.9, True{}),
      "a ray sloping down over a cell four tenths full leaves it before its plane and stays dry; one eight tenths full it meets at its plane, a top entry")
    expect(U32.is_eq(amount(World.pour(pool(1n, empty(), 64, 128), 64, 10, 64, 5), 64, 10, 64), 5)
      && U32.is_eq(amount(World.pour(pool(1n, empty(), 64, 128), 64, 10, 64, 300), 64, 10, 64), 255)
      && U32.is_ne(voxel_of(World.pour(pool(1n, empty(), 64, 128), 64, 10, 64, 0), 64, 10, 64), 8)
      && U32.is_eq(voxel_of(World.pour(pool(1n, empty(), 64, 128), 64, 10, 64, 3), 64, 10, 64), 8)
      && U32.is_eq(amount(World.pour(World.edit(empty(), 64, 64, 10, True{}, 2), 64, 10, 64, 5), 64, 10, 64), 0),
      "an amount poured reads back, is capped at 255, sets the mask's bit exactly when over zero, and a solid cell holds none")
    expect(U32.is_ne(surface_ray_w(Render.looks(), False{}, World.pour(surface_pool(), 64, 10, 64, 128)), surface_ray_w(Render.looks(), False{}, surface_pool()))
      && U32.is_eq(surface_ray_w(Render.looks(), False{}, World.pour(surface_pool(), 64, 10, 64, 255)), surface_ray_w(Render.looks(), False{}, surface_pool())),
      "a half-full top cell renders another surface; a full one the same")
    expect(F32.is_eq(Water.fresnel(True{}, (0.0 - 1.0 : F32)), 1.0)
      && F32.is_eq(Water.fresnel(True{}, 2.0), 0.02), "Fresnel clamps its angular input")
    expect(U32.is_ne(surface_ray(31457280, False{}, False{}), surface_ray(14680064, False{}, False{})), "reflection colours a real top entry at an edited water height")
    expect(U32.is_eq(surface_ray(31457280, True{}, False{}), surface_ray(14680064, True{}, False{}))
      && U32.is_eq(surface_ray(31457280, False{}, True{}), surface_ray(14680064, False{}, True{})), "reflection leaves submerged eyes and foreground banks unchanged")
    expect(U32.is_eq(emerged_ray(31457288, 0.8, 40), emerged_ray(14680072, 0.8, 40)), "upward water exit does not acquire a sky mirror")
    expect(U32.is_eq(surface_ray(Render.looks(), True{}, False{}), surface_ray((Render.looks() .&. U32.not(1048576) : U32), True{}, False{}))
      && U32.is_eq(surface_ray(Render.looks(), False{}, True{}), surface_ray((Render.looks() .&. U32.not(1048576) : U32), False{}, True{})),
      "ripples preserve submerged eyes and foreground banks")
    expect(U32.is_eq(far_surface_w(pool(88n, empty(), 40, 128)), Sky.rgb(100, 140, 180)), "air fog hides a distant reflecting water top")
    expect(U32.is_ne(Water.reflected_sky(134217728, 0.0, (0.0 - 1.0 : F32), 0.0, 0.0, 1.0, 0.0),
      Water.reflected_sky(0, 0.0, (0.0 - 1.0 : F32), 0.0, 0.0, 1.0, 0.0))
      && U32.is_ne(Water.reflected_sky(1073741824, 0.0, (0.0 - 1.0 : F32), 0.0, 0.0, (0.0 - 1.0 : F32), 0.0),
      Water.reflected_sky(0, 0.0, (0.0 - 1.0 : F32), 0.0, 0.0, (0.0 - 1.0 : F32), 0.0)), "reflected direction finds the sun and moon and respects their flags")
    expect(no_silhouette(6291464, 0.8) && no_silhouette(6291464, 0.0)
      && no_silhouette(6291464, (0.0 - 1.0 : F32)), "emerged ray hides distant silhouettes in daytime, twilight and night but keeps a nearby wall")
    expect(no_silhouette(2097160, 0.8) && no_silhouette(2153775112, 0.8), "background agrees with sky with water fog off and height fog on")
    expect(U32.is_eq(fog_ray(2097160, 2, 40), fog_ray(2097160, 2, 100))
      && U32.is_ne(fog_ray(2097160, 2, 40), Render.rgb(100, 140, 180)), "distance fog through a wet side exit reaches the same tinted sky")
    expect(U32.is_eq(fog_ray_w(6291464, World.edit(pool(88n, empty(), 40, 128), 56, 64, 10, True{}, 2)),
      Render.rgb(100, 140, 180)), "distant water stays hidden by foreground air fog")
    expect(U32.is_eq(fog_ray(6291464, 128, 40), Water.ink_at(Water.colour(0.8), 0.8, 1.5))
      && U32.is_eq(fog_ray(6291464, 128, 100), Water.ink_at(Water.colour(0.8), 0.8, 1.5))
      && (fog_ray(6291464, 128, 40) < Water.colour(0.8) : U32), "underwater wall and ray limit converge to the same fog colour, the water's at the eye's depth")
    expect(U32.is_ne(fog_ray(2097160, 128, 40), Water.ink_at(Water.colour(0.8), 0.8, 1.5)), "water fog has its own flag")
    expect(F32.is_eq(Water.light(0.0), 1.0) && near(Water.light(3.0), 0.575, 0.0001) && near(Water.light(6.0), 0.15, 0.0001)
      && near(Water.light(30.0), 0.15, 0.0001) && F32.is_eq(Water.drop(12.0), 0.0) && F32.is_eq(Water.drop(14.0), 0.0)
      && F32.is_eq(Water.drop(9.5), 2.5), "the light left under the surface: all of it at the level, a sixth six blocks down")
    expect(U32.is_eq(fog_ray(4194312, 128, 40), Render.rgb(100, 140, 180)), "water off keeps ordinary fog")
    expect(U32.is_eq(Water.fog(True{}, 123, 456, 456, 0.0, 0.0), 123)
      && U32.is_eq(Water.fog(True{}, 123, 456, 456, 0.0, 24.0), 456)
      && U32.is_eq(Water.fog(True{}, 123, 456, 456, 0.0, 80.0), 456)
      && U32.is_eq(Water.fog(False{}, 123, 456, 456, 0.0, 80.0), 123), "wet fog bounds and disable")
    expect(picked(Player.waim(World.edit(World.edit(empty(), 64, 64, 9, True{}, 2), 64, 64, 10, True{}, 8),
      64.5, 12.5, 64.5, 0.0, (0.0 - 1.0 : F32), 0.0)), "picking traverses water and finds the bottom")
    expect(Bool.not(shadow(Render.run_shadow(ring_of(World.put_col([0 : U32^18n], World.col_at(0, 64, 64), World.col6(0, 0, 0, 0, 0, 1024), 0)),
      0, 64.5, 12.5, 64.5, 0.0, (0.0 - 1.0 : F32), 0.0))), "water casts no solid shadow")
    expect(U32.is_eq(material(World.voxel(World.shift_xn(World.shift_xp(World.edit(empty(), 0, 64, 10, True{}, 8))), 0, 10, 64)), 8), "ring reload keeps edited water")
    expect(Bool.not(solid(World.wsolid(World.edit(empty(), 64, 64, 10, True{}, 8), 64.0, 10.0, 64.0))), "water is not a collision")
    expect(U32.is_eq(material(World.voxel(World.edit(empty(), 64, 64, 10, True{}, 8), 64, 10, 64)), 8), "water material reads back")
    expect(placed(Player.edit_world(True{}, (64 * 4096 + 10 * 128 + 64 : U32), True{}, 6,
      (World.edit(empty(), 64, 64, 10, True{}, 8), [0n, 0n, 0n, 0n, 0n, 0n, 1n, 0n]))), "placing spends one brick and displaces water")
    expect(same_masks(restored(Save.text(fixture(World.edit(empty(), 64, 64, 10, True{}, 8)))), 0, 1024), "save restores the water mask")
    expect(same_masks(restored(Save.text(fixture(World.edit(World.edit(empty(), 64, 64, 10, True{}, 8), 64, 64, 10, True{}, 6)))), 1024, 0), "save preserves displacement")
    expect(same_masks(col(World.get_col(ring_of(World.put_col([0 : U32^18n], World.col_at(0, 64, 64), World.col6(256, 1, 2, 3, 4, 3584), 0)), World.col_at(0, 64, 64))), 256, 3584), "column storage keeps both masks")
    expect(U32.is_eq(Save.water_of([], "0,0", 0), World.flood(World.terrain(0, 0), 0)), "old saves restore natural water")
    expect(U32.is_eq(Save.water_of(["0"], "0,0", 0), 0), "explicit dry edits stay dry")
    expect(same_levels(Save.levels_of(["1056"], 1056), World.Levels{0, 65280, 16711680, 0, 0, 0, 0, 0})
      && same_levels(Save.levels_of([], 1056), World.Levels{0, 65280, 16711680, 0, 0, 0, 0, 0})
      && same_levels(Save.levels_of(["1056", "1", "2", "3", "4"], 1056), World.Levels{32, 0, 64, 0, 96, 0, 128, 0})
      && same_levels(Save.levels_of(["1056", "8", "0", "0", "0"], 1056), World.Levels{255, 0, 0, 0, 0, 0, 0, 0})
      && same_levels(Save.levels_of(["1056", "1", "2", "3", "4", "5", "6", "7", "8"], 1056), World.Levels{1, 2, 3, 4, 5, 6, 7, 8}),
      "a six-word column loads full where it is wet; a ten-word one's nibbles widen to bytes, an eighth to 32 and eight to 255; a fourteen-word one keeps its bytes")
    expect(same_levels(World.levels(restored(Save.text(fixture(World.pour(surface_pool(), 64, 10, 64, 5))))), World.Levels{0, 0, 327680, 0, 0, 0, 0, 0}),
      "a poured amount survives a save and a load")
    expect(U32.is_eq(Save.water_of(["1024"], "0,0", 1024), 0), "loaded solids displace overlapping water")
