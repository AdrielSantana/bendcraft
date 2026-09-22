import Base
import ./util.bend as Util
import ./world.bend as World
import ./flow.bend as Flow
import ./render.bend as Render
import ./day.bend as Day
import ./inventory.bend as Inventory

# THE PLAYER: the game state, the events, the tick, the edits.
#
#   W A S D  move   space  jump   arrows  look   1-8  choose a block
#   P  save   Esc  quit (and save)
#   mouse: drag to look, left click breaks, right click places (or J / L)

type Game is Type:
  G{w: World.World, px: F32, py: F32, pz: F32, yaw: F32, pit: F32, vy: F32,
    held: U32, edge: U32, mx: U32, my: U32, sel: U32, res: U32, clock: U32, bag: List<&2, Nat>}

# the render's size, width above height in one word; 512 x 512 by default
def res_of(+rw: U32, +rh: U32) -> U32:
  (rw * 65536 + rh : U32)

def res512() -> U32:
  res_of(512, 512)

def view_fin(px: F32, py: F32, pz: F32, yaw: F32, pit: F32, vy: F32,
             held: U32, edge: U32, mx: U32, my: U32, sel: U32, res: U32, clock: U32, bag: List<&2, Nat>, m: Map<&2, World.Col>, ox: U32, oz: U32, q: List<&2, U32>, np: U32, made: U32, gone: U32,
             r: Array<U32> & Image) -> Game & Image:
  (ring, img) = r
  (G{World.W{ring, m, ox, oz, q, np, made, gone}, px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag}, img)

def view_w(+px: F32, +py: F32, +pz: F32, +yaw: F32, +pit: F32, vy: F32,
           held: U32, edge: U32, mx: U32, my: U32, +sel: U32, +res: U32, +clock: U32, +bag: List<&2, Nat>, +fl: U32, +fps: U32, more: U32, w: World.World) -> Game & Image:
  World.W{ring, m, +ox, +oz, q, +np, made, gone} = w
  +rw = (res / 65536 : U32)
  +rh = (res % 65536 : U32)
  view_fin(px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag, m, ox, oz, q, np, made, gone,
           Render.frame(Render.camera(px, py, pz, yaw, pit, Render.stat_base((ox * 128 + oz : U32), fps), Render.with_partial(more, (np > 0 : U32)), Inventory.hud_lo(sel, bag), Render.stat_items(Inventory.hud_hi(bag), fps), fl, rw, rh, clock), ring, rw, rh))

# the frame with the render's flags (Render.Cam), all looks on for the game
# `more` holds the looks the flags word has no room for (Render.looks_base)
def view_more(g: Game, +fl: U32, fps: U32, more: U32) -> Game & Image:
  G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag} = g
  view_w(px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag, fl, fps, more, w)

def view_info(g: Game, +fl: U32, fps: U32) -> Game & Image:
  view_more(g, fl, fps, Render.looks_base())

def view_with(g: Game, fl: U32) -> Game & Image:
  view_info(g, fl, 0)

def view(g: Game) -> Game & Image:
  view_with(g, Render.looks())

# the game's frame with the readout in its corner; zeros hide it
def view_stat(g: Game, +ms10: U32, +fps: U32) -> Game & Image:
  view_info(g, Render.stat_flags(Render.looks(), ms10, fps), fps)

# Time advances at the IO edge; a physics step has no wall-clock dependency.
# The water flows on the same clock (Flow.advance).
def advance(g: Game, +ms: U32) -> Game:
  G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, +clock, bag} = g
  G{Flow.advance(w, clock, ms), px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, Day.advance(clock, ms), bag}

# ---------- input ----------
# Keys are a bitmask in `held` (w a s d 1..8, arrows 16..128, p 256, f 512, j l
# 1024 2048, Esc 4096, space 8192) and the edge of a press in `edge`. The mouse keeps
# its last place in `mx`, `my` and two bits above the keys: 16384 while the
# left button is down, 32768 once that press has dragged. A drag looks, a
# left click (press and release without a drag) breaks, a right click places.

def kbit(+c: U32, +code: U32, +bit: U32) -> U32:
  Bool.pick(U32, U32.is_eq(c, code), bit, 0)

