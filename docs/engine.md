# How Bendcraft works

How each part is built, what each look costs, what the laws promise and
where the files are. The [README](../README.md) says what the game is,
[roadmap.md](roadmap.md) where it goes, and [AGENTS.md](../AGENTS.md) the
rules of working here and every word's layout, bit by bit.

## The frame

The render is a DDA through the world's window, one ray per pixel, 60
steps. The loop returns the solid hit and its distance, plus the first
wet entry and the total wet distance. The look is a `match` after the
walk: a second DDA toward the sun for shadows, a pixel-art tile of four
shades per face, ambient occlusion per vertex from the eight cells around
the hit, distance haze and a height fog into the sky along the ray. Every
look is a bit, of `Cam.fl` or of the high bits of `Cam.base`, and with a
look off every pixel takes the path it took before it, byte for byte;
`make profile` measures each.

The `!` runs a binary tree down to 4×4 tiles: a square splits into its two
rows, a row into its two squares, as many levels as the larger side needs,
and a half that lies past the render's edge is one pixel and never a task.
The shape follows the GPU runtime, which grows a frontier of tasks two-way
a turn until each of the 128 lanes of a group holds one, then runs each
task on its lane to the end: a two-way tree fills the frontier with tasks
of one size, and a wide frame at every pixel took 16 ms where a four-way
tree took 46. A ray walks its 60 steps whether it hits or not: the lanes
of a SIMD group that part ways run one case at a time, and a ray that
stopped at its hit made the frame slower.

## The world

**One array, shared by every pixel.** `Array` in Bend has one owner. Since
2.0.22 an `@unsafe` def may hand one array to both sides of a fork anyway,
two handles to one block that `Array.join` gives back, so the world is one
`Array<U32>` of 2^20 words (`src/frame.bend` holds all that relies on it).
Its low 2^18 words are the columns around the player, sixteen words a
column: the first a mask whose bit `y` says "there is a block at height
`y`", the next four the types of its 32 blocks, four bits each, then the
water's mask, eight words of its amounts, a byte a cell, the flow's marks
and the mask of partial cells. Thirty-two heights in one word is what
makes it cheap: the ray sees a column as a machine word, and break or
place is one bit. Above the columns lie the far map, the clouds', the
meadow's, the leaf plane and the light's. An edit is a few `Array.set` on
the host; a built world costs what an untouched one does.

**It is endless.** The terrain is seeded value noise, three octaves, a pure
function of `(x, z)`: sand on the lowest ground, dirt on the rest under
water, grass on dry ground and snow where it is high; three of dirt under
the top, stone below. About one grass column in eighty grows a tree when
its ground is dry (height at least 12), a trunk of four wood with a canopy
of leaves over the columns around it; a column takes its wood and leaf
bits from the trees of the 25 columns around it, so a canopy crosses
columns without anyone writing across. The array holds a ring of 128×128
columns around the player, and a `Map` holds the columns the player
edited. World column `(x, z)` sits at slot `(x·128 + z)·16`; the array
reads its index modulo its size, so any 128×128 window falls one-to-one on
the 16384 column slots, and a reader carries one word,
`base = ox·128 + oz`, to find local column `(lx, lz)`. The render and the
physics only see local coordinates in `[0, 128)`. The corner follows the
player one column at a time, loading the row that came into view, from
the map if it was edited and from the noise if not; an edit is a bit and
a nibble in the ring and the whole column in the map, so it is there when
you come back.

**The far horizon.** A ray that met nothing goes on over the far map from
where it left the window's columns (`Render.window_exit`): a word a column
for 256×256 columns around the window, holding the column's run from the
floor (its ground, a trunk or the sea over it), the canopy over that, and
the highest top of the column's 4×4 cell. This walk (`Render.run_far`)
takes 128 steps at most: a step crosses a cell where the ray stays over
the cell's highest top, a column elsewhere, and it stops at its hit, at
the map's edge, over the world's top and where the fog is whole, 120
blocks out. What it meets is shaded by the window's own look with the far
map in place of the window's columns: its type from the column's word,
the corners' occlusion from the eight cells around it, the shadow by the
far walk towards the sun. The sea is no block to it: it adds the ray's
path under the sea's plane to the window's wet trace and walks on to the
bed, so the far sea is the window's water across the seam, its mirror
walked over the far map. A block near the window's side reads past it the
same way. So the ground, its trees and its lakes go on to the horizon
block for block, and a block looks the same on either side of the seam
(`test/terrain.bend`: all 192 rays from the start's eye within 4 a
channel). The far map is the noise's alone: an edit does not reach it, so
past the window a tower someone built shows as the ground under it.

