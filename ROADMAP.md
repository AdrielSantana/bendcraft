# Roadmap

Written on 2026-09-21. Four tracks: the look, the game, the laws, and the
Bend compiler, where some steps wait on a decision that is not ours. The
game goes on whatever upstream decides.

## The vision

Bendcraft is Minecraft in spirit, not a clone of it. The base is the one
everybody knows: day and night, water that flows, survival, collecting,
crafting, mobs and entities. What it adds is what a Minecraft player
installs mods for, there from the first screen: the light of a shader pack
and the horizon of Distant Horizons. And one thing no mod can add: the
rules of the game are proved, so no update breaks them.

The point of it is Bend. Three things the game should show at a glance:

- **It is beautiful.** A sky, water, clouds, fog and a far horizon, all of
  them pure functions of a ray, run on the GPU by `!` alone: no shader
  language, no engine, no draw calls.
- **It is far.** A view of a kilometre from a world that is a function of
  its seed.
- **It is proved.** `LAWS.bend` holds the rules; `bend PROOF.bend` is the
  gate. A rule that a change breaks stops the build.

## The look

The renderer casts a ray for every pixel, so two of the classic cullings
are already its nature, and the work goes where a ray caster's cost is:

- *Frustum culling:* done by construction. Rays exist only for pixels on
  the screen, and the frame tree makes no task past the screen's edge.
- *Occlusion culling:* done by construction. A ray sees the first block it
  meets and nothing behind it.
- *What is left to win:* the empty space a ray crosses, and the distance it
  may reach. Both are the same piece of work, the far levels below.

The pieces, each behind a flag of `Cam.fl` with its line in `make profile`:

1. **Sky, sun and fog, done well — done (2026-09-21).** A sky gradient from the sun's height, a
   sun disc, a horizon glow; fog by distance and by height, its colour
   taken from the sky so the far terrain melts into it (it also hides
   where the far levels end). The fog measured nothing in the profile, so
   this is nearly free and changes every screenshot. It goes with the day
   cycle: dawn, noon, dusk, night with stars and a moon.
2. **Water's shader.** Tint by the depth crossed, a Fresnel term, the sky
   reflected analytically, ripples from a noise normal moved by time; then
   the world reflected by a second ray, paid like the shadow ray, only on
   the pixels that show water.
3. **The far horizon.** Levels over the world as Distant Horizons keeps
   them: next to the ring of 128² columns at one block, a ring of 128²
   cells of 4 blocks and one of 16, each cell its highest block and its
   top's type, a word a cell, filled from the noise as the rings shift. A
   ray that leaves the near ring goes on in the next level with steps four
   times as long, against flat-topped prisms. About thirty steps a level:
   a kilometre for twice the steps of today. The same levels let a near
   ray skip open air above the ground. Measure the steps with flag 32
   before and after.
4. **Clouds with volume.** A slab between two heights, a 3D noise moved by
   the wind, a short march of 8 to 16 steps for the rays that reach it,
   lit by the sun's side. And their shadows on the ground: one lookup of
   the same noise where the sun's line from the hit crosses the slab.
5. **Vegetation.** Tall grass and flowers as two crossed planes inside a
   voxel, leaves with holes: a ray that meets alpha goes on. Wind as an
   offset of the texture's coordinate by time and place.
6. **Light of the blocks.** Torches and a night that needs them.

**The budget.** At 1470×796 a frame is 15.6 ms with a ray for every pixel
and 5 ms at scale 2, which suits the pixel art. At 60 frames a second that
leaves about 11 ms for the look at scale 2. Every piece above says what it
took of them in the profile table.

**Ways to buy more of it**, in the order to try them; none is needed yet.

- *Fewer rays, scaled up.* There already: scale 2, nearest neighbour,
  which is the pixel art's own look. Its floor is the fixed part of a
  dispatch, about 3 ms of growing and packing.
- *The dear looks at a lower rate than the rays.* A primary ray for every
  pixel keeps the blocks' edges sharp; a cloud march, a reflection or a
  soft shadow is smooth, so a 2×2 block of pixels can share one, or one
  pixel of the block can renew it each frame. Clouds are the classic case:
  Horizon Zero Dawn renews one pixel in sixteen a frame.
- *Noise and a denoiser,* as path tracers and Teardown do. Only once a
  look is stochastic (soft shadows, jittered cloud steps): today's rays
  are deterministic, so there is no noise to remove. The filter goes on
  the light alone, never on the texture, or the pixel art smears.

**Reading the last frame**, which the last two need. What the runtime
allows, from `bend guide shaders` and the emitted C:

