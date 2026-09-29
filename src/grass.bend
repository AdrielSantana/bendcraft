import Base
import ./util.bend as Util
import ./sky.bend as Sky
import ./clouds.bend as Clouds
import ./meadow.bend as Meadow
import ./world.bend as World

# THE MEADOW: a carpet of tall grass on the grass tops, a ray meeting
# its blades on three walks over grids of cells: a fine one near, four
# cells a block with up to six blades each (three wider ones from 4
# blocks), gone by 12 blocks; a coarse one from 10 blocks, two cells a
# block with three blades wider still, gone by 22; and a broad one from
# 20 to 40, a cell a block with six. The blades are tapered stalks rooted
# anywhere in their cell, each leaning its own way, their tips bent by
# the wind; now and then a flower, a cup of five petals on a stem above
# them. Every blade stays inside its cell and under top() over its
# floor, so a ray that crosses the cell meets all of it, from any side.
# A walk crosses the cells from where the ray first came over a floor
# (the render's rim) to what it met, following the floor under it as it
# climbs or falls; it meets each blade where it passes it nearest, its
# edge as soft as the pixel is wide, and stops once it sees no more. A
# block column's patch, from the meadow's map (src/meadow.bend), says
# whether its floor is grass and how tall and thick its blades grow, the
# wind's push, how often they flower and in what colour. Under the
# blades and past them a grass top is the meadow seen from afar, and
# near, the shade at the blades' feet.

# a pixel's width a unit of distance at 796 pixels high
def pixel() -> F32: 0.0023

# how high over its floor the grass reaches at most: its tallest patch's
# blades and flowers (patch_grass, near_cell)
def top() -> F32: 0.6

def way4(+k: U32, +a: F32, +b: F32, +c: F32, +d: F32) -> F32:
  Bool.pick(F32, (k < 2 : U32), Bool.pick(F32, U32.is_eq(k, 0), a, b), Bool.pick(F32, U32.is_eq(k, 2), c, d))

# the share of a byte of 255, and of a nibble of 15
def byte(+b: U32) -> F32:
  (U32.to_f32((b % 256 : U32)) * 0.0039216 : F32)

def nib(+b: U32) -> F32:
  (U32.to_f32((b % 16 : U32)) * 0.0666667 : F32)

# how much of a pixel whose middle is d from a blade's axis a blade
# w wide either side covers: no more than its width when it is thinner
def cover(+w: F32, +d: F32, +ifp: F32) -> F32:
  F32.clamp(F32.min(((w - d) * ifp + 0.5 : F32), (2.0 * w * ifp : F32)), 0.0, 1.0)

# What the ray met of a cell: how much of the pixel (a), and summed over
# its blades by their shares, the shares (n), their light, how far up
# they were met, the flower's head and the heart in it, and how far
# along the ray.
type Tuft is Data:
  Tuft{a: F32, n: F32, lit: F32, s: F32, head: F32, heart: F32, t: F32}

def none() -> Tuft: Tuft{0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0}

def both(p: Tuft, q: Tuft) -> Tuft:
  Tuft{+a, +n, +lit, +s, +head, +heart, +t} = p
  Tuft{+b, +m, +lit2, +s2, +head2, +heart2, +t2} = q
  Tuft{(a + b - a * b : F32), (n + m : F32), (lit + lit2 : F32), (s + s2 : F32), (head + head2 : F32), (heart + heart2 : F32), (t + t2 : F32)}

# A blade (where on): rooted at (rx, rz) on the floor at y, ih its height's
# inverse, its tip (tx, tz) off its root; its middle bends towards the
# tip as it rises, faster near the top, and it narrows from wf times 0.056
# thick to its tip, darker down in the grass. The ray passes the root's upright
# nearest at tn (qh and qr: the inverse of its rate over the ground,
# squared and not), and the blade a little along from there, tm, where it
# passes the height it met at tn bent.
def blade(+on: Bool, +rx: F32, +rz: F32, +y: F32, +ih: F32, +tx: F32, +tz: F32, +lit: F32, +wf: F32,
          +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, +t1: F32, +ifp: F32, +qh: F32, +qr: F32) -> Tuft:
  +vx = (rx - ox : F32)
  +vz = (rz - oz : F32)
  +tn = ((vx * dx + vz * dz) * qh : F32)
  +e0 = F32.clamp(((oy + dy * tn - y) * ih : F32), 0.0, 1.0)
  +tm = (tn + (tx * dx + tz * dz) * e0 * (0.4 + 0.6 * e0) * qh : F32)
  +e = ((oy + dy * tm - y) * ih : F32)
  +ec = F32.clamp(e, 0.0, 1.0)
  +s = (ec * (0.4 + 0.6 * ec) : F32)
  +a = Bool.pick(F32, on && (tm > 0.0 : F32) && (tm < t1 : F32) && (e >= 0.0 : F32) && (e <= 1.0 : F32),
    cover(((0.026 * (1.0 - e) + 0.002) * wf : F32), (Util.absf(((vx + tx * s) * dz - (vz + tz * s) * dx : F32)) * qr : F32), ifp), 0.0)
  Tuft{a, a, (a * lit * (0.3 + 0.7 * ec * (0.6 + 0.4 * ec)) : F32), (a * ec : F32), 0.0, 0.0, (a * tm : F32)}