**It is saved.** `bendcraft.save` in the working directory holds the
corner, position, look, chosen block, day clock and nine counts on its
first line, then one line per edited column: its key and its fourteen
words. The game loads it at start, if it is there, and writes it on `P`
and on quit, after that tick's edits; the untouched columns are never
stored, they come back from the noise; a line that does not fit the
format is skipped.

## Water

**Its look.** Water is type 8, with a mask word of its own, so collisions,
picking, shadows and occlusion read the solid mask alone; the seed fills
the ground under y = 12 with it. The ray crosses water and sees the
ground; its wet distance gives the tint its depth. Seen from the air the
water is dense: the tint takes 1 − 0.88 / (1 + 0.35 d)² of the colour (an
exponential's shape, which Bend has no function for: a half at one block,
0.85 at four), and d counts the light's way down to the bed as well as
the ray's way up, so a look straight down doubles it. A clear lake showed
its bed through every mirror; a dense one leaves the surface to the sky,
the ripples and the bank. An eye under the water keeps the clear tint
(0.18 + 0.72 d / (d + 4)), or a diver would see two blocks. What lies deep
is lit by what little light got down to it: the light left at a point's
depth under the sea's level (all of it at the level, a sixth six blocks
down) dims whatever a wet ray meets there, from the air or from under the
water alike, so a diver at the bed sees the bed as the bank does; the
tint darkens with that depth to a near-black blue, and the fog a
submerged eye sees converges to the colour at its own depth. The depth
counts from the sea's level even where the bucket poured water higher.

The fog takes the whole path to the solid hit, the air after a lake
included, so going into water never resets it, and it colours the
background before the water tints it: a far block the fog hides matches
the sky seen through the same water. A water fog fades to the water's
colour by 24 wet blocks, before the ray's 60 steps run out. A top reflects
the analytic sky, its sun, stars and moon, greyed and veiled by the
weather as the sky is, and a glimpse of the clouds (`Clouds.mirrored`).
Fresnel raises the reflection from about 2% head-on toward a mirror at
grazing angles, by a cube where Schlick has a fifth power, so the mirror
shows at the angles a player sees a lake from (14% at 30 degrees, not 5).
The DDA marks the first entry down through a water top in a spare bit of
its step counter, so sides and a submerged eye keep absorption alone.
Ripples tilt the surface's normal with value noise on the world's
lattice, moved by the game's clock and looping every 8192 ms of it, so
loading columns never drags the pattern; its gradient takes four hashes
and no world read; the normal fades with distance and in the last degrees
before the horizon, and a mirrored ray that a steep ripple would send
under the water is lifted back over it.

**The world in the mirror.** A pixel that shows a water top walks the ring
again from where it met the water, along the mirrored and rippled
direction: the eye's own DDA, dry, for 32 steps (`Render.walk_from`), as
the ray of the eye's image under the water, so its distances count from
that image and the meadow's levels, the fog and a pixel's width read them
as the eye's ray's; the blades it passes over stand upside down in the
lake. What it meets gets the block's colour, texture and face tone, no
occlusion and no shadow of its own, is fogged by the whole path and laid
over the mirrored sky before Fresnel weighs the two. A step crosses one
face, so a ray of direction d meets what lies within
28 / (|dx| + |dy| + |dz|) blocks, 16 to 28 of them; over the last quarter
of that reach the mirror fades into the sky, and nothing pops in where the
walk ends. This is a function of the ray, which a ray caster gets for the
price of a walk; a screen-space reflection would be a function of the
image, which a pixel of the fork tree cannot read.

**From under the water** the surface is Snell's window. A ray from a
submerged eye that leaves the water up shows the surface where it leaves
(`Render.surfaced`). Snell's law, 1.33 to 1, bends it into the air through
the normal the ripples and the rain's rings tilt, at about half the tilt
the lake shows from above, and inside the window the bent ray sees the
sky, the clouds, the world and the rain as the lake's mirror walks them
(`Render.behind`): the whole sky in a cone of 97 degrees, the banks
crowding its rim, as a diver sees them. Past 49 degrees from the normal
the surface is a mirror, total internal reflection, and a glance of 24
steps down from it shows the world under the water. Fresnel weighs the
two, and the water between the eye and the surface tints the whole.

