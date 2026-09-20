import Base
import ./util.bend as Util
import ./world.bend as World
import ./player.bend as Player

# SAVE AND LOAD: the edited columns and where the player stands, as text.
#
# The file is `bendcraft.save` in the working directory: a first line with
# the corner, the position, the look and the chosen block, then one line
# per edited column, its key "x,z" and its five words. The game loads it
# at start and writes it on P and on quit. Floats travel as thousandths,
# offset by a thousand so they stay positive.

def enc(+v: F32) -> U32:
  Util.f2u(((v + 1000.0) * 1000.0 : F32))

def dec(+n: U32) -> F32:
  (Util.u2f(n) / 1000.0 - 1000.0 : F32)

# yaw modulo a turn: a hundred turns are added first, so it is positive
def wrap(+yaw: F32) -> F32:
  (yaw + 628.31853 - Util.floorf(((yaw + 628.31853) / 6.2831853 : F32)) * 6.2831853 : F32)

def num_of(m: Maybe<&2, U32>) -> U32:
  match m:
    case None{}:
      0
    case Some{n}:
      n

def num(s: String) -> U32:
  num_of(U32.read(s))

# --- writing ---------------------------------------------------------------

def col_line(kv: Sigma<&2, &2, String, _ => World.Col>) -> String:
  (k, c) = kv
  World.Col{m, a, b, cc, d} = c
  k ++ " " ++ U32.show(m) ++ " " ++ U32.show(a) ++ " " ++ U32.show(b) ++ " " ++ U32.show(cc) ++ " " ++ U32.show(d)

def col_lines(kvs: List<&2, Sigma<&2, &2, String, _ => World.Col>>) -> String:
  match kvs:
    case Nil{}:
      ""
    case Con{kv, rest}:
      "\n" ++ col_line(kv) ++ col_lines(rest)

def text_w(+px: F32, +py: F32, +pz: F32, +yaw: F32, +pit: F32, +sel: U32, w: World.World) -> World.World & String:
  World.W{ring, +m, +ox, +oz} = w
  (World.W{ring, m, ox, oz},
   "bendcraft 1 " ++ U32.show(ox) ++ " " ++ U32.show(oz) ++ " " ++ U32.show(enc(px)) ++ " " ++ U32.show(enc(py)) ++ " " ++ U32.show(enc(pz))
   ++ " " ++ U32.show(enc(wrap(yaw))) ++ " " ++ U32.show(enc(pit)) ++ " " ++ U32.show(sel)
   ++ col_lines(Map.to_list(&2, World.Col, m)))

def text_fin(px: F32, py: F32, pz: F32, yaw: F32, pit: F32, vy: F32, held: U32, edge: U32, mx: U32, my: U32, sel: U32,
             r: World.World & String) -> Player.Game & String:
  (w, s) = r
  (Player.G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my, sel}, s)

def text(g: Player.Game) -> Player.Game & String:
  Player.G{w, +px, +py, +pz, +yaw, +pit, vy, held, edge, mx, my, +sel} = g
  text_fin(px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, text_w(px, py, pz, yaw, pit, sel, w))

