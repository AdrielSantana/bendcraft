import Base
import ../src/player.bend as Player
import ../src/render.bend as Render
import ./profile.bend as Profile
import ./sky.bend as Export

# Inspect the real GPU image, above and below the surface and with the
# look disabled. This camera sits beside the seed's lake west of spawn.
def main() -> IO(Unit):
  do IO<Unit>:
    g : Player.Game = Player.start_at(Player.res_of(512, 288))
    a : Player.Game <- Export.save("build/water-default.tree", Player.view(g))
    b : Player.Game <- Export.save("build/water-lake.tree", Player.view(Profile.lake(a)))
    c : Player.Game <- Export.save("build/water-off.tree", Player.view_with(b, (Render.looks() .&. U32.not(2097152) : U32)))
    d : Player.Game <- Export.save("build/water-dusk.tree", Player.view(Export.aim(c, 524288, (0.0 - 1.5707963 : F32), (0.0 - 0.4 : F32))))
    e : Player.Game <- Export.save("build/water-under.tree", Player.view(Profile.submerged(Export.aim(d, 154747, 0.0, 0.0))))
    f : Player.Game <- Export.save("build/water-under-off.tree", Player.view_with(e, (Render.looks() .&. U32.not(4194304) : U32)))
    IO.pure(Unit, Unit{})
