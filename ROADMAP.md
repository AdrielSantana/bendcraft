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
2. **Water's shader.** Depth tint, Fresnel, the analytic reflected sky,
   ripples from a noise normal moved by time, and the world reflected by a
   second ray (2026-09-21) are done. The mirror is paid like the shadow
   ray, only on the pixels that show a water top: 32 dry steps, a fade at
   the end of its reach, bit 27 of the base word. Not screen-space
   reflections: those exist because a rasteriser cannot send a ray into
   its scene, so it marches the depth buffer instead, and pays with
   whatever is off the screen or hidden going missing. Here a ray is what
   we have, and a finished frame is what we cannot read (see "Reading the
   last frame"). It is the dearest look so far, 6 to 7 ms of a lake's frame
   at 1470×796 and 1.6 at scale 2, because a step costs what it costs
   anywhere (README, "What costs what"). Two ways to make it cheaper, for
   when the budget asks: walk the far horizon's ring of 4-block cells once
   it exists (8 steps for the same reach), or let the mirror ride the
   primary walk's idle steps, since a ray that met the lake's bed walks
   the rest of its 60 with its state frozen. The view from above, where
   the mirror is 2% of the colour, has its false caustic (2026-09-21): the
   ripples' noise read at the bed, two octaves, thin threads, bit 28. The
   shader is done; what is left of the water is its physics.
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
   column mask below y=12. Rays cross it, tint by wet distance and retain
   air fog underwater; water fog hides the ray limit. Placing solids
   displaces it, and saves keep it. Submerged grass surfaces generate as
   dirt; the lowest sandy beds remain sand. Trees only generate on dry grass;
   canopies may overhang the water from a dry bank. Existing edited columns
   remain authoritative when loading old saves.
   Fresnel, sky reflection and ripples have separate flags. The ripple
   pattern stays in world coordinates through ring shifts.
   Terrain reflection by a second ray is done. Next:
   physics, a cellular rule over the edits' Map: down first, sideways,
   sources stay. Swimming and collection are not implemented yet.
   The water model was chosen on 2026-09-21: **finite volume with explicit
   river sources**. Ordinary flow conserves volume; lakes can drain, and
   adjacent water does not create a new source. Use bounded integer amounts
   per cell and fixed simulation ticks independent of rendered frames:
   transfer down first, then sideways into remaining capacity. Read the old
   state and resolve competing transfers before applying the new one, so
   traversal order cannot duplicate water. Creation by sources and removal
   by explicit edits need accounting separate from ordinary flow. Keep
   unloaded boundaries closed to transfer and preserve edited amounts in
   saves. Work is limited to active cells; choose volume resolution and the
   tick/work budget with the bench. Prove bounds and transfer conservation
   before integrating flow. Player immersion, drag and swimming are a
   separate implementation step.
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

## Water physics: the design (2026-09-21)

The model is the one chosen above, finite volume with explicit sources,
made concrete. The picture of the still lake must not change until a
block moves; that is the first gate of every step below.

- **Units.** A cell holds 0 to 8 units of water; 8 is full. The amount
  is a nibble, four words a column at slots 6..9, so the column widens
  from 8 words to 16 (the ring is 2^18 words, a megabyte; slots 10..15
  are spare, four of them for the light of the blocks later). The water
  mask at slot 5 stays the truth for "any water here", bit y set exactly
  when the amount is over zero: the ray walks the mask as it does today
  and reads nothing new along the way. A save writes the four words after
  the six it writes now; a six-word column loads with 8 wherever its
  mask has a bit, so old saves are the same lake.
- **The surface.** Where a ray first enters water from above, the render
  reads that cell's nibble once and lowers the surface to y + amount / 8:
  the entry moves to where the ray meets that plane, the wet depth loses
  the air above it, and the reflection, the ripples, Fresnel, the mirror
  and the caustic all happen on the plane. A full cell's plane is its top
  face, so every picture of today stays bit for bit. A partial cell seen
  from the side shows its side face whole and its top lowered: the wedge
  of a stream is its top. The plane is a function of the ray and one
  read; nothing else changes in the DDA.
- **The rule.** A simulation tick every 200 ms, whatever the frame rate.
  For each active cell holding a > 0 units: first down, the cell below,
  if not solid, takes min(a, 8 - b); then sideways, each of the four
  neighbours that is not solid and holds less takes floor((a - n) / 2),
  never more than what is left. Every transfer is one atomic move of k
  units from a cell to a neighbour, applied at once on the current state:
  volume is conserved by construction, no cell exceeds 8 or goes under 0,
  and no traversal order can duplicate water. The order of the four
  sides alternates with the tick's parity, so the bias of a fixed order
  cancels over two ticks. A neighbour outside the ring is solid: the
  loaded window's edge is closed, and a lake that reaches it holds.
- **Sources.** A source is a cell marked in its column (a bit in a spare
  word) that refills to 8 at the end of each tick it took part in. The
  seed's lakes are not sources: dig a channel and they drain. Sources are
  the only creation of water, and an explicit edit (a solid placed in
  water, water collected) the only removal; the flow itself neither
  creates nor removes. The accounting is a law: a tick without sources
  keeps the world's volume; with sources, the volume grows by exactly
  what they refilled.
- **The active set.** As built (2026-09-22): a word of marks per column
  in the ring (slot 10, bit y: the cell is due a step) and a queue of the
  marked columns' slots in the world, oldest first, each once while its
  word is set; a `Map` keyed by column would have cost a string key per
  mark. Marks are on slots, so a mark on a column that has left the
  window is spent, harmlessly, on the column at its slot, and no mark is
  lost. A transfer marks the cell that lost water, the one above it and
  its four sides (they may fill it now) and the one that gained; an edit
  marks its cell, the one above and the four sides; a cell that could not
  move anything drops out; a column back from the edits is marked where
  it is wet, its sides whole. A tick steps at most 256 columns, the rest
  wait their turn, so the host's work a tick is bounded whatever the
  lake: `make flow-bench` drains the spawn's lake through shafts at 0.3 to
  1 ms a tick with 100 to 190 columns queued.
- **The steps.** (1) The levels: the wider column, the save, the surface
  plane; the digest and the physics hash unchanged; laws on the nibble
  packing — done 2026-09-21 (eleven laws, 110 in all; the frame costs the
  same within the noise; the lowered top is subtle until the step's side
  and side entries render, which go with (2)). (2) The rule, windowless: laws of one transfer (bounds and
  conservation), tests of a tick (a column drains, a pool spreads and
  settles, a wall holds, the ring's edge holds), then the tick in the
  game — done 2026-09-22 (thirteen laws, 123 in all; 152 tests; the
  digest and the physics hash unchanged; the tick every 256 ms of the
  day's clock, 4096 a turn; the DDA clips a partial cell's wet segment
  to its plane, specialized on a bit of the base so a frame without
  partial water costs what it did and one with it about a sixth more,
  34 → 41 ms on the lake at 1470×796). (3) Sources, with their accounting
  law. (4) Edits: what a placed block displaces and what collecting
  takes, both counted. (5) The player in water: buoyancy, drag, swimming,
  breath later.
- **What step 2 found: the unit is too coarse.** The rule moves nothing
  between neighbours a unit apart, so a surface at rest may slope one
  unit a cell toward wherever it drained: the spawn's lake breached into
  a pit (`make flow`) stops 424 ticks on with `8 8 8 7 6 5 4 3 2 1 0`
  along its top row, the pit under it holding a film of 214 units of the
  1152 it has room for, the queue empty. A unit is an eighth of a block,
  so a lake drained from one end tilts by an eighth a block, visibly,
  and a lake stops draining long before it is level. The rule is right
  (a unit of one that moved would slosh back for ever); the unit is the
  problem. The fix on the table: a byte a cell, 0..255, eight words of
  amounts at slots 6..13, the marks and the partial mask at 14 and 15,
  the column full, a source then a nibble type (9) in the type words
  rather than a spare bit; a slope of a unit a cell becomes 1/256 of a
  block, invisible, a stream's steps smooth, and a film of one unit
  effectively nothing to the eye while still counted. It changes step
  1's format (ten-word saves are only local so far; a loader can widen
  them) and the eleven nibble laws. The decision is the user's, since the
  design above said eight; nothing else in the flow changes.

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

Today's 92 laws include day and ripple periods for every `U32` clock word
and six universal inventory laws, with counts as `Nat` and slots as a list.
The other 84 laws are concrete checks, including water surface packing,
lake floors, dry tree roots, HUD packing and save/quit
edges. Floats stay in the windowless tests: the checker does not compute them.

## The order

A proposal, a piece of the look then a piece of the game, the look first
since it is what a visitor sees:

1. sky, sun, fog and the day cycle — done, 2026-09-21
2. collecting and the inventory, with laws stated for every count — done, 2026-09-21
3. water: still water and its shader done, 2026-09-21; then its physics
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

Underwater fog, 2026-09-21: using the first water entry as the fog
distance made fog vanish for a submerged eye (entry zero). Air fog now
uses the full solid-hit path, including dry distance after leaving water.
Flag 22 adds extinction over 24 wet blocks, before the 60-step limit;
foreground air fog still hides distant lakes. The submerged profile and
sixth exported image expose the new flag. Regression rays cover exit to
air, distant lakes, fog endpoints, the DDA limit and disabled flags.
70 laws close and all four gates pass. The default picture intentionally
changes to bench digest `eb4026d59c88c6fa0d1e00ab7990e825`; physics stays
`73516c0ead87f8c1151e34d25b3ac32e`.

After a possible open-game timing conflict, four fresh alternated rounds
checked that no Bendcraft process was running. At 1470×796, full profile
21.0 → 21.4 ms; submerged 20.6 → 21.2. The added work is the full-path
fog evaluation and water-extinction colour mixes, with unchanged DDA and
camera. Water-off and rays-only changes fall within overlapping run
ranges, recorded with the full table in README. Four alternated fresh-C
traces locate the increase in the work kernel, 17.430 → 19.290 ms minimum;
grow and pack stay within 0.051 ms. Six bench minima:
3/3/6/10/19/36 → 2/3/6/10/20/37 ms. The earlier possibly contended series
is not used for this comparison. Finite-volume flow with explicit river
sources is agreed above; flow and swimming remain unimplemented.

Dry tree roots, 2026-09-21: generated trees now require dry grass at their
origin, using the same sea height as water generation. A rejected tree
contributes neither trunk nor canopy to neighbouring columns; dry banks
can still overhang water. Edited columns retain their saved contents.
The initial window goes from 202 to 173 trees. Tests inspect all 16384
generated columns, check removed canopies, preserve a shoreline tree and
reload an old submerged wood edit. Three laws cover all 32 column heights;
73 laws close, all four gates pass, and the native game builds.

Four alternated rounds with no Bendcraft process detected: at 1470×796,
full profile 20.8 → 20.4 ms, rays alone 12.2 → 12.0. The six bench minima
stay 3/2/6/10/19/36 ms; lake and submerged full profiles stay 21.4 and
20.6. Increased off-row minima overlap the recorded ranges in README.
Removing trunks changes the scene: submerged steps to a hit or sky grow
31.1 → 35.5, with unchanged rendering code. The default picture changes
intentionally to `bde77065fa3245e3615faeeae5d5057d`; physics remains
`73516c0ead87f8c1151e34d25b3ac32e`. Shader work, finite-volume flow and
swimming remain subsequent steps.

Lake floors and underwater silhouettes, 2026-09-21: the generated surface
is dirt below water where it used to be grass; the lowest sandy beds,
dry shoreline grass, snow and saved edited columns retain their rules.
Fog now colours the background before water tints it, so a distant block
and the sky behind it converge through the same wet path. Foreground haze
attenuates that tint, keeping distant lakes hidden. The earlier side-exit
test expected an unfiltered sky and missed the bright silhouette visible
in the user's screenshot. New real-ray tests compare a far wall with sky
through identical water, preserve nearby walls, and cover day, twilight,
night and fog flags. The generated-column scan also checks lake materials.
Both regressions fail on the previous version. All four gates pass and
75 laws close; the native game and the six exported water views build.

Four alternated rounds after closing the game, with process checks:
full profile 21.2 → 21.6 ms, rays alone 12.6 → 12.8, lake 22.2 → 21.4,
submerged 21.6 → 21.4. The increased minima lie within the overlapping
ranges in README. Four fresh-C traces investigate the default increase:
work minima 18.287 → 18.308 ms, fastest traced dispatch
20.571 → 20.442; grow/pack minima differ by at most 0.038 ms. This does
not establish a repeatable 0.4 ms slowdown. Six normal bench minima:
3/3/6/10/20/38 → 3/3/6/10/19/38 ms. The wet shader reorders two colour
mixes and adds a subtraction and multiplication; ray geometry is unchanged.
The default picture changes intentionally to `d1956084325187d408ce8f22887852ce`.
Physics stays `73516c0ead87f8c1151e34d25b3ac32e`.

Fresnel and analytic sky reflection, 2026-09-21: the first downward
water-top entry reflects the sky, sun, stars and moon. Reflectance grows
from 2% head-on toward a mirror at grazing angles. Bits 23 and 24 switch
Fresnel and reflection independently; the first top entry uses a spare bit
of the existing ray step counter, without widening the camera or wet trace.
The surface uses foreground air fog and returns exact sky at full haze.
Submerged eyes, upward exits and banks before water keep their old image;
edited water heights also work. No second world ray is cast.

All four gates pass and 81 laws close, including an exhaustive integer
check of every legal step count and face code with and without the water
marker. Float tests cover angular response, signed entry, reflected bodies,
fog extinction and the earlier underwater silhouette regressions. Ten
exported views were inspected. The submerged image is byte-identical to
the previous version; disabling reflection restores the old lake image,
and disabling both new flags restores all thirty old bench checksums.

Four alternated rounds at 1470×796 with no game process: full profile
20.6 → 21.8 ms, lake 21.8 → 23.4, submerged 21.6 → 21.4. The reflected
sky and Fresnel add work at water surfaces; the shared first-top marker
also adds tests to the water-enabled DDA. Reflection off measures 20.6
in the default view and 21.8 at the lake. The new night-lake profile is
20.6 ms, reflection off 18.2, Fresnel off 20.2, stars off 19.4, moon off
20.0. Normal bench minima are 2/3/6/10/21/36 → 3/3/6/11/21/38 ms.

Rays alone initially rose 12.0 → 12.4 ms. Four fresh-C traces of the
exact profile cameras investigate that increase: rays-only work minima
10.496 → 10.593, fastest dispatch 11.992 → 12.057, overlapping frame
ranges in README. Four turning-camera traces likewise give work
10.455 → 10.520 and identical checksums. They do not reproduce a 0.4 ms
slowdown. Full work does increase 17.737 → 18.640, reflection off 18.250;
water-off dispatch improves 17.436 → 17.204. The consistent extra cost
is in the water-enabled path. Tracing submits kernels separately and
does not replace the normal timings or resolve every small difference.

The default picture changes intentionally to `4e4c70d58bf32c4c721ae9eaae96e707`.
Physics stays `73516c0ead87f8c1151e34d25b3ac32e`. Next are ripples, then
terrain reflection and finite-volume flow/swimming. All `Cam.fl` bits are
now assigned; another look needs a packing change with readback laws.

The world in the water's mirror, 2026-09-21: a second dry walk of 32
steps from the water top along the mirrored, rippled direction; the hit's
colour, texture and face tone, fogged by the whole path, fading into the
mirrored sky over the last quarter of the reach 28 / (|dx| + |dy| + |dz|).
The look is bit 27 of `Cam.base` (`Render.looks_base()`), since `Cam.fl`
is full; five laws keep the ring address, the ripple clock and the readout
through it. With the look off, four views are the previous commit's bit
for bit. The bench digest stays `0b9d000fe324fdac57d1dcc98658ec91`: no
mirrored ray meets a block in its views, though every water-top pixel pays
the walk (21 → 24 ms at 1470×796). Physics is unchanged. 97 laws.

Dense water, 2026-09-21: the user found the water too clear to show its
mirror. Seen from the air the tint is now 1 - 0.88 / (1 + 0.35 d)², with
the light's way down counted in d; the day colour is deeper (18, 84, 112);
Fresnel grows by a cube, not Schlick's fifth power; an eye under the water
keeps the clear tint. No measurable cost. New picture digest
`123459508674587f4d41b6c63389c05b`; physics unchanged; 118 tests.

The false caustic, 2026-09-21: `Water.caustic` multiplies the bed's colour
on a wet hit, from the ripples' value noise at the bed's point (scales 2
and 3, lattice scaled with them, the ripple clock), thin threads by the
squared product of two ridges, mean near zero, fading by six blocks of
drop, with daylight and towards a look along the surface. Bit 28 of
`Cam.base`, two laws (99), three tests, a view pair in `make water`. It
costs 1.0 to 1.4 ms on a lake at 1470×796 (31.0 → 32.0), 0.2 at scale 2,
nothing at night (skipped there, uniformly). New picture digest
`788495f2eae1d62c6cd89f92af855661`; physics unchanged.

Depth-darkened water, 2026-09-21: the tint's colour goes to a near-black
blue by six blocks of drop (`Water.ink_at`), the fog's colour unchanged;
the user asked whether the caustic should darken with depth, and what did
not darken was the water. No cost. New picture digest
`bb0a2b5042e9720be30cb2914db01a4a`. Then the light by depth: the user
found a diver at the bed saw it as bright as from the bank, because the
depth was the ray's vertical wet extent, near zero for a look along the
bed. Now `Water.drop(y)` is the point's depth under the level (the sea's,
until the physics gives columns their own), `Water.light` dims what a
wet ray meets by it, the ink darkens by it, the caustic fades by it, and
a submerged eye's fog converges to the colour at its own depth. No cost.
Picture digest `7f527573609445a1c0238d79accd24b5`; 123 tests.

