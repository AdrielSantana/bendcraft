import Base
import ./lib.bend as Lib
import ../src/water.bend as Water
import ../src/render.bend as Render
import ../src/world.bend as World
import ../src/player.bend as Player

# The water's mirror, windowless: its walk over the world, and the byte it
# leaves alone when it meets nothing. `bend test/mirror.bend`.

# one brick high over the start window, where no terrain reaches
def walled(g: Player.Game) -> World.World:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, sel, res, clock, bag} = g
  World.edit(w, 60, 70, 30, True{}, 6)

# a miss keeps walking, so its distance says nothing: only a hit's is held
def met(r: Array<U32> & Render.Glance, +col: U32, t: F32) -> Bool:
  (w, g) = r
  Render.Glance{c, at} = g
  U32.is_eq(c, col) && ((col < 1 : U32) || Lib.near(at, t, 0.001))

def walk(w: World.World, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, +col: U32, t: F32) -> Bool:
  World.W{ring, +meta} = w
  met(Render.run_glance(32n, ring, World.base(meta), ox, oy, oz, dx, dy, dz, 0), col, t)

def colour(r: Array<U32> & U32) -> U32:
  (w, c) = r
  c

# what the mirror at (ox, 30.5, 70.5) shows along x over the sky 123456,
# with no fog
def shows(w: World.World, +ox: F32) -> U32:
  World.W{ring, +meta} = w
  colour(Render.mirror_walk(False{}, 123456, 0, World.base(meta), 0, ox, 30.5, 70.5, 1.0, 0.0, 0.0, 0.0, 30.5, 0.5, 0.8, 0.0, ring))

def main() -> IO(Unit):
  do IO<Unit>:
    Lib.expect(walk(walled(Player.start()), 55.5, 30.5, 70.5, 1.0, 0.0, 0.0, 1, 4.5), "the walk meets a block's x face where it stands")
    Lib.expect(walk(walled(Player.start()), 60.5, 30.5, 75.5, 0.0, 0.0, (0.0 - 1.0 : F32), 3, 4.5), "and its z face from the other side")
    Lib.expect(walk(walled(Player.start()), 55.5, 30.5, 70.5, 0.0, 1.0, 0.0, 0, 0.0), "a ray to the sky meets nothing")
    Lib.expect(walk(walled(Player.start()), 20.5, 30.5, 70.5, 1.0, 0.0, 0.0, 0, 0.0), "a block past the walk's 32 steps is not met")
    Lib.expect(walk(walled(Player.start()), 32.5, 30.5, 70.5, 1.0, 0.0, 0.0, 1, 27.5)
      && walk(walled(Player.start()), 50.5, 30.5, 60.8, 0.70710678, 0.0, 0.70710678, 1, (9.5 / 0.70710678 : F32)), "what lies within the reach is met, along an axis and across")
    Lib.expect(Lib.near(Water.reach(21.0, 1.0, 0.0, 0.0), 0.0, 0.0001) && Lib.near(Water.reach(24.5, 1.0, 0.0, 0.0), 0.5, 0.0001)
      && Lib.near(Water.reach(28.0, 0.0, 0.0, (0.0 - 1.0 : F32)), 1.0, 0.0001) && Lib.near(Water.reach(40.0, 1.0, 0.0, 0.0), 1.0, 0.0001)
      && (Water.reach(19.0, 0.6, 0.0, (0.0 - 0.8 : F32)) > 0.79 : F32), "the mirror fades into the sky over the last quarter of the reach")
    Lib.expect(U32.is_eq(shows(walled(Player.start()), 20.5), 123456) && U32.is_eq(shows(walled(Player.start()), 31.5), 123456)
      && U32.is_ne(shows(walled(Player.start()), 55.5), 123456),
      "the mirror shows the sky behind it byte for byte where it meets nothing, a near block over it, and one at its reach's end faded into it")
    Lib.expect(Water.mirror_on(Water.with_looks(16383, Render.looks_base()))
      && Bool.not(Water.mirror_on(Water.with_looks(4294967295, 0))), "the look rides in the base's bit 27 and nowhere else")
