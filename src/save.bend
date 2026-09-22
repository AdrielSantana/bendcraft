import Base
import ./util.bend as Util
import ./world.bend as World
import ./player.bend as Player
import ./day.bend as Day
import ./inventory.bend as Inventory

# SAVE AND LOAD: the edited columns and where the player stands, as text.
#
# The file is `bendcraft.save` in the working directory: a first line with
# the corner, position, look, chosen block, optional day clock and eight
# optional counts, then a line per edited column: its key "x,z", five solid
# words and an optional water mask. The game loads it
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
  World.Col{m, a, b, cc, d, water, lv} = c
  World.Levels{la, lb, lc, ld} = lv
  k ++ " " ++ U32.show(m) ++ " " ++ U32.show(a) ++ " " ++ U32.show(b) ++ " " ++ U32.show(cc) ++ " " ++ U32.show(d) ++ " " ++ U32.show(water)
    ++ " " ++ U32.show(la) ++ " " ++ U32.show(lb) ++ " " ++ U32.show(lc) ++ " " ++ U32.show(ld)

def col_lines(kvs: List<&2, Sigma<&2, &2, String, _ => World.Col>>) -> String:
  match kvs:
    case Nil{}:
      ""
    case Con{kv, rest}:
      "\n" ++ col_line(kv) ++ col_lines(rest)

