# Roadmap

Four tracks: the look, the game, the laws, and the Bend compiler, where
some steps wait on a decision that is not ours. How each finished piece
works is in [engine.md](engine.md). This file keeps what comes next, and
what was tried and failed, with its numbers, so the next attempt does not
repeat it.

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

## The order

The look is finished before the game's loop (decided 2026-09-26): it is
what a visitor sees, and survival, crafting and mobs then play in the
finished world.

1. sky, sun, fog and the day cycle — done, 2026-09-21
2. collecting and the inventory, with laws for every count — done, 2026-09-21
3. water: its look, its flow, the bucket and swimming — done, 2026-09-22
4. the far horizon: a word a column to the fog — done 2026-09-22, seamless 2026-09-25
5. clouds and their shadows — done, 2026-09-27
6. the weather over the days, the wind, rain from heavy clouds and the
   wet it leaves — done, 2026-09-27
7. vegetation: the meadow, the leaves' holes and the wind in them — done, 2026-09-28
8. light: the sun's colour, the sun in the camera, its light in the haze
   and the moonlit night; the torch in the hand, as a block, and its
   light — done, 2026-09-29
9. survival and crafting
10. mobs and entities

Not yet placed in the order: a taller world (the game's step 4, below),
and the page in the browser, which waits to run on WebGPU.

## What is left of the look

- **The rain:** splashes, and the rain in the water's mirror.
- **The far horizon:** a coarser level where its cell is a few pixels, and
  the fog farther out; the same cells would let a near ray skip the open
  air above the ground. The far map carries neither the edits nor the
  water's amounts: past the window a built tower is the noise's ground and
  a lake is its plane.
- **The mirror**, when the budget asks: walk the far map instead (a step a
  column and a word a step, where the window's walk steps every block's
  face), or ride the primary walk's idle steps, since a ray that met the
  lake's bed walks the rest of its 60 with its state frozen.
- **The bucket** scoops from the bottom, the cell before the solid the
  crosshair meets; a scoop at the surface waits for the next change to the
  water.

## What was tried and failed

- **The far horizon.** The first far map was a ring of 64² cells of 4×4
  columns, each its highest block and the type of its top, 32 steps: 2 ms
  less at 1470×796, and it looked wrong (a tree a pillar of leaves four
  wide, the walls the grass's green, a cell four blocks wide where the
  window's walk ends); its first A/B read "free" from a script that took
  old rounds for new ones. A coarser level belongs where its cell is a few
  pixels, not where the window's walk ends. The line at the seam (reports
  of 2026-09-22 and 2026-09-25) had five causes: the far walk named the
  face it started on an x side whatever it was; a lake across the seam
  was two waters; a ray that left the window by its side stepped on over
  columns the window does not hold; a block near the side found air past
  it for its shadow, its mirror and its corners; and west and north of the
  window, where the coordinates are negative, the far look floored through
  U32, which takes a negative to 0. The last hid under the fog, and the
  far walk from the eye, the oracle of the others, shared it: judge the
  far look with the fog off.
- **The clouds' stripes.** A ray almost level stepped over many columns,
  and one read a step showed the slab in layers. A start jittered by the
  ray's hash turned the layers into grain; 24 steps thinned them; the
  density's mean at 12 steps left a few. Both showed the ramp's flaw, half
  its density at the slab's bottom under no cloud, which 12 steps from
  their middles never read: a veil over the whole sky. Sixteen averaged
  steps of a block each are what stayed.
- **The rain.** Streaks on cylinders about the eye, placed by the ray's
  bearing, walked with the player and read as a filter on the screen. The
  roof's test was a pow a drop, 3 of its 8 ms at 1470×796; a log2 of the
  column's mask does it once a column.
- **The puddles in the meadow.** A cell's blades thinned by the puddle at
  its middle left the broad walk's cells as squares in the distance; each
  blade thinned by its root costs the same hashes.
- **The meadow.** Crossed planes inside a voxel were the plan and never
  were: a blade anywhere in its cell, met where the ray passes it nearest,
  keeps its edge soft at any angle and shows no quad. Dropped on seeing
  them: the blades' shadows on each other, and flowers as balls. What was
  tried to make it cheaper is in [perf.md](perf.md).
- **The leaves' holes.** At the eye's 30 in a hundred a tree's shadow held
  almost no fleck of light, the sun crossing three or four leaf blocks; at
  55 the shadow was lost; the sun's glance sees 40. Three divisions in a
  leaf's test in place of three rates the walk carries were no cheaper.
- **The sun's light in the haze.** Three prototypes of rays did not read
  as rays: the same points out to 240 blocks over a haze of 60 read as a
  wash, and a beam through the leaves needs a point every texel; the halo
  weighed by the lit air read too faint, the halo being a fifth of the sky
  near the sun; 32 rays from the host in a ring around the sun gave a
  glow; shaded air that darkens as lit air brightens greyed the whole sky
  under the clouds. Light laid on a bright sky has no room left: rays need
  something dark close to the sun's line. They chose the haze ("uma névoa
  atmosférica mesmo").
- **The mist** in the low ground, lit as the haze is (2026-09-29, "prefiro
  sem do que desse jeito"): a density whole at the lake's plane and
  thinning upward, a closed form along a ray, in drifting patches,
  thickest from the evening to the morning, in the height fog's place, 1
  to 6 ms at 1470×796. Thinning by e every 3 blocks it lay over a lake as
  an opaque white band; every 12 blocks in the sky's colour it read as a
  thicker haze, and it moved in steps as the player walked. The height fog
  stays.
- **The torch.** Its light in the hand first fell as the square of what
  was left of its 14 blocks and showed within six under the full moon,
  which lights the night at 0.48 of the day. The stick's test in the walk's
  step first stood apart from the leaves' pierce, a second match, and cost
  1 to 5 ms at 1470×796 with no torch anywhere; in one match with the
  leaves but computed for every leaf cell, 1 to 2. The light grid first
  outshone the sun at noon (a cell beside a torch gave 1.08 of the sun's
  white in red, 1.35 on a blade), so the day now fades the torches' light.
- **The water's unit.** The design said eight units a cell, a nibble; the
  rule moves nothing between neighbours a unit apart, so a breached lake
  stopped at `8 8 8 7 6 5 4 3 2 1 0` along its top row, a terrace an eighth
  of a block a cell. A byte made it 1/255, invisible.
- **Springs.** Cells that refilled themselves (2026-09-22) filled their
  terrace and spilled a film of a few units over every flat reach, for
  ever: 400 ticks on, 18777 units made and 1212 wet cells, growing a cell a
  tick. The sink stopped the film; the springs then went whole for the
  bucket, so water is only moved.
- **Swimming** first had no way out of a river (2026-09-22): a rule of no
  jump off the bed went, since the water's clamp already held that jump,
  and a wall met swimming became a bank.

## The game

1. **Collecting and an inventory — done.** Time to break by block type and
   tools remain.
2. **Water — done.** Breath remains.
3. **Day and night — done** with the look's first step.
4. **A taller world.** The terrain stays under 32 blocks, the solid mask's
   word a column, with no mountains and no caves, so next to Minecraft it
   reads as a miniature (said 2026-09-27). More height is more words a
   column in the ring and the save, more bits a height in the far map, and
   longer walks; where it goes in the order is not decided.
5. **Survival.** Health, falling hurts, hunger, death and a place to come
   back to.
6. **Crafting.** A recipe is a vector over the counts: what it takes, what
   it gives. A grid in the HUD.
7. **Mobs and entities.** An entity is a few boxes a ray tests, binned by
   column so a ray tests only those of the cells it crosses; a dropped
   item is an entity too. Their physics is the player's.

**What only Bend gives**, candidates, not decided. The game's step is a
pure function, so the whole game is a function of its seed and its
inputs. That makes a replay a list of inputs, a save as small as one, a
rewind key that walks back through kept states (the Map of edits shares
its structure, so a past state costs little), and two players in lockstep
without a server deciding who is right.

## The water's open question

The rule halves a difference a tick, so a lake levels by diffusion, in
about as many ticks as the square of its length: the breached lake of
`make flow` takes 1300 ticks, five and a half minutes of the clock, with
640 columns active the whole way, 2.5 times the tick's budget, and its
whole surface a layer of partial cells after, which costs the frame the
plane's clip (30.3 → 39.4 ms at 1470×796 on a lake partial everywhere).
The options, each costed: a budget spread over the frames, so many columns
a millisecond of the clock rather than 256 a tick (1024 columns a tick
would be 10 ms if paid at once, a hitch every quarter second; a column a
millisecond is 0.1 ms a frame); a rest threshold of a few units, which
cuts the tail of the levelling but brings a terrace back, (t − 1)/255 of a
block a cell; and communicating vessels, one level per connected body of
still water found by a flood fill each tick, the right model for a lake
and a step of its own. Their call (2026-09-22): none of this needs
deciding now; the frame's budget is comfortable.

## The laws to come

Every rule the game adds gets its law in `LAWS.bend` before the feature is
done. Next:

- *Crafting:* a recipe changes the counts by exactly its vector, and does
  nothing when an input is short.
- *Water:* a tick never raises the amount of water; water never moves up.
- *Survival:* health stays within its bounds; the dead do not act.
- *Entities:* none ends a tick inside a solid block, the player's law.
- *The picture:* the bench's thirty checksums. A change that should not
  change the image cannot.

## The budget

At 1470×796 a frame is 51 ms with a ray for every pixel and 14 at scale 2,
which suits the pixel art (the bench's fastest frames, 2026-09-30). At 60
frames a second that leaves under 3 ms at scale 2 for the looks still to
come, and none at 120. What each look took is in engine.md; what a ray
caster can do to cost less, and what was tried, in [perf.md](perf.md).

## Bend: waiting on a decision

The game builds with 2.0.34 and the four changes below, from the
`bendcraft` branch of AdrielSantana/bend (the Makefile's `BEND`); once
they are released it goes back to the stock `bend`.

| | what it is | state | if yes | if no |
|---|---|---|---|---|
| [PR #1132](https://github.com/bendlang/bend/pull/1132) | Metal: the work pass after a grow runs each lane's own ring, [#925](https://github.com/bendlang/bend/issues/925)'s answer; 2.5-2.8 times faster frames on 2.0.34 | open | the stock `bend` | our branch, rebased at every release |
| d84f292c, our branch's | a def that a loop calls is inlined whatever its size; the meadow 14% faster ([perf.md](perf.md), 23) | not yet proposed: an issue or a PR to weigh | the stock `bend` | our branch |
| 9c4be1a1, our branch's | a loop over a Nat checks the error word as it enters, not every turn; 2 to 5% of every view ([perf.md](perf.md), 24) | not yet proposed, with the one above; comp.ts passes its 64k ttok cap | the stock `bend` | our branch |
| df0b066e, our branch's | `--relaxed-math`: Metal may reorder and fuse floats; 5 to 13% a frame, nearly every pixel within two levels ([perf.md](perf.md), 25) | not yet proposed: Bend computes floats as written on purpose | the stock `bend`, the flag kept | our branch |
| [#1143](https://github.com/bendlang/bend/issues/1143) | Metal: `heap_free`'s error check, 7-12% of the allocating benches; numbers and risks, no PR | open | nothing here: the frame does not allocate | — |
| [#1195](https://github.com/bendlang/bend/issues/1195) | a generic def at a Data record builds it on the device heap: a `Bool.pick` of two records kept Metal's compiler past 11 minutes | open | records may be picked | pick scalars, or match in a def of its own |
| [#923](https://github.com/bendlang/bend/issues/923) | Window: full screen | open | a key for it | `make full` sizes the window to the screen |

The frame's tree is binary because of how Metal's scheduler filled its
lanes (#925); on #1132, measure the four-way tree again, and go back to it
if it ties, since it reads better.

The page's compiler is a fork of its own (`BEND_WEB`, the web target of
[#866](https://github.com/bendlang/bend/pull/866), which was closed). The
page is not ready until it runs on WebGPU.

**The routine, for every `bend update`:** `make check test bench profile`;
the thirty checksums and the physics hash stay the same, or the update
says why; `test/trace.py` once, whose snippets match the runtime's text
and may need an update.

```sh
for n in 923 925 1132 1143 1195; do gh issue view $n -R bendlang/bend --json state,comments; done
```