def kmask(+c: U32) -> U32:
  (kbit(c, 119, 1) .|. kbit(c, 97, 2) .|. kbit(c, 115, 4) .|. kbit(c, 100, 8)
    .|. kbit(c, 63232, 16) .|. kbit(c, 63233, 32)
    .|. kbit(c, 63234, 64) .|. kbit(c, 63235, 128)
    .|. kbit(c, 106, 1024) .|. kbit(c, 108, 2048) .|. kbit(c, 112, 256) .|. kbit(c, 102, 512)
    .|. kbit(c, 27, 4096) .|. kbit(c, 32, 8192) : U32)

def key_apply(down: Bool, w: World.World, px: F32, py: F32, pz: F32, yaw: F32, pit: F32, vy: F32,
              +held: U32, edge: U32, mx: U32, my: U32, sel: U32, res: U32, clock: U32, bag: List<&2, Nat>, +m: U32) -> Game:
  match down:
    case True{}:
      G{w, px, py, pz, yaw, pit, vy, (held .|. m : U32),
        (edge .|. (m .&. U32.not(held)) : U32), mx, my, sel, res, clock, bag}
    case False{}:
      G{w, px, py, pz, yaw, pit, vy, (held .&. U32.not(m) : U32), edge, mx, my, sel, res, clock, bag}

# the digits 1..8 choose the block to place, 9 the spring (a source of water)
def on_key(g: Game, +code: U32, +down: Bool) -> Game:
  G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my, +sel, res, clock, bag} = g
  +lower = Bool.pick(U32, ((code >= 65) && (code <= 90) : U32), (code + 32 : U32), code)
  +digit = down && (code >= 49 : U32) && (code <= 57 : U32)
  key_apply(down, w, px, py, pz, yaw, pit, vy, held, edge, mx, my,
            Bool.pick(U32, digit, (code - 49 : U32), sel), res, clock, bag, kmask(lower))

# button 0 is the left one, 1 the right one, on both windows
def on_button(g: Game, +x: U32, +y: U32, +b: U32, +down: Bool) -> Game:
  G{w, px, py, pz, yaw, pit, vy, +held, +edge, mx, my, sel, res, clock, bag} = g
  +press = U32.is_eq(b, 0) && down
  +release = U32.is_eq(b, 0) && Bool.not(down)
  +click = release && U32.is_eq((held .&. 49152 : U32), 16384)
  +place = U32.is_eq(b, 1) && down
  +held1 = Bool.pick(U32, press, ((held .|. 16384) .&. U32.not(32768) : U32), held)
  G{w, px, py, pz, yaw, pit, vy,
    Bool.pick(U32, release, (held1 .&. U32.not(16384) : U32), held1),
    (edge .|. Bool.pick(U32, click, 1024, 0) .|. Bool.pick(U32, place, 2048, 0) : U32),
    Bool.pick(U32, press, x, mx), Bool.pick(U32, press, y, my), sel, res, clock, bag}

# a drag turns the camera, 0.0045 rad per pixel; y grows downwards
def on_move(g: Game, +x: U32, +y: U32) -> Game:
  G{w, px, py, pz, +yaw, +pit, vy, +held, edge, +mx, +my, sel, res, clock, bag} = g
  +drag = Util.on(held, 16384)
  +dx = (Util.u2f(x) - Util.u2f(mx) : F32)
  +dy = (Util.u2f(y) - Util.u2f(my) : F32)
  +far = ((Util.absf(dx) + Util.absf(dy) : F32) > 2.0 : F32)
  G{w, px, py, pz,
    Bool.pick(F32, drag, (yaw + 0.0045 * dx : F32), yaw),
    Bool.pick(F32, drag, F32.clamp((pit - 0.0045 * dy : F32), (0.0 - 1.45 : F32), 1.45), pit),
    vy,
    Bool.pick(U32, drag && far, (held .|. 32768 : U32), held),
    edge,
    Bool.pick(U32, drag, x, mx), Bool.pick(U32, drag, y, my), sel, res, clock, bag}

# whether a key of the mask went down in the events just fed (main.bend
# asks for F, the readout's switch, before the tick clears the edges)
def pressed(g: Game, +bit: U32) -> Game & Bool:
  G{w, px, py, pz, yaw, pit, vy, held, +edge, mx, my, sel, res, clock, bag} = g
  (G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag}, Util.on(edge, bit))

def quit_now(g: Game) -> Game:
  G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag} = g
  G{w, px, py, pz, yaw, pit, vy, held, (edge .|. 4096 : U32), mx, my, sel, res, clock, bag}