def written(fr: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (f, r) = fr
  File.close(f)

def opened_w(s: String, r: Result<&1, &1, U32 & String, File>) -> IO(Unit):
  match r:
    case Fail{e}:
      IO.print("could not save")
    case Done{f}:
      IO.bind(File & Result<&1, &1, U32 & String, Unit>, Unit, File.write(f, s), written)

def save_text(path: String, r: Player.Game & String) -> IO(Player.Game):
  (g, s) = r
  do IO<Player.Game>:
    o : Result<&1, &1, U32 & String, File> <- File.open(path, "w")
    opened_w(s, o)
    IO.pure(Player.Game, g)

def save_to(path: String, g: Player.Game) -> IO(Player.Game):
  save_text(path, text(g))

def save(g: Player.Game) -> IO(Player.Game):
  save_to("bendcraft.save", g)

# --- reading ---------------------------------------------------------------

def col_of(fs: List<&2, String>, m: Map<&2, World.Col>) -> Map<&2, World.Col>:
  match fs:
    case Con{k, Con{ms, Con{a, Con{b, Con{c, Con{d, rest}}}}}}:
      Map.set(&2, World.Col, m, k, World.Col{num(ms), num(a), num(b), num(c), num(d)})
    case Con{k, rest}:
      m
    case Nil{}:
      m

def cols_of(ls: List<&2, String>, m: Map<&2, World.Col>) -> Map<&2, World.Col>:
  match ls:
    case Nil{}:
      m
    case Con{l, rest}:
      cols_of(rest, col_of(String.split(l, ' '), m))

def game_of(fs: List<&2, String>, ls: List<&2, String>) -> Player.Game:
  match fs:
    case Con{tag, Con{ver, Con{ox, Con{oz, Con{px, Con{py, Con{pz, Con{yaw, Con{pit, Con{sel, rest}}}}}}}}}}:
      +cx = num(ox)
      +cz = num(oz)
      Player.G{World.load_all(128n, World.W{[0 : U32^17n], cols_of(ls, Map.new(&2, World.Col)), cx, cz}, cx, cz),
               dec(num(px)), dec(num(py)), dec(num(pz)), dec(num(yaw)), dec(num(pit)), 0.0, 0, 0, 0, 0, num(sel)}
    case Con{tag, rest}:
      Player.start()
    case Nil{}:
      Player.start()

def parse(ls: List<&2, String>) -> Player.Game:
  match ls:
    case Nil{}:
      Player.start()
    case Con{head, rest}:
      game_of(String.split(head, ' '), rest)

def load_text(r: Result<&1, &1, U32 & String, String>) -> Player.Game:
  match r:
    case Fail{e}:
      Player.start()
    case Done{s}:
      parse(String.lines(s))

def read_fin(fr: File & Result<&1, &1, U32 & String, String>) -> IO(Player.Game):
  (f, r) = fr
  do IO<Player.Game>:
    File.close(f)
    IO.pure(Player.Game, load_text(r))

def sized_r(f: File, r: Result<&1, &1, U32 & String, U32>) -> IO(Player.Game):
  match r:
    case Fail{e}:
      do IO<Player.Game>:
        File.close(f)
        IO.pure(Player.Game, Player.start())
    case Done{n}:
      IO.bind(File & Result<&1, &1, U32 & String, String>, Player.Game, File.read(f, n), read_fin)

def sized(fr: File & Result<&1, &1, U32 & String, U32>) -> IO(Player.Game):
  (f, r) = fr
  sized_r(f, r)

def opened_r(r: Result<&1, &1, U32 & String, File>) -> IO(Player.Game):
  match r:
    case Fail{e}:
      IO.pure(Player.Game, Player.start())
    case Done{f}:
      IO.bind(File & Result<&1, &1, U32 & String, U32>, Player.Game, File.size(f), sized)

def load_from(path: String) -> IO(Player.Game):
  IO.bind(Result<&1, &1, U32 & String, File>, Player.Game, File.open(path, "r"), opened_r)

def load() -> IO(Player.Game):
  load_from("bendcraft.save")

# --- the tick with the file: P saves, quitting saves ------------------------

def after_save(quit: Bool, g: Player.Game) -> IO(Maybe<Player.Game>):
  match quit:
    case True{}:
      IO.pure(Maybe<Player.Game>, None{})
    case False{}:
      IO.pure(Maybe<Player.Game>, Some{g})

def saved(quit: Bool, g: Player.Game) -> IO(Maybe<Player.Game>):
  IO.bind(Player.Game, Maybe<Player.Game>, save(g), after_save(quit))

def alive_go(act: Bool, +quit: Bool, g: Player.Game) -> IO(Maybe<Player.Game>):
  match act:
    case True{}:
      saved(quit, g)
    case False{}:
      IO.pure(Maybe<Player.Game>, Some{g})

def alive(g: Player.Game) -> IO(Maybe<Player.Game>):
  Player.G{w, px, py, pz, yaw, pit, vy, held, +edge, mx, my, sel} = g
  +quit = Util.on(edge, 4096)
  alive_go(quit || Util.on(edge, 256), quit, Player.G{w, px, py, pz, yaw, pit, vy, held, 0, mx, my, sel})

def tick(evs: List<Event>, g: Player.Game) -> IO(Maybe<Player.Game>):
  alive(Player.step(Player.feed(evs, g)))