# The wind's strength over x of the world, 0.2 to 1: its gusts are waves
# it blows along x, 3 blocks a second, their fronts bent by zphase.
def gusting(+xw: F32, +ck: U32, +zphase: F32) -> F32:
  +gust = (0.5 + 0.5 * F32.sin(((xw - U32.to_f32((ck % 85333 : U32)) * 0.003) * 0.7 + zphase : F32)) : F32)
  (0.2 + 0.8 * gust * gust : F32)

# how far a gust pushes, 0.65 to 1.35 of its strength: a quiver back and
# forth every second and a half, at a phase of 0 to 1
def quiver(+ck: U32, +phase: F32) -> F32:
  (0.65 + 1.4 * Util.absf((Util.fracf((U32.to_f32((ck % 1571 : U32)) * 0.00063654 + phase : F32)) - 0.5 : F32)) : F32)

# The blade hashed b of the cell whose corner is (x, z), on the floor at
# y: there where bits 26..31 fall under the patch's thickness; from 0.6
# to 1.2 of the patch's height (tall, its inverse itall; bits 8..9), up to
# 0.2 of its height off upright each way (10..17), rooted anywhere in
# the cell, sz wide, (0..7) that leaves its tip in it; the wind pushes
# its tip along x, quivering back and forth every second and a half at
# its own phase (18..21), no further than the cell's side, and never its
# root. Bits 22..25 make it brighter or darker; wf times as wide.
def stalk(+b: U32, +wf: F32, +sz: F32, +x: F32, +z: F32, +y: F32, +tall: F32, +itall: F32, +dense: F32, +wind: F32, +ck: U32,
          +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, +t1: F32, +ifp: F32, +qh: F32, +qr: F32) -> Tuft:
  +v = (b / 256 % 4 : U32)
  +h = (tall * way4(v, 0.6, 0.8, 1.0, 1.2) : F32)
  +lx = ((nib((b / 1024 : U32)) - 0.5) * 0.4 * h : F32)
  +lz = ((nib((b / 16384 : U32)) - 0.5) * 0.4 * h : F32)
  +rx = (x + 0.06 * sz + F32.max((0.0 - lx : F32), 0.0) + (0.88 * sz - Util.absf(lx)) * nib(b) : F32)
  +rz = (z + 0.06 * sz + F32.max((0.0 - lz : F32), 0.0) + (0.88 * sz - Util.absf(lz)) * nib((b / 16 : U32)) : F32)
  +push = (wind * quiver(ck, nib((b / 262144 : U32))) : F32)
  blade((U32.to_f32((b / 67108864 : U32)) * 0.015625 < dense : F32), rx, rz, y, (itall * way4(v, 1.6666667, 1.25, 1.0, 0.8333333) : F32),
    (F32.min((rx + lx + push : F32), (x + 0.96 * sz : F32)) - rx : F32), lz, (0.85 + 0.3 * nib((b / 4194304 : U32)) : F32), wf,
    ox, oy, oz, dx, dy, dz, t1, ifp, qh, qr)

# The flower's head is a cup, its petals rising from the heart along a
# cone 0.7 up for 1 out, tilted with its axis n; the ray meets the cone
# where it is (q0 + d t) . n = 0.7 |q0 + d t - ((q0 + d t) . n) n| over
# the heart, q0 the eye off it: a quadratic whose roots are the near
# and the far wall (real, when it has them). At a root t, z up the axis
# (before t1): how much of the pixel the petal there covers, five petals
# turned by (ca, sa), their edge as soft as the pixel is wide across the
# cup (ifp); and how much its heart covers, the cup's bottom.
def cup(+real: Bool, +t: F32, +t1: F32, +z: F32, +ux: F32, +uz: F32, +dx: F32, +dz: F32, +nx: F32, +nz: F32, +ca: F32, +sa: F32, +ifp: F32) -> F32:
  +r = (z * 1.4285714 : F32)
  +q = F32.clamp((((ux + dx * t - z * nx) * ca - (uz + dz * t - z * nz) * sa) / F32.max(r, 0.00001) : F32), (0.0 - 1.0 : F32), 1.0)
  +q2 = (q * q : F32)
  +edge = (0.055 * (0.775 + 0.225 * q * (16.0 * q2 * q2 - 20.0 * q2 + 5.0)) : F32)
  Bool.pick(F32, real && (t > 0.0 : F32) && (t < t1 : F32) && (z >= 0.0 : F32), F32.clamp(((edge - r) * ifp + 0.5 : F32), 0.0, 1.0), 0.0)

