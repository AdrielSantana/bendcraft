import Base
import ../src/world.bend as World
import ../src/render.bend as Render
import ../src/player.bend as Player
import ../src/frame.bend as Frame

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
  for  +more: U32
  for  +lv: Nat
  for  acc: Nat
  for  ssum: U32
  for  g: Player.Game
  IO(Player.Game & (Nat & U32))

@unsafe
def frames_fin(n: Nat, +fl: U32, +more: U32, +lv: Nat, +acc: Nat, +ssum: U32, +t0: Nat, +t1: Nat, r: Player.Game & Image) -> IO(Player.Game & (Nat & U32)):
  (g, img) = r
  frames(n, fl, more, lv, (acc + (t1 - t0 : Nat) : Nat), (ssum + area_sum(lv, img) : U32), g)

@unsafe
def frames(n, fl, more, lv, acc, ssum, g):
  match n:
    case 0n:
      IO.pure(Player.Game & (Nat & U32), (g, (acc, ssum)))
    case 1n+m:
      do IO<Player.Game & (Nat & U32)>:
        t0 : Nat <- IO.now()
        r : Player.Game & Image = Frame.view_more(g, fl, 0, more)
        t1 : Nat <- IO.now()
        frames_fin(m, fl, more, lv, acc, ssum, t0, t1, r)

# a render of the view: its line's name, what the line says (0 the ms of
# one frame, 1 the ms a frame of five, 2 the hits, 3 the steps), and the
# flags and the base's looks it renders with
type Run is Type:
  Run{name: String, kind: U32, fl: U32, more: U32}

# a look turned off: the flags' bits and the base's it clears
def off(name: String, +fl: U32, +more: U32) -> Run:
  Run{name, 1, (Render.looks() .&. U32.not(fl) : U32), (Render.looks_base() .&. U32.not(more) : U32)}

# the renders, in order: a warm-up, all on, each look off, the rays alone,
# the hits, the steps. HUD off includes the inventory labels under flag 16.
def plan() -> List<Run>:
  [Run{"warm-up, the GPU program loads", 0, Render.looks(), Render.looks_base()},
   off("all on           ", 0, 0),
   off("shadow off       ", 1, 0),
   off("occlusion off    ", 2, 0),
   off("texture off      ", 4, 0),
   off("distance fog off ", 8, 0),
   off("HUD off          ", 16, 0),
   off("day cycle off    ", 33554432, 0),
   off("sky gradient off ", 67108864, 0),
   off("sun disc off     ", 134217728, 0),
   off("horizon glow off ", 268435456, 0),
   off("stars off        ", 536870912, 0),
   off("moon off         ", 1073741824, 0),
   off("height fog off   ", 2147483648, 0),
   off("water off        ", 2097152, 0),
   off("water fog off    ", 4194304, 0),
   off("Fresnel off      ", 8388608, 0),
   off("sky reflection off", 16777216, 0),
   off("ripples off      ", 1048576, 0),
   off("clouds off       ", 128, 0),
   off("cloud shadows off", 256, 0),
   off("rain off         ", 512, 0),
   off("world mirror off ", 0, 134217728),
   off("caustic off      ", 0, 268435456),
   Run{"rays alone       ", 1, 0, Render.looks_base()},
   Run{"hits             ", 2, 64, Render.looks_base()},
   Run{"steps           ", 3, 32, Render.looks_base()}]

def dec(+t: U32) -> String:
  U32.show((t / 10 : U32)) ++ "." ++ U32.show((t % 10 : U32))

# the ms of five frames, as ms a frame with a decimal
def per_frame(+ms5: Nat) -> String:
  +t = Nat.mul(ms5, 2n)
  Nat.show(Nat.div(t, 10n)) ++ "." ++ Nat.show(Nat.mod(t, 10n))

def said(+kind: U32, +ms5: Nat, +sum: U32, +px: U32) -> String:
  Bool.pick(String, U32.is_eq(kind, 0), " " ++ Nat.show(ms5) ++ " ms, one frame",
    Bool.pick(String, U32.is_eq(kind, 2), U32.show((sum * 100 / px : U32)) ++ " % of the rays reach a block",
      Bool.pick(String, U32.is_eq(kind, 3), dec((sum * 10 / px : U32)) ++ " a ray to its hit, of the 60 it walks (a sky ray's 60 count)",
        " " ++ per_frame(ms5) ++ " ms a frame")))

law runs:
  for  rs: List<Run>
  for  +lv: Nat
  for  +px: U32
  for  g: Player.Game
  IO(Unit)

