import Base
import ../src/player.bend as Player

# Save the actual Bend Image tree for inspection with test/sky.py. The
# host walks it once; no screenshot effect or alternative renderer is used.
def tree(img: Image) -> String:
  match img:
    case Pix{c}:
      "P " ++ U32.show(c) ++ "\n"
    case Qua{tl, tr, bl, br}:
      "Q\n" ++ tree(tl) ++ tree(tr) ++ tree(bl) ++ tree(br)

def aim(g: Player.Game, t: U32, yaw: F32, pit: F32) -> Player.Game:
  Player.G{w, px, py, pz, oldyaw, oldpit, vy, held, edge, mx, my, sel, res, clock} = g
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, t}

def written(g: Player.Game, r: File & Result<&1, &1, U32 & String, Unit>) -> IO(Player.Game):
  (f, result) = r
  do IO<Player.Game>:
    IO.try(Unit, IO.pure(Result<&1, &1, U32 & String, Unit>, result))
    File.close(f)
    IO.pure(Player.Game, g)

def save(path: String, r: Player.Game & Image) -> IO(Player.Game):
  (g, img) = r
  do IO<Player.Game>:
    f : File <- IO.try(File, File.open(path, "w"))
    result : File & Result<&1, &1, U32 & String, Unit> <- File.write(f, tree(img))
    written(g, result)

def main() -> IO(Unit):
  do IO<Unit>:
    g : Player.Game = Player.start_at(Player.res_of(512, 288))
    a : Player.Game <- save("build/sky-dawn.tree", Player.view(aim(g, 0, 0.9272952, 0.1)))
    b : Player.Game <- save("build/sky-morning.tree", Player.view(aim(a, 154747, 0.9272952, 0.1)))
    c : Player.Game <- save("build/sky-noon.tree", Player.view(aim(b, 262144, 0.9272952, 1.1)))
    d : Player.Game <- save("build/sky-dusk.tree", Player.view(aim(c, 524288, 4.068888, 0.1)))
    e : Player.Game <- save("build/sky-night.tree", Player.view(aim(d, 786432, 0.9272952, 1.1)))
    f : Player.Game <- save("build/sky-default.tree", Player.view(aim(e, 154747, 0.0, (0.0 - 0.55 : F32))))
    IO.pure(Unit, Unit{})
