import Base
import ./util.bend as Util
import ./world.bend as World
import ./flow.bend as Flow
import ./render.bend as Render
import ./day.bend as Day
import ./inventory.bend as Inventory
import ./torch.bend as Torch

# THE PLAYER: the game state, the events, the tick, the edits.
#
#   W A S D  move   space  jump   arrows  look   1-8  choose a block   9  the bucket
#   0  the torch   P  save   Esc  quit (and save)
#   mouse: look (the window holds it), left click breaks, right click places (or J / L),
#   the wheel chooses

type Game is Type:
  G{w: World.World, px: F32, py: F32, pz: F32, yaw: F32, pit: F32, vy: F32,
    held: U32, edge: U32, sel: U32, res: U32, clock: U32, bag: List<&2, Nat>}

# the render's size, width above height in one word; 512 x 512 by default
def res_of(+rw: U32, +rh: U32) -> U32:
  (rw * 65536 + rh : U32)

def res512() -> U32:
  res_of(512, 512)

# Time advances at the IO edge; a physics step has no wall-clock dependency.
# The water flows on the same clock (Flow.advance).
def advance(g: Game, +ms: U32) -> Game:
  G{w, px, py, pz, yaw, pit, vy, held, edge, sel, res, +clock, bag} = g
  G{Flow.advance(w, clock, ms), px, py, pz, yaw, pit, vy, held, edge, sel, res, Day.advance(clock, ms), bag}

# ---------- input ----------
# Keys are a bitmask in `held` (w a s d 1..8, arrows 16..128, p 256, f 512, j l
# 1024 2048, Esc 4096, space 8192) and the edge of a press in `edge`. The
# window holds the mouse (main.bend), so its motion comes as looks; a left
# press breaks, a right press places.

def kbit(+c: U32, +code: U32, +bit: U32) -> U32:
  Bool.pick(U32, U32.is_eq(c, code), bit, 0)

def kmask(+c: U32) -> U32:
  (kbit(c, 119, 1) .|. kbit(c, 97, 2) .|. kbit(c, 115, 4) .|. kbit(c, 100, 8)
    .|. kbit(c, 63232, 16) .|. kbit(c, 63233, 32)
    .|. kbit(c, 63234, 64) .|. kbit(c, 63235, 128)
    .|. kbit(c, 106, 1024) .|. kbit(c, 108, 2048) .|. kbit(c, 112, 256) .|. kbit(c, 102, 512)
    .|. kbit(c, 27, 4096) .|. kbit(c, 32, 8192) : U32)

def key_apply(down: Bool, w: World.World, px: F32, py: F32, pz: F32, yaw: F32, pit: F32, vy: F32,
              +held: U32, edge: U32, sel: U32, res: U32, clock: U32, bag: List<&2, Nat>, +m: U32) -> Game:
  match down:
    case True{}:
      G{w, px, py, pz, yaw, pit, vy, (held .|. m : U32),
        (edge .|. (m .&. U32.not(held)) : U32), sel, res, clock, bag}
    case False{}:
      G{w, px, py, pz, yaw, pit, vy, (held .&. U32.not(m) : U32), edge, sel, res, clock, bag}

# the digits 1..8 choose the block to place, 9 the bucket, 0 the torch
def on_key(g: Game, +code: U32, +down: Bool) -> Game:
  G{w, px, py, pz, yaw, pit, vy, held, edge, +sel, res, clock, bag} = g
  +lower = Bool.pick(U32, ((code >= 65) && (code <= 90) : U32), (code + 32 : U32), code)
  +digit = down && (code >= 48 : U32) && (code <= 57 : U32)
  key_apply(down, w, px, py, pz, yaw, pit, vy, held, edge,
            Bool.pick(U32, digit, ((code - 39) % 10 : U32), sel), res, clock, bag, kmask(lower))

# button 0 is the left one, 1 the right one, on both windows
def on_button(g: Game, +b: U32, +down: Bool) -> Game:
  G{w, px, py, pz, yaw, pit, vy, held, edge, sel, res, clock, bag} = g
  G{w, px, py, pz, yaw, pit, vy, held,
    (edge .|. Bool.pick(U32, U32.is_eq(b, 0) && down, 1024, 0) .|. Bool.pick(U32, U32.is_eq(b, 1) && down, 2048, 0) : U32),
    sel, res, clock, bag}

