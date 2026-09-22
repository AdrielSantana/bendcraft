import Base
import ../src/day.bend as Day
import ../src/inventory.bend as Inventory
import ../src/sky.bend as Sky
import ../src/render.bend as Render
import ../src/world.bend as World
import ../src/player.bend as Player
import ../src/save.bend as Save

def expect(ok: Bool, name: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("ok " ++ name)
    case False{}:
      IO.die(Unit, 1, "failed " ++ name)

def blocked(r: Array<U32> & Bool) -> Bool:
  (w, got) = r
  got

# Each blocker is five cells away, beyond the initial cell and in range
# of the fixed shadow walk. Reversing the ray must leave it behind.
def probe(+x: U32, +y: U32, +z: U32, +dx: F32, +dy: F32, +dz: F32) -> Bool:
  w = Array.set(U32, [0 : U32^18n], World.col_at(0, x, z), U32.shln(1, U32.to_nat(y)))
  blocked(Render.run_shadow(w, 0, 64.5, 10.5, 64.5, dx, dy, dz))

def clock(g: Player.Game) -> U32:
  Player.G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, t, bag} = g
  t

def restored(r: Player.Game & String) -> U32:
  (g, text) = r
  clock(Save.parse(String.lines(text), Player.res512()))

def fixture(t: U32) -> Player.Game:
  Player.G{World.W{[0 : U32^18n], Map.new(&2, World.Col), 1048512, 1048512},
    64.5, 30.0, 64.5, 0.0, 0.0, 0.0, 0, 0, 0, 0, 0, Player.res512(), t, Inventory.empty()}

def main() -> IO(Unit):
  do IO<Unit>:
    expect(U32.is_ne(Sky.gradient(True{}, 0.0, 0.8), Sky.gradient(True{}, 1.0, 0.8)), "sky has a vertical gradient")
    expect((Sky.gradient(True{}, 0.5, (0.0 - 1.0 : F32)) < Sky.gradient(True{}, 0.5, 1.0) : U32), "night sky is darker")
    expect(F32.is_eq(Sky.fog(0, 40.0, 5.0, 5.0), 0.0), "fog flags disable both terms")
    expect(F32.is_eq(Sky.fog(8, 34.0, 30.0, 30.0), 1.0), "distant terrain reaches sky colour")
    expect((Sky.fog(2147483648, 20.0, 5.0, 5.0) > Sky.fog(2147483648, 20.0, 30.0, 30.0) : F32), "mist is denser near the ground")
    expect(U32.is_ne(Sky.sun(True{}, 0, 1.0, 0.8, 0.8), 0), "sun disc")
    expect(U32.is_eq(Sky.sun(False{}, 123, 1.0, 0.8, 0.8), 123), "sun flag")
    expect(U32.is_ne(Sky.moon(True{}, 0, (0.0 - 1.0 : F32), 0.0, 1.0, 0.0, (0.0 - 1.0 : F32)), 0), "moon disc")
    expect(U32.is_eq(Sky.moon(False{}, 123, (0.0 - 1.0 : F32), 0.0, 1.0, 0.0, (0.0 - 1.0 : F32)), 123), "moon flag")
    expect(probe(69, 10, 64, 1.0, 0.0, 0.0), "shadow +x")
    expect(probe(59, 10, 64, (0.0 - 1.0 : F32), 0.0, 0.0), "shadow -x")
    expect(probe(64, 15, 64, 0.0, 1.0, 0.0), "shadow +y")
    expect(probe(64, 5, 64, 0.0, (0.0 - 1.0 : F32), 0.0), "shadow -y")
    expect(probe(64, 10, 69, 0.0, 0.0, 1.0), "shadow +z")
    expect(probe(64, 10, 59, 0.0, 0.0, (0.0 - 1.0 : F32)), "shadow -z")
    expect(Bool.not(probe(69, 10, 64, (0.0 - 1.0 : F32), 0.0, 0.0)), "block behind ray")
    expect(probe(59, 18, 60, (0.0 - 0.48 : F32), 0.8, (0.0 - 0.36 : F32)), "afternoon shadow")
    expect(U32.is_eq(clock(Player.advance(fixture(1048575), 2)), 1), "clock wraps")
    expect(U32.is_eq(clock(Player.advance(Player.advance(fixture(1234), 16), 17)),
                     clock(Player.advance(fixture(1234), 33))), "frame rate independent clock")
    expect(U32.is_eq(restored(Save.text(fixture(786432))), 786432), "save restores night")
    expect(U32.is_eq(clock(Save.parse(["bendcraft 1 1048512 1048512 1064500 1030000 1064500 1000000 1000000 0"], Player.res512())), Day.morning()), "old save starts at morning")
