# Buying frame time

What a ray caster can do to cost less, borrowed from the industry and
shaped for Bend, each tried alone and kept only for what it measures.
The budget itself is in ROADMAP.md ("The budget").

## Where the time goes

The baseline, 2026-09-28, the meadow's grass and flowers before
techniques 1 and 4 (three walks to 40 blocks, cupped flowers): the least
of six runs, ms a frame.

| | meadow | bench's view | hill | night, all sky |
|---|---|---|---|---|
| all on, 1470×796 | 57.8 | 44.2 | 45.4 | 21.0 |
| grass off | 20.8 | 27.4 | 26.2 | 21.6 |
| rays alone | 10.4 | 13.2 | 11.8 | 9.8 |
| all on, 735×398 | 17.0 | 13.0 | 12.4 | 6.4 |
| grass off | 6.0 | 7.8 | 7.8 | 6.2 |
| rays alone | 3.0 | 3.8 | 3.6 | 3.0 |

The meadow (test/profile.bend's `meadow`, py 21.6, looking down the
field) is past 60 frames a second at the player's scale 2, and the grass
is two thirds of it. Its walks' steps are most of that: taking every
blade out of the coarse walk read 58.4 → 54.2 at 1470×796. The frame is
its slowest lane, and the slowest lanes hold the rays that skim the
grass towards the horizon, crossing dozens of cells each.

After techniques 1 and 4, six alternated rounds against that baseline:
the meadow 59.8 → 55.2 ms at 1470×796 and 16.6 → 15.8 at 735×398, back
under 60 frames a second; the bench's view 47.6 → 41.8 and 12.2 → 11.8,
the hill 46.6 → 44.4 and 12.6 → 12.4.

The meadow's grass, split (2026-09-28, six rotated rounds, the meadow at
1470×796, 54.6 ms all on, 19.8 with the walks off): the fine walk 19.4,
the coarse 7.8, the broad 4.8; the rim's bookkeeping nothing. Of the
blades' tests, some 15 ms: the three more blades of the near cells 3.6,
the flowers nothing, and a blade's setup (its hash, root, lean, height
and push) some 60% of a test, the ray against it the rest (setup made
trivial: 53.0 → 44.2; no test at all 38.0). A map of each pixel's steps
says the fine walk's tested cells lie over the whole near carpet, some 3
a pixel, each of up to six blades, and the skimming rays' extra steps
are mostly empty. The frame is throughput-bound: techniques 5, 17 and
22, each cutting the skimming rays' work, gave a millisecond at most.
The lanes of a SIMD group run their pixels together, so a step pays the
tests whenever one sibling tests: from the step maps, a group's fine walk
takes about twice its pixels' mean (1.7 to 2.1 in three views, walks
merged into one loop or not). Every blade near the eye is set up again
for each of the some 500 rays that cross its cell.

## How to try one

- One technique a build, against the build before, six alternated rounds
  with the game closed (`pgrep -fl build/bendcraft` first), the least of
  each row; at 1470×796 and at 735×398, the player's scale 2.
- Views: the meadow, the bench's, the hill (py 27 over the valley) and
  the night's all sky for the clouds.
- The picture: the bench's digest when the technique should not change
  it; when it does, renders beside the build before, judged by eye.
- Each result goes in its line below, kept or dropped, with its numbers.

## Cheaper steps

A step is the unit of cost: the near DDA's 60, the far walk's up to 128
with its cell skip, a shadow's 24, a mirror's 32, the clouds' 16, the
grass's three walks of up to 64.

- **1. The grass's patch from a map** — kept (2026-09-28). A block
   column's patch computed a lattice noise, two sines, two divisions and
   a hash at every new block of a walk. The split first, four rotated
   rounds at 1470×796: the patch constant read the meadow 58.6 → 52.8 ms
   and the hill 46.6 → 42.8; without its divisions, 56.4 and 46.6. Its
   lasting part is a function of the column mod 256, so `src/meadow.bend`
   writes it in 2^16 words past the clouds' map at the world's birth (how
   wild the meadow grows, the flower's kind, the wind's phase along z), and
   the patch reads a word and keeps one sine for the wind. Six alternated
   rounds: the meadow 56.4 → 54.8, the bench's view 47.6 → 44.0, the hill
   46.2 → 44.4. The wind no longer jumps where the window's columns wrap
   past 256.
- **2. No division in a step** — worth nothing here (2026-09-28): the
   patch's two, taken out, read the meadow 58.6 → 56.4 and the hill the
   same, within the noise. The far walk's three a step took 9 of its 31
   ms; these run once a block, not once a step.
- **3. Uniform steps.** Once the patch is a load, read it every step and
   drop `refetch`'s match: lanes of a group then stop parting ways.
- **4. Fewer hashes** — kept (2026-09-28), within the noise. The cell's
   hash was an argument, so every step paid it, the ray near the cell or
   not; `blades` now hashes it in its branch. Six rotated rounds against
   the map alone: the meadow 54.4 → 54.6 ms, the bench's view 44.8 →
   42.0, the hill 43.2 → 42.6. The wind's sine, taken out, read the
   meadow 54.6 → 52.2 in that run and 54.4 → 53.0 in the next, and a
   smoothed triangle in its place 53.8: noise, so the sine stays.

