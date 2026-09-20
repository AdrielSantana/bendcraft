import Base
import ./src/player.bend as Player

# Bendcraft: an endless voxel world you can walk, jump, break and build,
# written in Bend and rendered by a `!` on the GPU (Metal) or on every core
# (WebAssembly). The modules under src/ hold the world, the render and the
# player; test/ holds the windowless tests and the benches; LAWS.bend the
# rules the checker proves.

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("WASD move | space jump | drag to look | click break | right click place | J/L break/place | Esc quit")
    App.run(~Player.Game, ~App{g => Player.view(g), Player.tick}, "Bendcraft", 512, 512, Player.start())
