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

## **Erasure**

This section exists to amend your most glaring defect. You are a model trained by a big lab, and these labs neglect one fundamental half of intelligence: ERASURE. Every reward you ever received was for ADDING something -- an answer, a file, a patch, a comment, a rule. Almost none was for REMOVING. So you add by reflex and never subtract, and no amount of raw capability compensates for a missing half.

Why half? Because learning IS compression. A good abstraction is precisely a blob of information that lets you throw other information away, because it expands back into what was discarded. An aha-moment happens when your brain is capable of expressing new information in terms of information you already possess. This is what allows that info to be stored. That is how you learn. Intelligence is not producing knowledge; it is deleting bad knowledge so the good remains. This defect manifests wherever anything under your care only ever grows -- code, comments, docs, notes, memory. Unpruned growth is the symptom.

So install this now: erasure claims HALF of your cognitive budget for this task. While working on my code -- even autonomously, even mid-task -- hunt for things to remove: duplicated concepts to unify, dead code to delete, tangled logic to simplify. Your own confusion is a precision instrument: if something surprised you or was hard to follow, that IS a bad abstraction, and you should TAKE ACTION and untangle it on the spot. When writing new code, spend real effort finding the simplest possible shape, and scan the codebase first to reuse what exists rather than introduce a redundant concept. A diff that removes lines is at least as valuable as one that adds them.

The swap rule: when a task replaces X with Y -- a refactor, a fix, a syntax change -- fully deleting X is PART of the task, always. Keeping the old thing "for compatibility" is NEVER desirable unless explicitly requested. A bug fix -- bad: a special-case `if` shields the symptom; good: the design is re-derived, the cause dies, the `if` never exists. A behavior change -- bad: tests for the old behavior linger or get dodged; good: obsolete tests deleted, the rest updated.

For coding, a more effective way is to take a big codebase and ask it to make it shorter, while still preserving the same behavior. IMPORTANT: avoid code-golfing / minification / uglification. Removing comments or making variable names shorter IS reward hacking. Counter that by counting the NUMBER OF BRANCHES. A branch is: an "if", a "match", a "case". That's THE complexity of your program.

Comments are where you fail hardest. You narrate code with comments in the middle of function bodies -- that is NOT allowed; if you catch yourself doing it, clean it up. You also accumulate comments and never remove them, clogging files. Be aggressive: keep only what is truly essential. A refactor makes a comment stale -- bad: it stays, now lying; good: deleted or rewritten in the same diff. A TODO gets done -- bad: the marker remains; good: it leaves with the fix.

