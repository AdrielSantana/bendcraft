import Base
import ../src/player.bend as Player
import ../src/render.bend as Render
import ../src/world.bend as World
import ../src/water.bend as Water
import ../src/inventory.bend as Inventory
import ./profile.bend as Profile
import ./sky.bend as Export

# Hold the camera and sun fixed so the exported sequence isolates ripples.
def phase_camera(cam: Render.Cam, t: U32) -> Render.Cam:
  Render.Cam{px, py, pz, yaw, pit, +base, sel, items, fl, rw, rh, lx, ly, lz} = cam
  Render.Cam{px, py, pz, yaw, pit, Water.with_looks(Water.frame_base(base, t), base), sel, items, fl, rw, rh, lx, ly, lz}

def phase_view(g: Player.Game, t: U32) -> Player.Game & Image:
  Player.G{w, +px, +py, +pz, +yaw, +pit, vy, held, edge, mx, my, +sel, +res, +clock, +bag} = g
  World.W{ring, m, +ox, +oz, q, np, made, gone} = w
  +rw = (res / 65536 : U32)
  +rh = (res % 65536 : U32)
  Player.view_fin(px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag, m, ox, oz, q, np, made, gone,
    Render.frame(phase_camera(Render.camera(px, py, pz, yaw, pit, Render.stat_base((ox * 128 + oz : U32), 0), Render.looks_base(),
      Inventory.hud_lo(sel, bag), Inventory.hud_hi(bag), Render.looks(), rw, rh, clock), t), ring, rw, rh))

def motion(n: Nat, +i: U32, g: Player.Game) -> IO(Unit):
  match n:
    case 0n: IO.pure(Unit, Unit{})
    case 1n+k:
      do IO<Unit>:
        next : Player.Game <- Export.save("build/water-motion-" ++ U32.show(i) ++ ".tree", phase_view(g, (i * 64 : U32)))
        motion(k, (i + 1 : U32), next)

# Inspect the real GPU image, above and below the surface and with the
# look disabled. This camera sits beside the seed's lake west of spawn.
# a diver at the lake's deepest bed (local 36, 66: terrain 7, water to
# 11), looking east along it, where the bed climbs to the bank
def diver(g: Player.Game) -> Player.Game:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag} = g
  Player.G{w, 36.5, 8.3, 66.5, 1.5707963, (0.0 - 0.25 : F32), vy, held, edge, mx, my, sel, res, 300000, bag}

# a stair of amounts 32 to 224 (an eighth a step) in the lake's top
# cells (y 11) across the lake view's middle: the surface lowered to
# each level
def stair(n: Nat, g: Player.Game, +i: U32) -> Player.Game:
  match n:
    case 0n: g
    case 1n+k:
      Player.G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag} = g
      stair(k, Player.G{World.pour(w, (38 + i * 2 : U32), 11, 66, ((i + 1) * 32 : U32)), px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag}, (i + 1 : U32))

def main() -> IO(Unit):
  do IO<Unit>:
    g : Player.Game = Player.start_at(Player.res_of(512, 288))
    a : Player.Game <- Export.save("build/water-default.tree", Player.view(g))
    b : Player.Game <- Export.save("build/water-lake.tree", Player.view(Profile.lake(a)))
    q0 : Player.Game <- Export.save("build/water-caustic.tree", Player.view(Export.aim(Profile.lake(b), 300000, (0.0 - 1.5707963 : F32), (0.0 - 0.75 : F32))))
    q1 : Player.Game <- Export.save("build/water-caustic-off.tree", Player.view_more(q0, Render.looks(), 0, (Render.looks_base() .&. U32.not(268435456) : U32)))
    q2 : Player.Game <- Export.save("build/water-bed.tree", Player.view(diver(q1)))
    q : Player.Game <- Export.save("build/water-levels.tree", Player.view(Export.aim(stair(7n, Profile.lake(q2), 0), 300000, (0.0 - 1.5707963 : F32), (0.0 - 0.5 : F32))))
    r : Player.Game <- Export.save("build/water-reflection-off.tree", Player.view_with(q, (Render.looks() .&. U32.not(16777216) : U32)))
    s : Player.Game <- Export.save("build/water-fresnel-off.tree", Player.view_with(r, (Render.looks() .&. U32.not(8388608) : U32)))
    c : Player.Game <- Export.save("build/water-off.tree", Player.view_with(s, (Render.looks() .&. U32.not(2097152) : U32)))
    d : Player.Game <- Export.save("build/water-dusk.tree", Player.view(Export.aim(c, 524288, (0.0 - 1.5707963 : F32), (0.0 - 0.4 : F32))))
    e : Player.Game <- Export.save("build/water-under.tree", Player.view(Profile.submerged(Export.aim(d, 154747, 0.0, 0.0))))
    f : Player.Game <- Export.save("build/water-under-off.tree", Player.view_with(e, (Render.looks() .&. U32.not(4194304) : U32)))
    h : Player.Game <- Export.save("build/water-sunset-reflection.tree", Player.view(Export.aim(Profile.lake(f), 480000, 4.068888, (0.0 - 0.35 : F32))))
    i : Player.Game <- Export.save("build/water-night-reflection.tree", Player.view(Profile.night_lake(h)))
    j : Player.Game <- Export.save("build/water-night-ripples-off.tree", Player.view_with(i, (Render.looks() .&. U32.not(1048576) : U32)))
    motion(128n, 0, j)