# the wheel moves the choice d slots on, around the ten
def roll(+sel: U32, +d: U32) -> U32:
  ((sel + d) % 10 : U32)

# a scroll up chooses the slot before, down the slot after, one an event
# whatever its size, as a trackpad's points would spin the hotbar
def on_scroll(g: Game, +dy: F32) -> Game:
  G{w, px, py, pz, yaw, pit, vy, held, edge, sel, res, clock, bag} = g
  G{w, px, py, pz, yaw, pit, vy, held, edge,
    roll(sel, Bool.pick(U32, (dy > 0.0 : F32), 9, Bool.pick(U32, (dy < 0.0 : F32), 1, 0))), res, clock, bag}

# the mouse turns the camera, 0.0045 rad a point; y grows downwards
def on_look(g: Game, dx: F32, dy: F32) -> Game:
  G{w, px, py, pz, yaw, pit, vy, held, edge, sel, res, clock, bag} = g
  G{w, px, py, pz, (yaw + 0.0045 * dx : F32), F32.clamp((pit - 0.0045 * dy : F32), (0.0 - 1.45 : F32), 1.45),
    vy, held, edge, sel, res, clock, bag}

# whether a key of the mask went down in the events just fed (main.bend
# asks for F, the readout's switch, before the tick clears the edges)
def pressed(g: Game, +bit: U32) -> Game & Bool:
  G{w, px, py, pz, yaw, pit, vy, held, +edge, sel, res, clock, bag} = g
  (G{w, px, py, pz, yaw, pit, vy, held, edge, sel, res, clock, bag}, Util.on(edge, bit))

def quit_now(g: Game) -> Game:
  G{w, px, py, pz, yaw, pit, vy, held, edge, sel, res, clock, bag} = g
  G{w, px, py, pz, yaw, pit, vy, held, (edge .|. 4096 : U32), sel, res, clock, bag}

def feed(evs: List<Event>, g: Game) -> Game:
  match evs:
    case Nil{}:
      g
    case Con{Key{code, down}, rest}:
      feed(rest, on_key(g, code, down))
    case Con{Mouse{x, y, b, down}, rest}:
      feed(rest, on_button(g, b, down))
    case Con{Look{dx, dy}, rest}:
      feed(rest, on_look(g, dx, dy))
    case Con{Scroll{x, y, dx, dy}, rest}:
      feed(rest, on_scroll(g, dy))
    case Con{Close{}, rest}:
      feed(rest, quit_now(g))
    case Con{e, rest}:
      feed(rest, g)

# ---------- picking the block under the crosshair ----------
# The eye's walk, 40 steps (Render.walk_from), which meets a torch's stick
# and no leaf's hole: the block hit and the air cell before it
# (Render.face), as words 1 + (lx * 32 + y) * 128 + lz, 0 for none; a
# cell past the window is none, so nothing is placed there, and neither
# is anything against a torch, met inside its cell.

def pk_u(+x: U32, +y: U32, +z: U32) -> U32:
  ((x * 32 + y) * 128 + z : U32)

def pk(+x: F32, +y: F32, +z: F32) -> U32:
  pk_u(Util.f2u(x), Util.f2u(y), Util.f2u(z))

def cell(+x: F32, +y: F32, +z: F32) -> U32:
  Bool.pick(U32, World.inside(x, y, z), (1 + pk(x, y, z) : U32), 0)

def aim_face(got: Bool, w: Array<U32>, fc: Render.Face) -> Array<U32> & (U32 & U32):
  match got:
    case False{}:
      (w, (0, 0))
    case True{}:
      Render.Face{px, py, pz, ax, ay, hx, hy, hz, cx, cy, cz, da, u, wf, tone} = fc
      (w, (cell(cx, cy, cz), cell(hx, hy, hz)))

def aim_hit(torch: Bool, +c: U32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, +t: F32, w: Array<U32>) -> Array<U32> & (U32 & U32):
  match torch:
    case True{}:
      (w, (0, cell((ox + dx * t : F32), (oy + dy * t : F32), (oz + dz * t : F32))))
    case False{}:
      aim_face((c > 0 : U32), w, Render.face((c - 1 : U32), ox, oy, oz, dx, dy, dz, t))

