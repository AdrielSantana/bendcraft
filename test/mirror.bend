import Base
import ../src/water.bend as Water
import ../src/render.bend as Render
import ../src/world.bend as World
import ../src/player.bend as Player

# The water's mirror, windowless: its walk over the world, and the byte it
# leaves alone when it meets nothing. `bend test/mirror.bend`.

def expect(ok: Bool, name: String) -> IO(Unit):
  match ok:
    case True{}: IO.print("ok " ++ name)
    case False{}: IO.die(Unit, 1, "failed " ++ name)

def near(a: F32, b: F32, epsilon: F32) -> Bool:
  (F32.abs((a - b : F32)) <= epsilon : F32)

# one brick high over the start window, where no terrain reaches
def walled(g: Player.Game) -> World.World:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag} = g
  World.edit(w, 60, 70, 30, True{}, 6)

# a miss keeps walking, so its distance says nothing: only a hit's is held
def met(r: Array<U32> & Render.Glance, +col: U32, t: F32) -> Bool:
  (w, g) = r
  Render.Glance{c, at} = g
  U32.is_eq(c, col) && ((col < 1 : U32) || near(at, t, 0.001))

def walk(w: World.World, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, +col: U32, t: F32) -> Bool:
  World.W{ring, m, +cx, +cz} = w
  met(Render.run_glance(ring, (cx * 128 + cz : U32), ox, oy, oz, dx, dy, dz), col, t)

def main() -> IO(Unit):
  do IO<Unit>:
    expect(walk(walled(Player.start()), 55.5, 30.5, 70.5, 1.0, 0.0, 0.0, 1, 4.5), "the walk meets a block's x face where it stands")
    expect(walk(walled(Player.start()), 60.5, 30.5, 75.5, 0.0, 0.0, (0.0 - 1.0 : F32), 3, 4.5), "and its z face from the other side")
    expect(walk(walled(Player.start()), 55.5, 30.5, 70.5, 0.0, 1.0, 0.0, 0, 0.0), "a ray to the sky meets nothing")
    expect(walk(walled(Player.start()), 20.5, 30.5, 70.5, 1.0, 0.0, 0.0, 0, 0.0), "a block past the walk's 32 steps is not met")
    expect(walk(walled(Player.start()), 32.5, 30.5, 70.5, 1.0, 0.0, 0.0, 1, 27.5)
      && walk(walled(Player.start()), 50.5, 30.5, 60.8, 0.70710678, 0.0, 0.70710678, 1, (9.5 / 0.70710678 : F32)), "what lies within the reach is met, along an axis and across")
    expect(near(Water.reach(21.0, 1.0, 0.0, 0.0), 0.0, 0.0001) && near(Water.reach(24.5, 1.0, 0.0, 0.0), 0.5, 0.0001)
      && near(Water.reach(28.0, 0.0, 0.0, (0.0 - 1.0 : F32)), 1.0, 0.0001) && near(Water.reach(40.0, 1.0, 0.0, 0.0), 1.0, 0.0001)
      && (Water.reach(19.0, 0.6, 0.0, (0.0 - 0.8 : F32)) > 0.79 : F32), "the mirror fades into the sky over the last quarter of the reach")
    expect(U32.is_eq(Water.in_mirror(False{}, 123456, 654321, 0.5), 123456), "a miss leaves the mirrored sky's byte alone")
    expect(U32.is_eq(Water.in_mirror(True{}, 0, 16777215, 1.0), 0) && U32.is_eq(Water.in_mirror(True{}, 0, 16777215, 0.0), 16777215), "a hit fades into the sky behind it with the fog")
    expect(Water.mirror_on(Water.with_looks(Water.frame_base(16383, 8191), Render.looks_base()))
      && Bool.not(Water.mirror_on(Water.with_looks(Water.frame_base(4294967295, 8191), 0))), "the look rides in the base's bit 27 and nowhere else")
