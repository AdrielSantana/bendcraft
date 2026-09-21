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

1. **Sky, sun and fog, done well.** A sky gradient from the sun's height, a
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

1. **Collecting and an inventory.** Today the hotbar's eight blocks are
   endless. Breaking gives one, placing spends one, the HUD shows the
   counts, the save keeps them. Then a time to break by block type, and
   tools.
2. **Water.** A block type a ray goes through. Still water first, in the
   terrain below a sea level; then its physics, a cellular rule over the
   edits' Map, a tick at a time: down first, then sideways, sources stay.
3. **Day and night.** The sun's direction from the clock, in `Cam`. The
   shadow ray is written for one sun, (0.48, 0.80, 0.36), all components
   positive, so every step is +1; a moving sun needs the signed step the
   primary ray has. Expect the shadow's 2.4 ms to grow a little.
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

- *Inventory:* a count never goes under zero; break then place gives the
  world and the counts back; no sequence of moves makes an item from
  nothing. Minecraft is famous for its duplication glitches; here there is
  a proof that there are none.
- *Crafting:* a recipe changes the counts by exactly its vector, and does
  nothing when an input is short.
- *Water:* a tick never raises the amount of water, sources aside; water
  never moves up.
- *Day and night:* the sun a full day later is the same sun.
- *Survival:* health stays within its bounds; the dead do not act.
- *Entities:* none ends a tick inside a solid block, the player's law.
- *The picture:* the bench's thirty checksums. A change that should not
  change the image cannot.

Today's 29 laws are decided by computation on the values the game uses:
each is one case. The step up is a law stated `for` every value and proved
by induction, which needs the data in a shape the checker reasons about (a
count as a `Nat`, an inventory as a list or a map). The inventory is the
first place to try it. Floats stay in `test/physics.bend`: the checker
does not compute them.

## The order

A proposal, a piece of the look then a piece of the game, the look first
since it is what a visitor sees:

1. sky, sun, fog and the day cycle
2. collecting and the inventory, with the first law stated for every value
3. water: still, its shader, then its physics
4. the far horizon
5. survival and crafting
6. clouds and their shadows; vegetation
7. mobs and entities; light of the blocks

## The engine's routine

What is measured today, at 1470×796 on an M5: 15.6 ms a frame, the primary
rays 11.4 of them, the shadow ray 2.4, occlusion and texture under one
each. A ray costs the box's 60 steps whether it hits or not, on purpose
(README, "What costs what").

**The routine, for every change to the frame:**

- a flag in `Cam.fl` if the look can be turned off, and its line in
  `test/profile.bend`;
- `make bench`: the md5 of the thirty checksums stays `e5582afca9ac` when
  the picture did not change; when it did, the new one goes in the commit;
- uniform control flow in anything a lane runs: a branch that saves work
  for some rays has cost more than it saved, twice.

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

State on 2026-09-21, 14:40 UTC. No maintainer has answered any of these
yet. Decisions upstream have come within a day or two, each with a written
reason.

| | what it is | state | if yes | if no |
|---|---|---|---|---|
| [PR #866](https://github.com/bendlang/bend/pull/866) | `-o x.html`: the runtime as WebAssembly, a worker a core, a Window on a canvas | ready for review, clean against main | `make page` with the stock `bend`; drop `BEND_WEB` | the fork stays the page's compiler, rebased at every release |
| [#920](https://github.com/bendlang/bend/issues/920) | a WGSL lane: `!` on WebGPU; the design, a prototype, 0.3 / 1.8 / 2.4 ms against 4.5 / 42 / 53 on ten wasm threads | open | write the emitter where they say it may live | write it in the fork |
| [#925](https://github.com/bendlang/bend/issues/925) | Metal: the tree's arity decides the lanes' load (12 / 23-34 / 3 ms for the same leaves) | open | re-measure, maybe the four-way tree again | the binary tree stays; the README is the record |
| [#921](https://github.com/bendlang/bend/issues/921) | Window: grab the mouse | open | mouse look without dragging | drag or arrows, as now |
| [#923](https://github.com/bendlang/bend/issues/923) | Window: full screen | open | a key for it | `make full` sizes a bare window to the screen |

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