def heart_at(+real: Bool, +t: F32, +t1: F32, +z: F32, +ifp: F32) -> F32:
  Bool.pick(F32, real && (t > 0.0 : F32) && (t < t1 : F32) && (z >= 0.0 : F32), F32.clamp(((0.017 - z * 1.4285714) * ifp + 0.5 : F32), 0.0, 1.0), 0.0)

# a flower (where on) in the cell hashed c, sz wide, whose corner is
# (x, z), somewhere in its middle (bits 16..23): a stem up from the floor
# at y to 1.1 of the grass's height (tall), where the ray passes nearest
# over the ground, and its cup there, tilted its own way (24..31) and
# turned its own way (a second hash)
def flower(on: Bool, +c: U32, +sz: F32, +x: F32, +z: F32, +y: F32, +tall: F32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
           +t1: F32, +ifp: F32, +qh: F32, +qr: F32) -> Tuft:
  match on:
    case False{}:
      none()
    case True{}:
      +vx = (x + (0.24 + 0.52 * nib((c / 65536 : U32))) * sz - ox : F32)
      +vz = (z + (0.24 + 0.52 * nib((c / 1048576 : U32))) * sz - oz : F32)
      +top = (tall * 1.1 + 0.03 : F32)
      +tn = ((vx * dx + vz * dz) * qh : F32)
      +hn = (oy + dy * tn - y : F32)
      +vy = (y + top - oy : F32)
      +a = ((nib((c / 16777216 : U32)) - 0.5) * 1.2 : F32)
      +b = ((nib((c / 268435456 : U32)) - 0.5) * 1.2 : F32)
      +il = (1.0 / F32.sqrt((a * a + 1.0 + b * b : F32)) : F32)
      +nx = (a * il : F32)
      +nz = (b * il : F32)
      +na = (dx * nx + dy * il + dz * nz : F32)
      +nb = (0.0 - (vx * nx + vy * il + vz * nz) : F32)
      +tc = (vx * dx + vy * dy + vz * dz : F32)
      +qa = (1.49 * na * na - 0.49 : F32)
      +qb = (1.49 * na * nb + 0.49 * tc : F32)
      +disc = (qb * qb - qa * (1.49 * nb * nb - 0.49 * (vx * vx + vy * vy + vz * vz)) : F32)
      +sq = F32.sqrt(F32.max(disc, 0.0))
      +iq = (1.0 / Bool.pick(F32, (Util.absf(qa) > 0.0001 : F32), qa, 0.0001) : F32)
      +ta = ((0.0 - qb - sq) * iq : F32)
      +tb = ((sq - qb) * iq : F32)
      +real = (disc >= 0.0 : F32)
      +turn = (byte(Sky.star_hash(c, 7)) * 6.2831853 : F32)
      +ca = F32.cos(turn)
      +sa = F32.sin(turn)
      +fi = (ifp * F32.max(Util.absf(na), 0.35) : F32)
      +pa = cup(real, ta, t1, (nb + na * ta : F32), (0.0 - vx : F32), (0.0 - vz : F32), dx, dz, nx, nz, ca, sa, fi)
      +pb = cup(real, tb, t1, (nb + na * tb : F32), (0.0 - vx : F32), (0.0 - vz : F32), dx, dz, nx, nz, ca, sa, fi)
      +head = (pa + pb - pa * pb : F32)
      +a = F32.max(head, Bool.pick(F32, (tn > 0.0 : F32) && (tn < t1 : F32) && (hn >= 0.0 : F32) && (hn <= top : F32),
        cover(0.003, (Util.absf((vx * dz - vz * dx : F32)) * qr : F32), ifp), 0.0))
      Tuft{a, a, (a * 0.9 : F32), a, head, F32.max(heart_at(real, ta, t1, (nb + na * ta : F32), fi), heart_at(real, tb, t1, (nb + na * tb : F32), fi)),
        (a * tc : F32)}

