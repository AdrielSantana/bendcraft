import Base
import ../src/world.bend as World
import ../src/render.bend as Render
import ../src/player.bend as Player

# The profile: what costs what in a frame. For each size, one view (the
# start of the untouched world) is rendered five times with every look on,
# then with each look off in turn, then with the rays alone; the time of
# the `!` per frame, on the GPU. Two more renders give numbers instead of
# colours (Render.Cam's flags 64 and 32): how many rays hit a block, and how
# many DDA steps a ray walks to its hit, summed over the image by the same
# walk as the bench's checksum. `make profile`.

# the pixels summed, a Pix weighed by the square it stands for (a 2x2 of
# one value is one Pix in the image); k is the image's levels, the fork's
# depth and the tile's two
def area_sum(+k: Nat, img: Image) -> U32:
  match k:
    case 0n:
      match img:
        case Pix{c}:
          c
        case Qua{tl, tr, bl, br}:
          0
    case 1n+j:
      match img:
        case Pix{c}:
          U32.shln(U32.shln(c, k), k)
        case Qua{tl, tr, bl, br}:
          a b c d = area_sum(j, tl) area_sum(j, tr) area_sum(j, bl) area_sum(j, br)
          (a + b + c + d : U32)

# n frames of the same view with the flags: the game back, the ms of the
# `!` summed, the pixels summed
law frames:
  for  n: Nat
  for  +fl: U32
  for  +lv: Nat
  for  acc: Nat
  for  ssum: U32
  for  g: Player.Game
  IO(Player.Game & (Nat & U32))

@unsafe
def frames_fin(n: Nat, +fl: U32, +lv: Nat, +acc: Nat, +ssum: U32, +t0: Nat, +t1: Nat, r: Player.Game & Image) -> IO(Player.Game & (Nat & U32)):
  (g, img) = r
  frames(n, fl, lv, (acc + (t1 - t0 : Nat) : Nat), (ssum + area_sum(lv, img) : U32), g)

@unsafe
def frames(n, fl, lv, acc, ssum, g):
  match n:
    case 0n:
      IO.pure(Player.Game & (Nat & U32), (g, (acc, ssum)))
    case 1n+m:
      do IO<Player.Game & (Nat & U32)>:
        t0 : Nat <- IO.now()
        r : Player.Game & Image = Player.view_with(g, fl)
        t1 : Nat <- IO.now()
        frames_fin(m, fl, lv, acc, ssum, t0, t1, r)

# the variants, in order: a warm-up, all on, each look off, the rays alone,
# the hits, the steps
def off_bit(+i: U32) -> U32:
  Bool.pick(U32, U32.is_eq(i, 2), 1,
    Bool.pick(U32, U32.is_eq(i, 3), 2,
    Bool.pick(U32, U32.is_eq(i, 4), 4,
    Bool.pick(U32, U32.is_eq(i, 5), 8,
    Bool.pick(U32, U32.is_eq(i, 6), 16,
    Bool.pick(U32, U32.is_eq(i, 7), 33554432,
    Bool.pick(U32, U32.is_eq(i, 8), 67108864,
    Bool.pick(U32, U32.is_eq(i, 9), 134217728,
    Bool.pick(U32, U32.is_eq(i, 10), 268435456,
    Bool.pick(U32, U32.is_eq(i, 11), 536870912,
    Bool.pick(U32, U32.is_eq(i, 12), 1073741824, 2147483648)))))))))))

def flags_of(+i: U32) -> U32:
  Bool.pick(U32, (i < 2 : U32), Render.looks(),
    Bool.pick(U32, (i < 14 : U32), (Render.looks() .&. U32.not(off_bit(i)) : U32),
    Bool.pick(U32, U32.is_eq(i, 14), 0, Bool.pick(U32, U32.is_eq(i, 15), 64, 32))))