**The caustic.** Seen from above, where the mirror is 2% of the colour,
the water shows its bed, and the bed a caustic: threads of light the
rippled surface gathered. The real one follows the surface's curvature
down to the bed; this one is false: the ripples' own noise read at the
bed's point, at twice and three times their scale and moving with their
clock, the product of the two ridges squared so the threads are thin,
with a mean near zero so a shallow bed keeps its brightness. It is
strongest just under the surface and gone six blocks down, in daylight
alone, grows with the water over the bed (`Render.thickness`), and fades
where the eye looks along the surface. Four hashes an octave, on the
pixels of a wet hit alone.

**Amounts.** A cell holds 0 to 255 units of water; `World.pour` sets one,
and the mask's bit follows. A cell holding less than 255 is water only
under its plane at y + amount / 255, and the DDA clips its wet segment to
that plane: a ray coming down enters at the plane, a ray over the water
passes, a ray under it meets the side face whole, and the reflection, the
ripples, Fresnel, the mirror and the caustic happen on the plane. Between
two neighbours' planes there is a step, a unit tall on a lake at rest,
and a ray that crosses it enters the surface, not a wall
(`Render.keep_wet`); from the air a side entry stays a wall, the wedge of
a stream. The loop is specialized on whether the window holds a partial
cell (`World.partials`), so a frame without one pays nothing for them.

**The flow** (`src/flow.bend`) steps the marked cells every 256 ms of the
day's clock. A cell holding a > 0 units first gives the cell below what
fits, min(a, 255 − b), then each of its four sides that holds less takes
floor((a − n) / 2) of what is left, in an order that reverses on odd
ticks; every transfer is two `World.pour` at once, so the volume is kept
by construction and no cell leaves 0..255. A neighbour outside the window
is solid, so a lake that reaches the edge holds. An edit marks its cell,
the one above and the four sides; a move marks the cell that lost water,
the one above it and its sides, and the one that gained. A marked
column's slot is queued once, oldest first, and a tick steps at most 256
columns (`Flow.budget`), the rest waiting their turn, so a tick costs a
few milliseconds on the host whatever the lake (`make flow-bench`: 2 to 3
ms with 500 to 1600 columns queued). After a stall the flow catches up at
two ticks a frame. A difference of one unit does not move, so a surface
at rest slopes a unit a cell toward where it drained, 1/255 of a block,
nothing to the eye; and the rule halves a difference a tick, so a lake
levels by diffusion, in about as many ticks as the square of its length
(roadmap.md has the options).

**The bucket, the sink and the shove.** The ninth slot is a bucket: a
click takes all the water of the cell before the face aimed at, a partial
cell for what it holds, and the units add up (the bag's ninth count,
saved); a right click fills that cell from the bucket if it holds what the
cell lacks, 255 for air. The pick ignores water, so the cell taken is the
one before the solid the crosshair meets, the bed's under a lake: a scoop
from the bottom, and the water above falls into the gap. Thin water dries:
a cell that holds under four units at the end of its step loses them,
counted (`World.gone`). A cell still holding water then rests on a solid
or on full water, so falling water never dries, and a lake at rest, ten
units a cell and more, is untouched; without the sink a spill spreads as
a film of a unit or two over every flat reach and stays. A solid placed in
water shoves the cell's water up its column into the first cells with
room, marked, so a lake rises by what the block took (`World.shove`);
what finds no room under a ceiling is gone, counted. Water is only moved,
never made: the world, the bucket and what went sum to what was placed,
and the tests carry that ledger through the flow.

## Sky, sun and moon

**The day** is an integer clock in `Game`, advanced by the elapsed
milliseconds, apart from the physics and the frame rate. A day is 1048576
ms (17 minutes 28.576 seconds); phase zero is dawn, a quarter noon, a half
dusk and three quarters midnight. The clock counts the days too, for the
weather, and its word wraps after 4096 of them, whole turns. The game
starts in the morning. `H` held runs the clock 64 times as fast and `G`
back, no further than the first dawn (`Day.run`). The sun's sine and
cosine are computed on the host and ride in `Cam`. A sky gradient follows
the sun's height, with a warm glow toward dawn and dusk, a sun disc, fixed
stars at night and a moon opposite the sun. The fog takes the sky's
colour, without the discs, and reaches the sky at 120 blocks
(`Sky.reach`); a height fog thickens in the low ground.

