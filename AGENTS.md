# For an agent working on Bendcraft

Bend's guide gives an agent four lines, and they hold here:

```
When using Bend:
- run `bend guide` to learn it
- use `LAWS.bend` to keep important rules
- run `bend PROOF.bend` before committing
- parallelize the code whenever possible
```

The rest of this file is what those lines mean in this repository.

Bendcraft is a voxel game written in Bend 2, a new language: pure, affine,
proof-checked, run on the GPU by a parallel call marked `!`. You have very
likely not seen Bend 2 in training. Do not guess its syntax from Python or
from Bend 1. Read before you write:

- `bend guide` (the language), `bend guide shaders` (what makes a `!` fast
  or slow, written by AIs for AIs from a 120 FPS demo) and `bend base` (the
  Base library's source). All ship with the compiler.
- `README.md` (how the game works, the numbers, what costs what) and
  `ROADMAP.md` (the vision, the order of work, what was tried and failed).
- `src/*.bend` as the examples of every construct you will need.

Check early and often: `bend file.bend --check-only` takes a second.

## Think in Bend, not in OpenGL

The habit to drop first. An agent asked for graphics reaches for what it
knows: vertex buffers, a draw loop that mutates a framebuffer, shader
source in strings, a C effect that calls Metal or OpenGL, a thread pool.
None of that exists here and none of it is wanted. The game's point is
that Bend alone is enough. What takes their place:

- **A frame is a value.** `view : Game -> Game & Image`, and an `Image` is
  a quadtree: `Pix{colour}` paints a square, `Qua{tl, tr, bl, br}` splits
  it. The frame is built by recursion, handed to `Window.frame`, and the
  window's own shader shows it. There is no framebuffer to write, no draw
  call, no texture to upload, nothing to bind.
- **Parallelism is the recursion's shape.** A parallel let, `a b = f(x)
  f(y)`, says two calls are independent. One `!` at the root of the frame
  (`fork!` in `Render.frame`) hands the whole tree to the GPU. The same
  defs run on Metal, on CUDA, on every CPU core, and on wasm workers in the
  page. You never write a kernel, a thread or a lock. "Parallelize whenever
  possible" means: shape the work as a balanced tree of independent calls
  of about equal cost, one `!` a frame. It does not mean forking small
  things: a job under a third of a millisecond loses to the wake-up.
- **A renderer is a function of a ray.** This is a ray caster, not a
  rasteriser. There are no meshes, no triangles, no culling passes, no
  depth buffer: a ray a pixel walks the voxel grid (a DDA) and the first
  block it meets is what is seen. A new look (water, clouds, a reflection,
  a shadow) is more arithmetic along the ray, or a second ray. An entity is
  a few boxes a ray tests. Texture, fog, light: pure functions of the hit.
- **Data is small and plain.** Scalars in a record (`Cam`) ride in
  registers to every lane. The world is one `Array<U32>` every ray reads by
  index. Sparse edits live in a `Map` on the host. There are no handles
  into GPU memory and no copies to manage: one heap is shared by the CPU
  and the GPU.
- **State is threaded, effects sit at the edge.** `tick : events -> Game
  -> IO(Maybe<Game>)`; the step, the physics, the picking and the view are
  pure. That is why the whole game runs in tests with no window. A loop is
  a recursion with fuel (a `Nat`), and a tail call compiles to a real loop.
- **No new effects to get around the language.** `bend guide effects`
  shows how a C or JS effect is written; here that is a last resort, never
  a way to draw, and the user decides. What the platform lacks (grabbing
  the mouse, true full screen) is reported upstream, not patched around.
- **Rules are proved.** A rule of the game is a law in `LAWS.bend`, closed
  in `PROOF.bend`. That is the other half of why this is written in Bend.

If you catch yourself designing a pipeline of passes, a buffer to fill and
read back, or a cache keyed by frame, stop: ask what pure function of the
ray, or of the game's state, gives the same thing.

## The gate: every change passes all of it

```sh
make check      # every module and test type-checks; PROOF.bend closes the laws
make test       # physics, save and load, terrain, the readout, windowless
make bench      # five frames at six sizes on Metal, a checksum a frame
make profile    # what each look costs, at four sizes
```

- **The picture's digest.** `make bench | grep -o 'checksum=[0-9]*' | cut
  -d= -f2 | md5` is `e5582afca9ac...` today. A change that should not alter
  the game's default picture must leave it as it is. A change that alters
  the picture on purpose says so, and its commit message carries the new
  digest. `bend test/physics.bend | md5` is `73516c0ead87...`; same rule.
- **The frame's time.** Compare two builds by alternated runs and their
  fastest frames, never by one run: the small sizes read twice as slow on a
  busy or cold machine. The user's machine is often busy.
- **A look is a flag.** Whatever a pixel can do without (shadow, fog,
  water's reflection, clouds) gets a bit in `Cam.fl` and a line in
  `test/profile.bend`, from its first commit, and the README's "What costs
  what" table gets its number.
- **A rule is a law.** Whatever the game promises (a count never under
  zero, a packing that reads back) gets a law in `LAWS.bend`, closed in
  `PROOF.bend`, before the feature is called done. The checker computes
  integers, not floats: state laws on integer defs.

## Bend's rules, learned the hard way here

The checker:

- Values are affine: used at most once. `+x` on a binder allows reuse and
  needs the type to be `Data`. "consumed more than once" means a missing
  `+`. Arrays, closures and IO handles are never reusable: thread them
  through and hand them back (`Array<U32> & T` results).
- Every operator needs its type: `(a + b : U32)`, `(x < y : U32)` (a
  `Bool`), `(t1 - t0 : Nat)`. The same inside a law.
- A `match` must be on a parameter, nested matches follow the binders'
  order, and no `let` may come before them. To branch on a computed value,
  pass it to a small def and match there.
- No mutual recursion. Fold two defs into one with a flag parameter, or
  pass the continuation as a closure (see `loop` and `turn` in main.bend).
- A recursive call must keep every argument before the shrinking one
  unchanged: put the fuel (a `Nat`) or the structure first.
- `Bool.pick(T, c, a, b)` is strict: both sides are computed. To skip work,
  `match` on the Bool in a def of its own.
- In a `do` block a bind is `x : T <- act`; a pair is opened in a helper
  def's first lines with plain names, `(a, b) = r`.
- `import ./x.bend as M` prefixes defs, types and constructors: `M.f`,
  `M.T`, `M.C{..}`. A def is declared before its use in a module.
- `Nat.mul/div/mod` and `U32.from_nat/to_nat` exist; `U32.from_nat` is
  linear in its argument, cap it with `Nat.min` first.
- `@unsafe` is for IO recursion the checker cannot see end (the benches).
  Do not reach for it in game code.

The GPU (`!`), all measured here (see ROADMAP.md, "Tried, and worth
nothing", and the README):

- A `!` is one dispatch: the fork tree grows until every lane holds a task,
  then each lane runs its task to the end, alone. The frame's time is the
  slowest lane. Keep leaves equal in cost.
- Uniform control flow beats less work. A loop that exits early for some
  rays made the frame slower: lanes of a SIMD group that part ways are run
  one case at a time. The DDA walks its 60 steps whatever happens, on
  purpose.
- The frame tree is binary, and a half past the screen's edge is never a
  task. A four-way tree, a pruned four-way tree, 8x8 leaves: all tried, all
  slower. Do not change `fork`'s shape without the bench.
- The GPU never shifts by a variable: pick by a division and a mask, or by
  a chain of `Bool.pick` (see `nib_at`, `row_div`).
- A tile's fixed squares are unrolled, as the shaders guide says (`t4` is
  four `t2`, straight-line). A long walk is never unrolled into a row of
  non-recursive defs: the emitted program explodes. The DDA's 60 steps are
  one recursive def with fuel.
- The shaders guide's "Do not" list applies, with one note measured here:
  its typed picks in place of the generic `Bool.pick` changed nothing in
  this game (ROADMAP.md).
- What every lane shares must be flat (`Cam`: scalars, copied by words) or
  the one array (`w`, read at a plain load). A `+` tree read by every lane
  costs a count a node a pixel, on every node of that type.
- A new parameter rides in every task. Prefer a field's spare bits (the
  readout's numbers ride in `fl`) to a new argument down the fork.

## The code's fixed points

- `Cam.fl`: 1 shadow, 2 occlusion, 4 texture, 8 fog, 16 HUD; 32 and 64 are the profile's debug renders; bits 7..24 are the
  readout's numbers, and bit 25 enables the day cycle (`Render.looks()`). Test flags by mask (`Util.on`), never by `<`.
- The key mask in `Player` (`kmask`): 1 2 4 8 WASD, 16..128 arrows, 256 P,
  512 F, 1024 2048 J L, 4096 Esc, 8192 space, 16384 32768 the mouse.
- The world: a ring of 128x128 columns in one `Array<U32>`, eight words a
  column (a mask of 32 blocks, then their types four bits each); edits in a
  `Map`; terrain from a seeded noise. Block types 0..7: grass dirt stone
  sand wood leaves brick snow.
- `main.bend` runs the window's loop itself (not `App.run`), with a `Stat`
  beside the `Game`; `Save.tick` is the game's tick.
- The save file's first line and its per-column lines are a format: a
  change to it keeps old saves loading, or says it does not.

## How to work here

- One step of `ROADMAP.md`'s order at a time, in small commits that each
  pass the gate. Commit messages are plain sentences saying what changed
  and what was measured, as `git log` shows.
- Update `README.md` where it describes what you changed (how it works,
  the layout, the numbers, the laws' paragraph) and `ROADMAP.md` when a
  step is done or something was tried and failed. A failed attempt with its
  numbers is worth a line: it stops the next one.
- Comments say why, in a sentence, where the code cannot. No banners.
- If a number gets worse and you cannot say why, stop and report; do not
  stack workarounds. `test/trace.py` shows the dispatch kernel by kernel.
- A compiler bug or a missing Window feature is reported to the user with a
  minimal repro. Do not open or comment on issues and PRs at bendlang/bend,
  do not run `make publish`, and do not push, unless the user asks.
- The page (`make page`) needs a checkout of the web target, which is not
  in stock Bend: `git clone -b web-wasm https://github.com/AdrielSantana/bend
  ../bend-web`, with `bun` and `emcc` installed. `make page-test` drives it
  in headless Chrome. The native game does not need it.
