import Base
import ./src/player.bend as Player
import ./src/save.bend as Save

# Bendcraft: an endless voxel world you can walk, jump, break and build,
# written in Bend and rendered by a `!` on the GPU (Metal) or on every core
# (WebAssembly). The modules under src/ hold the world, the render and the
# player; test/ holds the windowless tests and the benches; LAWS.bend the
# rules the checker proves.

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("WASD move | space jump | drag to look | click break | right click place | J/L break/place | 1-8 choose | P save | Esc quit")
    g : Player.Game <- Save.load()
    App.run(~Player.Game, ~App{g => Player.view(g), Save.tick}, "Bendcraft", 512, 512, g)
