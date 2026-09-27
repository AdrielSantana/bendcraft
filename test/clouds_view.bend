import Base
import ../src/player.bend as Player
import ../src/frame.bend as Frame
import ../src/render.bend as Render
import ./sky.bend as Export

# the clouds from the start's hill: at each time of day, towards the sun
# and away from it, overhead, and the ground under their shadows, with
# each look off beside it
def main() -> IO(Unit):
  do IO<Unit>:
    g : Player.Game = Player.start_at(Player.res_of(512, 288))
    a : Player.Game <- Export.save("build/clouds-morning.tree", Frame.view(Export.aim(g, 154747, 0.9272952, 0.35)))
    b : Player.Game <- Export.save("build/clouds-morning-off.tree", Frame.view_with(a, (Render.looks() .&. U32.not(128) : U32)))
    c : Player.Game <- Export.save("build/clouds-away.tree", Frame.view(Export.aim(b, 154747, 4.068888, 0.35)))
    d : Player.Game <- Export.save("build/clouds-overhead.tree", Frame.view(Export.aim(c, 262144, 0.9272952, 1.1)))
    e : Player.Game <- Export.save("build/clouds-sunset.tree", Frame.view(Export.aim(d, 510000, 4.068888, 0.25)))
    f : Player.Game <- Export.save("build/clouds-night.tree", Frame.view(Export.aim(e, 786432, 0.9272952, 0.5)))
    h : Player.Game <- Export.save("build/clouds-ground.tree", Frame.view(Export.aim(f, 200000, 2.4, (0.0 - 0.6 : F32))))
    i : Player.Game <- Export.save("build/clouds-ground-off.tree", Frame.view_with(h, (Render.looks() .&. U32.not(256) : U32)))
    IO.pure(Unit, Unit{})