@unsafe
def runs_fin(rest: List<Run>, name: String, +kind: U32, +lv: Nat, +px: U32, r: Player.Game & (Nat & U32)) -> IO(Unit):
  (g, ms) = r
  (ms5, sum) = ms
  do IO<Unit>:
    IO.print("  " ++ name ++ said(kind, ms5, sum, px))
    runs(rest, lv, px, g)

@unsafe
def run(r: Run, rest: List<Run>, +lv: Nat, +px: U32, g: Player.Game) -> IO(Unit):
  Run{name, +kind, fl, more} = r
  do IO<Unit>:
    done : Player.Game & (Nat & U32) <- frames(Bool.pick(Nat, U32.is_eq(kind, 0), 1n, 5n), fl, more, lv, 0n, 0, g)
    runs_fin(rest, name, kind, lv, px, done)

@unsafe
def runs(rs, lv, px, g):
  match rs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{r, rest}:
      run(r, rest, lv, px, g)

# the image's levels: the fork's depth and the tile's two
def profile_view(name: String, +rw: U32, +rh: U32, g: Player.Game) -> IO(Unit):
  do IO<Unit>:
    IO.print(name)
    runs(plan(), (Frame.depth(rw, rh) + 2n : Nat), (rw * rh * 5 : U32), g)

def profile_size(name: String, +rw: U32, +rh: U32) -> IO(Unit):
  profile_view(name, rw, rh, Player.start_at(Player.res_of(rw, rh)))

def wide() -> Player.Game:
  Player.start_at(Player.res_of(1470, 796))

# Stars and the moon are skipped during the day. Measure them in their
# active state too, looking upward so the moon is in the frame.
def night(g: Player.Game) -> Player.Game:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, sel, res, clock, bag} = g
  Player.G{w, px, py, pz, 0.9272952, 1.1, vy, held, edge, sel, res, 786432, bag}

# This view is close enough to a lake to measure the active water look.
def lake(g: Player.Game) -> Player.Game:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, sel, res, clock, bag} = g
  Player.G{w, 51.5, 16.0, 66.5, (0.0 - 1.5707963 : F32), (0.0 - 0.4 : F32), vy, held, edge, sel, res, clock, bag}

def submerged(g: Player.Game) -> Player.Game:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, sel, res, clock, bag} = g
  Player.G{w, 45.5, 11.5, 66.5, (0.0 - 1.5707963 : F32), 0.1, vy, held, edge, sel, res, clock, bag}

# The ordinary night view points at the sky. This one activates water's
# reflected sky and moon as well as its daytime lake profile.
def night_lake(g: Player.Game) -> Player.Game:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, sel, res, clock, bag} = g
  Player.G{w, 36.5, 14.0, 60.5, 0.9272952, (0.0 - 0.215 : F32), vy, held, edge, sel, res, 560000, bag}

# The lake again with a stair of partial cells poured into it (the water
# view's levels): the frame then walks every ray with the plane clip.
def stair(n: Nat, w: World.World, +i: U32) -> World.World:
  match n:
    case 0n: w
    case 1n+k:
      stair(k, World.pour(w, (38 + i * 2 : U32), 11, 66, ((i + 1) * 32 : U32)), (i + 1 : U32))

def partial_lake(g: Player.Game) -> Player.Game:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, sel, res, clock, bag} = g
  Player.G{stair(7n, w, 0), 51.5, 16.0, 66.5, (0.0 - 1.5707963 : F32), (0.0 - 0.4 : F32), vy, held, edge, sel, res, clock, bag}

# The morning of the second day, overcast, in the rain.
def rain(g: Player.Game) -> Player.Game:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, sel, res, clock, bag} = g
  Player.G{w, px, py, pz, 0.9272952, 0.1, vy, held, edge, sel, res, 1203323, bag}

def main() -> IO(Unit):
  do IO<Unit>:
    profile_size("512 x 512", 512, 512)
    profile_size("735 x 398 (a 14-inch MacBook at scale 2)", 735, 398)
    profile_size("960 x 540 (a 1920 x 1080 window at scale 2)", 960, 540)
    profile_size("1470 x 796 (a 14-inch MacBook, every pixel a ray)", 1470, 796)
    profile_view("Night at 1470 x 796, looking at the moon", 1470, 796, night(wide()))
    profile_view("Rain at 1470 x 796, the second morning", 1470, 796, rain(wide()))
    profile_view("Lake at 1470 x 796, looking west", 1470, 796, lake(wide()))
    profile_view("Submerged at 1470 x 796, looking west", 1470, 796, submerged(wide()))
    profile_view("Night lake at 1470 x 796, looking at the reflected moon", 1470, 796, night_lake(wide()))
    profile_view("Lake at 1470 x 796 with partial water in the window (the plane clip on)", 1470, 796, partial_lake(wide()))