**The light** has a colour (`Sky.light`): a lit colour takes a factor a
channel, the sun's where the face is in the sun, warm white overhead and
gold as it sets, and the sky's in the shade, blue by day, violet at dusk,
deeper under the moon; a face takes between the two as much sun as the
shadow and the clouds leave it. The sun falls on a face as the cosine of
its angle to the face's normal, never under 0.4 of it (`Sky.sunned`), so
at sunset the sides turned to it glow and the tops it grazes take the
sky's violet. Around the sun (`Sky.halo`) the air takes a tight white
glare and a wide warm glow, fading as it sets, and the fog takes its
colour from it, so what stands against the sun melts into a bright haze.
Once the sun has set the moon lights the world in its place (`Sky.side`),
in a silver light: the faces turned to it, its shadows and the clouds'
shade, as the sun's by day. The night's light rises from 0.18 of the
day's to 0.48 (`Sky.level`), and the sky takes the full moon's blue and a
wide glow around it (`Sky.moonsky`).

**The lens** (`src/lens.bend`) puts the sun in the camera, and the moon
once the sun has set, a third as bright in a cool white. How much of it
the eye sees, 0 to 1, is found on the host once a frame
(`Render.sighted`, into `Cam.seen`): thirteen rays from the eye, to the
body's middle and to two rings of six points within its disc, each walked
as a pixel's ray is, through the window, the leaves' gaps and the water,
and on over the far map, each clear one a thirteenth, so it fades in
small steps as it goes behind an edge; the clouds on its line dim it
(`Clouds.unveiled`), and a heavy sky veils it. Over every pixel it lays
the glare, the body's light spilled around it in the lens, over what
stands before it too: a bright core, a glow, a wide veil and a thin streak
across it; and the flare, five ghosts of it along the line from it
through the screen's middle, soft hexagons, the aperture's shape, in
amber, jade, violet, orange and blue, their red a little wider than their
blue so the rim splits as glass does. Both are laid on as a screen does,
towards white, never past it. Behind a canopy the sun comes and goes with
the wind in the leaves' gaps, and the glare with it.

**The shafts** (`src/shafts.bend`) are the sun's light in the haze. Once a
4×4 tile, eight points along the rays through its four corners, out to 96
blocks and denser near the eye, are tested against the sun
(`Render.beams`): the clouds' shadow at each, and within the window a
glance of 16 steps towards it, through the leaves' gaps in the wind. A
pixel weighs its tile's corners by its place and sums the haze it looks
through to what it met, the far dimmed by the near (`Shafts.depth`), where
the sun reaches it. That light is laid on in the sun's colour, most
towards the sun, thicker as it sets, veiled by a heavy sky, and over the
meadow's blades where they stand before it: at sunset the far trees stand
in a golden haze, and the shade of a canopy, a hill or a cloud cuts darker
air out of it. The moon's haze glows silver at 0.7 of the sun's; the
mirror sees none. Beams through the leaves it cannot draw: eight points on
a ray miss a beam a texel wide, and the sky near the sun is too bright to
take more light.

## Clouds, weather, rain and the wet

**The clouds** are cumulus in a slab from y = 62 to 78, over the world's
columns, not the window's (`src/clouds.bend`). A coverage over the ground,
value noise of four octaves that repeats every 256 columns, raises each
cloud's top from a flat base. A sky pixel's ray marches the slab in 16
steps, a block of its height each; a step reads the coverage at its end,
and its two broad octaves again five blocks towards the sun, which light
the side the sun sees, while the cloud above a step dims it. Under a
cloud's top the density is a ramp, and a step takes its mean between the
step's two ends: a flat ray's step spans many columns, and read at one
point the slab showed in layers. The octaves are written into the world's
array at its birth (`Clouds.map_at`), a word a column holding the broad
ones' byte at its corner and at the three after it along x and z, and
another word the fine ones', so a step's three reads blend a cell each in
place of the 24 hashes that computing them takes; a single read, the
ground's or a mirror's, computes them. The fine octaves fade as a step
grows, at a flat ray, where they would alias into stripes. Their colour
follows the sun: white by day, rose and gold at its rising and setting,
grey-blue under the moon; from 180 blocks they fade into the horizon's
haze. The ground reads the broad coverage once, where the sun's line from
it crosses the slab's middle, and loses to a thin cloud a little of its
sun, to a heavy one down to 0.55 of it. A mirror, the lake's or a
puddle's, glimpses them in one read where its ray crosses the slab's
middle (`Clouds.glimpsed`).