- *A tile's own past is free.* The last image rides down the frame tree,
  opened in four at every node (`Image.open(old)` in the guide's demo), so
  each tile is handed its own square of it, owned: no sharing, no counts.
  Enough for a still camera, and for renewing one pixel of a block a frame.
- *Another tile's past is not.* A turning camera moves a point six pixels
  or more a frame, out of its 4×4 tile, and a tree has no way up or
  sideways: a tile holds what was handed down and nothing else. Sharing
  the whole last image as a `+` tree instead makes the compiler count its
  nodes, and sealing is per type, so every `Image` node pays, the new
  frame's too (the guide measured 8.0 → 16.5 ms on its frame); and lanes
  walking different paths diverge, which the early exit of the DDA already
  showed us the price of.
- *The way around is the world's way.* The ring is an `Array<U32>` every
  lane reads at a plain load. The last frame can be one too, filled on the
  host after the `!`: a parallel walk over a 1470×796 frame takes 1 to 2
  ms here; the writes, which have one owner and so one thread, are not
  measured. A ray then reads any old pixel by its index, and reprojects
  exactly, since it knows where it hit.
- Either way `main.bend` must call `Window.frame` itself, which hands the
  image back, in place of `App.run`, which drops it.

**Tried, and worth nothing here** (2026-09-21, so nobody tries again
without a reason): typed picks, `pick(c, a: F32, b: F32)` and `word` for
U32, in place of the 159 generic `Bool.pick` of the renderer, the world
and the player, which `bend guide shaders` says box their words. Same
checksums, same fastest frame at all six sizes, four alternated rounds.

## The game

1. **Collecting and an inventory — done (2026-09-21).** Breaking gives
   one of the actual type; placing spends one, rejected placements spend
   nothing. New games start empty. The HUD shows counts through `99+`,
   the save keeps their full values, and old saves load with zero counts.
   Time to break by block type and tools remain follow-up work.
2. **Water — still water done (2026-09-21).** Material 8 has its own
   column mask below y=12. Rays cross it, tint by wet distance and fog at
   the first surface; placing solids displaces it, and saves keep it.
   Next: Fresnel, sky reflection and ripples with their own flags, then
   physics, a cellular rule over the edits' Map: down first, sideways,
   sources stay. Swimming and collection are not implemented yet.
3. **Day and night — done with look step 1.** The saved integer clock
   drives the sun in `Cam`; the shadow has signed crossings on every axis.
   A full period returns the same sun phase for every clock word.
4. **Survival.** Health, falling hurts, hunger, death and a place to come
   back to.
5. **Crafting.** A recipe is a vector over the counts: what it takes, what
   it gives. A grid in the HUD.
6. **Mobs and entities.** An entity is a few boxes a ray tests, binned by
   column so a ray tests only those of the cells it crosses; a dropped
   item is an entity too. Their physics is the player's.

**What only Bend gives**, candidates, not decided. The game's step is a
pure function, so the whole game is a function of its seed and its inputs.
That makes a replay a list of inputs, a save as small as one, a rewind key
that walks back through kept states (the Map of edits shares its
structure, so a past state costs little), and two players in lockstep
without a server deciding who is right.

## The laws

Every rule the game adds gets its law in `LAWS.bend` before the feature is
done, closed in `PROOF.bend`, run by `make check`. A later change, ours or
a Bend update, that breaks a rule fails the gate. The laws to come:

- *Inventory (done):* natural counts, break/place roundtrip and conservation
  of a cell plus its count for every action list. The actual world and
  inventory share the transfer receipt; windowless tests cover the ring,
  type selection and simultaneous inputs. The proof is of the integer
  transfer model, not a blanket proof of the floating-point game loop.
- *Crafting:* a recipe changes the counts by exactly its vector, and does
  nothing when an input is short.
- *Water:* a tick never raises the amount of water, sources aside; water
  never moves up.
- *Day and night (done):* the sun a full day later is the same sun phase,
  for every clock word, including overflow.
- *Survival:* health stays within its bounds; the dead do not act.
- *Entities:* none ends a tick inside a solid block, the player's law.
- *The picture:* the bench's thirty checksums. A change that should not
  change the image cannot.

Today's 67 laws include the day period for every `U32` clock word and
six universal inventory laws, with counts as `Nat` and slots as a list.
The other 60 laws are concrete checks, including HUD packing and save/quit
edges. Floats stay in the windowless tests: the checker does not compute them.

## The order

A proposal, a piece of the look then a piece of the game, the look first
since it is what a visitor sees:

1. sky, sun, fog and the day cycle — done, 2026-09-21
2. collecting and the inventory, with laws stated for every count — done, 2026-09-21
3. water: still water done, 2026-09-21; finish its shader, then its physics
4. the far horizon
5. survival and crafting
6. clouds and their shadows; vegetation
7. mobs and entities; light of the blocks

The day-cycle foundation (2026-09-21) passed all four gates. Four
alternated rounds at 1470×796: full profile 15.0 → 15.8 ms, shadows off
12.6 → 12.6, rays alone 11.0 → 11.0. Signed shadow crossings account for
the increase. Fastest bench frames: 14 → 15 ms there, unchanged at the
other five sizes. The integer clock is saved in an optional header field;
old saves still load. Its default morning intentionally changes the bench
digest to `9a69584df64263efa23186046b24e5a2`; physics is unchanged.

Step 1 is complete (2026-09-21): sky gradient, sun disc, horizon glow,
stars, moon, distance haze and low mist, each optional look with its flag
and profile row. Fog uses the atmospheric sky colour and reaches it before
the primary ray's step limit. Six fixed views are available with `make sky`
(Pillow). The final four alternated rounds against the original build give
15.2 → 16.0 ms at 1470×796; shadows off 12.6 → 13.2, rays alone 11.0 →
11.0. Extra shadow crossings and atmospheric arithmetic explain the cost;
the 735×398 bench minimum is still 4 ms. Night, looking at the moon: 11.8
ms, stars off 11.4, moon off 11.8. The full table is in README. All four
gates pass, physics remains `73516c0ead87f8c1151e34d25b3ac32e`, and the
intentional new picture digest is `78d5ae6b7301de08432c237f1bbecc0b`.
The full-day law now covers every clock word by bit induction.

Step 2 is complete (2026-09-21): eight natural counts, collecting the
actual block type, spending only on accepted placements, HUD labels and
backward-compatible saves. The transfer laws cover every count and action
list; tests cover the world edits, all types, simultaneous break/place,
repeated air breaks and full counts through save/load. Placement rejects
cells outside the world and every cell through the player's height. The
save test also caught P's edge being discarded by the physics step; P and
Esc now reach the save after the same tick's edit. Time to break and tools
remain follow-up work.

All four gates pass, with 53 laws. Four alternated rounds at 1470×796:
full profile 16.0 → 16.2 ms, HUD off 15.8 → 16.2, rays alone 11.4 → 11.0.
The fastest bench frame moves 15 → 16 ms there, unchanged at the other
five sizes. That baseline 15 was one of twenty frames; a separate four-round
kernel trace has work minima 14.570 → 14.526 ms, without a reproducible
slowdown. The spread and one-ms timer explain the isolated floor change;
README records both the normal table and the diagnostic times. The HUD
intentionally changes the digest to `9e3773a2467d6ccbe097a74a29cf2f89`.
Physics stays `73516c0ead87f8c1151e34d25b3ac32e`; its historical fixture
supplies its sand placement, while separate tests check the empty start.

## The engine's routine

Water preparation, 2026-09-21: four FPS bits moved to spare bits in
`Cam.items`, freeing `Cam.fl` bits 21..24 without growing the camera.
All four gates pass, 58 laws; unchanged picture digest and physics hash.
Four alternated rounds: full profile 16.2 → 16.0 ms, rays alone 11.0 →
11.0. Off-row increases overlap the run ranges (README); their look code
is unchanged, and their readout is disabled. The six bench minima are
2/2/4/9/16/29 → 2/2/4/8/15/29 ms.

Still water, 2026-09-21: slot +5 stores its mask without changing the
solid terrain. The primary DDA accumulates wet intervals before the solid
hit, including signed side entry and a submerged eye. Flag 21 and a profile
row disable the water look; a lake view measures it active. Old saves load
natural water above original terrain, keeping excavations dry; the new
sixth word preserves displacement. Tests cover all six ray directions,
water behind solids, picking, collisions, shadows, ring reloads and saves.
67 laws close; all four gates pass. Physics remains
`73516c0ead87f8c1151e34d25b3ac32e`. Lakes intentionally change the picture:
bench digest `a6dac974097868bdae51a1963519f6a2`.

Four alternated rounds at 1470×796: full profile 15.8 → 20.0 ms, water off
17.4, rays alone 11.0 → 12.0. The extra mask load and wet interval arithmetic
cost time; the dry specialization still transports three added scalar
words and checks for a wet hit. Fresh-C kernel traces confirm the work
increase: 14.525 → 15.000 ms dry, 17.445 ms wet. This is measured overhead,
not a free look. The full table is in README. Bench minima at six sizes:
2/2/4/8/16/29 → 2/2/5/10/19/36 ms. The lake view is 20.8 ms, water off 17.6.
The dry build retains the old thirty checksums; camera size and fork shape
are unchanged. Shader work and water physics remain next; there is no flow
or swimming in this delivery.

What is measured today, at 1470×796 on an M5: 20.0 ms a frame, rays
alone 12.0, shadow off 17.2, water off 17.4. Small differences between
variants are noisy; use alternated runs. A ray walks the box's 60 steps
whether it hits or not, on purpose (README, "What costs what").

**The routine, for every change to the frame:**

- a flag in `Cam.fl` if the look can be turned off, and its line in
  `test/profile.bend`;
- `make bench`: the md5 of the thirty checksums stays `a6dac974097868bdae51a1963519f6a2` when
  the picture did not change (`make bench | grep -o 'checksum=[0-9]*' |
  cut -d= -f2 | md5`); when it did, the new one goes in the commit;
- uniform control flow in anything a lane runs: a branch that saves work
  for some rays has cost more than it saved, twice.

A single run reads high at the small sizes when the GPU is cold or the
machine busy (512² at 6 ms for 2): compare builds by alternated runs and
their fastest frames.

**The routine, for every `bend update`:** `make check test bench profile`,
rebuild the page with the rebased fork, run `test/trace.py` once (its
snippets match the runtime's text and may need an update).

**Work that is ours, when a feature asks for it:**

- *Full screen by default at scale 2* (5 ms), scale 1 by choice (16 ms).
- *The page.* 31 fps at 512² on ten wasm threads, 7 on one. The CPU is the
  ceiling there; the way up is the WebGPU lane, below.

**Work that waits on the runtime:** the frame tree is binary, with halves
past the edge run in place, because of how the Metal scheduler fills its
lanes (#925). If that changes, measure the four-way tree again and go back
to it if it ties: it reads better.

## Bend: waiting on a decision

State on 2026-09-21, 16:00 UTC. No maintainer has answered any of these
yet. Decisions upstream have come within a day or two, each with a written
reason.

| | what it is | state | if yes | if no |
|---|---|---|---|---|
| [PR #866](https://github.com/bendlang/bend/pull/866) | `-o x.html`: the runtime as WebAssembly, a worker a core, a Window on a canvas | ready for review, rebased onto 2.0.24; over the `comp.ts` cap by 60 tokens, said so in the PR | `make page` with the stock `bend`; drop `BEND_WEB` | the fork stays the page's compiler, rebased at every release |
| [#920](https://github.com/bendlang/bend/issues/920) | a WGSL lane: `!` on WebGPU; the design, a prototype, 0.3 / 1.8 / 2.4 ms against 4.5 / 42 / 53 on ten wasm threads | open | write the emitter where they say it may live | write it in the fork |
| [#925](https://github.com/bendlang/bend/issues/925) | Metal: the tree's arity decides the lanes' load (12 / 23-34 / 3 ms for the same leaves) | open | re-measure, maybe the four-way tree again | the binary tree stays; the README is the record |
| [#921](https://github.com/bendlang/bend/issues/921) | Window: grab the mouse | open | mouse look without dragging | our own effect, below |
| [#923](https://github.com/bendlang/bend/issues/923) | Window: full screen | open | a key for it | our own effect, below; until then `make full` sizes the window to the screen |

**Our own effects, if the Window asks stay unanswered.** `bend guide
effects` is the manual: a def of type `IO(R)` whose body imports a `.c` and
a `.js`; the C is spliced into the program after the runtime, so its
symbols are in scope, and a custom effect may take one of Base's handles.
On macOS the `Window` handle is the `NSWindow` itself, so full screen is a
call on it, and a grabbed mouse is the cursor hidden and unhooked plus a
second effect that reads the mouse's delta each frame. The page needs its
own branch (pointer lock), since the web target compiles the same C. The
price: the C names the runtime's internals, there is no ABI promise, and
it is rebuilt and re-tested at every `bend update`. This is input at the
edge, which is what effects are for; drawing stays in Bend. Wait some days
for #921 and #923 first; if we write one, offer it upstream as the issue's
implementation.

A third answer is likely for the PR: closed for the repo's budget, with a
branch to keep it in, as `hip` was offered in #891 and now exists. The
comment that took it out of draft asks for a `web` branch in that case.
Then: `gh pr edit 866 -R bendlang/bend --base web`, and the branch is kept
rebased; that promise is made.

The WGSL lane is the step that matters most for Bend on the web, and the
one least likely to fit upstream: `comp.ts` is at 64,972 of its 65,000
tokens, so the question to get answered in #920 is where such a lane may
live. Ours to do either way: the emitter. The prototype's leaves were
translated by hand; the next step is to emit WGSL from the same segments
the C and Metal lanes come from, one leaf kind at a time, each checked
against the C lane's checksums.

To see where things stand:

```sh
gh pr view 866 -R bendlang/bend --json state,mergeStateStatus,baseRefName,comments
for n in 920 921 923 925; do gh issue view $n -R bendlang/bend --json state,comments; done
gh api repos/bendlang/bend/branches -q '.[].name'
```
