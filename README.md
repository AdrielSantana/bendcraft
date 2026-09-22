# Bendcraft

An endless voxel world you can walk, jump, break and build, written in
[Bend](https://github.com/bendlang/bend) and rendered by one parallel call:
on the GPU through Metal, or on every core of your machine as WebAssembly.

**Play it in the browser:** https://adrielsantana.github.io/bendcraft/

`W A S D` walk · `space` jumps · drag the mouse to look (or the arrows) ·
click breaks · right click places (or `J` / `L`) · `1`–`8` choose the block
to place (grass, dirt, stone, sand, wood, leaves, brick, snow) · `P` saves ·
`F` shows the frame's time · `Esc` quits and saves.

You start with an empty inventory. Break a block to collect its type;
placing spends one of the selected type. The hotbar shows each count
(`99+` above 99), and saves keep the full counts.

![Bendcraft](site/bendcraft.png)

## Build and run

Bend 2.0.23 or later (`bend update`). On a Mac with Metal:

```sh
make            # bend main.bend -o build/bendcraft
make run        # ./build/bendcraft --gpu 2GB            a 512 x 512 window
make full       # the screen's visible size, half as many rays a side
./build/bendcraft --gpu 2GB 1470 796 2                   # the same, by hand: a 14" MacBook
```

The two numbers are the window in points (a Retina screen has twice the
pixels: 1470 x 956 points on a 14" MacBook, 2560 x 1664 pixels), the third
how many times fewer pixels a side the render has (a power of two; 1 when
left out). The window's shader walks the image quadtree from the window's
size and stops at the first pixel it meets, so a coarser render scales up
by itself, nearest neighbour, which suits the pixel art. `make full` asks
the screen for its visible size with a line of Swift and takes the title
bar off, at scale 2; `make full SCALE=1` is a ray for every pixel, 16 ms a
frame on a 14" MacBook. The costs are in the table below, and `make profile`
says what each part of a frame costs.

The page is built with the web target of Bend from
[bendlang/bend#866](https://github.com/bendlang/bend/pull/866), a checkout
of that branch:

```sh
make page BEND_WEB=../bend-web/bend2/main.ts   # site/index.html, index.js, index.wasm
make publish                                   # the same onto the gh-pages branch
```

## How it works

**The world is one array, shared by every pixel.** `Array` in Bend has one
owner. Since 2.0.22 an `@unsafe` def may hand one array to both sides of a
fork anyway, two handles to one block that `Array.join` gives back, so the
columns around the player live in an `Array<U32>`: sixteen words a
column, the first a mask whose bit `y` says "there is a block at height
`y`", the next four the types of its 32 solid blocks, four bits each. Word
six is a separate water mask; words seven to ten hold the amount of water
in each cell, 0 to 8 units in a nibble, the mask's bit set exactly when
the amount is over zero; word eleven marks the cells the flow steps next,
word twelve the cells holding less than eight units; four words remain
spare. A primary ray with water on reads both masks once per column it
crosses and the solid type once, at the hit; only while the window holds
partial water does it read the partial mask with them, and a partial
cell's amount as it enters one. An edit is a few `Array.set` on the host;
a built world costs what an untouched one does. Thirty-two heights in one word is what makes it cheap:
the ray sees a column as a machine word, and break or place is one bit.

**The world is endless.** The terrain is seeded value noise, three octaves,
a pure function of `(x, z)`: sand on the lowest ground, dirt on the other
submerged surfaces, grass on dry ground and snow where it is high;
three of dirt under the top, stone below. About one grass
column in eighty grows a tree when its ground is dry (height at least 12),
a trunk of four wood with a canopy of leaves
over the columns around it; a column takes its wood and leaf bits from the
trees of the 25 columns around it, so a canopy crosses columns without
anyone writing across. The array holds
a ring of 128×128 columns around the player, and a `Map` holds the columns
the player edited. World column `(x, z)` sits at slot `(x·128 + z)·8`; the
array reads its index modulo its size, so any 128×128 window falls
one-to-one on the 16384 column slots, and a reader carries one word,
`base = ox·128 + oz`, to find local column `(lx, lz)`. The render and the
physics only see local coordinates in `[0, 128)`. The corner follows the
player one column at a time, loading the row that came into view, from the
map if it was edited and from the noise if not; an edit is a bit and a
nibble in the ring and the whole column in the map, so it is there when
you come back.

**The render** is a DDA through the ring, one ray per pixel, 60 steps. The
loop returns the solid hit and its distance, plus the first wet entry and
total wet distance; the look is a `match` after it:
a second DDA toward the sun for shadows, a pixel-art tile of four shades per
face, ambient occlusion per vertex from the eight cells around the hit, distance haze and low mist into the sky along the ray. The `!` runs a binary tree down to 4×4 tiles: a
square splits into its two rows, a row into its two squares, as many levels
as the larger side needs, and a half that lies past the render's edge is
one pixel and never a task. The shape follows the GPU runtime, which grows
a frontier of tasks two-way a turn until each of the 128 lanes of a group
holds one, then runs each task on its lane to the end: a two-way tree fills
the frontier with tasks of one size, so a wide frame at every pixel takes
16 ms where the four-way tree took 46, and its pruned form, with some lanes
holding 64 leaves, 110 to 150.

**Still water** fills terrain below y=12, excluding every solid voxel.
Material 8 uses the spare column word, so collisions, picking, shadows and
occlusion keep their original solid mask. The primary ray crosses water
and sees the ground; its accumulated wet distance gives the tint its depth.
Seen from the air the water is dense: the tint takes 1 - 0.88 / (1 + 0.35
d)² of the colour (an exponential's shape, which Bend has no function for:
a half at one block, 0.85 at four), and d counts the light's way down to
the bed as well as the ray's way up, so a look straight down doubles it.
A clear lake showed its bed through every mirror; a dense one leaves the
surface to the sky, the ripples and the bank. An eye under the water keeps
the clear tint (0.18 + 0.72 d / (d + 4)), or a diver would see two blocks.
What lies deep is lit by what little light got down to it: the light
left at a point's depth under the surface (all of it at the level, a
sixth six blocks down) dims whatever a wet ray meets there, from the air
or from under the water alike, so a diver at the bed sees the bed as the
bank does, and the caustic's threads dim with it; the tint's colour
darkens with that depth to a near-black blue, so a deep lake reads as
deep; and the fog a submerged eye sees converges to the colour at the
eye's own depth. Every lake lies at the sea level today, so the depth is
the level less the height; the water's physics will give each column its
level. The tint follows daylight.

The amounts are the first step of the water's physics (the design is in
ROADMAP.md): a cell holds 0 to 8 units, `World.pour` sets one (the mask's
bit follows, a solid cell holds none), a save writes the four amount
words after its six and loads a six-word column full wherever it is wet.
A cell holding less than eight units is water only under its plane at
y + amount / 8, and the ray's DDA clips its wet segment to that plane
(`Render.dda`, `Column.lo` and `hi`): a descending ray's entry moves down
to the plane, a ray over the water passes, a ray under it meets the side
face whole, and the reflection, the ripples, Fresnel, the mirror and the
caustic happen on the plane. A full cell's plane is its top face, so the
picture of a still lake is the same bit for bit; and the loop is
specialized on bit 29 of the camera's base, set by `Player.view_w` when
the world counts a partial cell in the window (`World.partials`), so a
frame without one costs what it did, while a frame with one pays about
a sixth more at 1470×796 (34 → 41 ms on the lake, `make profile`'s last
view). `make water` renders a stair of amounts 1 to 7 in the lake's top
row (`build/water-levels.png`); `make flow` renders the flow itself.

The flow is the second step (`src/flow.bend`): a tick every 256 ms of the
day's clock steps the cells the world has marked. A cell holding a > 0
units first gives the cell below what fits, min(a, 8 - b), then each of
its four sides that holds less takes floor((a - n) / 2) of what is left,
in an order that reverses on odd ticks; every transfer is two `World.pour`
at once, so the volume is kept by construction and no cell leaves 0..8
(thirteen laws, and the tests sum a basin over ticks). A neighbour
outside the window is solid, so a lake that reaches the edge holds. The
marks: an edit marks its cell, the one above and the four sides; a move
marks the cell that lost water, the one above it and its sides, and the
one that gained; a marked column's slot is queued once, oldest first,
and a tick steps at most 256 columns (`Flow.budget`), the rest waiting
their turn, so a tick costs under a millisecond on the host whatever the
lake (`make flow-bench`: a lake draining through shafts, 0.3 to 1 ms a
tick at 100 to 190 columns queued). A cell that moved nothing drops out.
A column back in the window from the edits is stepped once where it is
wet, its sides whole. After a stall the flow catches up at two ticks a
frame. What the rule leaves: a difference of one unit between neighbours
does not move, so a surface at rest may slope one unit a cell toward
where it drained (the lake breached in `make flow` stops at `8 8 7 6 5 4
3 2 1 0` along its top row, 424 ticks on, the pit under it a film); a
unit is an eighth of a block, so the slope shows. Distance and height fog use the full solid-hit
path, including air after leaving the lake, so entering water never resets
visibility to zero. Fog colours the background before the water tints it:
a distant block hidden by fog must match the sky seen through the same
wet path. Foreground air haze attenuates that tint to keep distant lakes
hidden. A separate water-fog flag fades to the water colour by
24 wet blocks, before the 60-step ray limit. Foreground air fog also fades
that colour, keeping distant lakes hidden. Sky rays keep their celestial
discs through short wet paths and converge to the same water colour on
long ones.
This works from below and through vertical sides as well as from above.
Top surfaces also reflect the analytic sky, including its sun, stars and
moon. Fresnel raises reflectance from about 2% head-on toward a mirror at
grazing angles, by a cube where Schlick has a fifth power, so the mirror
shows at the angles a player sees a lake from (14% at 30 degrees, not 5);
disabling it keeps the 2% value. Reflection and Fresnel have
separate flags. The DDA marks the first downward entry through a water top
in a spare bit of its step counter, so vertical sides and submerged eyes
retain absorption alone, even for edited water away from the sea height.
The reflected sky is fogged to the surface, before any water depth, and
fully hidden lakes return the exact atmospheric colour. Ripples tilt the
surface normal with smooth value noise moved by the game clock. The noise
uses world lattice addresses, so loading columns never drags the pattern.
Its analytic gradient takes four hashes and no extra world loads; the
normal fades with distance, to limit shimmer, and in the last degrees
before the horizon; a mirrored ray that a steep ripple would send under
the water is lifted back over it and made a unit again, so the tilt stays
strong where reflections are strongest. Its 8192-ms loop divides the day,
with no jump when the saved day clock wraps. Flag 20 disables ripples.

The world is in that mirror too, by a second ray: a pixel that shows a
water top walks the ring again from where it met the water, along the
mirrored (and rippled) direction, as the shadow walks towards the sun. It
is a dry DDA of 32 steps over the solid bits alone; what it meets gets the
block's colour, its texture and its face's tone, with no occlusion and no
shadow of its own, is fogged by the whole path (eye to water to block) and
laid over the mirrored sky before Fresnel weighs the two. A step crosses
one face, so a ray of direction d always meets what lies within
28 / (|dx| + |dy| + |dz|) blocks, 16 to 28 of them; over the last quarter
of that reach the mirror fades into the sky, and nothing pops in where
the walk ends. A ray that meets nothing leaves the mirrored sky's byte as
it was. The look has a bit of its own, bit 27 of the camera's base word
(the flags word is full).

Seen from above, where the mirror is 2% of the colour, the water shows its
bed, and the bed shows a caustic: the light that came down through the
rippled surface, gathered into bright threads here and taken from there.
The real one follows the surface's curvature down to the bed; this one is
false: the ripples' own value noise read at the bed's point, at twice and
three times the ripples' scale and moving with their clock, the product of
the two ridges squared so the threads are thin, brightening the bed on the
threads and darkening it a little between them, with a mean near zero so
a shallow bed keeps its brightness. It is strongest just under the surface
and gone six blocks down, as the light is, in daylight alone, and fades
out where the eye looks along the surface. The scales are whole numbers
and the lattice is scaled with them, so a ring shift cannot drag the
pattern (a test walks the ring one column each way). No walk and no world
read: four hashes an octave, on the pixels of a wet hit alone. Bit 28 of
the base word; `make water` renders it on and off from above the lake. This is a function of the ray, which a ray
caster gets for the price of a walk; a screen-space reflection would be a
function of the image, which a pixel of the fork tree cannot read.
Placing an inventory block displaces water, and edits survive ring reloads
and saves. Water cannot be collected with the eight solid-block slots.
A lake lies west of the initial spawn; `make water` exports daytime,
dusk, submerged, reflected sun/moon, the caustic from above, a diver at
the deepest bed, a stair of amounts and each surface-look-off view as
sixteen PNGs. It also exports `build/water-motion.gif`, a 128-frame ripple cycle
with camera and sun fixed, and a contact sheet (requires Pillow).
This is still water: digging leaves a gap until flow is implemented, and
movement remains walking/gravity, with swimming left for a later step. Generated trees require dry grass at their origin;
their canopies can extend over water from the bank. Untouched columns
regenerate with this rule; edited columns in old saves keep their contents,
including any previously saved submerged wood or grass.

**The day clock** is an integer in `Game`, advanced by elapsed milliseconds
at the window loop, independently of the physics and frame rate. One day is
1048576 ms (17 minutes 28.576 seconds); phase zero is dawn, one quarter noon,
one half dusk and three quarters midnight. Its sine and cosine are computed
on the host and the three sun components ride in `Cam`. The shadow walks
with signed steps on all three axes; the terrain dims when the sun sets.
The default starts in the morning. A world-direction sky gradient follows
the sun's height, with a warm glow toward dawn and dusk, a sun disc, fixed
stars fading in at night and a moon opposite the sun. Fog takes the gradient
and glow's colour, without celestial discs; its distance term reaches the
sky at 34 blocks, before the 60-step ray budget ends even on a diagonal.
A separate height term thickens in the low ground.

**Collecting and building** use eight natural counts in `Game`. A successful
break reads the cell's actual type and credits that slot; a successful
placement debits the selected slot. Empty spending, occupied cells and
placement anywhere through the player's height are rejected without
changing either side. A break and place in the same tick run in that order,
so the new item may fund one placement. Their shared transfer rule is
proved to conserve the cell plus its inventory count, for every count and
every list of actions. The ring/Map integration is checked by windowless
tests, including repeated breaks and both actions together.

The counts stay on the host. The HUD gets four seven-bit numbers above the
selection in `Cam.sel`, plus four in one extra scalar, `Cam.items`; each is
capped at 100, meaning `99+`. The full inventory is never shared down the
render fork. Labels belong to HUD flag 16 and its existing profile row.

**The world is saved.** `bendcraft.save` in the working directory holds
the corner, position, look, chosen block, day clock and eight counts on its
first line, then one line per edited column: its key, five solid words and
the water mask. The game
loads it at start, if it is there, and writes it on `P` and on quit; the
untouched columns are never stored, they come back from the noise. On the
page the file lives in the browser's memory, so it lasts until the tab is
closed. Old headers without the optional clock still load at morning;
headers without counts start with an empty inventory. Column lines append the water mask. Old five-word columns restore
natural water above the original terrain, excluding their saved solids;
old excavations stay dry, and an explicit zero water word stays zero. Both `P` and `Esc` save after that tick's edits.

**The player** is 1.8 blocks tall with the eye at 1.6. Walking tests the
feet and the head per axis and stops at walls; gravity pulls, landing snaps
the feet onto the block, space pushes off it. A block is never placed on
the player. The hotbar along the bottom shows the eight block types and
frames the chosen one, with the available count below each swatch.

## Layout

```
main.bend          the window loop, elapsed time, the view, the tick
src/day.bend       integer day phase and the sun direction
src/inventory.bend natural counts, conserved cell/item transfers, packed HUD counts
src/sky.bend       sky gradient, sun, glow, stars, moon and distance/height fog
src/water.bend     wet intervals, tint, fog, Fresnel, reflected sky, ripple normals, the mirror, the caustic
src/util.bend      conversions, bit tests, smoothstep
src/world.bend     noise, terrain, the ring, the map, loads, shifts, edits, solid
src/render.bend    the DDA, the sun, the texture, the occlusion, the mirror's walk, the fork
src/player.bend    Game, events, picking, the tick
src/save.bend      the save file, and the tick that writes it
LAWS.bend          the rules the checker proves; PROOF.bend closes them
AGENTS.md          for an agent (or a person) about to write Bend here: the gate, the rules
ROADMAP.md         the vision and what comes next: the look, the game, the laws, what waits on Bend
test/physics.bend  the game without a window: events through feed and step
test/save.bend     place, walk, save, load: the brick and the position come back
test/inventory.bend transfers, rejected edits, simultaneous input, counts, saves and HUD packing
test/day.bend      signed shadows, sky/fog, clock wrapping, frame rate, old and new saves
test/water.bend    signed wet rays, emerged silhouettes, underwater fog, edits and saves
test/ripples.bend  clock/address packing, stable world noise, normals and wrap continuity
test/water_view.bend sixteen water views and a fixed-sun ripple cycle for test/water.py
test/mirror.bend   the mirror's walk over a placed brick, its reach and fade, the byte a miss keeps
test/mirror_view.bend four views with the world in the mirror and without, for test/mirror.py
test/sky.bend      six fixed sky views, saved as Image trees for test/sky.py
test/bench.bend    five frames on the GPU with checksums, untouched and built
test/profile.bend  what costs what: each look off in turn, the rays' hits and steps
test/trace.py      the frame's dispatch kernel by kernel, from the emitted C
test/terrain.bend  noise rows, lake floor materials, dry roots, canopies and saved columns
test/readout.bend  the readout's corner of a frame, printed a character a pixel
test/page.mjs      the page in headless Chrome: drag, click, place, jump
test/fps.mjs       the page's fps on N threads
site/              the page: notes.mjs post-processes the built index.html
```

```sh
make check      # the modules, the tests, the laws
make test       # physics, save and load, terrain, windowless
make bench      # five frames on Metal, untouched and with 300 blocks placed
make profile    # each look off, by size; also night, lake, submerged, night lake, partial water
make sky        # six PNGs and build/sky-contact.png; Python with Pillow
make water      # sixteen PNGs and a ripple animation; Python with Pillow
make flow       # the lake breached into a pit, filling and settled; Pillow
make flow-bench # a lake draining through shafts: ms a tick on the host
make mirror     # build/mirror-sheet.png: four views, mirror on and off; Pillow
make page-test  # the page in headless Chrome, hashes and fps
```

## Numbers

Apple M5, Bend 2.0.25 (the same thirty checksums and the same times as
2.0.24, four alternated rounds: 24 and 25 ms at 1470×796, 46 and 47 at
1920×1080, the small sizes equal; the kernel trace still reads the
runtime's text: grow1 0.5 ms, grow128 1.7, work 23.5, pack 0.3 at
1470×796). The historical tree comparison below predates the
day cycle; the current measurements follow it. The bench times
the `!` only, five frames with the camera turning; the thirty checksums are the same on every build that
changes nothing visible. The first column is the binary tree, the second
the four-way tree it replaced.

| | binary tree | four-way tree |
|---|---|---|
| Metal, 512×512 | 3 ms a frame | 7 ms |
| Metal, 512×512, 300 blocks placed | 3 ms | 7 ms |
| Metal, 735×398 rays, a 14" MacBook at scale 2 | 5 ms | 18–29 ms |
| Metal, 960×540 rays, a 1920×1080 window at scale 2 | 9–10 ms | 14–17 ms |
| Metal, 1470×796 rays, a 14" MacBook at every pixel | 16 ms | 46 ms |
| Metal, 1920×1080 rays | 28–31 ms | 50 ms |
| WebAssembly, 512×512, 10 threads | 31 fps | 37 fps |
| WebAssembly, 512×512, 1 thread | 7 fps | 7 fps |
| WebAssembly, 512×288 rays in a 1024×576 canvas, 10 threads | 54 fps | 54–56 fps |

After sky and day cycle, four alternated rounds against the original build:

| fastest bench frame | before | after |
|---|---|---|
| 512×512 | 2 ms | 2 ms |
| 512×512, 300 blocks placed | 2 ms | 2 ms |
| 735×398 | 4 ms | 4 ms |
| 960×540 | 8 ms | 9 ms |
| 1470×796 | 15 ms | 16 ms |
| 1920×1080 | 28 ms | 30 ms |

The extra work is the signed shadow, sky colour and height/distance fog;
the larger frames pay for that arithmetic at more pixels. The rays-alone
profile remains 11.0 ms at 1470×796. Web numbers have not been remeasured.

After collecting and inventory, four alternated rounds against the sky build:

| fastest bench frame | before inventory | with inventory |
|---|---|---|
| 512×512 | 2 ms | 2 ms |
| 512×512, 300 blocks placed | 2 ms | 2 ms |
| 735×398 | 4 ms | 4 ms |
| 960×540 | 8 ms | 8 ms |
| 1470×796 | 15 ms | 16 ms |
| 1920×1080 | 29 ms | 29 ms |

The 15 ms frame occurred once in twenty baseline samples; the rest were
16–18 ms, and the new build ranged from 16–20. To investigate that one-ms
floor change, four further alternated rounds used `test/trace.py`: the work
kernel's minimum was 14.570 → 14.526 ms, with the fastest traced dispatch
summing to 16.625 → 16.266 ms. Tracing submits kernels separately, so its
absolute times are diagnostic, not the normal bench. It found no repeatable
kernel slowdown; the isolated minimum and the profile's few-tenths changes
fit the run variation and the ordinary timer's one-ms resolution.

On the page, `?size=1024x576x2` in the address gives the wide frame, and
the fullscreen link scales whatever is rendered to the screen.

## What costs what

`make profile` renders one view five times with every look on, then with
each look off in turn (the camera's `fl` flags: shadow, occlusion, texture,
distance fog, HUD, day cycle, gradient, sun, glow, stars, moon, height fog,
water, water fog, Fresnel, sky reflection, ripples; and the world in the
mirror and the caustic, bits 27 and 28 of the base word),
then the rays alone, and prints the `!` per frame; then it
renders the view twice more with numbers for pixels, how many rays reach
a block and how many DDA steps a ray walks to its hit, summed over the
image with each pixel weighed by the square it stands for. The same
view as the bench is used for the full render (the profile sums by pixel
area; the bench sums the tree's leaves). At 1470×796:

Four alternated pre-inventory/current rounds, minimum five-frame mean per
variant (the timer resolves milliseconds):

| | before inventory | with inventory, ms a frame |
|---|---|---|
| all on | 16.0 | 16.2 |
| shadow off | 13.4 | 13.2 |
| occlusion off | 15.0 | 14.6 |
| texture off | 15.6 | 15.8 |
| distance fog off | 15.6 | 16.0 |
| HUD off | 15.8 | 16.2 |
| day cycle off | 15.8 | 15.8 |
| sky gradient off | 15.6 | 16.0 |
| sun disc off | 16.0 | 15.6 |
| horizon glow off | 15.6 | 15.8 |
| stars off | 16.0 | 16.0 |
| moon off | 16.0 | 16.2 |
| height fog off | 16.2 | 16.0 |
| rays alone | 11.4 | 11.0 |

The full profile's four means ranged from 16.0–16.6 before and 16.2–16.4
after; HUD-off ranged from 15.8–16.2 and 16.2–17.2. These overlapping
ranges and the kernel trace above matter more than a few tenths in an
off variant. The camera carries one extra word; digit decoding runs only
inside the eight slots, and HUD off skips it entirely.

Stars and moon are skipped in this morning view. The profile also looks
up at midnight, at 1470×796: all on 11.6 → 11.8 ms, stars off 11.6 →
11.6, moon off 11.6 → 11.8, rays alone 10.6 → 10.6. The moon is visible
in that view. The gradient and fog take no extra ray; the sun and moon
are angular discs and the stars are a fixed hash of direction.

Preparing room for water moves four FPS bits to the spare high bits of
`Cam.items`, keeping the same 14-word camera, pixels and physics. Four
alternated rounds at 1470×796, minimum five-frame mean:

| | before packing | after packing, ms |
|---|---|---|
| all on | 16.2 | 16.0 |
| shadow off | 13.4 | 13.2 |
| occlusion off | 14.8 | 14.8 |
| texture off | 15.6 | 15.6 |
| distance fog off | 15.8 | 15.6 |
| HUD off | 16.0 | 15.8 |
| day cycle off | 16.0 | 15.8 |
| sky gradient off | 15.2 | 15.8 |
| sun disc off | 16.0 | 15.6 |
| horizon glow off | 15.6 | 15.8 |
| stars off | 16.2 | 15.8 |
| moon off | 16.2 | 15.6 |
| height fog off | 15.6 | 16.0 |
| rays alone | 11.0 | 11.0 |

The larger off-row differences follow overlapping run ranges: gradient
15.2–16.6 → 15.8–16.4, height fog 15.6–16.6 → 16.0–17.2. Their rendering
code is unchanged; the readout is disabled in these views. Fastest bench
frames at the six sizes are 2/2/4/9/16/29 → 2/2/4/8/15/29 ms. The readout
test checks every FPS value through 256, including clamping and all four
inventory counts sharing its word.

Still-water delivery, four alternated pre-water/current rounds at 1470×796.
These compare the same default view; the bench picture changes intentionally.
Minimum five-frame means:

| | before water | with water, ms |
|---|---|---|
| all on | 15.8 | 20.0 |
| shadow off | 13.0 | 17.2 |
| occlusion off | 15.0 | 18.8 |
| texture off | 15.6 | 19.4 |
| distance fog off | 16.2 | 19.8 |
| HUD off | 15.8 | 19.8 |
| day cycle off | 16.0 | 20.4 |
| sky gradient off | 15.8 | 19.8 |
| sun disc off | 15.8 | 19.6 |
| horizon glow off | 15.4 | 20.6 |
| stars off | 16.2 | 20.0 |
| moon off | 16.0 | 20.2 |
| height fog off | 16.0 | 20.2 |
| water off | — | 17.4 |
| rays alone | 11.0 | 12.0 |

The cost is real: one extra mask read at each crossed column and wet
interval arithmetic during the 60-step walk. The emitted dry specialization
skips those operations but still carries three extra scalar words through
the loop (water mask, entry, depth), returns two extra words and checks for
a wet hit before shading. Water-off therefore includes some shared cost;
subtracting that row alone understates the feature's total cost.

Fresh emitted C and four alternated kernel traces locate the increase in
ray work: work-kernel minima 14.525 ms before, 15.000 with water off, 17.445
with water on. Fastest traced dispatch sums are 16.318 / 17.146 / 19.521 ms.
Camera width and fork shape are unchanged. Tracing submits kernels
separately, so those totals diagnose the increase rather than replace the
ordinary bench times. The dry build retains all thirty original checksums.

Fastest ordinary bench frames at the six sizes are
2/2/4/8/16/29 → 2/2/5/10/19/36 ms. At 735×398, the native scale-2 case,
the fastest frame is 5 ms. A separate lake view at 1470×796 measures 20.8
ms all on, 17.6 water off, 12.0 rays alone. Night measures 14.6 / 13.2 /
11.4 for those same variants. Solid hits and steps in the default view
remain 52% and 41.3, because water does not stop the ray.

Underwater fog correction, four fresh alternated before/after rounds at
1470×796. An open game may have affected the earlier measurement session;
that series is excluded here. Process checks throughout the timed runs
found no running Bendcraft instance. Minimum five-frame means:

| | before fog correction | after, ms |
|---|---|---|
| all on | 21.0 | 21.4 |
| shadow off | 18.0 | 18.0 |
| occlusion off | 20.0 | 20.6 |
| texture off | 20.0 | 20.2 |
| distance fog off | 21.2 | 21.8 |
| HUD off | 21.0 | 21.4 |
| day cycle off | 22.0 | 21.6 |
| sky gradient off | 20.6 | 21.2 |
| sun disc off | 20.2 | 21.2 |
| horizon glow off | 20.4 | 21.4 |
| stars off | 21.2 | 21.4 |
| moon off | 21.8 | 22.0 |
| height fog off | 21.4 | 21.6 |
| water off | 17.8 | 18.0 |
| water fog off | — | 21.2 |
| rays alone | 12.6 | 12.4 |

The new work is a second distance/height fog evaluation for the full
solid-hit path, plus density and two colour mixes for water extinction.
It runs only on wet rays; disabling water fog skips the extinction work
but retains the corrected air fog. The DDA, camera width and fork shape
are unchanged. The all-on means span 21.0–23.0 before and 21.4–22.4 after.
The larger off-row deltas also overlap: sun disc 20.2–22.6 → 21.2–25.8,
horizon glow 20.4–23.0 → 21.4–23.2. Water-off skips the changed shading
and spans 17.8–19.4 → 18.0–19.4; a 0.2 ms minimum difference does not
establish a slowdown on that path. Closing the game removes one source
of contention, not all timing noise.

The submerged view now has its own profile at 1470×796: all on
20.6 → 21.2 ms, water fog off 21.2, rays alone 12.2 → 12.0. Its water-off
means span 17.4–22.8 → 18.4–19.6. The lake view is 22.0 → 22.0 ms,
water fog off 21.8; night is 14.8 → 14.4. Night's unchanged rays-only
path spans 11.4–13.0 → 11.8–12.2. Fastest ordinary bench frames at the
six sizes are 3/3/6/10/19/36 → 2/3/6/10/20/37 ms. The extra wet-ray
shading is paid for; the overlapping ranges limit how precisely these
runs can separate that cost from noise.

Four alternated traces from freshly emitted C locate the increase in the
work kernel: 17.430 → 19.290 ms minimum at 1470×796. Grow and pack remain
within 0.051 ms; the fastest traced dispatch sums are 19.425 → 21.080 ms.
These separately submitted kernels diagnose the added pixel arithmetic;
their totals do not replace the ordinary bench or profile numbers.

Dry tree roots, four alternated before/after rounds at 1470×796, with no
running Bendcraft process detected. Minimum five-frame means:

| | before dry roots | after, ms |
|---|---|---|
| all on | 20.8 | 20.4 |
| shadow off | 17.2 | 17.4 |
| occlusion off | 19.2 | 18.8 |
| texture off | 20.0 | 19.4 |
| distance fog off | 20.4 | 20.8 |
| HUD off | 20.8 | 20.2 |
| day cycle off | 20.6 | 20.4 |
| sky gradient off | 20.6 | 20.6 |
| sun disc off | 20.6 | 20.8 |
| horizon glow off | 20.4 | 20.4 |
| stars off | 20.6 | 20.6 |
| moon off | 20.6 | 20.6 |
| height fog off | 20.4 | 20.2 |
| water off | 17.2 | 17.6 |
| water fog off | 20.6 | 20.2 |
| rays alone | 12.2 | 12.0 |

Only host generation changes: 202 → 173 trees in the initial window.
The renderer, camera and flags are unchanged, but the rays see a different
scene. Default solid hits fall 52% → 49%, and steps to a hit or sky rise
41.3 → 41.4. Underwater, removing trunks exposes longer paths: hits
63% → 59%, steps 31.1 → 35.5. All-on means span 20.8–21.0 → 20.4–21.4;
the default rows with increased minima overlap their earlier ranges:
shadow off 17.2–18.0 → 17.4–18.2, distance fog off 20.4–21.0 → 20.8–22.0,
sun disc off 20.6–21.0 → 20.8–21.2, water off 17.2–18.0 → 17.6–17.6.
These small deltas do not establish a rendering slowdown.

The lake all-on minimum stays 21.4 ms and the submerged view stays 20.6;
night moves 14.4 → 14.2. Submerged occlusion-off and sun-disc-off minima
each rise 1.2 ms; their ranges are 18.4–19.8 → 19.6–20.4 and
20.0–21.2 → 21.2–22.0. The changed ray paths and overlapping ranges limit
how precisely the timing deltas can be attributed to generation.
Fastest bench frames remain 3/2/6/10/19/36 ms at the six sizes.
The generated-column regression fails on the old generator and passes
on the new one; dry shoreline trees and saved edited columns remain.

Lake floors and underwater silhouettes, four alternated before/after
rounds at 1470×796, after the open game was closed. Process checks guarded
every timed run. Minimum five-frame means:

| | before correction | after, ms |
|---|---|---|
| all on | 21.2 | 21.6 |
| shadow off | 18.4 | 17.8 |
| occlusion off | 19.8 | 20.0 |
| texture off | 20.2 | 20.2 |
| distance fog off | 21.0 | 21.6 |
| HUD off | 20.8 | 21.6 |
| day cycle off | 21.2 | 21.4 |
| sky gradient off | 21.0 | 20.8 |
| sun disc off | 21.2 | 21.0 |
| horizon glow off | 20.6 | 20.6 |
| stars off | 21.4 | 21.4 |
| moon off | 20.8 | 21.0 |
| height fog off | 21.2 | 21.4 |
| water off | 18.0 | 18.2 |
| water fog off | 21.2 | 21.2 |
| rays alone | 12.6 | 12.8 |

The earlier fog correction still tinted sky misses differently from
fully fogged solids, leaving bright silhouettes after a ray exited water.
Its side-exit test expected the unfiltered atmospheric colour and missed
that mismatch. The new regression compares a far wall with the same ray
missing into the sky, while checking that a nearby wall remains visible;
it covers day, twilight, night, surface and side exits, and fog flags.
Both that test and the packed lake-floor check fail on the previous build.

The fix reorders two existing colour mixes and attenuates wet tint by
foreground air haze, adding one subtraction and multiplication on wet
rays. The dirt rule runs during world generation. Geometry, DDA, camera
and flags stay the same; default hits and steps remain 49% and 41.4.
The all-on means span 21.2–24.4 → 21.6–23.0 ms. Increased off-row minima
also overlap: distance fog 21.0–25.0 → 21.6–23.4, HUD 20.8–30.0 →
21.6–22.2, water off 18.0–20.6 → 18.2–18.8, rays alone 12.6–13.2 →
12.8–13.8. Night spans 14.8–15.8 → 15.4–17.8; its upward rays never
cross water. These runs cannot isolate a few tenths from the timing noise.

Four additional alternated traces from freshly emitted C investigate the
0.4 ms increase in the default profile minimum: work-kernel minima are
18.287 → 18.308 ms, grow/pack minima differ by at most 0.038 ms, and the
fastest traced dispatch sums are 20.571 → 20.442 ms. They do not establish
a repeatable slowdown of that size. Separate kernel submission makes
tracing diagnostic; the normal bench minima are
3/3/6/10/20/38 → 3/3/6/10/19/38 ms. Lake all-on moves 22.2 → 21.4 ms,
submerged 21.6 → 21.4. The six water views were rendered and inspected.

Fresnel and reflected sky, four alternated before/after rounds at 1470×796,
with no game process running. Minimum five-frame means:

| | before reflection | after, ms |
|---|---|---|
| all on | 20.6 | 21.8 |
| shadow off | 17.6 | 18.8 |
| occlusion off | 19.8 | 20.4 |
| texture off | 20.0 | 21.2 |
| distance fog off | 20.6 | 21.8 |
| HUD off | 20.8 | 21.2 |
| day cycle off | 20.6 | 21.4 |
| sky gradient off | 20.0 | 21.0 |
| sun disc off | 20.6 | 21.4 |
| horizon glow off | 20.2 | 21.6 |
| stars off | 20.8 | 22.0 |
| moon off | 20.8 | 21.8 |
| height fog off | 20.8 | 21.2 |
| water off | 17.6 | 17.4 |
| water fog off | 20.0 | 21.6 |
| Fresnel off | — | 22.0 |
| sky reflection off | — | 20.6 |
| rays alone | 12.0 | 12.4 |

The surface look costs 1.2 ms in the default view and 1.6 ms in the lake
view (21.8 → 23.4, reflection off 21.8, Fresnel off 22.6). This includes
marking the first water-top crossing in the existing 60-step walk, then
evaluating the sky in the reflected direction and mixing its colour.
The shared crossing marker is still computed with sky reflection off;
the off row measures the surface shading, not all of that bookkeeping.
Neither the 14-word camera nor the ray's two-word wet trace grows, and
no second world ray is cast. Hits and steps stay 49% and 41.4 by default,
77% and 31.3 at the lake.

The all-on ranges are 20.6–21.6 → 21.8–23.0 ms; Fresnel off spans
22.0–23.0, so its 0.2 ms increase over all-on is within the overlapping
timing noise. Water off is 17.6–18.4 → 17.4–18.0. The submerged image is
byte-identical to the previous build and its full profile is 21.6 → 21.4;
the lake image with reflection off is also identical. Disabling both new
flags reproduces all thirty previous bench checksums.

The rays-alone profile minimum initially rose 0.4 ms, with disjoint
five-frame ranges (12.0–12.2 → 12.4–13.4), so it was investigated before
accepting the change. Four alternated traces from fresh C, using the exact
profile cameras, give rays-alone work minima 10.496 → 10.593 ms and
fastest dispatch sums 11.992 → 12.057. Individual work frames span
10.496–12.299 → 10.593–12.252. Four turning-camera bench traces agree:
work 10.455 → 10.520, dispatch 11.956 → 12.009, identical checksums.
They do not reproduce a 0.4 ms slowdown; smaller differences remain within
the run-to-run spread. Tracing submits kernels separately and diagnoses
the increase; it does not replace the normal profile table.

The fixed-camera full work kernel does increase, 17.737 → 18.640 ms,
with reflection off at 18.250. The shared top-crossing tests still run
throughout the water-enabled DDA, even with reflection off; the remaining
surface work evaluates the reflected sky, Fresnel and colour blends.
Water-off traced dispatch minima are 17.436 → 17.204 ms. This supports
attributing the consistent increase to the added water work, without
claiming that individual off-row differences isolate each operation.

The upward night view is 14.8 → 15.2 ms (ranges 14.8–15.8 → 15.2–15.4),
with reflection off 14.8 and rays alone unchanged at 11.4. A new night-lake
view includes the reflected moon: all on 20.6, reflection off 18.2,
Fresnel off 20.2, stars off 19.4 and moon off 20.0. Those bodies are active
here; the daytime off rows cannot measure them. The ten water views were
rendered and inspected. Normal bench minima at the six sizes are
2/3/6/10/21/36 → 3/3/6/11/21/38 ms.

`Cam.fl` bits 0..4 are shadow, occlusion, texture, distance fog and HUD;
5 and 6 are debug renders; 7..16 hold milliseconds and 17..19 the low
three FPS bits. FPS bit 3 uses `Cam.base` bit 31; the high four use
`Cam.items` bits 28..31, above the counts. Bit 20 enables ripples;
bit 21 enables water, bit 22 water fog, bit 23 Fresnel and bit 24
sky reflection. Bits 25..31 are day
cycle, sky gradient, sun disc, horizon glow, stars, moon and height fog.
`Render.looks()` enables them all. Day cycle off uses the original fixed
sun for profiling. HUD off also disables the new count labels. The default
picture intentionally changes with stronger ripples kept over the horizon:
bench digest `0b9d000fe324fdac57d1dcc98658ec91`; physics stays
`73516c0ead87f8c1151e34d25b3ac32e`.

Ripples, three alternated before/after rounds at 1470×796 with no game
process running. Minimum five-frame means, default view:

| | before ripples | after, ms |
|---|---|---|
| all on | 22.2 | 22.6 |
| shadow off | 18.2 | 19.0 |
| water off | 17.8 | 17.6 |
| sky reflection off | 21.2 | 21.2 |
| ripples off | — | 22.0 |
| rays alone | 12.2 | 12.4 |

The tilted normal costs about 0.4 ms in the default view and 0.2 at the
lake (23.4 → 23.6, ripples off 22.8); the night view is unchanged (15.2 →
15.4). It is four hashes and a square root on the pixels that show a
water top, and no world read. The bench agrees: 21 → 22 ms at 1470×796,
38 → 39 at 1920×1080, the smaller sizes the same. Water as a whole is now
the dearest look, about 5 ms of the 22.6, ahead of the shadow ray's 3.6:
the wet intervals are tracked along every ray's 60 steps. The Codex session
that wrote the ripples ended before these rounds; they were run afterwards
on the same tree.

The first ripples were too soft to see: on against off, three lake views
differed by 3 levels of 255 at most. The tilt was 0.04 and faded out below
14 degrees of elevation, where the reflection is strongest, because a
stronger one sent mirrored rays under the horizon and failed its test. The
tilt is now 0.15, fades only in the last 4 degrees, and the mirrored ray
is lifted over the horizon: 15 levels, about 2% of the pixels, the same
eight ripple tests, and the same frame (21 ms at 1470×796 and 39 at
1920×1080 before and after, four alternated rounds).

The world in the mirror is the first look whose price is a walk of its
own since the shadow. Against the commit before it, at 1470×796, three
alternated rounds of the whole profile and four of a short one:

| | before, ms | with the mirror | mirror off (bit 27) |
|---|---|---|---|
| the bench's view | 21.8 | 25.2 | 23.0 |
| lake, looking west | 24.4 | 31.2 | 24.0 |
| night lake | 21.0 | 27.6 | 21.4 |
| submerged | 21.8 | 22.0 | 21.6 |
| lake at 735×398 (scale 2) | — | 8.4 | 6.8 |

With the look off the frame is the old one, in time and bit for bit (four
views compared with the commit before); the `Water.Mirror` record that
every pixel now carries costs nothing. With it on, the bench's checksums
did not move either, because no mirrored ray meets a block in its views,
and yet its frames got slower (21 → 24 ms at 1470×796, 39 → 46 at
1920×1080): the walk is paid by every pixel of a water top, whether it
meets a block or the sky, and the frame is its slowest lane. The walk's
length says what a step costs: 32, 24 and 16 steps gave the lake 30.6,
29.4 and 28.0 ms, so 0.16 ms a step at this size, the same as the shadow's
24 steps for 3.6 ms and the primary ray's 60 for about 10, plus 1.6 ms for
the mirrored direction, the hit's colour and its fog. Sixteen steps would
save 2.6 ms and cut the reach to 8 blocks; the 32 stay, and the fade at
the end of the reach costs nothing measurable. Water as a whole is now
about 13 ms of a lake's 31 at full size, and 1.6 of 8.4 at scale 2.

The dense water, the deeper colour and the cubed Fresnel are arithmetic
on a pixel and cost nothing measurable (lake 31.0 and 31.0 ms, 8.4 and 8.2
at scale 2); with them the mirror moves up to 53 levels on 10% of the
bank view's pixels, where it moved 37 on 7%. Measuring it taught the
routine something: on a busy machine the build that runs second in a pair
reads 2 to 3 ms slower, whichever it is, so alternated rounds also swap
their order.

The caustic is arithmetic on the pixels of a wet hit, eight hashes and a
few products, and costs what such arithmetic costs on the lake's lanes:
at 1470×796 the lake goes 31.0 → 32.0 ms (caustic off 30.8), the bench's
view 25.2 → 25.6, the lake at scale 2 8.4 → 8.6; four alternated rounds,
order swapped. At night its factor is 1.0 and the sun's height is the
same for every pixel, so the render skips it there with no divergence:
the night lake stays at 28.2, where paying it read 29.2. The light left
at a depth and the colour that darkens with it are two more mixes and
cost nothing measurable (lake 32.4 and 31.8, order swapped).

In the original profile, 52% of the rays reached a block after 24 steps
on average; the rest walked the box's 60. Primary rays took three quarters
of the frame and the shadow ray most of the rest; occlusion and texture
cost under a millisecond each, fog and HUD nothing measurable. Two lessons
came out of the first run. A ray that stopped at its hit walked a third
of the steps and made the frame slower, 15 → 17 ms here and 28 → 32 at
1920×1080, with the same checksums: the lanes of a SIMD group then leave
the loop at different steps, and the runtime's switch over segments runs
them one case at a time, so the loop walks its 60 steps with the state
frozen, on purpose. And a `Bool.pick` is strict, so a look that is off
must be skipped by a `match`, or it is paid for anyway.

`test/trace.py` goes one level down: it patches the emitted C so the
frame's single dispatch runs as four command buffers, one a kernel, and
prints each kernel's time and the tasks left in the lanes' rings
(`bend test/bench.bend -o build/bench.c && python3 test/trace.py
build/bench.c && ./build/bench_trace`). For the 1470×796 frame: grow1
0.4 ms leaving 128 tasks, grow128 2.0 ms leaving 11504 tasks one a ring,
work 10.3 ms, pack 0.5 ms. It reaches into the runtime's text, so a new
Bend may need its snippets updated; it is a diagnostic, not part of the
build.

## The frame's time, in the game

`F` puts a readout in the frame's corner: `16.4 MS  60 FPS`. The first
number is the `!` alone, the render, as the bench times it; the second is
the frames that reached the screen, which the display's rate caps, so a
render of 5 ms still reads 60 or 120. `main.bend` runs the window's loop
itself, in `App.run`'s shape, to read the clock on each side of the view
and not around the wait for the screen; twice a second it publishes the
mean since. The two numbers ride to the GPU in the flags word and spare
bits of the inventory and ring-address words. The camera keeps its 14
words: only 14 low address bits affect the ring's wrapping array reads;
bits 14..26 carry the ripple clock, and bit 31 carries one FPS bit.
The HUD draws the readout with glyphs of 3 × 5 picked by divisions
and masks (no table, no variable shift). With the readout off the frame
is the same bit for bit: the bench's checksums and its times did not move.

## Laws

`LAWS.bend` states what the checker can decide: integer and bit rules on the
values the game uses. The pick word packs and unpacks; a 128×128 window of
the ring spans its 16384 column slots exactly; placing sets one bit,
breaking clears it, breaking air changes nothing; a type's nibble writes
and reads back without touching its neighbours, and the device's read (a
select, since the GPU never shifts by a variable) agrees with the host's;
the terrain's layers are what they should be, a trunk packs as wood with
leaves over it and grass under it, and the packed word the loader writes
reads back the same; no key touches the mouse's bits of the held mask;
the readout's numbers ride above the looks without touching them, read
back, and stop at their room even with high look flags set. The day phase
returns after a whole turn for every `U32` clock value, including overflow,
proved by induction over the low 20 bits. This is the sun's sole integer
input. Its last millisecond advances to dawn. The inventory uses natural
counts: a transfer conserves the cell plus its count, and induction extends that to every list of actions.
Empty spending and occupied placement are rejected, break then place
restores the count, and edits preserve the number of inventory slots.
The HUD packing has mixed-slot and boundary laws; save/quit edges survive
the physics step. Still-water laws cover generation above ground, the sea
limit, banks preserved on water placement, displacement, neighboring bits
and material packing. Water fog has its own flag, enabled by default and
preserved by readout packing. Three tree laws check all 32 column heights:
submerged ground and snow reject roots, dry grass accepts them. Two lake
floor laws cover the submerged dirt heights and their material packing;
dry shoreline grass, low sand and high snow keep their existing laws.
Six surface laws cover independent flags, readout preservation and packing
the top-entry bit with all 61 step counts and four face codes. Float tests
cover Fresnel endpoints and growth, reflected sun/moon, signed entry,
submerged eyes, foreground banks and distant fog.
Eleven ripple laws include the 8192-ms period for every clock word,
boundary packing checks, flag independence, readout preservation and
integer recentering. Windowless tests exhaust all 8192 phase values,
16384 ring addresses and 257 FPS inputs, and check unit normals,
grazing reflection, positive/negative recentering and temporal continuity.
Five mirror laws keep its look in bit 27 of the base word: it reads back,
it is off unless asked for, and the ring address, the ripple clock and
the readout's bit pass through it untouched. Windowless tests walk the
mirror's ray to a placed brick along an axis and across, past its reach,
and to the sky, and check the fade and the byte a miss leaves alone.
Two more keep the caustic's look in bit 28. Eleven amount laws: a column
born of the terrain or a save is full where it is wet, an amount reads
its nibble, water placed is a full cell, a solid placed holds none, and
a pour sets the amount and the bit, clears the bit at zero, caps at
eight and does nothing to a solid. There are 110 laws: eight universal
claims and 102 concrete checks. Integration tests exercise the actual ring edits, all eight types,
both actions in one tick, and save/load through `P` and `Esc`.
The historical physics fixture supplies its one sand placement explicitly;
its output hash stays unchanged, while the inventory tests check an empty
new game.
`bend PROOF.bend` is the gate. The float physics, a player
never inside a block or a jump that lands where it left, is checked by
`test/physics.bend`, whose lines the README of the history records.

## History

Bendcraft began as `gfx/05_craft.bend` in
[metal-bending](https://github.com/AdrielSantana/metal-bending), a notebook
of what Bend costs on Metal. The wall it hit there, an editable world read
through a shared tree, was
[bendlang/bend#885](https://github.com/bendlang/bend/issues/885); Bend
2.0.22 answered it with the array fork, and this repository carries that
file's history from its first commit. Open upstream:
[#920](https://github.com/bendlang/bend/issues/920), a WGSL lane so the page
could run its `!` on WebGPU, and
[#921](https://github.com/bendlang/bend/issues/921), a way to grab the mouse,
[#923](https://github.com/bendlang/bend/issues/923), a way to go full
screen, and [#925](https://github.com/bendlang/bend/issues/925), the shape
of the frame's tree deciding the lanes' load, with a 90-line reproduction.

Written by Claude (Anthropic) with Adriel Santana.
