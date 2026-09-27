import Base
import ../src/player.bend as Player

# What every windowless test needs: a check that prints ok or dies, two
# floats near each other, ticks of the game, one event, and a line said
# with its game.

def expect(ok: Bool, name: String) -> IO(Unit):
  match ok:
    case True{}: IO.print("ok " ++ name)
    case False{}: IO.die(Unit, 1, "failed " ++ name)

def near(a: F32, b: F32, epsilon: F32) -> Bool:
  (F32.abs((a - b : F32)) <= epsilon : F32)

def ticks(n: Nat, g: Player.Game) -> Player.Game:
  match n:
    case 0n:
      g
    case 1n+m:
      ticks(m, Player.step(g))

def one(e: Event) -> List<Event>:
  Con{e, Nil{}}

def say(tag: String, r: Player.Game & String) -> IO(Player.Game):
  (g, s) = r
  do IO<Player.Game>:
    IO.print(tag ++ s)
    IO.pure(Player.Game, g)
