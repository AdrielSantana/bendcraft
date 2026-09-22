import Base
import ../src/player.bend as Player
import ../src/render.bend as Render

# The readout, windowless: a frame with "16.4 MS  60 FPS" asked for, and its
# top left corner printed a character a pixel: # a lit dot, . the box, a
# blank the scene. `bend test/readout.bend`.

def look(img: Image, top: Bool, left: Bool, +h: U32, +x: U32, +y: U32) -> U32:
  match img:
    case Pix{c}:
      c
    case Qua{tl, tr, bl, br}:
      match top:
        case True{}:
          match left:
            case True{}:
              look(tl, (y < (h / 2) : U32), (x < (h / 2) : U32), (h / 2 : U32), x, y)
            case False{}:
              look(tr, (y < (h / 2) : U32), ((x - h) < (h / 2) : U32), (h / 2 : U32), (x - h : U32), y)
        case False{}:
          match left:
            case True{}:
              look(bl, ((y - h) < (h / 2) : U32), (x < (h / 2) : U32), (h / 2 : U32), x, (y - h : U32))
            case False{}:
              look(br, ((y - h) < (h / 2) : U32), ((x - h) < (h / 2) : U32), (h / 2 : U32), (x - h : U32), (y - h : U32))

def mark(+c: U32) -> String:
  Bool.pick(String, U32.is_eq(c, 16777215), "#", Bool.pick(String, U32.is_eq(c, 1052696), ".", " "))

def row(n: Nat, +img: Image, +x: U32, +y: U32) -> String:
  match n:
    case 0n:
      ""
    case 1n+m:
      mark(look(img, (y < 256 : U32), (x < 256 : U32), 256, x, y)) ++ row(m, img, (x + 1 : U32), y)

def rows(n: Nat, +img: Image, +y: U32) -> IO(Unit):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+m:
      do IO<Unit>:
        IO.print(row(130n, img, 0, y))
        rows(m, img, (y + 1 : U32))

def shown(r: Player.Game & Image) -> IO(Unit):
  (g, +img) = r
  rows(19n, img, 0)

def packing_ok(ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "readout packing changed a number")

def packing(n: Nat, +fps: U32) -> IO(Unit):
  match n:
    case 0n: IO.pure(Unit, Unit{})
    case 1n+m:
      do IO<Unit>:
        +stat : U32 = Render.stat_of(5000, fps)
        packing_ok(U32.is_eq(Render.stat_ms(stat), 999) && U32.is_eq(Render.stat_fps(stat), U32.min(fps, 255)))
        packing(m, (fps + 1 : U32))

def main() -> IO(Unit):
  do IO<Unit>:
    packing(257n, 0)
    shown(Player.view_stat(Player.start(), 164, 60))