# the cell's blades 4 to 6, wf times as wide (where on)
def rest(on: Bool, +c: U32, +wf: F32, +sz: F32, +x: F32, +z: F32, +y: F32, +tall: F32, +itall: F32, +dense: F32, +wind: F32, +ck: U32,
         +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, +t1: F32, +ifp: F32, +qh: F32, +qr: F32) -> Tuft:
  match on:
    case False{}:
      none()
    case True{}:
      both(stalk(Sky.star_hash(c, 4), wf, sz, x, z, y, tall, itall, dense, wind, ck, ox, oy, oz, dx, dy, dz, t1, ifp, qh, qr),
           both(stalk(Sky.star_hash(c, 5), wf, sz, x, z, y, tall, itall, dense, wind, ck, ox, oy, oz, dx, dy, dz, t1, ifp, qh, qr),
                stalk(Sky.star_hash(c, 6), wf, sz, x, z, y, tall, itall, dense, wind, ck, ox, oy, oz, dx, dy, dz, t1, ifp, qh, qr)))

# the hash of the window's cell (i, j), per of them a block, by its
# place in the world's 256 blocks (fm, the far map's corner) and a seed
def cell(+fm: U32, +per: F32, +seed: U32, +i: F32, +j: F32) -> U32:
  +m = Util.f2u((256.0 * per : F32))
  Sky.star_hash((Util.f2u((Clouds.corner_x(fm) * per + i : F32)) % m + seed : U32), (Util.f2u((Clouds.corner_z(fm) * per + j : F32)) % m : U32))

# The window's cell (i, j), sz wide, whose corner is (x, z), on the floor
# at y (where on: a grass floor the ray passes low and near enough),
# hashed only then (cell): its six
# blades wm times as wide, and a flower where bits 8..15 fall under the
# patch's rate, somewhere in its middle (16..23). As q goes from 0 to 1
# three of the blades thin away as the other three widen to 1.6 times,
# and past that the ray meets those three alone.
def blades(on: Bool, +fm: U32, +per: F32, +seed: U32, +i: F32, +j: F32, +q: F32, +wm: F32, +sz: F32, +x: F32, +z: F32, +y: F32, +tall: F32, +itall: F32, +dense: F32, +wind: F32, +rate: F32, +ck: U32,
           +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, +t1: F32, +ifp: F32, +qh: F32, +qr: F32) -> Tuft:
  match on:
    case False{}:
      none()
    case True{}:
      +c = cell(fm, per, seed, i, j)
      +wf = (wm * (1.0 + 0.6 * q) : F32)
      both(both(stalk(Sky.star_hash(c, 1), wf, sz, x, z, y, tall, itall, dense, wind, ck, ox, oy, oz, dx, dy, dz, t1, ifp, qh, qr),
                stalk(Sky.star_hash(c, 2), wf, sz, x, z, y, tall, itall, dense, wind, ck, ox, oy, oz, dx, dy, dz, t1, ifp, qh, qr)),
           both(stalk(Sky.star_hash(c, 3), wf, sz, x, z, y, tall, itall, dense, wind, ck, ox, oy, oz, dx, dy, dz, t1, ifp, qh, qr),
                both(rest((q < 1.0 : F32), c, (wm * (1.0 - q) : F32), sz, x, z, y, tall, itall, dense, wind, ck, ox, oy, oz, dx, dy, dz, t1, ifp, qh, qr),
                  flower((byte((c / 256 : U32)) < rate : F32), c, sz, x, z, y, tall, ox, oy, oz, dx, dy, dz, t1, ifp, qh, qr))))

# whether the ray passes the cell whose middle is (x, z), anywhere in it
# (reach from the middle), while as low as its grass grows (top) over the
# floor at y, before t1: where it passes the middle nearest over the
# ground, give or take the rise of the ray over the reach
def near_cell(+x: F32, +z: F32, +reach: F32, +y: F32, +top: F32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, +t1: F32, +qh: F32, +qr: F32) -> Bool:
  +vx = (x - ox : F32)
  +vz = (z - oz : F32)
  +tn = ((vx * dx + vz * dz) * qh : F32)
  +hn = (oy + dy * tn - y : F32)
  +m = (reach * Util.absf(dy) * qr : F32)
  (Util.absf((vx * dz - vz * dx : F32)) * qr < reach : F32) && (hn > (0.0 - m : F32) : F32) && (hn < (top + m : F32) : F32)
    && ((tn - reach * qr : F32) < t1 : F32)

# 2 to the n, n under 32, exactly and without a shift
def pow2(+n: U32) -> U32:
  (Bool.pick(U32, Util.on(n, 1), 2, 1) * Bool.pick(U32, Util.on(n, 2), 4, 1) * Bool.pick(U32, Util.on(n, 4), 16, 1)
    * Bool.pick(U32, Util.on(n, 8), 256, 1) * Bool.pick(U32, Util.on(n, 16), 65536, 1) : U32)