def label_of(+i: U32) -> String:
  Bool.pick(String, U32.is_eq(i, 0), "warm-up, the GPU program loads",
    Bool.pick(String, U32.is_eq(i, 1), "all on           ",
    Bool.pick(String, U32.is_eq(i, 2), "shadow off       ",
    Bool.pick(String, U32.is_eq(i, 3), "occlusion off    ",
    Bool.pick(String, U32.is_eq(i, 4), "texture off      ",
    Bool.pick(String, U32.is_eq(i, 5), "distance fog off ",
    Bool.pick(String, U32.is_eq(i, 6), "HUD off          ",
    Bool.pick(String, U32.is_eq(i, 7), "day cycle off    ",
    Bool.pick(String, U32.is_eq(i, 8), "sky gradient off ",
    Bool.pick(String, U32.is_eq(i, 9), "sun disc off     ",
    Bool.pick(String, U32.is_eq(i, 10), "horizon glow off ",
    Bool.pick(String, U32.is_eq(i, 11), "stars off        ",
    Bool.pick(String, U32.is_eq(i, 12), "moon off         ",
    Bool.pick(String, U32.is_eq(i, 13), "height fog off   ", "rays alone       "))))))))))))))

def dec(+t: U32) -> String:
  U32.show((t / 10 : U32)) ++ "." ++ U32.show((t % 10 : U32))

# the ms of five frames, as ms a frame with a decimal
def per_frame(+ms5: Nat) -> String:
  +t = Nat.mul(ms5, 2n)
  Nat.show(Nat.div(t, 10n)) ++ "." ++ Nat.show(Nat.mod(t, 10n))

def line(+i: U32, +ms5: Nat, +sum: U32, +px: U32) -> String:
  Bool.pick(String, (i < 1 : U32), "  " ++ label_of(i) ++ " " ++ Nat.show(ms5) ++ " ms, one frame",
    Bool.pick(String, U32.is_eq(i, 15), "  hits             " ++ U32.show((sum * 100 / px : U32)) ++ " % of the rays reach a block",
      Bool.pick(String, U32.is_eq(i, 16), "  steps           " ++ dec((sum * 10 / px : U32)) ++ " a ray to its hit, of the 60 it walks (a sky ray's 60 count)",
        "  " ++ label_of(i) ++ " " ++ per_frame(ms5) ++ " ms a frame")))

law runs:
  for  n: Nat
  for  +i: U32
  for  +lv: Nat
  for  +px: U32
  for  g: Player.Game
  IO(Unit)

@unsafe
def runs_fin(n: Nat, +i: U32, +lv: Nat, +px: U32, r: Player.Game & (Nat & U32)) -> IO(Unit):
  (g, ms) = r
  (ms5, sum) = ms
  do IO<Unit>:
    IO.print(line(i, ms5, sum, px))
    runs(n, (i + 1 : U32), lv, px, g)

@unsafe
def runs(n, i, lv, px, g):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+m:
      do IO<Unit>:
        r : Player.Game & (Nat & U32) <- frames(Bool.pick(Nat, U32.is_eq(i, 0), 1n, 5n), flags_of(i), lv, 0n, 0, g)
        runs_fin(m, i, lv, px, r)

# the image's levels: the fork's depth and the tile's two
def profile_size(name: String, +rw: U32, +rh: U32) -> IO(Unit):
  do IO<Unit>:
    IO.print(name)
    runs(17n, 0, (Render.depth(rw, rh) + 2n : Nat), (rw * rh * 5 : U32), Player.start_at(Player.res_of(rw, rh)))

# Stars and the moon are skipped during the day. Measure them in their
# active state too, looking upward so the moon is in the frame.
def night(g: Player.Game) -> Player.Game:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock} = g
  Player.G{w, px, py, pz, 0.9272952, 1.1, vy, held, edge, mx, my, sel, res, 786432}

def main() -> IO(Unit):
  do IO<Unit>:
    profile_size("512 x 512", 512, 512)
    profile_size("735 x 398 (a 14-inch MacBook at scale 2)", 735, 398)
    profile_size("960 x 540 (a 1920 x 1080 window at scale 2)", 960, 540)
    profile_size("1470 x 796 (a 14-inch MacBook, every pixel a ray)", 1470, 796)
    IO.print("Night at 1470 x 796, looking at the moon")
    runs(17n, 0, (Render.depth(1470, 796) + 2n : Nat), (1470 * 796 * 5 : U32), night(Player.start_at(Player.res_of(1470, 796))))
