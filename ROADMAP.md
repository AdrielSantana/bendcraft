# Roadmap

Written on 2026-09-21. Three tracks: the game, the engine under it, and the
Bend compiler, where some steps wait on a decision that is not ours. The
rule that ties them: the game goes on whatever upstream decides, and every
step that touches the frame leaves a line in `make profile`.

## The game

In this order. None of them needs anything from upstream.

1. **Collecting and an inventory.** Today the hotbar's eight blocks are
   endless. Breaking a block gives one of it, placing spends one, the HUD
   shows the count, the save file keeps the counts. Laws to write: a count
   never goes under zero; break then place gives the world and the counts
   back. Costs nothing in the frame but the HUD's digits.
2. **Water.** A block type a ray goes through: the ray keeps walking past
   the surface and the hit behind is tinted by the depth it crossed. Still
   water first, in the terrain below a sea level. Flow is a later step, a
   cellular rule over the edits' Map, a tick at a time. This one touches
   the DDA, so it gets a flag and a profile line from the first commit.
3. **A day cycle.** The sun's direction from the clock, the sky's colour
   with it, night. The shadow ray is written for one sun, (0.48, 0.80,
   0.36), all components positive, so every step is +1; a moving sun needs
   the signed step the primary ray has. The direction goes in `Cam`. Expect
   the shadow's 2.4 ms to grow a little; measure before and after.

Candidates after these, not decided: caves in the noise, a second biome,
sounds when Bend has a way to make them, something that moves.

## The engine

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

- *Render distance.* The ring is 128² columns and a ray walks 60 steps.
  More distance is more steps for every ray, linearly. The engine answer
  is to skip empty space: a coarse level over the columns (the highest
  block of each 4×4 group), so a ray above it crosses four columns in one
  step. Measure the step count with flag 32 first; it only pays if most
  steps are over open ground.
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