- **15. What a frame shares, computed once.** The camera's basis takes
    five sines and cosines, two divisions and a root a pixel from the
    yaw and the pitch. Taken once a frame on the host instead (four camera
    words for two), worth nothing (2026-09-28): the rays alone 10.2 →
    10.2 ms at 1470×796, the meadow 54.2 → 53.8, within the noise; a sine
    is not dear here. Still a function of the clock alone, per pixel: the
    weather (`Clouds.weather`, two hashes, five calls a sky pixel), the
    wet (three weathers a wet pixel), the clouds' drift; cheap by the same
    token, untried.
- **16. A narrower walk** — the level as a template, worth nothing
    (2026-09-28). The shaders guide: a wide record round-trips the stack,
    and a constant passed as a `~` template rides in no task. The walk
    carries some forty words a step, eight of them its level's constants;
    handing the level as `~fine()` and opening it in a helper each step
    compiled a walk per level and read slower in every view: the meadow
    54.4 → 60.0 ms, the bench's view 44.0 → 47.4, the hill 44.0 → 47.0,
    the picture byte for byte the same. Three copies of the walk and all
    it calls cost more than eight words.

## Fewer steps

- **5. The grass skips blocks** — worth nothing (2026-09-28). A map of each
   pixel's steps at 735×398 found the fine walk's in the slowest regions
   85% empty: cells over a floor with no grass, or under the ray's pass
   over the blades, and the top 1% of the meadow's pixels ran the fine
   walk to its fuel's end. Crossing the rest of such a block in one step,
   the sides passed along each axis counted, halved those regions' steps
   (the meadow's worst 76 → 40 a pixel, the bench's 40 → 25, the hill's
   32 → 25) and moved no picture past a level but one pixel's. Six
   alternated rounds: the meadow 54.4 → 53.4 ms at 1470×796 and 16.2 →
   15.4 at 735×398, the bench's view 43.2 → 44.4 and 12.4 → 12.4, the hill
   44.2 → 44.6 and 12.6 → 12.8. An empty step is cheap; the cells the ray
   meets blades in are the cost.
- **22. The grass's walk stops sooner** — worth nothing (2026-09-28). It
    stops once the ray sees 5% through the blades; at 20%: the meadow 54.8
    → 53.4 ms at 1470×796 and 16.4 → 15.6 at 735×398, the others within
    the noise, and a meadow a little more see-through.
- **6. A column's top for the near DDA and the shadows.** A ray above a
   column's highest block crosses it without its y steps, so fewer fixed
   steps reach as far. The solid mask holds the top; finding it cheaply is
   the question (no free word in a column).
