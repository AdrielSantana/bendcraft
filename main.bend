import Base
import ./src/player.bend as Player
import ./src/save.bend as Save

# Bendcraft: an endless voxel world you can walk, jump, break and build,
# written in Bend and rendered by a `!` on the GPU (Metal) or on every core
# (WebAssembly). The modules under src/ hold the world, the render and the
# player; test/ holds the windowless tests and the benches; LAWS.bend the
# rules the checker proves.

# `bendcraft [W H [S]]`: a window of W x H, the render S times smaller on
# each side (a power of two: the window's shader scales it up); 512 512 1
# when nothing is said. On a 1920 x 1080 screen, `1920 1080 2` fills it
# with 960 x 540 rays.
def size_of(xs: List<String>) -> U32 & (U32 & U32):
  match xs:
    case Con{w, Con{h, Con{s, rest}}}:
      (Save.num(w), (Save.num(h), U32.max(Save.num(s), 1)))
    case Con{w, Con{h, rest}}:
      (Save.num(w), (Save.num(h), 1))
    case Con{w, rest}:
      (512, (512, 1))
    case Nil{}:
      (512, (512, 1))

# ---------- the loop, with the readout ----------
# App.run's loop written out, so the `!` is timed apart from the wait for
# the screen: a clock read on each side of the view. F switches the readout
# in the frame's corner. Twice a second it takes the mean of the `!` over
# the frames since, in tenths of a millisecond, and the frames a second.

type Stat is Data:
  Stat{on: Bool, t0: Nat, n: U32, sum: U32, ms10: U32, fps: U32, last: Nat}

def stat_ms(st: Stat) -> U32:
  Stat{on, t0, n, sum, ms10, fps, last} = st
  Bool.pick(U32, on, ms10, 0)

def stat_fps(st: Stat) -> U32:
  Stat{on, t0, n, sum, ms10, fps, last} = st
  Bool.pick(U32, on, fps, 0)

def stat_new(now: Bool, on: Bool, t0: Nat, tb: Nat, +n: U32, +sum: U32, +span: U32, ms10: U32, fps: U32, last: Nat) -> Stat:
  match now:
    case True{}:
      Stat{on, tb, 0, 0, (sum * 10 / n : U32), (n * 1000 / span : U32), last}
    case False{}:
      Stat{on, t0, n, sum, ms10, fps, last}

def stat_add(st: Stat, +ta: Nat, +tb: Nat) -> Stat:
  Stat{on, +t0, n, sum, ms10, fps, last} = st
  +span = U32.from_nat(Nat.min((tb - t0 : Nat), 9999n))
  stat_new((span >= 500 : U32), on, t0, tb, (n + 1 : U32),
    (sum + U32.from_nat(Nat.min((tb - ta : Nat), 999n)) : U32), span, ms10, fps, ta)

def stat_flip(st: Stat, f: Bool) -> Stat:
  Stat{+on, t0, n, sum, ms10, fps, last} = st
  Stat{Bool.pick(Bool, f, Bool.not(on), on), t0, n, sum, ms10, fps, last}

def next(window: Window, st: Stat, rest: Window -> Stat -> Player.Game -> IO(Unit), got: Maybe<Player.Game>) -> IO(Unit):
  match got:
    case None{}:
      Window.close(window)
    case Some{g}:
      rest(window, st, g)

def keyed(window: Window, st: Stat, r: Player.Game & Bool, rest: Window -> Stat -> Player.Game -> IO(Unit)) -> IO(Unit):
  (g, f) = r
  IO.bind(Maybe<Player.Game>, Unit, Save.tick(Nil{}, g), next(window, stat_flip(st, f), rest))

def after(shown: Window & Image & List<Event>, st: Stat, g: Player.Game, rest: Window -> Stat -> Player.Game -> IO(Unit)) -> IO(Unit):
  (window, image, evs) = shown
  do IO<Unit>:
    Unit <- IO.pure(Unit, Image.drop!(image))
    keyed(window, st, Player.pressed(Player.feed(evs, g), 512), rest)

def show(window: Window, st: Stat, r: Player.Game & Image, rest: Window -> Stat -> Player.Game -> IO(Unit)) -> IO(Unit):
  (g, image) = r
  do IO<Unit>:
    shown : Window & Image & List<Event> <- Window.frame(window, image)
    after(shown, st, g, rest)

def elapsed(st: Stat, now: Nat) -> U32:
  Stat{on, t0, n, sum, ms10, fps, last} = st
  U32.from_nat(Nat.min(Nat.mod((now - last : Nat), 1048576n), 1048575n))

def turn(window: Window, +st: Stat, g: Player.Game, rest: Window -> Stat -> Player.Game -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    +ta : Nat <- IO.now()
    r : Player.Game & Image = Player.view_stat(Player.advance(g, elapsed(st, ta)), stat_ms(st), stat_fps(st))
    tb : Nat <- IO.now()
    show(window, stat_add(st, ta, tb), r, rest)

def loop(fuel: Nat, window: Window, st: Stat, g: Player.Game) -> IO(Unit):
  match fuel:
    case 0n:
      Window.close(window)
    case 1n+f:
      turn(window, st, g, w => s => h => loop(f, w, s, h))

def run_hs(+w: U32, hs: U32 & U32) -> IO(Unit):
  (+h, +s) = hs
  do IO<Unit>:
    g : Player.Game <- Save.load(Player.res_of((w / s : U32), (h / s : U32)))
    window : Window <- IO.try(Window, Window.open("Bendcraft", w, h))
    +t : Nat <- IO.now()
    loop(U32.to_nat(4294967295), window, Stat{False{}, t, 0, 0, 0, 0, t}, g)

def run(whs: U32 & (U32 & U32)) -> IO(Unit):
  (w, hs) = whs
  run_hs(w, hs)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("WASD move | space jump | drag to look | click break | right click place | J/L break/place | 1-8 choose | P save | F frame time | Esc quit")
    xs : List<String> <- IO.args()
    run(size_of(xs))
