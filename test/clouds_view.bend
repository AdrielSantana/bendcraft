import Base
import ../src/player.bend as Player
import ../src/frame.bend as Frame
import ../src/render.bend as Render
import ./sky.bend as Export

# the clouds from the start's hill: at each time of day, towards the sun
# and away from it, overhead, on a clear day and an overcast one, the
# ground under their shadows, and wet in the rain and after it, with each
# look off beside it
def main() -> IO(Unit):
  do IO<Unit>:
    g : Player.Game = Player.start_at(Player.res_of(512, 288))
    a : Player.Game <- Export.save("build/clouds-morning.tree", Frame.view(Export.aim(g, 154747, 0.9272952, 0.35)))
    b : Player.Game <- Export.save("build/clouds-morning-off.tree", Frame.view_with(a, (Render.looks() .&. U32.not(128) : U32)))
    c : Player.Game <- Export.save("build/clouds-clear.tree", Frame.view(Export.aim(b, 3300475, 0.9272952, 0.35)))
    d : Player.Game <- Export.save("build/clouds-overcast.tree", Frame.view(Export.aim(c, 1203323, 0.9272952, 0.35)))
    e : Player.Game <- Export.save("build/clouds-away.tree", Frame.view(Export.aim(d, 154747, 4.068888, 0.35)))
    f : Player.Game <- Export.save("build/clouds-overhead.tree", Frame.view(Export.aim(e, 262144, 0.9272952, 1.1)))
    h : Player.Game <- Export.save("build/clouds-sunset.tree", Frame.view(Export.aim(f, 510000, 4.068888, 0.25)))
    i : Player.Game <- Export.save("build/clouds-night.tree", Frame.view(Export.aim(h, 786432, 0.9272952, 0.5)))
    j : Player.Game <- Export.save("build/clouds-ground.tree", Frame.view(Export.aim(i, 200000, 2.4, (0.0 - 0.6 : F32))))
    k : Player.Game <- Export.save("build/clouds-ground-off.tree", Frame.view_with(j, (Render.looks() .&. U32.not(256) : U32)))
    l : Player.Game <- Export.save("build/clouds-ground-overcast.tree", Frame.view(Export.aim(k, 1203323, 2.4, (0.0 - 0.6 : F32))))
    m : Player.Game <- Export.save("build/clouds-ground-clear.tree", Frame.view(Export.aim(l, 3300475, 2.4, (0.0 - 0.6 : F32))))
    n : Player.Game <- Export.save("build/clouds-wet.tree", Frame.view(Export.aim(m, 1203323, 2.4, (0.0 - 0.25 : F32))))
    o : Player.Game <- Export.save("build/clouds-wet-off.tree", Frame.view_with(n, (Render.looks() .&. U32.not(1024) : U32)))
    q : Player.Game <- Export.save("build/clouds-drying.tree", Frame.view(Export.aim(o, 5400000, 2.4, (0.0 - 0.25 : F32))))
    IO.pure(Unit, Unit{})
