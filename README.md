# Bendcraft

An endless voxel world you can walk, jump, break and build, written in
[Bend](https://github.com/bendlang/bend) and rendered by one parallel call:
on the GPU through Metal, or on every core of your machine as WebAssembly.

**Play it in the browser:** https://adrielsantana.github.io/bendcraft/

`W A S D` walk · `space` jumps, and swims up in water · the mouse looks, dragged in the browser (or the arrows) ·
click breaks · right click places (or `J` / `L`) · `1`–`8` or the wheel choose the block
to place (grass, dirt, stone, sand, wood, leaves, brick, snow) · `9` the
bucket: a click takes a cell of water, a right click pours one · `0` a
torch in the hand, which lights what is near as you walk · `P`
saves · `F` shows the frame's time · `Esc` quits and saves.

You start with an empty inventory. Break a block to collect its type;
placing spends one of the selected type. The hotbar shows each count
(`99+` above 99), and saves keep the full counts.

![Bendcraft](site/bendcraft.png)

## Build and run

Bend 2.0.34 with a fix that is not released yet,
[bendlang/bend#1132](https://github.com/bendlang/bend/pull/1132) (the lanes
after a grow): a frame takes 2.5 to 2.8 times less than on stock 2.0.34.
The Makefile runs it with `bun` from a checkout beside this one;
`make BEND=bend` builds with the installed Bend.

```sh
git clone -b bendcraft https://github.com/AdrielSantana/bend ../bend
```

On a Mac with Metal:

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
bar off, at scale 2; `make full SCALE=1` is a ray for every pixel, 20 ms a
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
columns around the player live in the low 2^18 words of an `Array<U32>`
of 2^20 (above them, the far map, the clouds' map, the meadow's and the
leaf plane, below): sixteen
words a column, the first a mask whose bit `y` says "there is a block at height
`y`", the next four the types of its 32 solid blocks, four bits each. Word
six is a separate water mask; words seven to fourteen hold the amount of
water in each cell, 0 to 255 units in a byte, the mask's bit set exactly
when the amount is over zero; word fifteen marks the cells the flow steps
next, word sixteen the cells holding less than 255 units; no word remains
spare, so a column's leaf mask lies apart, in the leaf plane. A primary ray with water on reads both masks once per column it
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
the player edited. World column `(x, z)` sits at slot `(x·128 + z)·16`; the
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
total wet distance. A ray that met nothing goes on over the far map
from where it left the window's columns (`Render.window_exit`), a word a
column for 256x256 columns around the window: the column's run
from the floor, its ground, a trunk or the sea over it, and the canopy
over that, and the highest top of the column's 4x4 cell. The second walk
(`Render.run_far`) takes 128 steps at most: a step crosses a cell where
the ray stays over the cell's highest top, a column elsewhere, and it
stops at its hit, at the map's edge, over the world's top and where the
fog is whole. What it meets is shaded by the window's own look, with the
far map in place of the window's columns: its type from the column's
word, the corners' occlusion from the eight cells around it, the shadow
by the far walk towards the sun to where the window's glance reaches.
The sea is no block to it: it adds the ray's path under the sea's plane
to the window's wet trace and walks on to the bed, so the far sea is the
window's water over its bed, one water with the window's across the
seam, its mirror walked over the far map. A block near the window's
side reads past it the same way: its corners' cells there are the map's,
and its shadow and its mirror, once their glance ends past the side, go
on over the far map from the side. Then it is fogged into
the sky: the ground, its trees and its lakes go on to the horizon, block
for block, and a block looks the same on either side of the walks' seam
(test/terrain.bend: all 192 rays from the start's eye within 4 a
channel). A far map of 4x4 cells, each its
highest block, came first and looked wrong: a tree made a pillar of
leaves four wide, and a cell showed four times a block's size where the
window's walk ends. The look is a `match` after the walk:
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
ROADMAP.md): a cell holds 0 to 255 units, `World.pour` sets one (the
mask's bit follows, a solid cell holds none), and a save writes the eight
amount words after its six.
A cell holding less than 255 units is water only under its plane at
y + amount / 255, and the ray's DDA clips its wet segment to that plane
(`Render.dda`, `Column.lo` and `hi`): a descending ray's entry moves down
to the plane, a ray over the water passes, a ray under it meets the side
face whole, and the reflection, the ripples, Fresnel, the mirror and the
caustic happen on the plane. Between two neighbours' planes there is a
step, a unit tall on a lake at rest, and a ray that crosses it enters
the surface, not a wall: a side entry into water from a cell whose
water the ray passed over is a top entry too (the last cell's water bit
rides in the step count, `Render.keep_wet`; without it every cell
boundary of a settled lake drew a dark dashed line, the rays that met
the step in the band between the planes losing their sky). A side entry
from the air stays a wall, the wedge of a stream. A full cell's plane is
its top face, so the
picture of a still lake is the same bit for bit; and the loop is
specialized on bit 29 of the camera's base, set by `Frame.view_w` when
the world counts a partial cell in the window (`World.partials`), so a
frame without one costs what it did, while a frame with one pays about
a sixth more at 1470×796 (34 → 41 ms on the lake, `make profile`'s last
view). `make water` renders a stair of amounts 32 to 224 in the lake's top
row (`build/water-levels.png`); `make flow` renders the flow itself.

The flow is the second step (`src/flow.bend`): a tick every 256 ms of the
day's clock steps the cells the world has marked. A cell holding a > 0
units first gives the cell below what fits, min(a, 255 - b), then each
of its four sides that holds less takes floor((a - n) / 2) of what is
left, in an order that reverses on odd ticks; every transfer is two
`World.pour` at once, so the volume is kept by construction and no cell
leaves 0..255 (ten laws, and the tests sum a basin over ticks). A neighbour
outside the window is solid, so a lake that reaches the edge holds. The
marks: an edit marks its cell, the one above and the four sides; a move
marks the cell that lost water, the one above it and its sides, and the
one that gained; a marked column's slot is queued once, oldest first,
and a tick steps at most 256 columns (`Flow.budget`), the rest waiting
their turn, so a tick costs a few milliseconds on the host whatever the
lake (`make flow-bench`: a lake draining through shafts, 2 to 3 ms a
tick at 500 to 1600 columns queued). A cell that moved nothing drops out.
A column back in the window from the edits is stepped once where it is
wet, its sides whole. After a stall the flow catches up at two ticks a
frame. What the rule leaves: a difference of one unit between neighbours
does not move, so a surface at rest slopes one unit a cell toward where
it drained; a unit is 1/255 of a block, so the slope is nothing to the
eye (the lake breached in `make flow` rests at `193 192 191 … 173` along
its top row, 0.08 of a block over 22 cells; with eighths it stopped at
`8 8 7 6 5 4 3 2 1 0`, a visible terrace, which is why the unit is a
byte). The price of the fine unit is time: the rule halves a difference
a tick, so a lake levels by diffusion, in about as many ticks as the
square of its length; the breached lake takes 1300 ticks, five and a
half minutes of the clock, with 640 columns active the whole way, 2.5
times the budget, and its whole surface a layer of partial cells after,
so the frame pays the plane clip from then on.

The bucket is the third step, in place of the springs built first (a
cell whose type nibble was 9, refilled by the flow at the end of each
step: water from nothing; they went on 2026-09-22, with `World.made`,
their laws and their tests). The ninth slot is a bucket: a click takes
all the water of the cell before the face aimed at into it, a partial
cell for what it holds, and the units add up (the bag's ninth count, a
natural, saved with the others); a right click fills that cell from the
bucket, if the bucket holds what the cell lacks, 255 for air. Water is
only moved, never made: the world, the bucket and what dried sum to the
same, and the tests carry that ledger through the flow. The hotbar's
ninth count is the full cells the bucket holds, the pours it has. The
pick ignores water, so the cell taken is the one before the solid the
crosshair meets, the bed's under a lake: a scoop from the bottom, and
the water above falls into the gap.

The sink: thin water dries. A cell that holds under four units at the
end of its step loses them, and the world counts what went
(`World.gone`). A cell that holds water at the end of its step rests on
a solid or on full water, since the down move took all that fit, so
falling water never dries; and a lake at rest holds ten units a cell and
more, so it is untouched. Without the sink a poured cell's spill spreads
as a film of a unit or two over every flat reach it comes to and stays,
each cell a partial one for the frame; the springs showed it without a
bound (400 ticks on the spawn's hill, before the sink: 18777 units made,
1212 wet cells and growing a cell a tick). A cell of 255 units spread
over a floor dries six at its thin edge and rests at 249.

A solid placed in water is the fourth step's first half: it shoves the
cell's water up its column into the first cells with room, each marked
so the flow takes it from there, and a lake rises by what the block
took (`World.shove`, one recursive walk up the column with the flow's
probe); what finds no room under a ceiling is gone, counted. Placing a
block in the settled pool lifts its ten units onto the block and the
basin keeps them; a stone at the bottom of three full cells sends a
cell of water past them to the fourth. Collecting water, the other half,
is the bucket above. Distance and height fog use the full solid-hit
path, including air after leaving the lake, so entering water never resets
visibility to zero. Fog colours the background before the water tints it:
a distant block hidden by fog must match the sky seen through the same
wet path. Foreground air haze attenuates that tint, and a top the haze hides
whole is the exact sky. A separate water-fog flag fades to the water
colour by 24 wet blocks, before the 60-step ray limit. Sky rays keep their celestial
discs through short wet paths and converge to the same water colour on
long ones.
This works from below and through vertical sides as well as from above.
Top surfaces also reflect the analytic sky, including its sun, stars and
moon, greyed and veiled by the weather as the sky is, and a glimpse of
the clouds (`Clouds.mirrored`, the puddles' too). Fresnel raises reflectance from about 2% head-on toward a mirror at
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
strong where reflections are strongest. Its 8192-ms loop reads the game's
clock in the camera and divides its day and its word, with no jump at
either's wrap. Flag 20 disables ripples.

The world is in that mirror too, by a second ray: a pixel that shows a
water top walks the ring again from where it met the water, along the
mirrored (and rippled) direction. It is the eye's own DDA, dry, for 32
steps (`Render.walk_from`), as the ray of the eye's image under the
water: its distances count from that image, so the meadow's levels, the
fog and a pixel's width read them as the eye's ray's, and the blades it
passes over stand upside down in the lake (`Cam.fl` bit 16), lit as the
eye's are but for the shadows of what stands between them and the sun.
What it meets gets the block's colour, its texture (a grass top the
meadow seen from afar) and its face's tone, with no occlusion and no
shadow of its own, is fogged by the whole path (eye to water to block) and
laid over the mirrored sky before Fresnel weighs the two. A step crosses
one face, so a ray of direction d always meets what lies within
28 / (|dx| + |dy| + |dz|) blocks, 16 to 28 of them; over the last quarter
of that reach the mirror fades into the sky, and nothing pops in where
the walk ends. A ray that meets nothing leaves the mirrored sky's byte as
it was. The look has a bit of its own, bit 27 of the camera's base word
(the flags word is full).

From under the water the surface is Snell's window (`Cam.fl` bit 15). A
ray from a submerged eye that leaves the water up shows the surface where
it leaves (`Render.surfaced`), not what its straight walk met behind it.
Snell's law, 1.33 to 1, bends it into the air through the normal the
ripples and the rain's rings tilt (`Water.bent`), at about half the tilt
the lake shows from above: near the critical angle a small tilt swings a
ray between the window and the mirror, and at the full tilt the rings
over the eye read as rings of glass. Inside the window the bent ray sees
the sky, the clouds and the world, the meadow's blades on the banks, as
the lake's mirror walks them (`Render.behind`), and the rain falling in
it: the whole sky in a cone of
97 degrees, the banks crowding its rim, as a diver sees them. Past 49
degrees from the normal the surface is a mirror, total internal
reflection, and a glance of 24 steps down from it shows the world under
the water, what it meets lit as deep as it lies and fogged by the water
it crossed, the deep water's colour where it meets nothing. Fresnel weighs
the two, a mirror at the window's edge, and the water between the eye and
the surface tints the whole as before. A ray that leaves the water stays
in the window's walk, so no far walk runs for it. In the profile's view under the lake, along its surface at
1470×796, the look makes the frame cheaper, 32.2 → 24.0 ms (the least of
three rounds): a ray that leaves the water walks 24 or 32 steps in place
of the straight hit's shading and the far walk's 128.

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
the base word; `make water` renders it on and off from above the lake. The threads grow
with the water over the bed, whole from nine tenths of a block, so a film
the flow leaves has none and a bank's wall just under the surface little
(`Render.thickness`: the wet path's height for an eye in the air). This is a function of the ray, which a ray
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
one half dusk and three quarters midnight. The clock counts the days too,
for the weather, and its word wraps after 4096 of them, whole turns; the
save keeps it whole, and a save from before the days starts on the first. Its sine and cosine are computed
on the host and the three sun components ride in `Cam`. The shadow walks
with signed steps on all three axes; the terrain dims when the sun sets.
The default starts in the morning. A world-direction sky gradient follows
the sun's height, with a warm glow toward dawn and dusk, a sun disc, fixed
stars fading in at night and a moon opposite the sun. Fog takes the gradient
and glow's colour, without celestial discs; its distance term reaches the
sky at 120 blocks (`Sky.reach`), where the far walk stops; its map ends
128 blocks from the window's centre on an axis. A separate height term thickens in the low ground.

**The light** has a colour (`Cam.fl` bit 17, `Sky.light`): a lit colour
takes a factor a channel, the sun's where the face is in the sun, warm
white overhead and gold as it sets, brighter than the sky's then, and the
sky's in the shade, blue by day, violet at dusk, deeper under the moon; a
face takes between the two as much sun as the shadow and the clouds leave
it. The sun falls on a face as the cosine of its angle to the face's
normal, never under 0.4 of it (`Sky.sunned`), so at sunset the sides
turned to it glow and the tops it grazes take the sky's violet. The
blocks near and far, the meadow's blades and the world in the mirror take
the same light. With the bit off every factor is 1 and the frame is the
one before, byte for byte. Around the sun (bit 18, `Sky.halo`) the
atmosphere takes a tight white glare and a wide warm glow, fading as it
sets; the fog takes its colour from the atmosphere, so what stands against
the sun melts into a bright haze. Once the sun has set the moon lights the
world in its place (with the moon's look, `Cam.fl` bit 30; `Sky.side`),
from opposite the sun, in a silver light: the faces turned to it, its
shadows and the clouds' shade, as the sun's by day. The night's light
rises from 0.18 of the day's to 0.48 (`Sky.level`), the sky takes the full
moon's blue and a wide glow around it (`Sky.moonsky`), which the fog takes
too, and the clouds turn silver where it lights them. With the look off
the night is as it was, lit by nothing.

**The lens** (bit 19, `src/lens.bend`) puts the sun in the camera, and
the moon once the sun has set, a third as bright in a cool white
(`Sky.side`, `Sky.strength`). How much of it the eye sees, 0 to 1, is
found on the host once a frame (`Render.sighted`, into the camera's
`seen`): thirteen rays from the eye, to the body's middle and to two rings
of six points within its disc, each walked as a pixel's ray is, through
the window, the leaves' gaps and the water, and on over the far map, each
clear one a thirteenth, so it fades in small steps as it goes behind an
edge; the clouds the sky shows on its line dim it (`Clouds.unveiled`:
what the cloud lets through, `Clouds.through`, which the ground's shade
under them shares, faded as the sky's clouds fade into the haze), a heavy
sky veils it, and it sets and rises with the body. The walks take a
fraction of a millisecond of the host's frame. Over every pixel it lays
the glare, the body's light spilled around it in the lens, over what
stands before it too: a bright core, a glow, a wide veil and a thin streak
across it, in its colour; and the flare, five ghosts of it along the line
from it through the screen's middle, soft hexagons, the aperture's shape,
in amber, jade, violet, orange and blue, their red a little wider than
their blue so the rim splits as glass does, fading as the body leaves the
screen. Both are laid on as a screen does, towards white, never past it.
Behind a canopy the sun comes and goes with the wind in the leaves' gaps,
and the glare with it.

**The shafts** (bit 30 of the base word, `src/shafts.bend`) are the
sun's light in the haze. Once a 4x4 tile, eight points along the rays through
its four corners, out to 96 blocks and denser near the eye, are tested
against the sun (`Render.beams`): the clouds' shadow at each, and within
the window a glance of 16 steps towards it, through the leaves' gaps in
the wind; how much of the sun reaches a point is a nibble. A pixel weighs
its tile's corners by its place into a profile of eight nibbles and sums
the haze it looks through to what it met (its block, the water it went
into, or the clouds' base), the far dimmed by the near
(`Shafts.depth`, over 24 blocks), where the sun reaches it. That light is
laid on in the sun's colour as a screen does, most towards the sun,
thicker as it sets, veiled by a heavy sky, and over the meadow's blades
where they stand before it: at sunset the far trees stand in a golden
haze, and the shade of a canopy, a hill or a cloud cuts darker air out of
it. It needs the sun up, or the moon, whose haze glows silver at 0.7 of
the sun's; the mirror sees none of it. Beams through
the leaves it cannot draw: eight points on a ray miss a beam a texel
wide, and the sky near the sun is too bright to take more light.

**The torch** (bit 31 of the base word, `src/torch.bend`) is the hotbar's
tenth slot, key `0`, with no count: infinite for now, and it places
nothing yet. Chosen, it stands in the hand in the screen's bottom right
corner, its flame flickering, and lights what lies within 14 blocks of
the eye in a warm light (bit 26 of the base says the eye holds it,
`Torch.in_hand`). The light stands at the eye, so every point the eye
sees it reaches: it casts no shadow and walks nothing. It is near the
day's within a few blocks and gone smoothly at 14, less on a face the ray
grazes, and it flickers with the flame. A lit colour takes the brighter
of its own light and the torch's, channel by channel, as Minecraft takes
the brighter of the sky's light and a block's, so the day hides it and
the shade and the night show it. The blocks, the meadow's blades and the
water's own colour take it (`Torch.lit`, `Torch.lamp`, `Torch.ink`).
With no torch in hand every pixel takes the path it took before, byte for
byte.

**The clouds** are cumulus in a slab from y=62 to 78, over the world's
columns, not the window's (`src/clouds.bend`). A coverage over the
ground's plane, value noise of four octaves that repeats every 256
columns, raises each cloud's top from a flat base. A sky pixel's ray
marches the slab in 16 steps, a block of its height each; a step reads
the coverage at its end, and its two broad octaves again five blocks
towards the sun, which light the side the sun sees, while the cloud
above a step dims it. Under a cloud's top the density is a ramp, and a
step takes its mean between the step's two ends: a flat ray's step spans
many columns, and read at one point the slab showed in layers, the faint
stripes of the horizon's clouds. The march reads them
from the world's array: at the world's birth the octaves are written
above the far map (`Clouds.map_at`), a word a column holding the broad
ones' byte at its corner and at the three after it along x and z, and
another word the fine ones', so a step's three reads blend a cell each
in place of the 24 hashes that computing them takes. A single read, the
ground's or a mirror's, computes them. The light a step stops
falls off as through fog, and the fine octaves fade as a step grows, at a
flat ray, where they would alias into stripes. Their colour follows the
sun: white by day, rose and gold at its rising and setting, grey-blue
under the moon; from 180 blocks they fade into the horizon's haze. The
weather, 0 clear to 1 overcast, is a noise over half days of the clock,
squared so that fair days are the most (`Clouds.weather`): it sets how
much of the sky they cover and how much light a block of them stops, and
a heavy sky greys the sky and its fog and veils the sun, the moon and the
stars. The first morning is fair with some clouds, and the second day
brings the first overcast. The wind carries them along x, their 256
columns in half a day, a column every two seconds. The ground reads the broad coverage once, where the
sun's line from it crosses the slab's middle, and loses to a thin cloud a
little of its sun, to a heavy one down to 0.55 of it, a shade darker
than a block's shadow. A mirror, the lake's or a puddle's, glimpses them
(`Clouds.glimpsed`): one read of the broad coverage where its ray crosses
the slab's middle, through the cloud's height along the ray and lit
halfway, in place of the sixteen steps a sky pixel marches.

**The rain** falls when the weather passes 0.62, from the cloud over the
eye: as much as that cloud holds, so a gap between clouds stays dry
(`src/rain.bend`). Its drops are in the world, three a column, thin
vertical streaks at places the column's hashes choose on the ripples'
world lattice, falling 12 blocks a second. A ray walks the 11 columns it
crosses first, as the render's walk does, and shows the drops it passes
within 0.02 of a block, in front of what it met or of the water's
surface, and only where no block stands over them, which the column's
solid mask, read once a step, tells. A drop near the eye is wide and a
far one thin, and walking passes them by. On still water, the lake's
and the puddles', with no block over it (`Wet.reached`, the column's
mask read once, as for a wet face), the drops ring (`Water.rings`): in
every half of a block one falls in 0.8 seconds, in as many halves as it
rains, at a place and a time the half's hash on the ripples' world
lattice chooses, and its ring's steep wave spreads 0.17 of a block and
fades, tilting the mirror as the ripples do.

**The wet** is what the rain leaves (`src/wet.bend`). A face with no
block over the air before it, which that column's solid mask tells in
one read, darkens where it is lit and takes a sheen of the sky it
mirrors, more the flatter it is seen. On the ground's tops (grass, dirt,
stone, sand, brick) puddles gather where a noise over the world's
columns, in cells of two columns and of one, passes a level the wetness
lowers: darker still, they mirror the sky with its sun, moon and stars
(`Clouds.mirrored`) and the world, walked as the lake's mirror walks it
(`Render.behind`, with the world in the mirror, bit 27), almost whole at
a glance, and shiver with the rain's rings. The wetness is the
rain's amount, or 0.7 of what fell a quarter day before, or 0.4 of what
fell half a day before, so the ground stays wet after the rain and
dries, its puddles shrinking first.
A dry world reads nothing; a far face is taken as open, and a face seen
through water shows none of it.

**The meadow** is tall grass on the grass tops (`src/grass.bend`). The
render's walk marks a ray's rim, where it first came into air over a
solid block low enough to meet its grass (under `Grass.top()`, 0.6 of a
block over the floor) and where it last left such air, and after it the
ray walks the grass between, as far as what it met, on three grids of
cells: four a block with six blades each to 12 blocks (three of them
alone from 4), two a block with three wider blades from 10 to 22, and
one a block with six wider still from 20 to 40, each fading into the
next over two blocks. A cell's hash roots its blades anywhere in it,
tapered stalks each leaning its own way, their tips pushed by the
wind's gusts, and now and then a flower, a cup of five petals on a stem
(dandelion, daisy, poppy, cornflower and clover, one kind to 8×8
blocks). A blade stays inside its cell and under the grass's top, so a
ray that crosses a cell meets all of it; it meets a blade where it
passes it nearest, its edge as soft as the pixel is wide, and the walk
stops once it sees no more than 5% through. The blades are lit where the
ray met them, in the sun or a block's shadow, yellower at their tips,
the sun shining through them when it is ahead, fogged and wet as there;
their feet stand in their own shade, and past them, and past 40 blocks,
a grass top is the meadow seen from afar: their colour and shade by how
wild the meadow grows, greener or straw by how dry. Each column's patch,
whether its floor is grass, how tall and thick its blades, how often
they flower and in what, and the wind's phase, is a word of the meadow's
map, 2^16 words past the clouds' (`Meadow.map_at`), written at the
world's birth as the clouds' is and read once a block a walk. The
meadow repeats every 256 columns, as the clouds do.

**The leaves** have holes (`Render.pierced`). A leaf block's face is an
8×8 tile of texels, as its texture is, and 30 in a hundred of them are
open, the same ones on every block; a ray that enters a leaf block
through an open texel goes on through the block, so a canopy shows the
sky and the leaves behind it through its gaps, and its edge is ragged.
The texel is where the ray came into the cell. The eye's walk reads a
column's leaf mask with its solid mask, a word a column in the leaf
plane past the meadow's map (`World.leaf_at`), written with the column.
The sun's glance sees 40 in a hundred: under a canopy it enters three or
four leaf blocks, and at the eye's 30 a tree's shadow held almost no
fleck of light, at 55 the shadow was lost among them. So a tree's shadow
is dappled, on the ground, the grass and the leaves under the canopy's
top. The world in the water's mirror sees the eye's holes, picking sees
none, and past the window the far walk's canopies are solid, where the
fog has taken most of them. The wind sways them (`Render.swayed`): a
leaf block's texels slide along the wind, and less up and across, up to
two texels with the gusts that push the grass, quivering at the block's
own phase (`Grass.gusting` and `Grass.quiver`, the grass's own), so the
canopies ruffle with the meadow and the flecks of light under them
dance. The gusts run over the column's slot, `x·128 + z` of the world
whatever the window, so the sway never jumps as the window moves.

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
the corner, position, look, chosen block, day clock and nine counts on its
first line, then one line per edited column: its key and its fourteen
words. The game loads it at start, if it is there, and writes it on `P`
and on quit; the untouched columns are never stored, they come back from
the noise; a line that does not fit the format is skipped. On the page the
file lives in the browser's memory, so it lasts until the tab is closed.
Both `P` and `Esc` save after that tick's edits.

**The player** is 1.8 blocks tall with the eye at 1.6. Walking tests the
feet and the head per axis and stops at walls; gravity pulls, landing snaps
the feet onto the block, space pushes off it. In water at the waist the
player swims (`Player.step_swim`, `World.wet_at`: the cell holds water and
the waist is under its plane): the water's lift nearly balances gravity, so
they sink at a fiftieth of a block a tick and drag; space swims up, to a
bob at the surface with the eye eight tenths over it; a stroke is half a
step; and a wall met swimming is a bank: the player pushes off it as off
the ground, a push the water's clamp holds down until the waist is out,
where it carries them over the bank (the fixture's stroke climbs out of
the lake, and the walk back crosses it and climbs the far shore). Out of
water nothing changed: the old fixture's lines are the same, and eight
swim lines follow them.
A block is never placed on
the player. The hotbar along the bottom shows the eight block types, the
bucket and the torch, and frames the chosen one, with the available count
below each block's swatch and the full cells it holds below the bucket's.

## Layout

```
main.bend          the window loop, elapsed time, the view, the tick
src/day.bend       integer day phase and the sun direction
src/inventory.bend natural counts, conserved cell/item transfers, packed HUD counts
src/sky.bend       sky gradient, sun, glow and halo, stars, moon, distance/height fog, the light's colour, the body that lights the world
src/lens.bend      the sun in the camera: the glare and the flare over a pixel
src/shafts.bend    the sun's light in the haze a pixel looks through, from its tile's shafts
src/torch.bend     the torch in the hand: its light on what the eye sees, its flame, its swatch
src/clouds.bend    the clouds' coverage and its map, their march along a sky ray, their shadow, the weather
src/rain.bend      the rain's drops in the world, under the cloud over the eye and the open sky
src/wet.bend       how wet the world is, where puddles lie, their rings, the sheen; the render reads the air and walks the mirror
src/meadow.bend    the meadow's map: how wild it grows, its flowers, the wind's phase, a word a column
src/grass.bend     the meadow's blades and flowers, the walks that meet them, the meadow from afar
src/water.bend     wet intervals, tint, fog, Fresnel, reflected sky, ripple normals, the rain's rings, the mirror, the caustic
src/util.bend      conversions, bit tests, smoothstep, a colour mixed, dimmed or lit as a screen does
src/world.bend     noise, terrain, the ring, the map, loads, shifts, edits, solid
src/render.bend    the DDA, the sun, the texture, the occlusion, the mirror's walk, a pixel, the sun the eye sees, a tile's shafts
src/frame.bend     the frame's tree, its one `!` and the game's view: all that relies on @unsafe
src/player.bend    Game, events, picking, the tick
src/flow.bend      the water's flow: marked cells stepped bottom up
src/save.bend      the save file, and the tick that writes it
LAWS.bend          the rules the checker proves; PROOF.bend closes them
AGENTS.md          for an agent (or a person) about to write Bend here: the gate, the rules
ROADMAP.md         the vision and what comes next: the look, the game, the laws, what waits on Bend
PERF.md            what a ray caster can do to cost less, each technique measured alone
test/lib.bend      what every windowless test needs: expect, ticks, one event, say
test/physics.bend  the game without a window: events through feed and step
test/save.bend     place, walk, save, load: the brick and the position come back
test/inventory.bend transfers, rejected edits, simultaneous input, counts, saves and HUD packing
test/day.bend      signed shadows, sky/fog, the clock's days and save, frame rate, the clouds' place, shadow, wind and weather, the rain, the wet, its puddles and their mirror, the light, the lens, the shafts, the torch
test/water.bend    signed wet rays, emerged silhouettes, underwater fog, edits and saves
test/ripples.bend  ring addresses under the looks' bits, stable world noise, normals and wrap continuity, the rain's rings, Snell's window
test/water_view.bend sixteen water views and a fixed-sun ripple cycle for test/water.py
test/mirror.bend   the mirror's walk over a placed brick, its reach and fade, the byte a miss keeps
test/mirror_view.bend four views with the world in the mirror and without, for test/mirror.py
test/sky.bend      six fixed sky views, saved as Image trees for test/sky.py
test/clouds_view.bend twelve cloud views, clear and overcast, each look off, for test/clouds.py
test/bench.bend    five frames on the GPU with checksums, untouched and built
test/profile.bend  what costs what: each look off in turn, the rays' hits and steps
test/trace.py      the frame's dispatch kernel by kernel, from the emitted C
test/terrain.bend  noise rows, lake floor materials, dry roots, canopies, saved columns, the far map and its look
test/far.bend      the far walk over a map written by hand: sides, tops, canopies, the sea and its trace, the look, its shadow and mirror
test/meadow.bend   the meadow's map, and rays through the grass, over it, over stone and down onto it
test/leaves.bend   the leaf plane, and walks through a leaf block's open texels and stopped by the rest
test/readout.bend  the readout's corner of a frame, printed a character a pixel
test/page.mjs      the page in headless Chrome: drag, click, place, jump
test/fps.mjs       the page's fps on N threads
site/              the page: notes.mjs post-processes the built index.html
```

```sh
make check      # the modules, the tests, the laws
make test       # physics, save and load, terrain, windowless
make bench      # five frames on Metal, untouched and with 300 blocks placed
make profile    # each look off, by size; also night, rain, the lake in the rain, lake, submerged, night lake, partial water
make sky        # six PNGs and build/sky-contact.png; Python with Pillow
make clouds     # twelve PNGs and build/clouds-contact.png; Pillow
make water      # sixteen PNGs and a ripple animation; Python with Pillow
make flow       # the lake breached into a pit, filling and settled; Pillow
make flow-bench # a lake draining through shafts: ms a tick on the host
make mirror     # build/mirror-sheet.png: four views, mirror on and off; Pillow
make page-test  # the page in headless Chrome, hashes and fps
```

## Numbers

Apple M5, the game closed, twelve rounds alternated with stock Bend 2.0.25
and the order swapped every round (2026-09-27); the last column, eight
rounds alternated with the build before the clouds' map (5, 5, 8, 12, 27
and 47 ms, the clouds, the weather, the rain and the wet), the same day;
the meadow's, eight rounds alternated with the build before it
(2026-09-28); the leaves', eight rounds alternated with the meadow's
build, which read 7, 7, 11, 20, 38 and 69 ms that evening; the wind's,
eight rounds alternated with the leaves' build, which read 8, 8, 13,
23, 44 and 79 that night; the mirror's meadow, eight rounds alternated
with 2.0.34's build, which read 7, 7, 11, 20, 38 and 73 (2026-09-29); the
light's, eight rounds alternated with that build, which read 7, 7, 11,
22, 41 and 72 that night; the lens's, eight rounds alternated with the
light's build, which read 7, 8, 11, 21, 42 and 75; the shafts', eight
rounds alternated with the build before them, which read 8, 7, 12, 22,
44 and 80.
The bench
times the `!` only, five frames a size with the camera turning; its thirty
checksums are the same on every build that changes nothing visible, both
compilers too.

| fastest bench frame | Bend 2.0.25 | 2.0.32 with #1132 and #1140 | and the clouds on their map | and the meadow | and the leaves' holes | and the wind in them | on 2.0.34 with #1132 | and the meadow in the mirror | and the light's colour | and the lens | and the shafts |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 512×512 | 5 ms | 3 ms | 4 ms | 7 ms | 8 ms | 8 ms | 7 ms | 7 ms | 8 ms | 8 ms | 9 ms |
| 512×512, 300 blocks placed | 5 ms | 3 ms | 4 ms | 7 ms | 8 ms | 8 ms | 7 ms | 7 ms | 7 ms | 7 ms | 9 ms |
| 735×398, a 14" MacBook at scale 2 | 13 ms | 6 ms | 6 ms | 10 ms | 12 ms | 13 ms | 11 ms | 11 ms | 11 ms | 12 ms | 14 ms |
| 960×540, a 1920×1080 window at scale 2 | 23 ms | 9 ms | 11 ms | 20 ms | 23 ms | 23 ms | 21 ms | 21 ms | 21 ms | 22 ms | 26 ms |
| 1470×796, a 14" MacBook at every pixel | 48 ms | 19 ms | 24 ms | 40 ms | 44 ms | 47 ms | 40 ms | 39 ms | 40 ms | 43 ms | 51 ms |
| 1920×1080 | 91 ms | 33 ms | 40 ms | 71 ms | 82 ms | 85 ms | 73 ms | 75 ms | 76 ms | 75 ms | 87 ms |

Stock 2.0.32 took 215 ms at 1470×796: its fix of a race
([#975](https://github.com/bendlang/bend/issues/975)) made every read of
a shared array two atomic loads, dear on Metal
([#1139](https://github.com/bendlang/bend/issues/1139)). #1140 read it
plainly again, and raced: with the meadow's walk in the lake's mirror a
frame died at random ("frontier drained without a result"). 2.0.34 reads
it plainly and once a loop
([#1155](https://github.com/bendlang/bend/pull/1155)), and the same
frames run whole, 16 runs of 16; the last column is eight rounds
alternated with 2.0.32 and #1140, which read 8, 8, 12, 24, 46 and 88. The page was last
measured before the sky: 31 fps at 512×512 on ten threads, 7 on one. On
the page, `?size=1024x576x2` in the address gives the wide frame, and the
fullscreen link scales whatever is rendered to the screen.

## What costs what

`make profile` renders a view five times with every look on, then with
each look off in turn (the camera's `fl` flags, and the world in the
mirror, the caustic, the shafts and the torch's light, bits 27, 28, 30 and 31 of the base word), then the rays
alone, and prints the `!` a frame; then it renders the view twice more
with numbers for pixels, how many rays reach a block and how many DDA
steps a ray walks to its hit, each pixel weighed by the square it stands
for. Its views are the bench's at four sizes, then at 1470×796 the
meadow from the start's hill, night looking at the moon, the meadow at
night with a torch in hand, the rain of the
second morning, the lake in that rain, a lake looking west, under its
water, the night lake with the moon in it, and the lake with partial
water in the window. The least of four rounds on a busy machine
(2026-09-28), ms a frame; the rows of the leaves are four more rounds
alternated with the build before the wind in them, the last row four
rounds alternated with the build before the meadow:

| | bench's view, 735×398 | bench's view, 1470×796 | meadow | lake | night lake | night, all sky |
|---|---|---|---|---|---|---|
| all on | 12.0 | 45.6 | 56.8 | 51.4 | 39.6 | 21.8 |
| shadow off | 12.0 | 42.4 | 53.0 | 45.6 | 40.4 | 21.4 |
| occlusion off | 11.8 | 44.2 | 55.8 | 48.0 | 38.6 | 21.2 |
| texture off | 12.4 | 45.6 | 55.0 | 47.4 | 37.8 | 21.6 |
| water off | 11.4 | 38.4 | 53.6 | 45.2 | 33.4 | 19.8 |
| sky reflection off | 11.8 | 45.4 | 58.6 | 45.2 | 34.8 | 22.0 |
| world mirror off | 12.4 | 44.4 | 59.0 | 49.4 | 36.0 | 21.6 |
| caustic off | 12.6 | 45.4 | 57.4 | 51.6 | 40.0 | 21.8 |
| clouds off | 12.4 | 46.2 | 49.4 | 48.6 | 35.8 | 14.0 |
| cloud shadows off | 13.4 | 45.2 | 56.0 | 48.8 | 38.6 | 21.6 |
| meadow off | 8.4 | 27.8 | 20.6 | 28.2 | 25.8 | 22.6 |
| rays alone | 4.0 | 13.8 | 10.4 | 12.4 | 10.8 | 9.8 |
| all on, with the leaves in the wind | 14.8 | 54.8 | 63.8 | 55.0 | 46.2 | 25.4 |
| leaves' holes off | 13.2 | 49.6 | 63.2 | 55.4 | 42.6 | 23.4 |
| leaf light off | 13.8 | 50.4 | 59.0 | 57.2 | 45.0 | 24.6 |
| leaf wind off | 14.0 | 52.8 | 61.0 | 56.2 | 44.2 | 24.6 |
| all on, before the wind | 14.2 | 54.0 | 64.4 | 68.2 | 48.0 | 26.6 |
| all on, before the meadow | 8.0 | 24.8 | | 28.0 | 23.6 | 19.8 |

The other looks (distance and height fog, HUD, day cycle, gradient, sun,
glow, stars, moon, water fog, Fresnel, ripples, the light's colour and the
sun's halo) are arithmetic on a pixel and read within the noise of all
on: six rounds read the light's two looks 47.0 against 45.0 on the build
before them in the bench's view at 1470×796, 57.2 against 56.2 in the
evening towards the sun, and 12.4 against 12.6 at 735×398. The lens,
whose ghosts and glare every pixel computes while the sun is seen, reads
up to 3 ms at 1470×796 (six rounds: the bench's view 48.4 on and 45.0
off, the sun aside 51.2 both) and nothing at scale 2 (12.8 both); the
moon's, from above the trees, 26.4 on and 24.0 off. The shafts, whose
glances and clouds' reads every tile makes at its four corners while the
sun is up, read 8 ms at 1470×796 (six rounds: the bench's view 56.2 on
and 48.4 off, the sunset towards the sun 66.6 and 58.0) and 2 at scale 2
(14.6 and 12.8). The moon's light costs the night what the sun's costs
the day, its shadows and its haze: at midnight over the meadow 67.4 ms at
1470×796 with it and 54.0 without (six rounds; the build before, 54.6),
and 18.2 and 16.0 at scale 2. The torch in hand, arithmetic on a
pixel with no walk, reads within the noise: eight rounds read the meadow
at night at 1470×796 64.0 with its light and 63.0 without (the build
before it, 64.2), and at the lake's shore 70.0 and 69.2 (68.0). In the bench's view 49% of the rays
reach a block, after 41.4 steps with a sky ray's 60; at the lake 77%,
after 31.3.

The meadow is the dearest look: 4 ms of the bench's view at scale 2 and
18 at 1470×796, 36 where the view is all meadow, and nothing where it is
sky; its fine walk is most of it, and PERF.md splits it and holds what
was tried to make it cheaper. The leaves' holes cost about 1 ms of the
bench's frame at scale 2 and 6 at 1470×796, and neither of their rows
alone gives much of it back. With both off, eight bench rounds read 7,
7, 11, 21, 41 and 82 ms, and the build before them 7, 7, 11, 20, 41 and
75: the leaf mask and the rates the walks now carry cost nothing at
scale 2 and a few ms at the largest sizes. The wind in them takes
nothing at scale 2 and 1 to 3 ms at 1470×796. The meadow in the water's
mirrors takes 8 ms at 1470×796 where the lake shows its banks (six
rounds, the lake seen from its shore: 60.4 all on, 52.4 with bit 16 off)
and 2 at scale 2; with it off the mirror still walks the eye's DDA, whose
rim it needs, in place of a glance over the solid bits, 1 to 5 ms more
than the build before it (47.0 there, 14.4 at scale 2). The rays alone are a
third of a frame. After them come the walks a look adds, since a DDA step costs about the same wherever it happens, the
frame being its slowest lane: the shadow's 24 steps, the mirror's 32, and
the clouds' 16, each of them three reads of their map, the density's
mean along it and a step's light. The clouds take 3 ms in the bench's
view, whose top is sky, and 7 where the whole frame is, since a sky
ray's lane marches them all; off, they cost nothing. A step hashed its
six lattices before the map, 6 and 17 ms. The table is the map's, whose
12 steps read the density at one point: the 16 averaged ones took 2 ms
more where the frame is all sky and none in the bench's view (six
alternated rounds of those rows alone, 17.6 against 19.8 and 25.6
against 25.8). Their shadow, one read a lit block, takes 1. The
rain takes about 5 where it rains (the second morning: all on 35.0, rain
off 30.2), its 11 columns and 33 drops a ray, and nothing where it does
not. The wet it leaves takes about 3.5 more, a column's read, a glimpse
of the clouds a face and the mirror's walk a puddle (1.4 of it, in the
second morning's rain on the hill), and nothing on a dry day. Water
comes next, 3 to 5 ms, because it tracks the wet intervals along every
ray's 60 steps. Two lessons of the first profile hold: a ray that stopped
at its hit walked a third of the steps and made the frame slower, the
lanes of a SIMD group then leaving the loop at different steps; and a
`Bool.pick` is strict, so a look that is off is skipped by a `match`, or
it is paid for anyway.

`test/trace.py` goes one level down: it patches the emitted C so the
frame's dispatch runs as one command buffer a kernel, and prints each
kernel's time and the tasks left in the lanes' rings (`bend
test/bench.bend -o build/bench.c && python3 test/trace.py build/bench.c &&
./build/bench_trace`). It reaches into the runtime's text, written for
2.0.25's; it does not find 2.0.34's yet.

## The frame's time, in the game

`F` puts a readout in the frame's corner: `16.4 MS  60 FPS`. The first
number is the `!` alone, the render, as the bench times it; the second is
the frames that reached the screen, which the display's rate caps, so a
render of 5 ms still reads 60 or 120. `main.bend` runs the window's loop
itself, in `App.run`'s shape, to read the clock on each side of the view
and not around the wait for the screen; twice a second it publishes the
mean since. The two numbers ride to the GPU in a word of their own,
`Cam.stat` (they rode in spare bits of the flags, the inventory and the
ring-address words while the camera was kept at 14 words; the fifteenth
word measured free, so the splices and their 22 laws went, 2026-09-22;
the sixteenth, `Cam.far`, the far map's address, measured free too).
Only 14 low address bits affect the ring's wrapping array reads, and the
camera keeps only those.
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
reads back the same; a key the game does not know sets no bit, and the wheel goes around the ten slots;
the readout's numbers read back from their word and stop at their room.
The day phase
returns after a whole turn for every `U32` clock value, including overflow,
proved by induction over the low 20 bits. This is the sun's sole integer
input. Its last millisecond advances to dawn. The inventory uses natural
counts: a transfer conserves the cell plus its count, and induction extends that to every list of actions.
Empty spending and occupied placement are rejected, break then place
restores the count, and edits preserve the number of inventory slots.
The HUD packing has mixed-slot and boundary laws; save/quit edges survive
the physics step. Still-water laws cover generation above ground, the sea
limit, banks preserved on water placement, displacement, neighboring bits
and material packing. Water fog has its own flag, enabled by default.
Three tree laws check all 32 column heights:
submerged ground and snow reject roots, dry grass accepts them. Two lake
floor laws cover the submerged dirt heights and their material packing;
dry shoreline grass, low sand and high snow keep their existing laws.
Five surface laws cover independent flags and packing
the top-entry bit with all 61 step counts and four face codes. Float tests
cover Fresnel endpoints and growth, reflected sun/moon, signed entry,
submerged eyes, foreground banks and distant fog.
Four ripple laws: the 8192-ms period for every clock word, its loop
whole in a day, flag independence and integer recentering. Windowless
tests exhaust 16384 ring addresses under the looks' bits and 257 FPS
inputs, and check unit normals,
grazing reflection, positive/negative recentering and temporal continuity.
Three mirror laws keep its look in bit 27 of the base word: it reads
back, it is off unless asked for, and the ring address passes through it
untouched. Windowless tests walk the
mirror's ray to a placed brick along an axis and across, past its reach,
and to the sky, and check the fade and the byte a miss leaves alone.
Two more keep the caustic's look in bit 28. Sixteen amount laws: a column
born of the terrain or a save is full where it is wet, an amount reads
its byte, a byte written reads back and leaves the others, the device's
read agrees with the host's, water placed is a full cell, a solid placed
holds none, a pour sets the amount and the bit, clears the bit at zero,
caps at 255 and does nothing to a solid, and the partial mask has a bit
for a poured cell and none for a full one. Ten flow laws bound one
transfer. Eight bucket laws: it takes a cell whole and nothing from a
solid, a pour is what the cell lacks, 255 into air and nothing into a
full cell or a solid, the bucket is the ninth slot and the HUD shows its
full cells above the readout's numbers. Seven shove
laws: what fits is the room, all of less, nothing in full or in a
solid; a solid placed on water shoves its amount, water placed and a
break shove nothing. Eleven far-map laws: the window wraps under the far map,
its columns live above it, the render reads the word the host wrote, a
column is its run and its canopy, its top is the higher of the two,
leaves inside the run are the run's, a far column's types are the
window's for the ground, the trunk and the sea, the sea is its plane
over a lower ground, and it is not solid. Two meadow laws: its map
wraps in 2^16 words past the clouds', and a column's word reads back how
wild the meadow grows, its flower and the wind's phase. Two leaf laws:
the leaf plane follows the meadow's map, and a column's leaf mask marks
its solid leaves alone. There are 134 laws: eight universal claims and
126 concrete
checks. Integration tests exercise the actual ring edits, all eight types,
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
[#923](https://github.com/bendlang/bend/issues/923), a way to go full
screen, and [#925](https://github.com/bendlang/bend/issues/925), the shape
of the frame's tree deciding the lanes' load, with a 90-line reproduction,
which [#1132](https://github.com/bendlang/bend/pull/1132) answers.

Written by Claude (Anthropic) with Adriel Santana.
