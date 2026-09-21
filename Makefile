# Bendcraft. `make` builds the native game; `make run` starts it on the GPU.
BEND ?= bend
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

# the checker: the modules, the tests and the laws
check:
	$(BEND) main.bend --check-only
	$(BEND) test/physics.bend --check-only
	$(BEND) test/terrain.bend --check-only
	$(BEND) test/save.bend --check-only
	$(BEND) test/day.bend --check-only
	$(BEND) test/inventory.bend --check-only
	$(BEND) test/water.bend --check-only
	$(BEND) test/water_view.bend --check-only
	$(BEND) test/sky.bend --check-only
	$(BEND) test/bench.bend --check-only
	$(BEND) test/profile.bend --check-only
	$(BEND) test/readout.bend --check-only
	$(BEND) PROOF.bend

# the game without a window: events through feed and step
test:
	@mkdir -p build
	$(BEND) test/physics.bend
	$(BEND) test/save.bend
	$(BEND) test/day.bend
	$(BEND) test/inventory.bend
	$(BEND) test/water.bend
	$(BEND) test/terrain.bend
	$(BEND) test/readout.bend

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

# Inspect the lake, water-off, dusk and submerged views (Pillow).
water: test/water_view.bend test/profile.bend test/sky.bend src/*.bend
	@mkdir -p build
	$(BEND) test/water_view.bend -o build/water-view
	./build/water-view
	$(PYTHON) test/water.py

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
page-test:
	cd site && python3 ../test/serve.py 8770 & sleep 1; \
	node test/page.mjs 'http://127.0.0.1:8770/index.html?threads=10' build/shot_; \
	node test/fps.mjs 'http://127.0.0.1:8770/index.html?threads=1' 8; \
	kill %1

.PHONY: run full check test bench profile sky water page publish page-test
