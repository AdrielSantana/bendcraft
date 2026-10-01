# Bendcraft. `make` builds the native game; `make run` starts it on the GPU.
# Bend 2.0.34 with bendlang/bend#1132 and three changes of ours, until they
# are released (docs/roadmap.md, "Bend: waiting on a decision"); the third is
# --relaxed-math, Metal's floats reordered and fused:
# git clone -b bendcraft https://github.com/AdrielSantana/bend ../bend
BEND ?= bun ../bend/bend2/main.ts --relaxed-math
PYTHON ?= python3
# the web-wasm fork of the compiler (bendlang/bend#866), for the page
BEND_WEB ?= ../bend-web/bend2/main.ts

build/bendcraft: main.bend src/*.bend
	@mkdir -p build
	$(BEND) main.bend -o build/bendcraft

# make run SIZE="1470 796 2" for a window of that size in points, half as
# many rays a side; make full asks the screen for its visible size (in
# points: a Retina screen has twice the pixels) and takes the title bar off
SIZE ?=
run: build/bendcraft
	./build/bendcraft --gpu 2GB $(SIZE)

SCALE ?= 2
full: build/bendcraft
	./build/bendcraft --gpu 2GB $$(swift -e 'import AppKit; let f = NSScreen.main!.visibleFrame; print(Int(f.width), Int(f.height) - 28)') $(SCALE)

# the checker: the modules, the tests and the laws. A program relies on
# @unsafe (Render.frame shares the ring with the GPU), so its verdict is
# SOME PROOFS FAIL by design and a type error is anything else; the laws'
# verdict must be ALL PROOFS CHECK
check:
	@for f in main.bend test/*.bend; do \
	  out=$$($(BEND) $$f --check-only 2>&1) || echo "$$out" | grep -q 'on unsafe or foreign code:$$' \
	    || { echo "$$f: $$out"; exit 1; }; \
	done
	$(BEND) PROOF.bend

TESTS = physics save day inventory water flow ripples mirror terrain readout far meadow leaves torch light

# the game without a window: events through feed and step
test:
	@mkdir -p build
	@for t in $(TESTS); do $(BEND) test/$$t.bend || exit 1; done

# the same tests built to C, the path the game's host runs on: each prints
# the lines it prints above, since a compiler can be right in one backend
# and wrong in the other. The `!` runs on the cores: the GPU's frame is the
# bench's digest
test-native:
	@mkdir -p build/native
	@for t in $(TESTS); do \
	  $(BEND) test/$$t.bend -o build/native/$$t || exit 1; \
	  ./build/native/$$t --gpu off > build/native/$$t.out 2>&1; \
	  $(BEND) test/$$t.bend 2>&1 | cmp -s - build/native/$$t.out \
	    || { echo "test/$$t.bend: the native build prints other lines"; exit 1; }; \
	  echo "ok test/$$t.bend, native"; \
	done

# five frames on the GPU, untouched and with 300 blocks placed, with checksums
bench: test/bench.bend src/*.bend
	@mkdir -p build
	$(BEND) test/bench.bend -o build/bench
	./build/bench

# the profile: a view rendered with each look off in turn, the rays alone,
# and the rays' hits and steps, per size; what costs what
profile: test/profile.bend src/*.bend
	@mkdir -p build
	$(BEND) test/profile.bend -o build/profile
	./build/profile

# Inspect dawn, morning, noon, dusk, night and the default frame (Pillow).
sky: test/sky.bend src/*.bend
	@mkdir -p build
	$(BEND) test/sky.bend -o build/sky
	./build/sky
	$(PYTHON) test/sky.py

# the clouds by day, at sunset, overhead and at night, and the ground under
# their shadows, each look off beside it (Pillow)
clouds: test/clouds_view.bend test/sky.bend src/*.bend
	@mkdir -p build
	$(BEND) test/clouds_view.bend -o build/clouds-view
	./build/clouds-view
	$(PYTHON) test/clouds.py

# the water's mirror on and off, four views, as a sheet of PNGs (Pillow)
mirror: test/mirror_view.bend test/profile.bend test/sky.bend src/*.bend
	@mkdir -p build
	$(BEND) test/mirror_view.bend -o build/mirror-view
	./build/mirror-view
	$(PYTHON) test/mirror.py

# Inspect the lake, surface flags, submerged views and reflected sky (Pillow).
water: test/water_view.bend test/profile.bend test/sky.bend src/*.bend
	@mkdir -p build
	$(BEND) test/water_view.bend -o build/water-view
	./build/water-view
	$(PYTHON) test/water.py

# the flow: the lake breached into a pit, filling and settled, and a
# partial cell from the side (Pillow)
flow: test/flow_view.bend test/sky.bend src/*.bend
	@mkdir -p build
	$(BEND) test/flow_view.bend -o build/flow-view
	./build/flow-view
	$(PYTHON) test/flow.py

# the flow's cost on the host: a lake draining through shafts, ms a tick
flow-bench: test/flow_bench.bend src/*.bend
	@mkdir -p build
	$(BEND) test/flow_bench.bend -o build/flow_bench
	./build/flow_bench

# the page: WebAssembly, a worker a core, the service worker for the headers
page: main.bend src/*.bend
	bun $(BEND_WEB) main.bend -o site/index.html
	node site/notes.mjs site/index.html

# the page onto the gh-pages branch (a worktree under build/)
publish: page
	@test -d build/ghp || git worktree add build/ghp gh-pages
	cp site/index.html site/index.js site/index.wasm site/coi-serviceworker.js build/ghp/
	cd build/ghp && git add -A && git commit -q -m "page: $$(git -C ../.. log --format=%s -1)" && git push -q origin gh-pages

# the page in headless Chrome: drag, click, place, jump; hashes and fps
# (make's shell has no job control, so the server is stopped by its pid)
page-test:
	(cd site && exec python3 ../test/serve.py 8770) & echo $$! > build/serve.pid; sleep 1; \
	node test/page.mjs 'http://127.0.0.1:8770/index.html?threads=10' build/shot_; \
	node test/fps.mjs 'http://127.0.0.1:8770/index.html?threads=1' 8; \
	kill $$(cat build/serve.pid); rm -f build/serve.pid

.PHONY: mirror run full check test test-native bench profile sky clouds water page publish page-test
