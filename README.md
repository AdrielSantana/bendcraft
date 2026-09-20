# Bendcraft

An endless voxel world you can walk, jump, break and build, written in
[Bend](https://github.com/bendlang/bend) and rendered by one parallel call:
on the GPU through Metal, or on every core of your machine as WebAssembly.

**Play it in the browser:** https://adrielsantana.github.io/bendcraft/

`W A S D` walk · `space` jumps · drag the mouse to look (or the arrows) ·
click breaks · right click places (or `J` / `L`) · `1`–`8` choose the block
to place (grass, dirt, stone, sand, wood, leaves, brick, snow) · `Esc` quits.

![Bendcraft](site/bendcraft.png)

## Build and run

Bend 2.0.22 or later (`bend update`). On a Mac with Metal:

```sh
make            # bend main.bend -o build/bendcraft
make run        # ./build/bendcraft --gpu 2GB
```

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
columns around the player live in an `Array<U32>`: eight words a column,
the first a mask whose bit `y` says "there is a block at height `y`", the
next four the types of its 32 blocks, four bits each. A ray reads the mask
through its handle once per column it crosses and the type once, at the
hit; an edit is a few `Array.set` on the host; a built world costs what an
untouched one does. Thirty-two heights in one word is what makes it cheap:
the ray sees a column as a machine word, and break or place is one bit.

**The world is endless.** The terrain is seeded value noise, three octaves,
a pure function of `(x, z)`: grass on top, sand where it is low and snow
where it is high, three of dirt under the top, stone below. About one grass
column in eighty grows a tree, a trunk of four wood with a canopy of leaves
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
loop returns only what was hit and where; the look is a `match` after it:
a second DDA toward the sun for shadows, a pixel-art tile of four shades per
face, ambient occlusion per vertex from the eight cells around the hit, fog
into the sky by distance. The `!` runs a 4^7 tree of 4×4 tiles, 512×512.

**The player** is 1.8 blocks tall with the eye at 1.6. Walking tests the
feet and the head per axis and stops at walls; gravity pulls, landing snaps
the feet onto the block, space pushes off it. A block is never placed on
the player. The hotbar along the bottom shows the eight block types and
frames the chosen one.

## Layout

```
main.bend          App.run: the window, the view, the tick
src/util.bend      conversions, bit tests, smoothstep
src/world.bend     noise, terrain, the ring, the map, loads, shifts, edits, solid
src/render.bend    the DDA, the sun, the texture, the occlusion, the fork
src/player.bend    Game, events, picking, the tick
LAWS.bend          the rules the checker proves; PROOF.bend closes them
test/physics.bend  the game without a window: events through feed and step
test/bench.bend    five frames on the GPU with checksums, untouched and built
test/terrain.bend  rows of the terrain, to see the noise
test/page.mjs      the page in headless Chrome: drag, click, place, jump
test/fps.mjs       the page's fps on N threads
site/              the page: notes.mjs post-processes the built index.html
```

```sh
make check      # the modules, the tests, the laws
make test       # physics and terrain, windowless
make bench      # five frames on Metal, untouched and with 300 blocks placed
make page-test  # the page in headless Chrome, hashes and fps
```

## Numbers

Apple M5, 512×512, Bend 2.0.22. The bench times the `!` only, five frames
with the camera turning; the ten checksums are the same on every build that
changes nothing visible.

| | untouched | 300 blocks placed |
|---|---|---|
| Metal | 3–8 ms a frame | 3–8 ms |
| WebAssembly, 10 threads | 35–40 fps | |
| WebAssembly, 1 thread | 8 fps | |

## Laws

`LAWS.bend` states what the checker can decide: integer and bit rules on the
values the game uses. The pick word packs and unpacks; a 128×128 window of
the ring spans its 16384 column slots exactly; placing sets one bit,
breaking clears it, breaking air changes nothing; a type's nibble writes
and reads back without touching its neighbours, and the device's read (a
select, since the GPU never shifts by a variable) agrees with the host's;
the terrain's layers are what they should be, a trunk packs as wood with
leaves over it and grass under it, and the packed word the loader writes
reads back the same; no key touches the mouse's bits of the held mask.
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
[#921](https://github.com/bendlang/bend/issues/921), a way to grab the mouse.

Written by Claude (Anthropic) with Adriel Santana.