Water amounts, 2026-09-21 (physics step 1): sixteen-word columns, the
amounts at slots 6..9, `World.pour`, ten-word save lines, the surface
lowered at the first top entry (`Water.lowered`, one read). Digest and
physics unchanged; eleven laws; 128 tests; bench and lake the same within
the noise (32.4 and 32.8 ms, both orders).

What is measured today, at 1470×796 on an M5: 25.2 ms a frame (23.0 with
the mirror off), rays alone 12.4, shadow off 21.6, water off 18.2; a lake
31.2. Small differences between
variants are noisy; use alternated runs. A ray walks the box's 60 steps
whether it hits or not, on purpose (README, "What costs what").

**The routine, for every change to the frame:**

- a flag in `Cam.fl` if the look can be turned off, and its line in
  `test/profile.bend`;
- `make bench`: the md5 of the thirty checksums stays `7f527573609445a1c0238d79accd24b5` when
  the picture did not change (`make bench | grep -o 'checksum=[0-9]*' |
  cut -d= -f2 | md5`); when it did, the new one goes in the commit;
- uniform control flow in anything a lane runs: a branch that saves work
  for some rays has cost more than it saved, twice.

A single run reads high at the small sizes when the GPU is cold or the
machine busy (512² at 6 ms for 2): compare builds by alternated runs and
their fastest frames.