def aim_fin(+ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, r: Array<U32> & Render.Ray) -> Array<U32> & (U32 & U32):
  (w, ray) = r
  Render.Ray{+code, t, rim, rim_end, tr} = ray
  aim_hit(Util.on(code, 1024), (code % 4 : U32), ox, oy, oz, dx, dy, dz, t, w)

def aim(w: Array<U32>, +base: U32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32) -> Array<U32> & (U32 & U32):
  aim_fin(ox, oy, oz, dx, dy, dz, Render.walk_from(~False{}, ~False{}, 40n, w, base, 0, 0, ox, oy, oz, dx, dy, dz, 0.0))

def waim_fin(meta: World.Meta, r: Array<U32> & (U32 & U32)) -> World.World & (U32 & U32):
  (ring, ph) = r
  (World.W{ring, meta}, ph)

def waim(w: World.World, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32) -> World.World & (U32 & U32):
  World.W{ring, +meta} = w
  waim_fin(meta, aim(ring, World.base(meta), ox, oy, oz, dx, dy, dz))

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
# A torch is no item: a break takes it and credits nothing.
def edit_commit(w: World.World, idx: U32, set: Bool, what: U32, gone: Bool, e: Inventory.Edit) -> World.World & List<&2, Nat>:
  Inventory.Edit{bag, changed} = e
  (write_block(changed || gone, w, idx, set, what), bag)

def edit_type(+set: Bool, +what: U32, idx: U32, bag: List<&2, Nat>, solid: Bool, r: World.World & U32) -> World.World & List<&2, Nat>:
  (w, +actual) = r
  edit_commit(w, idx, set, Bool.pick(U32, set, what, 0), Bool.not(set) && U32.is_eq(actual, Torch.slot()),
    Inventory.edit(bag, U32.to_nat(Bool.pick(U32, set, what, actual)), set, solid))

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

# ---------- the torch ----------
# The tenth slot's torch costs nothing: a right click stands one in the
# cell before the face aimed at, if that cell is open and dry and a solid
# block is under it; the player may stand in it, since it is not solid.
def torch_fin(+idx: U32, bag: List<&2, Nat>, +open: U32, r: World.World & Bool) -> World.World & List<&2, Nat>:
  (w, under) = r
  (write_block(under && U32.is_eq(open, 0), w, idx, True{}, Torch.slot()), bag)

def torch_open(+idx: U32, bag: List<&2, Nat>, r: World.World & U32) -> World.World & List<&2, Nat>:
  (w, open) = r
  torch_fin(idx, bag, open, World.wsolid(w, Util.u2f(ix_x(idx)), (Util.u2f(ix_y(idx)) - 1.0 : F32), Util.u2f(ix_z(idx))))

def torch_put(act: Bool, +idx: U32, r: World.World & List<&2, Nat>) -> World.World & List<&2, Nat>:
  match act:
    case False{}:
      r
    case True{}:
      (w, bag) = r
      torch_open(idx, bag, World.probe(w, ix_x(idx), ix_y(idx), ix_z(idx)))

# ---------- the bucket ----------
# The ninth slot moves water instead of a block. A left click takes all
# the water of the cell before the face aimed at into the bucket, a
# partial cell for what it holds; a right click fills that cell from the
# bucket, if the bucket holds what the cell lacks (255 for air). The
# units only move: the world, the bucket and what dried sum to the same.
# The bucket's units are the bag's ninth count.

# what moves: the cell's amount out, or the room the cell has in; nothing
# where the probe says 256 (a solid, or outside the window)
def pail_take(put: Bool, +a: U32) -> U32:
  Bool.pick(U32, put, World.fits(World.full(), a), Bool.pick(U32, (a < 256 : U32), a, 0))

def pail_move(ok: Bool, w: World.World, +lx: U32, +y: U32, +lz: U32, +amt: U32, bag: List<&2, Nat>, left: Nat) -> World.World & List<&2, Nat>:
  match ok:
    case False{}:
      (w, bag)
    case True{}:
      (World.mark_around(World.pour(w, lx, y, lz, amt), lx, y, lz), List.set(&2, Nat, bag, 8n, left))