**The weather**, 0 clear to 1 overcast, is a noise over half days of the
clock, squared so that fair days are the most (`Clouds.weather`): it sets
how much of the sky the clouds cover and how much light a block of them
stops, and a heavy sky greys the sky and its fog and veils the sun, the
moon and the stars. The first morning is fair with some clouds, and the
second day brings the first overcast. The wind carries the clouds along x,
their 256 columns in half a day. None of it is state: the weather is the
clock's, so `C` turns it by moving the clock whole days on, to the same
hour of the next day of rain or of dry ground (`Wet.turn_key`).

**The rain** falls when the weather passes 0.62, from the cloud over the
eye: as much as that cloud holds, so a gap between clouds stays dry
(`src/rain.bend`). Its drops are in the world, three a column, thin
streaks at places the column's hashes choose, falling 12 blocks a second.
A ray walks the 11 columns it crosses first and shows the drops it passes
within 0.02 of a block, in front of what it met or of the water's surface,
and only where no block stands over them, which the column's solid mask,
read once a step, tells. It falls over the meadow's blades, and past them
it shows as much as the ray sees through them (`Render.rim_met`). A drop
near the eye is wide and a far one thin, and walking passes them by. On
still water under the open sky the drops ring (`Water.rings`): in every
half of a block one falls in 0.8 seconds, in as many halves as it rains,
and its ring's steep wave spreads 0.17 of a block and fades, tilting the
mirror as the ripples do.

**The wet** is what the rain leaves (`src/wet.bend`). A face with no block
over the air before it, which that column's solid mask tells in one read,
darkens where it is lit and takes a sheen of the sky it mirrors, more the
flatter it is seen. On the ground's tops (grass, dirt, stone, sand, brick)
puddles gather where a noise over the world's columns passes a level the
wetness lowers: darker still, they mirror the sky and the world, walked as
the lake's mirror walks it, and shiver with the rain's rings. In the
meadow a puddle thins the blades at their roots, and the shade at their
feet, as it covers the ground there (`Grass.thin`, from the puddle's depth
and its slope, `Wet.pool`), so it shows among them. The wetness is the
rain's amount, or 0.7 of what fell a quarter day before, or 0.4 of what
fell half a day before, so the ground stays wet after the rain and dries,
its puddles shrinking first. A dry world reads nothing.

## The meadow and the leaves

**The meadow** is tall grass on the grass tops (`src/grass.bend`). The
render's walk marks a ray's rim, where it first came into air over a solid
block low enough to meet its grass (under `Grass.top()`, 0.6 of a block
over the floor) and where it last left such air, and after it the ray
walks the grass between, as far as what it met, on three grids of cells:
four a block with six blades each to 12 blocks, two a block with three
wider blades from 10 to 22, and one a block with six wider still from 20
to 40, each fading into the next over two blocks. A cell's hash roots its
blades anywhere in it, tapered stalks each leaning its own way, their tips
pushed by the wind's gusts, and now and then a flower, a cup of five
petals on a stem (dandelion, daisy, poppy, cornflower and clover, one kind
to 8×8 blocks). A blade stays inside its cell and under the grass's top,
so a ray that crosses a cell meets all of it; it meets a blade where it
passes it nearest, its edge as soft as the pixel is wide, and the walk
stops once it sees no more than 5% through. The blades are lit where the
ray met them, in the sun or a block's shadow, yellower at their tips, the
sun shining through them when it is ahead; past them, and past 40 blocks,
a grass top is the meadow seen from afar, its colour by how wild the
meadow grows. Each column's patch, whether its floor is grass, how tall
and thick its blades, how often they flower and in what, and the wind's
phase, is a word of the meadow's map (`Meadow.map_at`), written at the
world's birth as the clouds' is and read once a block a walk.

**The leaves** have holes (`Render.pierced`). A leaf block's face is an
8×8 tile of texels, as its texture is, and 30 in a hundred of them are
open, the same ones on every block; a ray that enters a leaf block through
an open texel goes on through the block, so a canopy shows the sky and the
leaves behind it through its gaps, and its edge is ragged. The eye's walk
reads a column's leaf mask with its solid mask (`World.leaf_at`). The
sun's glance sees 40 in a hundred: under a canopy it enters three or four
leaf blocks, and at the eye's 30 a tree's shadow held almost no fleck of
light, at 55 the shadow was lost among them. So a tree's shadow is
dappled. The mirror sees the eye's holes, picking none, and past the
window the far walk's canopies are solid, where the fog has taken most of
them. The wind sways them (`Render.swayed`): a leaf block's texels slide
along the wind with the gusts that push the grass, quivering at the
block's own phase, over the column's slot in the world, so the sway never
jumps as the window moves and the flecks of light under the trees dance.