def feed(evs: List<Event>, g: Game) -> Game:
  match evs:
    case Nil{}:
      g
    case Con{Key{code, down}, rest}:
      feed(rest, on_key(g, code, down))
    case Con{Mouse{x, y, b, down}, rest}:
      feed(rest, on_button(g, x, y, b, down))
    case Con{Move{x, y}, rest}:
      feed(rest, on_move(g, x, y))
    case Con{Close{}, rest}:
      feed(rest, quit_now(g))

# ---------- picking the block under the crosshair ----------
# A voxel is a word, 1 + (lx * 32 + y) * 128 + lz, 0 for none; the pick
# returns the one hit and the one before it.

def pk_u(+x: U32, +y: U32, +z: U32) -> U32:
  ((x * 32 + y) * 128 + z : U32)

def pk(+x: F32, +y: F32, +z: F32) -> U32:
  pk_u(Util.f2u(x), Util.f2u(y), Util.f2u(z))

def pick_end(+prev: U32, +hit: U32, r: Array<U32> & Bool) -> Array<U32> & (U32 & U32):
  (w, s) = r
  (w, (prev, hit))

def pick(fuel: Nat, +base: U32,
         +vx: F32, +vy: F32, +vz: F32,
         +sx: F32, +sy: F32, +sz: F32,
         +mx: F32, +my: F32, +mz: F32,
         +ex: F32, +ey: F32, +ez: F32,
         +last: U32, +prev: U32, +hit: U32, r: Array<U32> & Bool) -> Array<U32> & (U32 & U32):
  match fuel:
    case 0n:
      pick_end(prev, hit, r)
    case 1n+f:
      (w, sol) = r
      +take = sol && (hit < 1 : U32)
      +here = Bool.pick(U32, World.inside(vx, vy, vz), (1 + pk(vx, vy, vz) : U32), 0)
      +ux = (mx < my : F32) && (mx < mz : F32)
      +uy = Bool.pick(Bool, ux, False{}, (my < mz : F32))
      +nvx = Bool.pick(F32, ux, (vx + sx : F32), vx)
      +nvy = Bool.pick(F32, uy, (vy + sy : F32), vy)
      +nvz = Bool.pick(F32, ux, vz, Bool.pick(F32, uy, vz, (vz + sz : F32)))
      nmx = Bool.pick(F32, ux, (mx + ex : F32), mx)
      nmy = Bool.pick(F32, uy, (my + ey : F32), my)
      nmz = Bool.pick(F32, ux, mz, Bool.pick(F32, uy, mz, (mz + ez : F32)))
      pick(f, base, nvx, nvy, nvz, sx, sy, sz, nmx, nmy, nmz, ex, ey, ez, here,
           Bool.pick(U32, take, last, prev), Bool.pick(U32, take, here, hit),
           World.solid(w, base, nvx, nvy, nvz))

def aim(w: Array<U32>, +base: U32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32) -> Array<U32> & (U32 & U32):
  +vx = Util.floorf(F32.max(ox, 0.0))
  +vy = Util.floorf(F32.max(oy, 0.0))
  +vz = Util.floorf(F32.max(oz, 0.0))
  +px = (dx > 0.0 : F32)
  +py = (dy > 0.0 : F32)
  +pz = (dz > 0.0 : F32)
  +ax = F32.max(Util.absf(dx), 0.00001)
  +ay = F32.max(Util.absf(dy), 0.00001)
  +az = F32.max(Util.absf(dz), 0.00001)
  +nx = Bool.pick(F32, px, (vx + 1.0 - ox : F32), (ox - vx : F32))
  +ny = Bool.pick(F32, py, (vy + 1.0 - oy : F32), (oy - vy : F32))
  +nz = Bool.pick(F32, pz, (vz + 1.0 - oz : F32), (oz - vz : F32))
  pick(40n, base, vx, vy, vz,
       Bool.pick(F32, px, 1.0, (0.0 - 1.0 : F32)),
       Bool.pick(F32, py, 1.0, (0.0 - 1.0 : F32)),
       Bool.pick(F32, pz, 1.0, (0.0 - 1.0 : F32)),
       (nx / ax : F32), (ny / ay : F32), (nz / az : F32),
       (1.0 / ax : F32), (1.0 / ay : F32), (1.0 / az : F32),
       0, 0, 0, World.solid(w, base, vx, vy, vz))