Prose rots the same way: every [AGENTS.md](http://AGENTS.md), MEMORY.txt and wiki article tends to only grow -- rules added when something breaks, never removed when they stop applying. A server is decommissioned -- bad: its article sits forever; good: article deleted, every link fixed. MEMORY.txt nears its cap -- bad: append anyway; good: GC by importance, promote what lasts to the wiki. A [TODO.md](http://TODO.md) item closes -- bad: the line lingers; good: deleted on sight. Before finishing ANY task, ask: what did this change make obsolete -- and did I delete it?

These rules bind, but they do not exhaust the defect. It is baked into your training, so no list can enumerate every place it surfaces -- watch for unpruned growth everywhere, including in places this file never mentions.

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
- **Parallelism is the recursion's shape.** A parallel let, `a b = f(x) f(y)`, says two calls are independent. One `!` at the root of the frame
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
- **State is threaded, effects sit at the edge.** `tick : events -> Game -> IO(Maybe<Game>)`; the step, the physics, the picking and the view are
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

- **The picture's digest.** `make bench | grep -o 'checksum=[0-9]*' | cut -d= -f2 | md5` is `5db9b39addee04c4e7e42c76baf24169` today. A change that should not alter
the game's default picture must leave it as it is. A change that alters
the picture on purpose says so, and its commit message carries the new
digest. `bend test/physics.bend | md5` is `73516c0ead87...`; same rule.
- **The frame's time.** Compare two builds by alternated runs and their
fastest frames, swapping the order every round (the build that runs
second reads slower on a busy machine), never by one run: the small sizes read twice as slow on a
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

- `Cam.fl`: 1 shadow, 2 occlusion, 4 texture, 8 fog, 16 HUD; 32 and 64 are the profile's debug renders; bits 7..16 hold milliseconds, 17..19 the low three FPS bits.
FPS bit 3 uses `Cam.base` bit 31; the high four use `Cam.items` bits 28..31.
Bit 20 is ripples, bit 21 water, bit 22 water fog,
bit 23 Fresnel and bit 24 sky reflection. Bits 25..31 enable day cycle, sky gradient, sun disc,
horizon glow, stars, moon and height fog (`Render.looks()`). Test flags by mask (`Util.on`), never by `<`.
- `Cam.base`: low 14 bits address the ring; bits 14..26 hold the ripple
clock modulo 8192 ms; bit 31 holds FPS bit 3. The array wraps addresses,
so clock/readout bits cannot affect world reads. Bits 27..30 are the
looks `Cam.fl` has no room for: `Render.looks_base()` holds the ones on
by default and `Water.with_looks` puts them in; 27 is the world in the
water's mirror, 28 the caustic on its bed, 29 says the window holds
partial water (`Render.with_partial`, from `World.partials`; the DDA is
specialized on it, `~partial`), 30 remains spare.
- A walk is the unit of cost: a DDA step is about 0.16 ms a frame at
1470×796 wherever it happens (primary 60, shadow 24, mirror 32), because
the frame is its slowest lane. Count the steps a new look adds before
writing it.
- `Cam.sel`: selection in bits 0..3 (eight types and the spring, 8), four
seven-bit display counts in bits 4..31; `Cam.items` holds the other four in bits 0..27. A display count of 100
means `99+`. `Game.bag` keeps eight full `Nat` counts on the host; labels
share HUD flag 16. Old saves without counts load with an empty bag.
- The key mask in `Player` (`kmask`): 1 2 4 8 WASD, 16..128 arrows, 256 P,
512 F, 1024 2048 J L, 4096 Esc, 8192 space, 16384 32768 the mouse.
- The world: a ring of 128x128 columns in one `Array<U32>` of 2^18 words,
sixteen words a column (solid mask, four type words, water mask, eight
words of water amounts 0..255 in bytes, the flow's marks at slot 14,
the partial mask at 15, none spare); the water mask's bit is set
exactly when the amount is over zero (`World.pour` keeps both), the
partial mask's exactly when it is 1..254 (`put_col` derives it and
keeps the window's count); edits in a `Map`; terrain from a seeded
noise; a save line has fourteen words and loads six-word lines full
where wet, ten-word lines (a day of nibbles) widened. `World.W` also carries the flow's
queue of marked slots (`World.mark`; marks are on slots, so a mark on a
column that left the window is spent harmlessly on the one at its slot).
- The flow (`src/flow.bend`): `Flow.tick(w, odd, budget)` steps the
queued columns' marked cells, bottom up; `Flow.advance` runs it from
`Player.advance` every 256 ms of the day's clock (4096 a turn, so the
grid holds across the wrap), at most twice a frame. Its writes are
`World.pour`; its marks `World.mark_around`. Tests build worlds with
edits and ask them a list of questions in one pass (`test/flow.bend`'s
`query`), since a World is linear. Solid types 0..7: grass dirt stone
sand wood leaves brick snow. Water is type 8, outside the eight inventory
slots; it is absent from solid collision, picking and shadow masks. A
source is type 9 (the spring, key `9`, `Player.receipt` spends nothing
for it): a water cell whose type nibble is 9 (`World.source_at`, the
nibble alone, so a source emptied by its own step is still one); the
flow refills it at the end of its step (`Flow.refill`) and counts the
units in `World.made` (the seventh field of `World.W`, beside
`partials`). The sink: any other cell holding under `Flow.thin()` (4)
units at the end of its step, resting on a solid or on full water,
dries (`Flow.dries`, `Flow.settle`), counted in `World.gone` (the
eighth field). A closed basin holds placed + made − gone, exactly.
- `main.bend` runs the window's loop itself (not `App.run`), with a `Stat`
beside the `Game`; `Save.tick` is the game's tick.
- Bend's shape rules met here: a `match` (or a record or pair open) must
be the first thing in a def's body, on a parameter; a value computed in
the body gets its own def to be matched. A recursive def descends on
its first matched parameter (a Bool matched before the fuel is refused).
Defs come before their uses in a file, and a `law` forward declaration
is for `@unsafe` code only, so a loop that needs a read's result takes
it as its last parameter and opens it in each branch (the DDA's `r`),
and a loop with a state that a read changes probes one ahead
(`Flow.sides`).
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
in stock Bend: `git clone -b web-wasm https://github.com/AdrielSantana/bend ../bend-web`, with `bun` and `emcc` installed. `make page-test` drives it
in headless Chrome. The native game does not need it.