## Torches

**In the hand** (`src/torch.bend`) the torch is the hotbar's tenth slot,
key `0`, with no count. Chosen, it stands in the screen's bottom right
corner, its flame flickering, and lights what lies within 14 blocks of
the eye in a warm light. The light stands at the eye, so every point the
eye sees it reaches: it casts no shadow and walks nothing. It is near the
day's within a few blocks and gone smoothly at 14, less on a face the ray
grazes, and it flickers with the flame. A lit colour takes the brighter of
its own light and the torch's, channel by channel, as Minecraft takes the
brighter of the sky's light and a block's, and the day fades it out, whole
once the sun is 0.12 under the horizon and gone from 0.17 over it
(`Torch.night`).

**As a block.** A right click stands a torch, block type 9, in the cell
before the face aimed at, if that cell is open and dry and a solid block
is under it; a click takes it and gives nothing. It is a stick of 2 by 10
texels of 16 in the middle of its cell, its top three the flame, white,
gold, then orange, flickering at a phase of its column's own. It is in
neither mask: the player walks through it, it casts no shadow and darkens
no corner, and the flow's water puts it out, as the break of the block
under it takes it. Its bit rides the leaf plane where the cell is not
solid (`World.plane`): a walk that comes into a torch's cell crosses the
stick's box or goes on (`Render.through`), and a hit on the stick says so
in bit 10 of the hit word, with its distance inside the cell, so the
meadow's blades before it stand over it. The picking is the eye's walk,
so the crosshair finds a torch and a click on the ground behind it passes
it by; nothing is placed against a torch.

**Its light** is Minecraft's block light: a level a cell, 0 to 14, a nibble
a height in four words a column (`World.light_at`). A torch's cell holds
14, and the light spreads through the cells that are not solid, one less a
step, a cell holding the most any path brings it: it goes around a block
and not through a wall. The host spreads it in rounds from 14 down
(`World.relight`): an edit relights the 27 × 27 columns it can reach, a
shift of the window the row that came into view, the world's birth the
whole window. A face takes the level of the cell before it and of the
eight around it, a vertex the mean of its open cells, blended as the
occlusion is (`Render.glow_fin`); the meadow's blades and the water's top
take the four cells around their point, and the water's mirror the cell
before the face it meets. A level l lights as the torch in the hand does
14 − l blocks away (`Torch.glow`), and the day fades it out as it does the
hand's.

## The player

**Moving.** The player is 1.8 blocks tall with the eye at 1.6. Walking
tests the feet and the head per axis and stops at walls; gravity pulls,
landing snaps the feet onto the block, space pushes off it. In water at
the waist the player swims (`Player.step_swim`, `World.wet_at`): the
water's lift nearly balances gravity, so they sink at a fiftieth of a
block a tick and drag; space swims up, to a bob at the surface with the
eye eight tenths over it; a stroke is half a step; and a wall met swimming
is a bank: the player pushes off it as off the ground, a push the water
holds down until the waist is out, where it carries them over the bank.

**Collecting and building** use eight natural counts in `Game`. A break
reads the cell's actual type and credits that slot; a placement debits
the chosen slot. Spending from zero, occupied cells and a placement
anywhere through the player's height are refused without changing either
side, and a block is never placed on the player. A break and a place in
the same tick run in that order, so the new item may fund the placement.
The counts stay on the host: the HUD gets four seven-bit numbers in
`Cam.sel` and four in `Cam.items`, each capped at 100, shown as `99+`.
The hotbar shows the eight blocks, the bucket and the torch, frames the
chosen one, and writes each block's count under its swatch and the full
cells the bucket holds under its own.

**The frame's time.** `F` puts a readout in the frame's corner:
`16.4 MS  60 FPS`. The first number is the `!` alone, the render, as the
bench times it; the second is the frames that reached the screen, which
the display's rate caps, so a render of 5 ms still reads 60 or 120.
`main.bend` runs the window's loop itself, in `App.run`'s shape, to read
the clock on each side of the view and not around the wait for the
screen; twice a second it publishes the mean since, in a word of its own
(`Cam.stat`). The HUD draws it with glyphs of 3 × 5 picked by divisions
and masks (no table, no variable shift).

## The laws