def waim_fin(m: Map<&2, World.Col>, ox: U32, oz: U32, q: List<&2, U32>, np: U32, made: U32, gone: U32, r: Array<U32> & (U32 & U32)) -> World.World & (U32 & U32):
  (ring, ph) = r
  (World.W{ring, m, ox, oz, q, np, made, gone}, ph)

def waim(w: World.World, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32) -> World.World & (U32 & U32):
  World.W{ring, m, +cx, +cz, q, np, made, gone} = w
  waim_fin(m, cx, cz, q, np, made, gone, aim(ring, (cx * 128 + cz : U32), ox, oy, oz, dx, dy, dz))

# unpack: word -> lx, y, lz
def ix_x(+i: U32) -> U32: (i / 4096 : U32)
def ix_y(+i: U32) -> U32: (i / 128 % 32 : U32)
def ix_z(+i: U32) -> U32: (i % 128 : U32)

def write_block(act: Bool, w: World.World, +idx: U32, set: Bool, +what: U32) -> World.World:
  match act:
    case False{}:
      w
    case True{}:
      World.edit(w, ix_x(idx), ix_z(idx), ix_y(idx), set, what)

# The receipt changes the ring and the count together. A break credits the
# actual voxel type, and a place can only debit an empty cell's chosen type.
def edit_commit(w: World.World, idx: U32, set: Bool, what: U32, e: Inventory.Edit) -> World.World & List<&2, Nat>:
  Inventory.Edit{bag, changed} = e
  (write_block(changed, w, idx, set, what), bag)

# the spring (9) places a source of water and spends nothing: the bag is
# the same and the write goes ahead, into air or water, never a solid
def receipt(spring: Bool, +set: Bool, +what: U32, +actual: U32, bag: List<&2, Nat>, solid: Bool) -> Inventory.Edit:
  match spring:
    case True{}:
      Inventory.Edit{bag, True{}}
    case False{}:
      Inventory.edit(bag, U32.to_nat(U32.min(Bool.pick(U32, set, what, actual), 8)), set, solid)

def edit_type(+set: Bool, +what: U32, idx: U32, bag: List<&2, Nat>, +solid: Bool, r: World.World & U32) -> World.World & List<&2, Nat>:
  (w, actual) = r
  edit_commit(w, idx, set, Bool.pick(U32, set, what, 0),
    receipt(set && U32.is_eq(what, 9) && Bool.not(solid), set, what, actual, bag, solid))

def edit_solid(set: Bool, what: U32, +idx: U32, bag: List<&2, Nat>, r: World.World & Bool) -> World.World & List<&2, Nat>:
  (w, solid) = r
  edit_type(set, what, idx, bag, solid, World.voxel(w, ix_x(idx), ix_y(idx), ix_z(idx)))

def edit_if(act: Bool, +idx: U32, set: Bool, what: U32, r: World.World & List<&2, Nat>) -> World.World & List<&2, Nat>:
  match act:
    case False{}:
      r
    case True{}:
      (w, bag) = r
      edit_solid(set, what, idx, bag, World.wsolid(w, Util.u2f(ix_x(idx)), Util.u2f(ix_y(idx)), Util.u2f(ix_z(idx))))

def edit_world(act: Bool, +idx: U32, set: Bool, what: U32, r: World.World & List<&2, Nat>) -> World.World & List<&2, Nat>:
  edit_if(act && (idx < 524288 : U32), idx, set, what, r)

# ---------- one tick ----------
# The player is 1.8 blocks tall with the eye at 1.6, so they stand in the
# block of `py - 1.6` and the one of `py + 0.2`. Walking tests those two
# per axis and stops at a wall (the feet test sits 0.05 up, so the block
# under the feet never counts). Gravity pulls `vy`; landing snaps the feet
# onto the block; space pushes off it. Then the world's corner follows
# (step_bump), so the player is back in local column 64, and the
# crosshair's block is found. A block is never placed on the player.
# Every test reads the world, so the tick is a chain that passes it along.

def eye() -> F32: 1.6

def blocked_fin(feet: Bool, r: World.World & Bool) -> World.World & Bool:
  (w, head) = r
  (w, feet || head)

def blocked_head(+x: F32, +y: F32, +z: F32, r: World.World & Bool) -> World.World & Bool:
  (w, feet) = r
  blocked_fin(feet, World.wsolid(w, x, (y + 0.2 : F32), z))