def counts_text(xs: List<&2, Nat>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{h, t}:
      " " ++ Nat.show(h) ++ counts_text(t)

def text_w(+px: F32, +py: F32, +pz: F32, +yaw: F32, +pit: F32, +sel: U32, clock: U32, bag: List<&2, Nat>, w: World.World) -> World.World & String:
  World.W{ring, +m, +ox, +oz} = w
  (World.W{ring, m, ox, oz},
   "bendcraft 1 " ++ U32.show(ox) ++ " " ++ U32.show(oz) ++ " " ++ U32.show(enc(px)) ++ " " ++ U32.show(enc(py)) ++ " " ++ U32.show(enc(pz))
   ++ " " ++ U32.show(enc(wrap(yaw))) ++ " " ++ U32.show(enc(pit)) ++ " " ++ U32.show(sel) ++ " " ++ U32.show(clock) ++ counts_text(bag)
   ++ col_lines(Map.to_list(&2, World.Col, m)))

def text_fin(px: F32, py: F32, pz: F32, yaw: F32, pit: F32, vy: F32, held: U32, edge: U32, mx: U32, my: U32, sel: U32, res: U32, clock: U32, bag: List<&2, Nat>,
             r: World.World & String) -> Player.Game & String:
  (w, s) = r
  (Player.G{w, px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag}, s)

def text(g: Player.Game) -> Player.Game & String:
  Player.G{w, +px, +py, +pz, +yaw, +pit, vy, held, edge, mx, my, +sel, res, +clock, +bag} = g
  text_fin(px, py, pz, yaw, pit, vy, held, edge, mx, my, sel, res, clock, bag, text_w(px, py, pz, yaw, pit, sel, clock, bag, w))

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

# Five-word columns predate water. Restore only the natural lake above
# the original terrain, leaving old excavations dry. An explicit zero in
# the sixth word remains zero after loading.
def legacy_water(coords: List<&2, String>, +solid: U32) -> U32:
  match coords:
    case Con{x, Con{z, rest}}: World.flood(World.terrain(num(x), num(z)), solid)
    case Con{x, rest}: 0
    case Nil{}: 0

def water_of(fs: List<&2, String>, k: String, +solid: U32) -> U32:
  match fs:
    case Nil{}: legacy_water(String.split(k, ','), solid)
    case Con{w, rest}: (num(w) .&. U32.not(solid) : U32)

# The four amount words follow the water word; a column saved before
# them is full wherever it is wet.
def levels_of(fs: List<&2, String>, +water: U32) -> World.Levels:
  match fs:
    case Con{w, Con{la, Con{lb, Con{lc, Con{ld, rest}}}}}: World.Levels{num(la), num(lb), num(lc), num(ld)}
    case Con{w, rest}: World.full_levels(water)
    case Nil{}: World.full_levels(water)

def col_with(+k: String, +ms: U32, a: U32, b: U32, c: U32, d: U32, +water: U32, fs: List<&2, String>, m: Map<&2, World.Col>) -> Map<&2, World.Col>:
  Map.set(&2, World.Col, m, k, World.Col{ms, a, b, c, d, water, levels_of(fs, water)})

def col_of(fs: List<&2, String>, m: Map<&2, World.Col>) -> Map<&2, World.Col>:
  match fs:
    case Con{+k, Con{+ms, Con{a, Con{b, Con{c, Con{d, +rest}}}}}}:
      col_with(k, num(ms), num(a), num(b), num(c), num(d), water_of(rest, k, num(ms)), rest, m)
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

# Old headers end after sel; their morning is the new game's morning.
def clock_of(fs: List<&2, String>) -> U32:
  match fs:
    case Nil{}:
      Day.morning()
    case Con{t, rest}:
      Day.phase(num(t))

def natural(m: Maybe<&2, Nat>) -> Nat:
  match m:
    case None{}: 0n
    case Some{n}: n

# Every load makes eight slots. Missing fields in old headers are zero;
# the optional clock stays before them. Column water is parsed separately.
def counts_of(n: Nat, fs: List<&2, String>) -> List<&2, Nat>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      match fs:
        case Nil{}:
          Con{0n, counts_of(p, Nil{})}
        case Con{h, t}:
          Con{natural(Nat.read(h)), counts_of(p, t)}

def inventory_of(fs: List<&2, String>) -> List<&2, Nat>:
  match fs:
    case Nil{}: Inventory.empty()
    case Con{clock, counts}: counts_of(8n, counts)

def game_of(fs: List<&2, String>, ls: List<&2, String>, +res: U32) -> Player.Game:
  match fs:
    case Con{tag, Con{ver, Con{ox, Con{oz, Con{px, Con{py, Con{pz, Con{yaw, Con{pit, Con{sel, +rest}}}}}}}}}}:
      +cx = num(ox)
      +cz = num(oz)
      Player.G{World.load_all(128n, World.W{[0 : U32^18n], cols_of(ls, Map.new(&2, World.Col)), cx, cz}, cx, cz),
               dec(num(px)), dec(num(py)), dec(num(pz)), dec(num(yaw)), dec(num(pit)), 0.0, 0, 0, 0, 0, (num(sel) % 8 : U32), res, clock_of(rest), inventory_of(rest)}
    case Con{tag, rest}:
      Player.start_at(res)
    case Nil{}:
      Player.start_at(res)

def parse(ls: List<&2, String>, +res: U32) -> Player.Game:
  match ls:
    case Nil{}:
      Player.start_at(res)
    case Con{head, rest}:
      game_of(String.split(head, ' '), rest, res)

def load_text(r: Result<&1, &1, U32 & String, String>, +res: U32) -> Player.Game:
  match r:
    case Fail{e}:
      Player.start_at(res)
    case Done{s}:
      parse(String.lines(s), res)

def read_fin(+res: U32, fr: File & Result<&1, &1, U32 & String, String>) -> IO(Player.Game):
  (f, r) = fr
  do IO<Player.Game>:
    File.close(f)
    IO.pure(Player.Game, load_text(r, res))

def sized_r(+res: U32, f: File, r: Result<&1, &1, U32 & String, U32>) -> IO(Player.Game):
  match r:
    case Fail{e}:
      do IO<Player.Game>:
        File.close(f)
        IO.pure(Player.Game, Player.start_at(res))
    case Done{n}:
      IO.bind(File & Result<&1, &1, U32 & String, String>, Player.Game, File.read(f, n), read_fin(res))

def sized(+res: U32, fr: File & Result<&1, &1, U32 & String, U32>) -> IO(Player.Game):
  (f, r) = fr
  sized_r(res, f, r)

def opened_r(+res: U32, r: Result<&1, &1, U32 & String, File>) -> IO(Player.Game):
  match r:
    case Fail{e}:
      IO.pure(Player.Game, Player.start_at(res))
    case Done{f}:
      IO.bind(File & Result<&1, &1, U32 & String, U32>, Player.Game, File.size(f), sized(res))

def load_from(path: String, +res: U32) -> IO(Player.Game):
  IO.bind(Result<&1, &1, U32 & String, File>, Player.Game, File.open(path, "r"), opened_r(res))

def load(+res: U32) -> IO(Player.Game):
  load_from("bendcraft.save", res)

# --- the tick with the file: P saves, quitting saves ------------------------

def after_save(quit: Bool, g: Player.Game) -> IO(Maybe<Player.Game>):
  match quit:
    case True{}:
      IO.pure(Maybe<Player.Game>, None{})
    case False{}:
      IO.pure(Maybe<Player.Game>, Some{g})

def saved(path: String, quit: Bool, g: Player.Game) -> IO(Maybe<Player.Game>):
  IO.bind(Player.Game, Maybe<Player.Game>, save_to(path, g), after_save(quit))

def alive_go(act: Bool, +quit: Bool, path: String, g: Player.Game) -> IO(Maybe<Player.Game>):
  match act:
    case True{}:
      saved(path, quit, g)
    case False{}:
      IO.pure(Maybe<Player.Game>, Some{g})

def alive_at(path: String, g: Player.Game) -> IO(Maybe<Player.Game>):
  Player.G{w, px, py, pz, yaw, pit, vy, held, +edge, mx, my, sel, res, clock, bag} = g
  +quit = Util.on(edge, 4096)
  alive_go(quit || Util.on(edge, 256), quit, path, Player.G{w, px, py, pz, yaw, pit, vy, held, 0, mx, my, sel, res, clock, bag})

def tick_to(path: String, evs: List<Event>, g: Player.Game) -> IO(Maybe<Player.Game>):
  alive_at(path, Player.step(Player.feed(evs, g)))

def tick(evs: List<Event>, g: Player.Game) -> IO(Maybe<Player.Game>):
  tick_to("bendcraft.save", evs, g)