`LAWS.bend` states what the checker can decide: integer and bit rules on
the values the game uses, stated on integer defs since the checker
computes no floats. `bend PROOF.bend` closes them, and `make check` runs
it. Nine hold for every input: for every `U32` clock word the day's phase
returns after a whole turn (by induction over its low 20 bits), the
ripples' too, and with no key held the clock runs as ever; and six of the
inventory's, for every count and every list of actions, among them that a
transfer conserves a cell plus its count. The rest check the exact values
the game uses.

| the laws of | what they say | how many |
|---|---|---|
| the world's words | a cell's word packs and unpacks; a 128×128 window spans the ring's 16384 slots exactly; a break or a place is one bit; a type's nibble reads back without touching its neighbours, the device's read agreeing with the host's; the terrain's layers, trees and lake floors are what they should be; the far map's addresses, columns and sea; the meadow's map and the leaf plane read back | 47 |
| water | generation, displacement and banks; a cell's amount is a byte whose writes read back and whose mask follows; one transfer of the flow; the bucket moves water and never makes it; a solid placed in water shoves it up | 50 |
| water's looks | the surface's packed bits for every step count and face; the ripples' period; each look has its own bit and is on by default | 16 |
| the inventory | conservation for every list of actions; nothing spent from zero; break then place restores; the HUD's packed counts; save and quit survive the step | 13 |
| the clock | the day returns after a turn; `H` runs it 64 times as fast and `G` back no further than the first dawn | 5 |
| the torches | a torch is in neither mask, rides the leaf plane, goes with the block under it and with water; its cell holds light 14 and a column with none holds no light | 8 |
| the readout, the keys, the wheel | the numbers read back and stop at their room; an unknown key sets no bit; the wheel goes around the ten slots | 6 |

The float physics, a player never inside a block or a jump that lands, is
checked by `test/physics.bend`, whose output's hash is fixed; the water's
volume through the flow by the tests in `test/flow.bend`, which sum a
basin over ticks.

## What costs what

**The bench.** `make bench` times the `!` alone, five frames a size with
the camera turning, on an Apple M5 with the game closed; its thirty
checksums are the same on every build that changes nothing visible. The
fastest frames of eight alternated rounds on a busy machine (2026-10-01):

| render | a frame | stock 2.0.34 |
|---|---|---|
| 512×512 | 9 ms | 20 ms |
| 512×512, 300 blocks placed | 8 ms | 19 ms |
| 735×398, a 14" MacBook at scale 2 | 12 ms | 38 ms |
| 960×540, a 1920×1080 window at scale 2 | 22 ms | 72 ms |
| 1470×796, a 14" MacBook at every pixel | 45 ms | 146 ms |
| 1920×1080 | 80 ms | 280 ms |