def blocked(w: World.World, +x: F32, +y: F32, +z: F32) -> World.World & Bool:
  blocked_head(x, y, z, World.wsolid(w, x, (y - 1.55 : F32), z))

def ax2(+held: U32, +negbit: U32, +posbit: U32) -> F32:
  (Bool.pick(F32, Util.on(held, posbit), 1.0, 0.0)
   - Bool.pick(F32, Util.on(held, negbit), 1.0, 0.0) : F32)

# Save and quit reach the IO edge after the edit; action edges are consumed.
def io_edges(edge: U32) -> U32:
  (edge .&. 4352 : U32)

def step_done(px: F32, py: F32, pz: F32, vy: F32, yaw: F32, pit: F32,
              held: U32, edge: U32, mx: U32, my: U32, sel: U32, res: U32, clock: U32,
              r: World.World & List<&2, Nat>) -> Game:
  (w, bag) = r
  G{w, px, py, pz, yaw, pit, vy, held, io_edges(edge), mx, my, sel, res, clock, bag}

def step_edit(+npx: F32, +npy: F32, +npz: F32, nvy: F32, nyaw: F32, npit: F32,
              held: U32, +edge: U32, mx: U32, my: U32, +sel: U32, res: U32, clock: U32, bag: List<&2, Nat>, w: World.World, ph: U32 & U32) -> Game:
  (+prev, +hit) = ph
  +got = (hit > 0 : U32)
  +tgt = (prev - 1 : U32)
  +onme = U32.is_eq(ix_x(tgt), Util.f2u(npx)) && U32.is_eq(ix_z(tgt), Util.f2u(npz))
    && (ix_y(tgt) >= Util.f2u((npy - eye() : F32)) : U32) && (ix_y(tgt) <= Util.f2u((npy + 0.2 : F32)) : U32)
  +brk = got && Util.on(edge, 1024)
  +put = got && (prev > 0 : U32) && Util.on(edge, 2048) && Bool.not(onme)
  step_done(npx, npy, npz, nvy, nyaw, npit, held, edge, mx, my, sel, res, clock,
    edit_world(put, tgt, True{}, sel, edit_world(brk, (hit - 1 : U32), False{}, 0, (w, bag))))

def step_aim(+npx: F32, +npy: F32, +npz: F32, nvy: F32, nyaw: F32, npit: F32,
             held: U32, edge: U32, mx: U32, my: U32, sel: U32, res: U32, clock: U32, bag: List<&2, Nat>, r: World.World & (U32 & U32)) -> Game:
  (w, ph) = r
  step_edit(npx, npy, npz, nvy, nyaw, npit, held, edge, mx, my, sel, res, clock, bag, w, ph)

def step_bump(+npx: F32, +py: F32, +npz: F32, +ty: F32, +vy1: F32, +land: Bool, bank: Bool,
              +nyaw: F32, +npit: F32, +held: U32, edge: U32, mx: U32, my: U32, sel: U32, res: U32, clock: U32, bag: List<&2, Nat>,
              r: World.World & Bool) -> Game:
  (w, above) = r
  +bump = (vy1 > 0.0 : F32) && above
  +feet = (ty - eye() : F32)
  +npy = F32.clamp(Bool.pick(F32, land, (Util.floorf(feet) + 1.0 + eye() : F32),
                             Bool.pick(F32, bump, py, ty)), eye(), 31.5)
  +nvy = Bool.pick(F32, (land && Util.on(held, 8192)) || bank, 0.2,
                   Bool.pick(F32, land || bump, 0.0, vy1))
  +cx = Util.f2u(npx)
  +cz = Util.f2u(npz)
  +lx = (npx - Util.u2f(cx) + 64.0 : F32)
  +lz = (npz - Util.u2f(cz) + 64.0 : F32)
  step_aim(lx, npy, lz, nvy, nyaw, npit, held, edge, mx, my, sel, res, clock, bag,
           waim(World.follow(U32.to_nat(Bool.pick(U32, (cz > 64 : U32), (cz - 64 : U32), (64 - cz : U32))), False{}, (cz > 64 : U32),
                World.follow(U32.to_nat(Bool.pick(U32, (cx > 64 : U32), (cx - 64 : U32), (64 - cx : U32))), True{}, (cx > 64 : U32), w)),
                lx, npy, lz, Render.look_x(nyaw, npit), Render.look_y(npit), Render.look_z(nyaw, npit)))