# whether a column's block at y - 1 is solid and its cell at y air
def floor_top(+mask: U32, +y: F32) -> Bool:
  U32.is_eq((mask / pow2(Util.f2u((y - 1.0 : F32))) % 4 : U32), 1)

def daisy() -> U32: Util.rgb(236, 236, 226)

# the flowers: dandelion, daisy, poppy, cornflower, clover
def bloom(+kind: U32) -> U32:
  Bool.pick(U32, (kind < 2 : U32), Bool.pick(U32, U32.is_eq(kind, 0), Util.rgb(240, 196, 38), daisy()),
    Bool.pick(U32, U32.is_eq(kind, 2), Util.rgb(200, 38, 34), Bool.pick(U32, U32.is_eq(kind, 3), Util.rgb(78, 112, 222), Util.rgb(150, 82, 192))))

# a flower's heart: golden in the white ones, a dark shade of the petals
# in the others
def eye(+hue: U32) -> U32:
  Bool.pick(U32, U32.is_eq(hue, daisy()), Util.rgb(236, 180, 36), Util.dim(hue, 0.5))

# A block column's patch of the meadow: the floor y when it is a grass
# top there (else under 0), its blades' height and its inverse, the share
# of them that grow, the wind's push at their tips, how often a cell
# flowers and in what colour; and the pixel's inverse width where the ray
# came over it. How wild the meadow grows at the column makes the grass
# taller and thicker, or shorter and thinner, and the short grass
# flowers, each 8 by 8 blocks in one colour.
type Patch is Data:
  Patch{y: F32, tall: F32, itall: F32, dense: F32, wind: F32, rate: F32, hue: U32, ifp: F32}

def patch_word(+y: F32, +xw: F32, +ck: U32, +ifp: F32, r: Array<U32> & U32) -> Array<U32> & Patch:
  (w, +word) = r
  +wild = byte(word)
  +tall = (0.25 + 0.17 * wild : F32)
  (w, Patch{y, tall, (1.0 / tall : F32), F32.clamp((0.6 + wild : F32), 0.0, 1.0), (gusting(xw, ck, ((byte(Meadow.phase(word)) - 0.5) * 3.4 : F32)) * 0.07 : F32),
    (F32.clamp(((0.45 - wild) * 3.0 : F32), 0.0, 1.0) * 0.04 : F32), bloom(Meadow.flower(word)), ifp})

def patch_grass(grass: Bool, +bx: F32, +bz: F32, +y: F32, +fm: U32, +ck: U32, +ifp: F32, w: Array<U32>) -> Array<U32> & Patch:
  match grass:
    case False{}:
      (w, Patch{(0.0 - 1.0 : F32), 0.0, 0.0, 0.0, 0.0, 0.0, 0, ifp})
    case True{}:
      +xw = (bx + Clouds.corner_x(fm) : F32)
      patch_word(y, (xw + 0.5 : F32), ck, ifp,
        Array.get(U32, w, Meadow.map_at(Util.f2u(xw), Util.f2u((bz + Clouds.corner_z(fm) : F32)))))

def patch_type(+mask: U32, +bx: F32, +bz: F32, +y: F32, +fm: U32, +ck: U32, +ifp: F32, r: Array<U32> & U32) -> Array<U32> & Patch:
  (w, +word) = r
  patch_grass(floor_top(mask, y) && U32.is_eq(World.nib_at(word, Util.f2u((y - 1.0 : F32))), 0), bx, bz, y, fm, ck, ifp, w)

def patch_mask(+base: U32, +bx: F32, +bz: F32, +y: F32, +fm: U32, +ck: U32, +ifp: F32, r: Array<U32> & U32) -> Array<U32> & Patch:
  (w, +mask) = r
  patch_type(mask, bx, bz, y, fm, ck, ifp,
    Array.get(U32, w, (World.col_at(base, Util.f2u(bx), Util.f2u(bz)) + 1 + Util.f2u((y - 1.0 : F32)) / 8 : U32)))

# the patch of the block column (bx, bz) over its floor at y, where the
# ray comes over it t from the eye
def patch(w: Array<U32>, +base: U32, +bx: F32, +bz: F32, +y: F32, +fm: U32, +ck: U32, +t: F32) -> Array<U32> & Patch:
  patch_mask(base, bx, bz, y, fm, ck, (1.0 / ((t + 0.3) * pixel()) : F32), Array.get(U32, w, World.col_at(base, Util.f2u(bx), Util.f2u(bz))))