The difference is [#1132](https://github.com/bendlang/bend/pull/1132) and
our three changes to the compiler ([perf.md](perf.md), 23 to 25).

**The profile.** `make profile` renders a view five times with every look
on, then with each look off in turn, then the rays alone, and prints the
`!` a frame; then it counts, for every pixel, whether its ray reached a
block and how many steps it walked. Its views are the bench's at four
sizes, then at 1470×796 the meadow from the start's hill, night looking at
the moon, the meadow at night with a torch in hand and five on the ground,
the rain of the second morning, the lake in that rain, a lake looking
west, under its water, the night lake with the moon in it, and the lake
with partial water in the window. The least of four rounds on a busy
machine (2026-09-28, before the leaves' holes), ms a frame:

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

The rays alone are a third of a frame. After them come the walks a look
adds, since a DDA step costs about the same wherever it happens, the frame
being its slowest lane: the shadow's 24 steps, the mirror's 32, the
clouds' 16. In the bench's view 49% of the rays reach a block, after 41.4
steps with a sky ray's 60; at the lake 77%, after 31.3. Each later look
was measured alone, against the build before it or with its bit off, at
1470×796 and, after it, at scale 2 (735×398):

- **The meadow** is the dearest look: 18 ms of the bench's view and 4 at
  scale 2, 36 where the view is all meadow, nothing where it is sky; its
  fine walk is most of it, and [perf.md](perf.md) splits it.
- **The leaves' holes** about 6, and 1 at scale 2; **the wind in them** 1
  to 3, and none.
- **The meadow in the water's mirrors** 8 where the lake shows its banks,
  and 2.
- **The clouds** 3 in the bench's view, whose top is sky, and 7 where the
  whole frame is; **their shadow** 1.
- **The rain** about 5 where it rains, and nothing where it does not; **the
  wet** about 3.5 more. **The puddles in the meadow** 5 to 15 more where it
  grows in the rain, and nothing on a dry day ([perf.md](perf.md), 23).
- **Partial water** a sixth more on the lake (34 → 41 ms), three tenths on
  a lake partial everywhere.
- **The lens** up to 3, and none; **the shafts** 8, and 2; **the moon's
  light** costs the night what the sun's costs the day, its shadows and
  its haze: 13 at midnight over the meadow, and 2.
- **The torches**, in the hand, as blocks and their light: within the
  noise. On the host an edit takes 0.18 ms more for its relighting, a
  shift of the window 0.06.
- **The rest** (the fogs, the HUD, the day, the sky's gradient, sun, glow,
  stars and moon, the water's fog, Fresnel, the ripples, the light's
  colour and the halo) are arithmetic on a pixel, within the noise.

`test/trace.py` goes one level down: it patches the emitted C so the
frame's dispatch runs as one command buffer a kernel, and prints each
kernel's time. It reaches into the runtime's text as 2.0.25 wrote it and
does not find 2.0.34's yet.

## Layout

```
main.bend           the window's loop, the elapsed time, the view, the tick
src/frame.bend      the frame's tree, its one `!` and the game's view: all that relies on @unsafe
src/render.bend     the DDA, the sun, the texture, the occlusion, the mirror's walk, a pixel, the sun the eye sees, a tile's shafts
src/world.bend      noise, terrain, the ring, the map, loads, shifts, edits, the far map, the torches' light
src/player.bend     Game, events, picking, physics, the tick
src/flow.bend       the water's flow: marked cells stepped bottom up
src/water.bend      wet intervals, tint, fog, Fresnel, reflected sky, ripples, the rain's rings, the mirror, the caustic
src/sky.bend        the sky's gradient, sun, glow and halo, stars, moon, fogs, the light's colour
src/day.bend        the integer day and the sun's direction, the day run by keys
src/clouds.bend     the clouds' coverage and map, their march, their shadow, the weather
src/rain.bend       the rain's drops in the world
src/wet.bend        how wet the world is, the puddles, their rings, the sheen
src/meadow.bend     the meadow's map: how wild it grows, its flowers, the wind's phase
src/grass.bend      the meadow's blades and flowers, the walks that meet them, the meadow from afar
src/lens.bend       the sun in the camera: the glare and the flare
src/shafts.bend     the sun's light in the haze, from a tile's shafts
src/torch.bend      the torch in the hand and as a block, its light's fall, the day's fade
src/inventory.bend  natural counts, conserved transfers, the HUD's packed counts
src/save.bend       the save file, and the tick that writes it
src/util.bend       conversions, bit tests, smoothstep, a colour mixed, dimmed or lit
LAWS.bend           the rules the checker proves; PROOF.bend closes them
test/lib.bend       what every windowless test needs: expect, ticks, one event, say
test/*.bend         the windowless tests, one file a part: physics, save, inventory, day, water,
                    ripples, mirror, flow, terrain, far, meadow, leaves, torch, light, readout
test/bench.bend     five frames on the GPU with checksums, untouched and built
test/profile.bend   what costs what: each look off in turn, the rays' hits and steps
test/*_view.bend    fixed views for the contact sheets below, with sky.bend
test/trace.py       the frame's dispatch kernel by kernel, from the emitted C
test/page.mjs       the page in headless Chrome: drag, click, place, jump; fps.mjs its fps on N threads
site/               the page: notes.mjs post-processes the built index.html
```

```sh
make check      # the modules, the tests, the laws
make test       # the windowless tests
make bench      # five frames on Metal at six sizes, untouched and with 300 blocks placed
make profile    # each look off, by size; then night, rain, the lake in the rain, lake, submerged, night lake, partial water
make sky        # six views and build/sky-contact.png (Pillow)
make clouds     # twelve views and build/clouds-contact.png (Pillow)
make water      # sixteen views and a ripple animation (Pillow)
make flow       # the lake breached into a pit, filling and settled (Pillow)
make flow-bench # a lake draining through shafts: ms a tick on the host
make mirror     # four views, the mirror on and off (Pillow)
```

The page, the game in the browser on every core as WebAssembly, is built
with the web target of Bend from
[bendlang/bend#866](https://github.com/bendlang/bend/pull/866), a checkout
of that branch at `../bend-web` (`make page`, `make page-test` in headless
Chrome). It is not ready until it runs on WebGPU.