def step_land(+npx: F32, +py: F32, +npz: F32, +ty: F32, +vy1: F32, bank: Bool,
              nyaw: F32, npit: F32, held: U32, edge: U32, mx: U32, my: U32, sel: U32, res: U32, clock: U32, bag: List<&2, Nat>,
              r: World.World & Bool) -> Game:
  (w, below) = r
  step_bump(npx, py, npz, ty, vy1, (vy1 < 0.0 : F32) && below, bank, nyaw, npit, held, edge, mx, my, sel, res, clock, bag,
            World.wsolid(w, npx, (ty + 0.2 : F32), npz))

def step_z(+npx: F32, +py: F32, +pz: F32, +tz: F32, +vy1: F32, swim: Bool, bx: Bool,
           nyaw: F32, npit: F32, held: U32, edge: U32, mx: U32, my: U32, sel: U32, res: U32, clock: U32, bag: List<&2, Nat>,
           r: World.World & Bool) -> Game:
  (w, +bz) = r
  +npz = Bool.pick(F32, bz, pz, tz)
  +ty = (py + vy1 : F32)
  step_land(npx, py, npz, ty, vy1, swim && (bx || bz), nyaw, npit, held, edge, mx, my, sel, res, clock, bag,
            World.wsolid(w, npx, (ty - eye() : F32), npz))

def step_x(+px: F32, +py: F32, +pz: F32, +tx: F32, +tz: F32, +vy1: F32, swim: Bool,
           nyaw: F32, npit: F32, held: U32, edge: U32, mx: U32, my: U32, sel: U32, res: U32, clock: U32, bag: List<&2, Nat>,
           r: World.World & Bool) -> Game:
  (w, +bx) = r
  +npx = Bool.pick(F32, bx, px, tx)
  step_z(npx, py, pz, tz, vy1, swim, bx, nyaw, npit, held, edge, mx, my, sel, res, clock, bag, blocked(w, npx, py, tz))

# In water at the waist the player swims: the water's lift nearly balances
# gravity, so they sink slowly and the water drags; space swims up, to a
# bob at the surface with the eye over it; a stroke is half a step; and a
# wall met swimming is a bank: the player pushes off it as off the ground,
# a push the water's clamp holds down until the waist is out, where it
# carries them over the bank. Out of water, the walk and the fall.
def step_swim(+px: F32, +py: F32, +pz: F32, yaw: F32, pit: F32, +vy: F32, +held: U32, edge: U32, mx: U32, my: U32, sel: U32, res: U32, clock: U32, bag: List<&2, Nat>,
              r: World.World & Bool) -> Game:
  (w, +swim) = r
  +nyaw = (yaw + 0.055 * ax2(held, 64, 128) : F32)
  +npit = F32.clamp((pit + 0.045 * ax2(held, 32, 16) : F32), (0.0 - 1.45 : F32), 1.45)
  +sy = F32.sin(nyaw)
  +cy = F32.cos(nyaw)
  +fw = ax2(held, 4, 1)
  +st = ax2(held, 2, 8)
  +stride = Bool.pick(F32, swim, 0.08, 0.16)
  +tx = (px + stride * (fw * sy + st * cy) : F32)
  +tz = (pz + stride * (fw * cy - st * sy) : F32)
  +vy1 = Bool.pick(F32, swim,
    F32.clamp((vy * 0.85 + Bool.pick(F32, Util.on(held, 8192), 0.008, (0.0 - 0.003 : F32)) : F32), (0.0 - 0.08 : F32), 0.06),
    F32.max((vy - 0.012 : F32), (0.0 - 0.9 : F32)))
  step_x(px, py, pz, tx, tz, vy1, swim, nyaw, npit, held, edge, mx, my, sel, res, clock, bag, blocked(w, tx, py, pz))

def step(g: Game) -> Game:
  G{w, +px, +py, +pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag} = g
  step_swim(px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag, World.wet_at(w, px, (py - 0.8 : F32), pz))

# the world's corner starts far from zero, so walking west never wraps it
def start_at(+res: U32) -> Game:
  G{World.load_all(128n, World.W{[0 : U32^18n], Map.new(&2, World.Col), 1048512, 1048512, Nil{}, 0, 0, 0}, 1048512, 1048512),
    64.5, 30.0, 64.5, 0.0, (0.0 - 0.55 : F32), 0.0, 0, 0, 0, 0, 0, res, Day.morning(), Inventory.empty()}

def start() -> Game:
  start_at(res512())