def pail_fin(+put: Bool, +lx: U32, +y: U32, +lz: U32, +bag: List<&2, Nat>, r: World.World & U32) -> World.World & List<&2, Nat>:
  (w, a) = r
  +k = U32.to_nat(pail_take(put, a))
  +had = Inventory.count(bag, 8n)
  pail_move(Nat.is_gt(k, 0n) && (Bool.not(put) || Nat.is_le(k, had)), w, lx, y, lz, Bool.pick(U32, put, World.full(), 0), bag,
    Bool.pick(Nat, put, Nat.sub(had, k), Nat.add(had, k)))

def pail(act: Bool, put: Bool, +idx: U32, r: World.World & List<&2, Nat>) -> World.World & List<&2, Nat>:
  match act:
    case False{}:
      r
    case True{}:
      (w, bag) = r
      pail_fin(put, ix_x(idx), ix_y(idx), ix_z(idx), bag, World.probe(w, ix_x(idx), ix_y(idx), ix_z(idx)))

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
              held: U32, edge: U32, sel: U32, res: U32, clock: U32,
              r: World.World & List<&2, Nat>) -> Game:
  (w, bag) = r
  G{w, px, py, pz, yaw, pit, vy, held, io_edges(edge), sel, res, clock, bag}

def step_edit(+npx: F32, +npy: F32, +npz: F32, nvy: F32, nyaw: F32, npit: F32,
              held: U32, +edge: U32, +sel: U32, res: U32, clock: U32, bag: List<&2, Nat>, w: World.World, ph: U32 & U32) -> Game:
  (+prev, +hit) = ph
  +got = (hit > 0 : U32)
  +tgt = (prev - 1 : U32)
  +onme = U32.is_eq(ix_x(tgt), Util.f2u(npx)) && U32.is_eq(ix_z(tgt), Util.f2u(npz))
    && (ix_y(tgt) >= Util.f2u((npy - eye() : F32)) : U32) && (ix_y(tgt) <= Util.f2u((npy + 0.2 : F32)) : U32)
  +pail_on = U32.is_eq(sel, 8)
  +brk = got && Util.on(edge, 1024)
  +use = got && (prev > 0 : U32) && Util.on(edge, 2048)
  +put = use && Bool.not(onme)
  step_done(npx, npy, npz, nvy, nyaw, npit, held, edge, sel, res, clock,
    edit_world(put && (sel < 8 : U32), tgt, True{}, sel,
      torch_put(use && U32.is_eq(sel, Torch.slot()), tgt,
        edit_world(brk && Bool.not(pail_on), (hit - 1 : U32), False{}, 0,
          pail(pail_on && (brk || put), put, tgt, (w, bag))))))

def step_aim(+npx: F32, +npy: F32, +npz: F32, nvy: F32, nyaw: F32, npit: F32,
             held: U32, edge: U32, sel: U32, res: U32, clock: U32, bag: List<&2, Nat>, r: World.World & (U32 & U32)) -> Game:
  (w, ph) = r
  step_edit(npx, npy, npz, nvy, nyaw, npit, held, edge, sel, res, clock, bag, w, ph)

def step_bump(+npx: F32, +py: F32, +npz: F32, +ty: F32, +vy1: F32, +land: Bool, bank: Bool,
              +nyaw: F32, +npit: F32, +held: U32, edge: U32, sel: U32, res: U32, clock: U32, bag: List<&2, Nat>,
              r: World.World & Bool) -> Game:
  (w, above) = r
  +bump = (vy1 > 0.0 : F32) && above
  +feet = (ty - eye() : F32)
  +npy = F32.clamp(Bool.pick(F32, land, (F32.floor(feet) + 1.0 + eye() : F32),
                             Bool.pick(F32, bump, py, ty)), eye(), 31.5)
  +nvy = Bool.pick(F32, (land && Util.on(held, 8192)) || bank, 0.2,
                   Bool.pick(F32, land || bump, 0.0, vy1))
  +cx = Util.f2u(npx)
  +cz = Util.f2u(npz)
  +lx = (npx - Util.u2f(cx) + 64.0 : F32)
  +lz = (npz - Util.u2f(cz) + 64.0 : F32)
  step_aim(lx, npy, lz, nvy, nyaw, npit, held, edge, sel, res, clock, bag,
           waim(World.follow(U32.to_nat(Bool.pick(U32, (cz > 64 : U32), (cz - 64 : U32), (64 - cz : U32))), False{}, (cz > 64 : U32),
                World.follow(U32.to_nat(Bool.pick(U32, (cx > 64 : U32), (cx - 64 : U32), (64 - cx : U32))), True{}, (cx > 64 : U32), w)),
                lx, npy, lz, Render.look_x(nyaw, npit), Render.look_y(npit), Render.look_z(nyaw, npit)))

