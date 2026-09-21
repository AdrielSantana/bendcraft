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

def run_hs(+w: U32, hs: U32 & U32) -> IO(Unit):
  (+h, +s) = hs
  do IO<Unit>:
    g : Player.Game <- Save.load(Player.res_of((w / s : U32), (h / s : U32)))
    App.run(~Player.Game, ~App{g => Player.view(g), Save.tick}, "Bendcraft", w, h, g)

def run(whs: U32 & (U32 & U32)) -> IO(Unit):
  (w, hs) = whs
  run_hs(w, hs)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("WASD move | space jump | drag to look | click break | right click place | J/L break/place | 1-8 choose | P save | Esc quit")
    xs : List<String> <- IO.args()
    run(size_of(xs))