def refetch(moved: Bool, w: Array<U32>, +base: U32, +bx: F32, +bz: F32, +y: F32, +fm: U32, +ck: U32, +t: F32, +p: Patch) -> Array<U32> & Patch:
  match moved:
    case False{}:
      (w, p)
    case True{}:
      patch(w, base, bx, bz, y, fm, ck, t)

# How finely a walk meets the grass: cells sz blocks wide, per of them a
# block, hashed with seed; blades wm times as
# wide, three of them alone from q0 blocks and 2 more; seen from fi
# blocks, in over 2, and gone from fo, over 1 / fk.
type Level is Data:
  Level{sz: F32, per: F32, seed: U32, wm: F32, q0: F32, fi: F32, fo: F32, fk: F32}

def fine() -> Level:
  Level{0.25, 4.0, 40009, 1.0, 4.0, (0.0 - 100.0 : F32), 10.0, 0.5}

def coarse() -> Level:
  Level{0.5, 2.0, 60013, 2.5, (0.0 - 100.0 : F32), 10.0, 20.0, 0.5}

def broad() -> Level:
  Level{1.0, 1.0, 80021, 8.0, 100.0, 20.0, 34.0, 0.1666667}

# What the ray saw of the grass: what it still sees through (tr); summed
# by how much of each blade it saw, their shares, light, height up the
# blade, the flowers' heads and how far along the ray; the colour of the
# first flower; and how much of the floor the ray met is the grass's
# shade (low).
type Meadow is Data:
  Meadow{tr: F32, n: F32, lit: F32, s: F32, head: F32, heart: F32, t: F32, hue: U32, low: F32}

def walk_end(acc: Meadow, r: Array<U32> & Patch) -> Array<U32> & Meadow:
  (w, p) = r
  (w, acc)

# what the ray saw once past a cell: what it saw before (tr .. hue), and
# the cell seen through what it still sees, faded by f; the first
# flower's colour is its patch's (phue), the floor's shade the cell's
# (low), which is the last cell's when the ray meets the floor in it
def met(+tr: F32, +n: F32, +lit: F32, +s: F32, +head: F32, +heart: F32, +t: F32, +hue: U32, +f: F32, +phue: U32, +low: F32, tf: Tuft) -> Meadow:
  Tuft{+a, +tn, +tlit, +ts, +thead, +theart, +tt} = tf
  +g = (tr * f : F32)
  Meadow{(tr * (1.0 - a * f) : F32), (n + g * tn : F32), (lit + g * tlit : F32), (s + g * ts : F32), (head + g * thead : F32),
    (heart + g * theart : F32), (t + g * tt : F32), Bool.pick(U32, (head > 0.0 : F32), hue, phue), low}

# the floor under the ray where it passes a cell from ta to tb: the
# block's under its lowest point there, a hair up for a point on a top
def level(+oy: F32, +dy: F32, +ta: F32, +tb: F32) -> F32:
  F32.floor((oy + dy * Bool.pick(F32, (dy < 0.0 : F32), tb, ta) + 0.001 : F32))