- **7. A tile's beam.** The 4×4 tile's corner rays bound where its pixels
   can first meet a block (Laine and Karras's beam optimisation); each
   pixel starts there. Needs a conservative bound, or thin things between
   the corners are missed.

## Fewer rays

- **8. Adaptive 2×2 in the tile** (variable rate shading, the classic
   adaptive sampling) — dropped (2026-09-28). A tile
   shades one ray per 2×2 first; where the four agree within 8 levels a
   channel, each paints its 2×2, and elsewhere the other twelve are
   shaded, none wasted. No pass and no buffer: the tile's own recursion,
   the HUD laid over every pixel. It coarsens a quarter of the pixels of
   the meadow's views, in the sky and inside the blades too; what it loses
   is a two-pixel step on some edges, of leaves and blades, and features
   under two pixels between the samples. Six runs, the flag off → on:
   at 1470×796 the meadow 56.4 → 52.4 ms, the bench's view 46.0 → 41.4,
   the hill 45.2 → 42.2, the night's all sky 21.0 → 14.6; at 735×398
   16.2 → 16.0, 12.4 → 11.6, 12.2 → 12.2, 6.6 → 5.2. It pays at full size
   and in the sky; at scale 2 the grass's slowest lanes are left as they
   were, and a 2×2 is four screen pixels a side. Dropped: seen in the
   game, the corners of blocks and leaves read strange, for too little
   at the player's scale.
- **9. The dear looks at a lower rate than the rays.** A ray a pixel keeps
   the blocks' edges sharp; the clouds' march, a mirror or a soft shadow
   is smooth, so a 2×2 of sky can share one march.
- **10. Dynamic resolution.** The host reads the frame's time and picks the
    next frame's scale to hold the budget, as most AAA games do. Host
    state, no pass. Scale 2, nearest neighbour, is already there, with a
    floor of about 3 ms of growing and packing a dispatch; the window's
    shader scales by a power of two (main.bend), so the steps between are
    the question.

## Level of detail

- **11. The grass's ranges by their cost.** Fine to 12 blocks, coarse 10
    to 22, broad 20 to 40: each walk's share per view, and the ranges moved
    where the look and the cost meet.
- **12. Looks off where the fog hides them.** Texture, occlusion and the
    shadow's ray for hits the fog nearly covers; the far band is one
    region, so its lanes agree.
- **13. Quality presets.** The flags are there; a key or a menu picks the
    grass's walks and the clouds.
- **17. The grass's detail by a ray's budget** — worth nothing
    (2026-09-28). The fine walk handed over to the coarse one once it had
    crossed some 24 cells (6 blocks over the ray's rate across the ground
    after its rim), not at 10 blocks; it changed under 1% of the pixels,
    the tips in the skimming band. Six alternated rounds: the meadow 54.4 →
    54.6 ms at 1470×796 and 16.2 → 16.0 at 735×398, the bench's view 45.2
    → 44.6 and 12.2 → 12.0, the hill 41.8 → 45.0 and 12.2 → 12.2. With
    technique 5, it says the skimming rays are not the slowest lanes: the
    fine walk costs the meadow 19.4 of its 54.6 ms (the coarse 7.8, the
    broad 4.8; the rim's bookkeeping nothing), spread over the whole near
    carpet, some 3 cells of up to six blades a pixel; the three more blades
    of the near cells cost 3.6, the flowers nothing.

## Precomputed light

- **14. A horizon map.** Per column, the sun's lowest height that reaches
    its top, refreshed on the host as the day turns: a top's shadow
    becomes a read. State updated by the tick, like the flow, not a
    frame's cache; the sun moves every frame, so how often to refresh is
    the question.

## Reading the last frame

The industry's largest savings are temporal: Horizon Zero Dawn renews
one cloud pixel in sixteen a frame, checkerboarding shades half the
pixels, TAA and DLSS or FSR rebuild a frame from the last ones, and
path tracers and Teardown filter their noise over frames. Each needs the
last frame, a cache keyed by frame, which AGENTS.md rules out; trying one
means revisiting that rule first. What the runtime allows, from
`bend guide shaders` and the emitted C:

- *A tile's own past is free.* The last image rides down the frame tree,
  opened in four at every node (`Image.open(old)` in the guide's demo), so
  each tile is handed its own square of it, owned: no sharing, no counts.
  Enough for a still camera, and for renewing one pixel of a block a frame.
- *Another tile's past is not.* A turning camera moves a point six pixels
  or more a frame, out of its 4×4 tile, and a tree has no way up or
  sideways. Sharing the whole last image as a `+` tree makes the compiler
  count its nodes, and sealing is per type, so every `Image` node pays,
  the new frame's too (the guide measured 8.0 → 16.5 ms on its frame).
- *The way around is the world's way.* The last frame as an `Array<U32>`
  filled on the host after the `!` (a parallel walk over a 1470×796 frame
  takes 1 to 2 ms; the writes are not measured); a ray reads any old
  pixel by its index and reprojects exactly, since it knows where it hit.
  `main.bend` then calls `Window.frame` itself, which hands the image back.
- A denoiser only once a look is stochastic, and on the light alone,
  never on the texture, or the pixel art smears.

## Passes and primitives

- **18. A beam through the grass.** The tile's sixteen rays cross nearly
    the same cells; a walk of the tile's beam could read each cell's patch
    and hash once and set up its blades once for the sixteen (packet ray
    tracing, and Laine and Karras's beams). Untried, for its shape: rays
    a pixel apart part cells at the cells' sides, and a walk that tests
    the cell across a side for the rays that crossed it pays that test in
    every lane of the SIMD group whenever one of them does.
- **19. Rasterised grass,** the industry's way: blades as triangles, binned
    into the screen's tiles (the lists and flat loops of the shaders
    guide's 120 FPS demo), each tile drawing its own over the ray's depth.
    A blade is set up once a frame where the walks set it up once for
    each of the some 500 rays crossing its cell, and a pixel tests the
    blades over its tile, not the cells its ray crosses. A second renderer
    beside the ray caster, and a pass to bin. Estimated and not built
    (2026-09-28): a pixel of the near carpet would still test the 16 to 20
    blades whose boxes cover its tile, about as many as the walk tests, so
    the saving is the setup and the walk's steps, while binning on the
    host costs some 2 ms a frame whatever the size: 1 to 2 ms at scale 2,
    10 to 13 at 1470×796.
- **20. Two passes.** The rays' hits as a tree the shading walks, the old
    image's way down the frame tree: smaller kernels, more of them in
    flight. A dispatch's floor is about 3 ms at scale 2, so it must buy
    more than that.

## The runtime

- **21. Lanes that share the work.** Each lane runs one fixed region of
    the screen to its end, so a frame waits for its slowest lanes; more
    tasks than lanes, handed out as lanes free up (a queue, persistent
    threads), would bring it nearer the mean. That is Bend's runtime (the
    combined compiler at ../bend), not the game's, and the meadow says it
    would buy little: its frame is throughput-bound (above), and the work
    taken from its slowest rays came back as a millisecond at most.

## Tried, and worth nothing here

- Typed picks, `pick(c, a: F32, b: F32)` and `word` for U32, in place of
  the 159 generic `Bool.pick` of the renderer, the world and the player,
  which `bend guide shaders` says box their words (2026-09-21): same
  checksums, same fastest frame at all six sizes, four alternated rounds.
- The GPU's own lessons (the fork's shape, early exits, divisions in a
  walk) are in AGENTS.md.
