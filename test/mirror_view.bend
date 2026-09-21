import Base
import ../src/player.bend as Player
import ../src/render.bend as Render
import ./profile.bend as Profile
import ./sky.bend as Export

# The water's mirror, on and off, from four cameras by the seed's lake. A
# mirror shows where the eye is low: from above, water reflects 2 to 10 %
# of what is over it, and nearly all of it a few degrees off its plane. So
# two cameras stand a block and a half over the water, looking across it.
# Off keeps the other looks of the base word (the caustic), so the sheet
# shows the mirror alone.
# `make mirror` turns the trees into a sheet of PNGs (Python with Pillow).
def low(g: Player.Game, yaw: F32) -> Player.Game:
  Player.G{w, px, py, pz, oy, op, vy, held, edge, mx, my, sel, res, clock, bag} = g
  Player.G{w, 45.5, 14.6, 66.5, yaw, (0.0 - 0.06 : F32), vy, held, edge, mx, my, sel, res, 300000, bag}

def off(g: Player.Game) -> Player.Game & Image:
  Player.view_more(g, Render.looks(), 0, (Render.looks_base() .&. U32.not(134217728) : U32))

def main() -> IO(Unit):
  do IO<Unit>:
    g : Player.Game = Player.start_at(Player.res_of(512, 288))
    a : Player.Game <- Export.save("build/mirror-across.tree", Player.view(low(g, 4.712389)))
    b : Player.Game <- Export.save("build/mirror-across-off.tree", off(a))
    c : Player.Game <- Export.save("build/mirror-bank.tree", Player.view(low(b, 3.1415927)))
    d : Player.Game <- Export.save("build/mirror-bank-off.tree", off(c))
    e : Player.Game <- Export.save("build/mirror-lake.tree", Player.view(Profile.lake(d)))
    f : Player.Game <- Export.save("build/mirror-lake-off.tree", off(e))
    h : Player.Game <- Export.save("build/mirror-sunset.tree", Player.view(Export.aim(Profile.lake(f), 480000, 4.068888, (0.0 - 0.35 : F32))))
    i : Player.Game <- Export.save("build/mirror-sunset-off.tree", off(h))
    IO.pure(Unit, Unit{})