# The cells of lvl the ray crosses, as the render's walk crosses blocks,
# until t1 or once what it sees through is spent (go): (ix, iz) the cell,
# mx and mz the distance to its next side along x and z, ux and uz
# between sides. Only the floor under the ray's lowest point in a cell
# (lv) can hold grass it meets there (a floor higher up would have
# stopped it), so the walk follows the floors as the ray climbs or falls;
# the patch is read again as it comes into another block column or over
# another floor (r).
def walk(fuel: Nat, go: Bool, +lvl: Level, +ix: F32, +iz: F32, +mx: F32, +mz: F32, +ux: F32, +uz: F32, +lv: F32,
         +base: U32, +fm: U32, +ck: U32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32, +t1: F32, +qh: F32, +qr: F32,
         acc: Meadow, r: Array<U32> & Patch) -> Array<U32> & Meadow:
  match fuel:
    case 0n:
      walk_end(acc, r)
    case 1n+f:
      match go:
        case False{}:
          walk_end(acc, r)
        case True{}:
          Level{+sz, +per, +seed, +wm, +q0, +fi, +fo, +fk} = lvl
          Meadow{+tr, +n, +lit, +s, +head, +heart, +t, +hue, +low} = acc
          (w, +p) = r
          Patch{+py, +tall, +itall, +dense, +wind, +rate, +phue, +ifp} = p
          +next = F32.min(mx, mz)
          +xs = (mx < mz : F32)
          +nx = Bool.pick(F32, xs, (ix + Bool.pick(F32, (dx > 0.0 : F32), 1.0, (0.0 - 1.0 : F32)) : F32), ix)
          +nz = Bool.pick(F32, xs, iz, (iz + Bool.pick(F32, (dz > 0.0 : F32), 1.0, (0.0 - 1.0 : F32)) : F32))
          +nmx = Bool.pick(F32, xs, (mx + ux : F32), mx)
          +nmz = Bool.pick(F32, xs, mz, (mz + uz : F32))
          +nlv = level(oy, dy, next, F32.min(F32.min(nmx, nmz), t1))
          walk(f, (next < t1 : F32) && (tr > 0.05 : F32), lvl, nx, nz, nmx, nmz, ux, uz, nlv, base, fm, ck, ox, oy, oz, dx, dy, dz, t1, qh, qr,
            met(tr, n, lit, s, head, heart, t, hue,
              (Util.smooth(F32.clamp(((next - fi) * 0.5 : F32), 0.0, 1.0)) * (1.0 - Util.smooth(F32.clamp(((next - fo) * fk : F32), 0.0, 1.0))) : F32), phue,
              Bool.pick(F32, (py >= 0.0 : F32) && (Util.absf((oy + dy * t1 - py : F32)) < 0.01 : F32),
                (0.85 * (1.0 - Util.smooth(F32.clamp(((t1 - 6.0) * 0.2 : F32), 0.0, 1.0))) : F32), 0.0),
              blades((py >= 0.0 : F32)
                  && near_cell(((ix + 0.5) * sz : F32), ((iz + 0.5) * sz : F32), (0.76 * sz : F32), py, (tall * 1.2 + 0.07 : F32), ox, oy, oz, dx, dy, dz, t1, qh, qr),
                fm, per, seed, ix, iz, F32.clamp(((next - q0) * 0.5 : F32), 0.0, 1.0), wm, sz, (ix * sz : F32), (iz * sz : F32), py, tall, itall, dense, wind, rate, ck, ox, oy, oz, dx, dy, dz, t1, ifp, qh, qr)),
            refetch((Util.absf((F32.floor((nx * sz : F32)) - F32.floor((ix * sz : F32)) : F32))
                   + Util.absf((F32.floor((nz * sz : F32)) - F32.floor((iz * sz : F32)) : F32))
                   + Util.absf((nlv - lv : F32)) > 0.5 : F32),
              w, base, F32.floor((nx * sz : F32)), F32.floor((nz * sz : F32)), nlv, fm, ck, next, p))

# The walk of level lvl from t0 to t1 (where on), on from what the ray
# saw; it starts a hair past t0, in the block past a side the ray came in
# by there.
def march_at(on: Bool, +lvl: Level, +base: U32, +fm: U32, +ck: U32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
             +t0: F32, +t1: F32, r: Array<U32> & Meadow) -> Array<U32> & Meadow:
  match on:
    case False{}:
      r
    case True{}:
      Level{+sz, +per, +seed, +wm, +q0, +fi, +fo, +fk} = lvl
      (w, acc) = r
      +ts = (t0 + 0.001 : F32)
      +px = (ox + dx * ts : F32)
      +pz = (oz + dz * ts : F32)
      +gx = (px * per : F32)
      +gz = (pz * per : F32)
      +ix = F32.floor(gx)
      +iz = F32.floor(gz)
      +ux = (sz / F32.max(Util.absf(dx), 0.00001) : F32)
      +uz = (sz / F32.max(Util.absf(dz), 0.00001) : F32)
      +mx = (ts + Bool.pick(F32, (dx > 0.0 : F32), (ix + 1.0 - gx : F32), (gx - ix : F32)) * ux : F32)
      +mz = (ts + Bool.pick(F32, (dz > 0.0 : F32), (iz + 1.0 - gz : F32), (gz - iz : F32)) * uz : F32)
      +qh = (1.0 / F32.max((dx * dx + dz * dz : F32), 0.000001) : F32)
      +lv = level(oy, dy, ts, F32.min(F32.min(mx, mz), t1))
      walk(64n, True{}, lvl, ix, iz, mx, mz, ux, uz, lv, base, fm, ck, ox, oy, oz, dx, dy, dz, t1, qh, F32.sqrt(qh), acc,
        patch(w, base, F32.floor(px), F32.floor(pz), lv, fm, ck, ts))