def step_land(+npx: F32, +py: F32, +npz: F32, +ty: F32, +vy1: F32, bank: Bool,
              nyaw: F32, npit: F32, held: U32, edge: U32, sel: U32, res: U32, clock: U32, bag: List<&2, Nat>,
              r: World.World & Bool) -> Game:
  (w, below) = r
  step_bump(npx, py, npz, ty, vy1, (vy1 < 0.0 : F32) && below, bank, nyaw, npit, held, edge, sel, res, clock, bag,
            World.wsolid(w, npx, (ty + 0.2 : F32), npz))

def step_z(+npx: F32, +py: F32, +pz: F32, +tz: F32, +vy1: F32, swim: Bool, bx: Bool,
           nyaw: F32, npit: F32, held: U32, edge: U32, sel: U32, res: U32, clock: U32, bag: List<&2, Nat>,
           r: World.World & Bool) -> Game:
  (w, +bz) = r
  +npz = Bool.pick(F32, bz, pz, tz)
  +ty = (py + vy1 : F32)
  step_land(npx, py, npz, ty, vy1, swim && (bx || bz), nyaw, npit, held, edge, sel, res, clock, bag,
            World.wsolid(w, npx, (ty - eye() : F32), npz))

def step_x(+px: F32, +py: F32, +pz: F32, +tx: F32, +tz: F32, +vy1: F32, swim: Bool,
           nyaw: F32, npit: F32, held: U32, edge: U32, sel: U32, res: U32, clock: U32, bag: List<&2, Nat>,
           r: World.World & Bool) -> Game:
  (w, +bx) = r
  +npx = Bool.pick(F32, bx, px, tx)
  step_z(npx, py, pz, tz, vy1, swim, bx, nyaw, npit, held, edge, sel, res, clock, bag, blocked(w, npx, py, tz))

# In water at the waist the player swims: the water's lift nearly balances
# gravity, so they sink slowly and the water drags; space swims up, to a
# bob at the surface with the eye over it; a stroke is half a step; and a
# wall met swimming is a bank: the player pushes off it as off the ground,
# a push the water's clamp holds down until the waist is out, where it
# carries them over the bank. Out of water, the walk and the fall.
def step_swim(+px: F32, +py: F32, +pz: F32, yaw: F32, pit: F32, +vy: F32, +held: U32, edge: U32, sel: U32, res: U32, clock: U32, bag: List<&2, Nat>,
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
  step_x(px, py, pz, tx, tz, vy1, swim, nyaw, npit, held, edge, sel, res, clock, bag, blocked(w, tx, py, pz))

def step(g: Game) -> Game:
  G{w, +px, +py, +pz, yaw, pit, vy, held, edge, sel, res, clock, bag} = g
  step_swim(px, py, pz, yaw, pit, vy, held, edge, sel, res, clock, bag, World.wet_at(w, px, (py - 0.8 : F32), pz))

# the world's corner starts far from zero, so walking west never wraps it
def start_at(+res: U32) -> Game:
  G{World.load_world(World.W{[0 : U32^20n], World.Meta{Map.new(&2, World.Col), 1048512, 1048512, Nil{}, 0, 0}}, 1048512, 1048512),
    64.5, 30.0, 64.5, 0.0, (0.0 - 0.55 : F32), 0.0, 0, 0, 0, res, Day.morning(), Inventory.empty()}

def start() -> Game:
  start_at(res512())
