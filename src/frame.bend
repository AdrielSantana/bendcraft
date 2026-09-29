import Base
import ./world.bend as World
import ./render.bend as Render
import ./inventory.bend as Inventory
import ./player.bend as Player

# THE FRAME: the one `!` a frame, and the game's view through it. Its tree
# hands the ring to both halves of every fork (`+w`, given back by
# `Array.join`), which only an `@unsafe` def may do; nothing else in the
# game relies on unsafe code, and the laws import none of this, so their
# verdict stays ALL PROOFS CHECK.

# the tree of a frame: see fork below
def pair(l: Array<U32> & Image, r: Array<U32> & Image) -> Array<U32> & Image:
  (wl, p) = l
  (wr, q) = r
  (Array.join(U32, wl, wr), Qua{p, q, Pix{0}, Pix{0}})

def solo(l: Array<U32> & Image) -> Array<U32> & Image:
  (wl, p) = l
  (wl, Qua{p, Pix{0}, Pix{0}, Pix{0}})

def merge_fin(p: Image, q: Image, j: Image) -> Image:
  match j:
    case Qua{r, s, c, d}:
      Qua{p, q, r, s}
    case Pix{z}:
      Qua{p, q, Pix{0}, Pix{0}}

def merge(i: Image, j: Image) -> Image:
  match i:
    case Qua{p, q, a, b}:
      merge_fin(p, q, j)
    case Pix{c}:
      Pix{c}

def quad2(t: Array<U32> & Image, b: Array<U32> & Image) -> Array<U32> & Image:
  (wt, i) = t
  (wb, j) = b
  (Array.join(U32, wt, wb), merge(i, j))

def top(t: Array<U32> & Image) -> Array<U32> & Image:
  (wt, i) = t
  (wt, merge(i, Pix{0}))

# The tree of a frame is binary: a node at f = 2k is a square of 2h = 4 * 2^k
# pixels and splits into its top and bottom rows, a row (f odd) into its left
# and right squares of half h. A node exists only if its corner is inside
# the render, and v says whether its second half is: a node with one half
# inside runs that half in place, without a fork. The shape is for the GPU
# runtime, which grows a frontier of tasks two-way a turn until its 128
# lanes a group hold one each, then runs each task on its lane to the end:
# a two-way tree fills the frontier with tasks of one size, and a half
# that never becomes a task never skews it. The four-way tree, pruned,
# left some lanes 64 leaves and took 110-150 ms on a 1470 x 796 frame
# where this takes 16; unpruned it took 46.
@unsafe
def fork(+f: Nat, +wide: Bool, v: Bool, +cam: Render.Cam, +w: Array<U32>, +rw: U32, +rh: U32, +h: U32, +x: U32, +y: U32) -> Array<U32> & Image:
  match f:
    case 0n:
      Render.t4(cam, w, x, y)
    case 1n+g:
      match wide:
        case True{}:
          match v:
            case True{}:
              +h2 = (h / 2 : U32)
              +vy = ((y + h2 : U32) < rh : U32)
              l r = fork(g, False{}, vy, cam, w, rw, rh, h2, x, y) fork(g, False{}, vy, cam, w, rw, rh, h2, (x + h : U32), y)
              pair(l, r)
            case False{}:
              +h2 = (h / 2 : U32)
              solo(fork(g, False{}, ((y + h2 : U32) < rh : U32), cam, w, rw, rh, h2, x, y))
        case False{}:
          match v:
            case True{}:
              +vx = ((x + h : U32) < rw : U32)
              t b = fork(g, True{}, vx, cam, w, rw, rh, h, x, y) fork(g, True{}, vx, cam, w, rw, rh, h, x, (y + h : U32))
              quad2(t, b)
            case False{}:
              top(fork(g, True{}, ((x + h : U32) < rw : U32), cam, w, rw, rh, h, x, y))

# the levels of fork that cover the larger side with 4x4 leaves
def depth_at(fuel: Nat, +side: U32, +m: U32, +k: U32) -> U32:
  match fuel:
    case 0n:
      k
    case 1n+f:
      Bool.pick(U32, (side >= m : U32), k, depth_at(f, (side * 2 : U32), m, (k + 1 : U32)))

def depth(+rw: U32, +rh: U32) -> Nat:
  U32.to_nat(depth_at(12n, 4, U32.max(rw, rh), 0))

# the frame: one `!` over the lane cube, the camera shared as Data and the
# ring as the array both sides may read
@unsafe
def cast(+cam: Render.Cam, +ring: Array<U32>, +rw: U32, +rh: U32) -> Array<U32> & Image:
  +d = depth(rw, rh)
  +h = U32.shln(2, d)
  fork!((d + d : Nat), False{}, (h < rh : U32), cam, ring, rw, rh, h, 0, 0)

# the frame of a camera that saw the sun (Render.sighted)
def cast_seen(r: Array<U32> & Render.Cam, +rw: U32, +rh: U32) -> Array<U32> & Image:
  (ring, cam) = r
  cast(cam, ring, rw, rh)

def view_fin(px: F32, py: F32, pz: F32, yaw: F32, pit: F32, vy: F32,
             held: U32, edge: U32, sel: U32, res: U32, clock: U32, bag: List<&2, Nat>, meta: World.Meta,
             r: Array<U32> & Image) -> Player.Game & Image:
  (ring, img) = r
  (Player.G{World.W{ring, meta}, px, py, pz, yaw, pit, vy, held, edge, sel, res, clock, bag}, img)

def view_w(+px: F32, +py: F32, +pz: F32, +yaw: F32, +pit: F32, vy: F32,
           held: U32, edge: U32, +sel: U32, +res: U32, +clock: U32, +bag: List<&2, Nat>, +fl: U32, stat: U32, more: U32, w: World.World) -> Player.Game & Image:
  World.W{ring, +meta} = w
  World.Meta{m, ox, oz, q, +np, gone} = meta
  +rw = (res / 65536 : U32)
  +rh = (res % 65536 : U32)
  view_fin(px, py, pz, yaw, pit, vy, held, edge, sel, res, clock, bag, meta,
           cast_seen(Render.sighted(ring, Render.camera(px, py, pz, yaw, pit, World.base(meta), World.far_cam(meta), Render.with_partial(more, (np > 0 : U32)), Inventory.hud_lo(sel, bag), Inventory.hud_hi(bag), Render.with_pail(stat, Inventory.hud_pail(bag)), fl, rw, rh, clock)), rw, rh))

# the frame with the render's flags (Render.Cam), all looks on for the game;
# `more` holds the looks the flags word has no room for (Render.looks_base),
# `stat` the readout's numbers (Render.stat_of), zero for none
def view_more(g: Player.Game, +fl: U32, stat: U32, more: U32) -> Player.Game & Image:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, sel, res, clock, bag} = g
  view_w(px, py, pz, yaw, pit, vy, held, edge, sel, res, clock, bag, fl, stat, more, w)

def view_with(g: Player.Game, fl: U32) -> Player.Game & Image:
  view_more(g, fl, 0, Render.looks_base())

def view(g: Player.Game) -> Player.Game & Image:
  view_with(g, Render.looks())

# the game's frame with the readout in its corner; zeros hide it
def view_stat(g: Player.Game, +ms10: U32, +fps: U32) -> Player.Game & Image:
  view_more(g, Render.looks(), Render.stat_of(ms10, fps), Render.looks_base())