# The grass the ray from the eye passes from t0 to t1, over whatever
# floors: the fine walk to 12 blocks, the coarse one from 10 to 22, and
# the broad one from 20 to 40.
def march(w: Array<U32>, +base: U32, +fm: U32, +ck: U32, +ox: F32, +oy: F32, +oz: F32, +dx: F32, +dy: F32, +dz: F32,
          +t0: F32, +t1: F32) -> Array<U32> & Meadow:
  march_at((t1 > 20.0 : F32) && (t0 < 40.0 : F32), broad(), base, fm, ck, ox, oy, oz, dx, dy, dz, F32.max(t0, 20.0), F32.min(t1, 40.0),
    march_at((t1 > 10.0 : F32) && (t0 < 22.0 : F32), coarse(), base, fm, ck, ox, oy, oz, dx, dy, dz, F32.max(t0, 10.0), F32.min(t1, 22.0),
      march_at((t0 < 12.0 : F32), fine(), base, fm, ck, ox, oy, oz, dx, dy, dz, t0, F32.min(t1, 12.0), (w, Meadow{1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, 0.0}))))

# how dry the meadow is at (x, z) of the window
def dryness(+fm: U32, +x: F32, +z: F32) -> F32:
  Clouds.lattice(Clouds.wrap((x + Clouds.corner_x(fm) : F32)), Clouds.wrap((z + Clouds.corner_z(fm) : F32)), 0.0625, 16, 947)

# the blades' green, between two, towards straw where it is dry
def green(+dry: F32) -> U32:
  Util.mix(Util.mix(Util.rgb(86, 160, 50), Util.rgb(118, 194, 60), dry), Util.rgb(170, 160, 86), (dry * dry * 0.5 : F32))

# The meadow seen from afar, a grass top's colour at (x, z) of the window
# t from the eye where no blade is met: the blades' green, and a little
# of their tips, between the shade at their feet and their light as they
# cover the floor, more where the meadow grows wild, mottled a quarter of
# a block across, and evenly by 33 blocks.
def afar(+fm: U32, +x: F32, +z: F32, +t: F32) -> U32:
  +xw = Clouds.wrap((x + Clouds.corner_x(fm) : F32))
  +zw = Clouds.wrap((z + Clouds.corner_z(fm) : F32))
  Util.dim(Util.mix(green(dryness(fm, x, z)), Util.rgb(168, 206, 92), 0.15),
    (0.3 + 0.4 * F32.clamp((0.35 + 0.3 * Meadow.wild(xw, zw) + (Clouds.lattice(xw, zw, 4.0, 1024, 977) - 0.5) * 0.4 * F32.clamp((1.0 - t * 0.03 : F32), 0.0, 1.0) : F32), 0.0, 1.0) : F32))

# The grass's colour: its green by how dry, yellower up the blades, darker down in the grass; in
# the sun's light where the ray met it (sun: 0.6 in the shade), its colour tint, more of
# it on the side the ray sees when the sun is behind it, and through the
# blades against it; darker when wet, the flowers' heads among them;
# fogged as the ray (v, f) and over what it met behind them (c), whose
# floor under the grass is the shade at the blades' feet.
def over(+c: U32, +v: U32, +f: F32, +sun: F32, +tint: Sky.Tint, +wet: F32, +dry: F32, +dx: F32, +dy: F32, +dz: F32, +lx: F32, +ly: F32, +lz: F32,
         lw: Meadow) -> U32:
  Meadow{+tr, +n, +lit, +s, +head, +heart, +t, +hue, +low} = lw
  +m = (1.0 / F32.max(n, 0.0001) : F32)
  +tip = (s * m : F32)
  +tone = (0.18 + 0.82 * Sky.daylight(ly) : F32)
  +dl = (dx * lx + dy * ly + dz * lz : F32)
  +toward = F32.clamp(dl, 0.0, 1.0)
  +glow = (toward * toward * toward * toward * F32.clamp((ly * 5.0 : F32), 0.0, 1.0) * F32.clamp(((sun - 0.6) * 2.5 : F32), 0.0, 1.0) : F32)
  +base = green(dry)
  +blades = Util.dim(Util.mix(Util.dim(Util.mix(base, Util.rgb(168, 206, 92), (0.25 * tip * tip : F32)), (tone * (0.6 + (sun - 0.6) * (0.85 - 0.25 * dl)) * lit * m : F32)),
    Util.dim(Util.rgb(200, 220, 100), tone), (0.5 * glow * tip : F32)), (1.0 - 0.3 * wet : F32))
  Util.mix(Util.mix(c, Util.mix(Sky.tinted(Util.dim(base, (0.3 * tone * (0.6 + (sun - 0.6) * 0.85) * (1.0 - 0.3 * wet) : F32)), tint), v, f), low),
    Util.mix(Sky.tinted(Util.mix(Util.mix(blades, Util.dim(hue, (tone * sun : F32)), (head * m : F32)), Util.dim(eye(hue), (tone * sun : F32)), (heart * m : F32)), tint), v, f),
    (1.0 - tr : F32))