**The routine, for every `bend update`:** `make check test bench profile`,
rebuild the page with the rebased fork (`../bend-web`, the fork's
`web-wasm` branch, the PR's head) and run `make page-test`, run
`test/trace.py` once (its snippets match the runtime's text and may need
an update). 2.0.25
(2026-09-21): the gate passes as it did, the thirty checksums and the
physics hash are the same, the frames are the same within a millisecond
(order-swapped rounds), the trace's snippets still match. The page's
fork rebased onto 2.0.25 and pushed the same night, after a bisect of the
18 upstream commits found the page out of memory from 2.0.25's `select`
sets (see the PR row below); the page is published from it.

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
| [PR #866](https://github.com/bendlang/bend/pull/866) | `-o x.html`: the runtime as WebAssembly, a worker a core, a Window on a canvas | ready for review, rebased onto 2.0.25 (2026-09-21); over the `comp.ts` cap by 83 tokens (main itself is 42 under it), said so in the PR; carries a one-line fix the page needs: 2.0.25's `io_wait` sizes its `select` sets by the highest fd, and Emscripten's `select` is a shim that `FD_ZERO`s whole `fd_set`s, 128 bytes into an 8-byte set | `make page` with the stock `bend`; drop `BEND_WEB` | the fork stays the page's compiler, rebased at every release |
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
