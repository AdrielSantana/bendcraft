import Base
import ./sky.bend as Sky
import ./util.bend as Util

# Array indices wrap at 2^18 words: only 14 column-address bits matter.
# The next 13 carry milliseconds in an 8.192-second ripple loop; bits
# 27..30 are looks the flags word has no room for, put there by the camera
# (27: the world in the water's mirror, 28: the caustic on its bed); bit
# 31 belongs to the readout.
# None of these high bits changes a world load.
def phase(t: U32) -> U32: (t .&. 8191 : U32)
def frame_base(+base: U32, clock: U32) -> U32:
  ((base .&. 2147500031) .|. (phase(clock) * 16384) : U32)
def mirror_on(base: U32) -> Bool: Util.on(base, 134217728)
def caustic_on(base: U32) -> Bool: Util.on(base, 268435456)
def with_looks(base: U32, more: U32) -> U32:
  ((base .&. 2281701375) .|. (more .&. 2013265920) : U32)
def clock(base: U32) -> U32: (base / 16384 % 8192 : U32)
def lattice(base: U32, x: U32, z: U32) -> U32:
  ((base + x * 128 + z) .&. 16383 : U32)

# A ray accumulates only the wet intervals before its first solid hit.
# Entry locates the first surface; it is zero for a submerged eye and
# cannot stand in for the whole ray's distance when computing fog.
type Trace is Data:
  Trace{entry: F32, depth: F32}

# A cell holding a units has its surface a / 8 up its height: the DDA
# (Render.dda) clips the ray's wet segment in such a cell to the part
# under that plane, so the entry moves down a descending ray to the
# plane, a ray over the water passes, and the reflection, the ripples,
# Fresnel, the mirror and the caustic happen on the plane. A full cell's
# plane is its top face, and its segment is what it was, bit for bit.
def entry_of(tr: Trace) -> F32:
  Trace{entry, depth} = tr
  entry

def depth_of(tr: Trace) -> F32:
  Trace{entry, depth} = tr
  depth

# The primary ray uses six bits for its 60-step count. Bit six records
# entry through the first water top, without widening the DDA state.
def mark_top(steps: U32, top: Bool) -> U32:
  (steps .|. Bool.pick(U32, top, 64, 0) : U32)

def top(code: U32) -> Bool: Util.on(code, 256)
def steps(code: U32) -> U32: (code / 4 % 64 : U32)

# the first wet segment's start is a top entry through the cell's top face,
# or through a partial cell's plane, where the segment starts past the face
def crossed_top(on: Bool, wet: Bool, +t: F32, +ws: F32, next: F32, axis: F32, sy: F32, tr: Trace, n: U32) -> U32:
  match on:
    case False{}: n
    case True{}:
      Trace{entry, depth} = tr
      mark_top(n, wet && (depth <= 0.0 : F32) && (ws > 0.0 : F32) && (next > ws : F32)
        && ((F32.is_eq(axis, 1.0) && (sy < 0.0 : F32)) || (ws > t : F32)))

def crossed(on: Bool, +wet: Bool, +t: F32, +next: F32, tr: Trace) -> Trace:
  match on:
    case False{}: tr
    case True{}:
      Trace{+entry, +depth} = tr
      Trace{Bool.pick(F32, wet && (depth <= 0.0 : F32), t, entry),
        (depth + Bool.pick(F32, wet, F32.max((next - t : F32), 0.0), 0.0) : F32)}

# Depth absorption and the reflected sky take no second world ray.
def colour(sun_y: F32) -> U32:
  Sky.mix(Sky.rgb(7, 28, 43), Sky.rgb(18, 84, 112), Sky.daylight(sun_y))

# How much of the water's colour a wet path of `depth` blocks leaves over
# what is behind it. Seen from the air the water is dense, 1 - 0.88 / (1 +
# 0.35 d)^2 (an exponential's shape without one: a half at one block, 0.85
# at four), so the bed does not compete with what the surface mirrors. An
# eye under the water keeps the clear one, or a diver would see two blocks.
# Every lake lies at the sea level today, so a point's depth under the
# surface is the level less its height. The water's physics, the next
# step, gives each column its own level, and this will read it there.
def level() -> F32: 12.0
def drop(y: F32) -> F32: F32.max((level() - y : F32), 0.0)

# What lies deep is lit by what little light got down to it. The light
# left at a depth dims whatever a wet ray meets there, from the air or
# from under the water alike (a diver at the bed sees the bed as the bank
# does), and the water's own colour darkens with it to a near-black blue,
# so a deep lake reads as deep, where one colour at every depth made a
# lake of ten blocks look like one of four. The fog a submerged eye sees
# converges to the colour at the eye's own depth.
def light(+drop: F32) -> F32:
  (1.0 - 0.85 * F32.clamp((drop / 6.0 : F32), 0.0, 1.0) : F32)

def deep(sun_y: F32) -> U32:
  Sky.mix(Sky.rgb(3, 12, 22), Sky.rgb(5, 30, 48), Sky.daylight(sun_y))

def ink_at(+ink: U32, sun_y: F32, +drop: F32) -> U32:
  Sky.mix(ink, deep(sun_y), F32.clamp((drop / 6.0 : F32), 0.0, 1.0))

def opacity(from_air: Bool, +depth: F32) -> F32:
  +k = (1.0 + 0.35 * depth : F32)
  Bool.pick(F32, from_air, (1.0 - 0.88 / (k * k) : F32), (0.18 + 0.72 * depth / (depth + 4.0) : F32))

# The light that shows the bed went down to it before coming up the ray:
# looking straight down doubles the wet path, a grazing look leaves it.
def lit_path(depth: F32, dy: F32) -> F32:
  (depth * (1.0 + F32.max((0.0 - dy : F32), 0.0)) : F32)

def fog_on(fl: U32) -> Bool: Util.on(fl, 4194304)
def fresnel_on(fl: U32) -> Bool: Util.on(fl, 8388608)
def reflection_on(fl: U32) -> Bool: Util.on(fl, 16777216)
def ripples_on(fl: U32) -> Bool: Util.on(fl, 1048576)

# Hash the same world lattice as the ring, so integer recentering cannot
# move the pattern. Offsetting both coordinates keeps floor inputs positive.
def noise_at(base: U32, x: U32, z: U32) -> F32:
  (U32.to_f32((Sky.star_hash(lattice(base, x, z), 47) % 256 : U32)) / 255.0 : F32)

type Slope is Data:
  Slope{x: F32, z: F32}

# Differentiate one smooth value-noise cell analytically: four hashes,
# with no finite-difference resampling or extra world reads.
def slope(+base: U32, +x: F32, +z: F32) -> Slope:
  +ix = Util.f2u(x)
  +iz = Util.f2u(z)
  +fx = (x - U32.to_f32(ix) : F32)
  +fz = (z - U32.to_f32(iz) : F32)
  +u = Util.smooth(fx)
  +v = Util.smooth(fz)
  +a = noise_at(base, ix, iz)
  +b = noise_at(base, (ix + 1 : U32), iz)
  +c = noise_at(base, ix, (iz + 1 : U32))
  +d = noise_at(base, (ix + 1 : U32), (iz + 1 : U32))
  Slope{(6.0 * fx * (1.0 - fx) * ((b - a) * (1.0 - v) + (d - c) * v) : F32),
        (6.0 * fz * (1.0 - fz) * ((c - a) * (1.0 - u) + (d - b) * u) : F32)}

# the smooth value noise the slope above is the gradient of, at a point:
# the same four hashes
def value(+base: U32, +x: F32, +z: F32) -> F32:
  +ix = Util.f2u(x)
  +iz = Util.f2u(z)
  +u = Util.smooth((x - U32.to_f32(ix) : F32))
  +v = Util.smooth((z - U32.to_f32(iz) : F32))
  +a = noise_at(base, ix, iz)
  +b = noise_at(base, (ix + 1 : U32), iz)
  +c = noise_at(base, ix, (iz + 1 : U32))
  +d = noise_at(base, (ix + 1 : U32), (iz + 1 : U32))
  ((a * (1.0 - u) + b * u) * (1.0 - v) + (c * (1.0 - u) + d * u) * v : F32)

# a ridge where the noise crosses its middle: the bright thread of a caustic
def thread(n: F32) -> F32:
  (1.0 - Util.absf((2.0 * n - 1.0 : F32)) : F32)

# The light on a lake's bed came down through the rippled surface, which
# gathers it into bright threads here and takes it from there: a caustic.
# The real one follows the surface's curvature down to the bed; this one
# reads the ripples' noise at the bed's own point, two octaves at twice and
# three times the ripples' scale, moving with their clock, and brightens
# the bed on the threads (the product of the two ridges, squared, so the
# threads are thin) and darkens it a little between them: the mean is
# near zero, so a shallow bed keeps its brightness. The scales
# are whole numbers and the lattice is scaled with them, so a ring shift
# cannot drag the pattern. It is strongest just under the surface and gone
# six blocks down, as the light is, in daylight alone, and fades out where
# the eye looks along the surface, and where the water over the bed is
# thin: a film has no depth to focus the light, so the threads grow with
# the water's thickness up to nine tenths of a block (a lake's shallowest
# cell, a whole block, keeps them whole). No walk and no world read: four
# hashes an octave. The factor multiplies the bed's colour; 1.0 leaves it
# alone.
def caustic(+base: U32, +x: F32, +z: F32, +drop: F32, +dy: F32, sun_y: F32, +thick: F32) -> F32:
  +angle = (U32.to_f32(clock(base)) * (6.2831853 / 8192.0) : F32)
  +sx = (0.8 * F32.sin(angle) : F32)
  +sz = (0.8 * F32.cos(angle) : F32)
  +a = thread(value((base * 2 : U32), (x * 2.0 + 512.0 + sx : F32), (z * 2.0 + 512.0 + sz : F32)))
  +b = thread(value((base * 3 : U32), (x * 3.0 + 768.0 - sz : F32), (z * 3.0 + 768.0 - sx : F32)))
  +fade = (Sky.daylight(sun_y) * (1.0 - F32.clamp((drop / 6.0 : F32), 0.0, 1.0))
    * F32.clamp((0.0 - dy * 8.0 : F32), 0.0, 1.0) * F32.clamp((thick / 0.9 : F32), 0.0, 1.0) : F32)
  +t = (a * b : F32)
  (1.0 + fade * (2.6 * t * t - 0.45) : F32)

type Reflection is Data:
  Reflection{x: F32, y: F32, z: F32, cosine: F32}

# What the render hands the surface: the ground's colour under the water,
# the mirrored ray, and what that ray met in the world (render.bend walks
# it, since the world is its to read): a colour and the fog to the sky
# behind it, or no hit.
type Mirror is Data:
  Mirror{bottom: U32, r: Reflection, hit: Bool, colour: U32, fog: F32}

# a water top seen with no mirror asked for still needs its flat normal
def flat(dx: F32, +dy: F32, dz: F32) -> Reflection:
  Reflection{dx, (0.0 - dy : F32), dz, (0.0 - dy : F32)}

# A steep ripple seen at a grazing angle would send the mirrored ray under
# the water. There it would meet another wave; the cheap stand-in is to
# lift it back over the horizon and make it a unit again, so the tilt can
# stay strong where reflections are strongest.
def lifted(+rx: F32, ry: F32, +rz: F32, cosine: F32) -> Reflection:
  +y = F32.max(ry, 0.02)
  +k = (1.0 / F32.sqrt((rx * rx + y * y + rz * rz : F32)) : F32)
  Reflection{(rx * k : F32), (y * k : F32), (rz * k : F32), F32.max(cosine, 0.0001)}

def tilted(+dx: F32, +dy: F32, +dz: F32, +strength: F32, s: Slope) -> Reflection:
  Slope{gx, gz} = s
  +nx = (0.0 - strength * gx : F32)
  +nz = (0.0 - strength * gz : F32)
  +inv = (1.0 / F32.sqrt((nx * nx + 1.0 + nz * nz : F32)) : F32)
  +cosine = ((0.0 - dx * nx - dy - dz * nz) * inv : F32)
  lifted((dx + 2.0 * cosine * nx * inv : F32), (dy + 2.0 * cosine * inv : F32),
    (dz + 2.0 * cosine * nz * inv : F32), cosine)

def reflected(on: Bool, +base: U32, x: F32, z: F32, distance: F32,
              dx: F32, +dy: F32, dz: F32) -> Reflection:
  match on:
    case False{}: Reflection{dx, (0.0 - dy : F32), dz, (0.0 - dy : F32)}
    case True{}:
      +angle = (U32.to_f32(clock(base)) * (6.2831853 / 8192.0) : F32)
      # Fade with distance to avoid small distant shimmer, and only in the
      # last degrees before the horizon: `lifted` keeps a grazing ray's
      # mirror over the water. This changes shading, not water volume.
      +fade = (F32.clamp((0.0 - dy * 16.0 : F32), 0.0, 1.0)
        * (1.0 - F32.clamp((distance / 32.0 : F32), 0.0, 1.0)) : F32)
      tilted(dx, dy, dz, (0.15 * fade : F32),
        slope(base, (x + 256.0 + 0.8 * F32.sin(angle) : F32),
                    (z + 256.0 + 0.8 * F32.cos(angle) : F32)))

# About 2% reflection head-on, a mirror at grazing angles, as Schlick's
# approximation has it, but by a cube and not his fifth power: the mirror
# shows at the angles a player sees a lake from (14% at 30 degrees, not 5).
# Disabling Fresnel leaves that normal-incidence reflectance constant.
def fresnel(on: Bool, cosine: F32) -> F32:
  match on:
    case False{}: 0.02
    case True{}:
      +c = (1.0 - F32.clamp(cosine, 0.0, 1.0) : F32)
      (0.02 + 0.98 * c * c * c : F32)

def reflected_sky(+fl: U32, +dx: F32, +dy: F32, +dz: F32, +sx: F32, +sy: F32, +sz: F32) -> U32:
  +ry = (0.0 - dy : F32)
  Sky.bodies(fl, Sky.atmosphere(fl, dx, ry, dz, sx, sy, sz), dx, ry, dz, sx, sy, sz)

# The mirror's walk has 32 steps, and a step crosses one face: a ray of
# direction d has crossed at most (|dx| + |dy| + |dz|) t + 3 faces at the
# distance t, so whatever lies within 28 / (|dx| + |dy| + |dz|) is met.
# Over the last quarter of that reach the mirror fades into the sky behind
# (0 keeps the world, 1 the sky): nothing pops in where the walk ends.
def reach(t: F32, dx: F32, dy: F32, dz: F32) -> F32:
  F32.clamp((t * (Util.absf(dx) + Util.absf(dy) + Util.absf(dz)) / 7.0 - 3.0 : F32), 0.0, 1.0)

# The mirror shows the world where its ray met a block, fogged into the
# sky that lies behind it, and that sky alone where it met none: the same
# arithmetic as before the world was in it, so a miss is the same byte.
def in_mirror(hit: Bool, behind: U32, colour: U32, f: F32) -> U32:
  match hit:
    case False{}: behind
    case True{}: Sky.mix(colour, behind, f)

def reflected_colour(+fl: U32, c: U32, sky: U32, front: F32,
                     +sx: F32, +sy: F32, +sz: F32, m: Mirror) -> U32:
  Mirror{bottom, r, hit, colour, f} = m
  Reflection{+rx, +ry, +rz, cosine} = r
  Sky.mix(c, Sky.mix(in_mirror(hit, Sky.bodies(fl, Sky.atmosphere(fl, rx, ry, rz, sx, sy, sz), rx, ry, rz, sx, sy, sz), colour, f), sky, front),
    fresnel(fresnel_on(fl), cosine))

def surface(on: Bool, hidden: Bool, +fl: U32, c: U32, sky: U32, front: F32,
            sx: F32, sy: F32, sz: F32, m: Mirror) -> U32:
  match on:
    case False{}: c
    case True{}:
      match hidden:
        # Return the exact sky at full haze; mixing identical byte colours
        # through floats can otherwise leave a one-level silhouette.
        case True{}: sky
        case False{}:
          # Reflection travels only to the surface; the water depth behind
          # it must not absorb it. Foreground air still fogs the reflection.
          reflected_colour(fl, c, sky, front, sx, sy, sz, m)

# Full extinction at 24 wet blocks hides the 60-step limit even on a
# diagonal. Sky and solid rays converge to the same daylight-aware colour.
def fog(on: Bool, c: U32, ink: U32, sky: U32, front: F32, depth: F32) -> U32:
  match on:
    case False{}: c
    case True{}:
      +d = F32.clamp((depth / 24.0 : F32), 0.0, 1.0)
      Sky.mix(c, Sky.mix(ink, sky, front), (d * d : F32))

def dry(r: Array<U32> & Mirror) -> Array<U32> & U32:
  (w, m) = r
  Mirror{bottom, x, hit, colour, f} = m
  (w, bottom)

def shade(on: Bool, +fl: U32, +sky: U32, +oy: F32, +dy: F32,
          sun_x: F32, +sun_y: F32, sun_z: F32, water_top: Bool,
          +distance: F32, +hit: Bool, tr: Trace, r: Array<U32> & Mirror) -> Array<U32> & U32:
  match on:
    case False{}: dry(r)
    case True{}:
      Trace{+entry, +depth} = tr
      (w, +m) = r
      Mirror{bottom, mr, mhit, mcolour, mf} = m
      +ink = colour(sun_y)
      # Fog the whole solid distance, including air after leaving water.
      # A sky miss already has its atmospheric colour and celestial discs.
      +front = Sky.fog(fl, entry, oy, (oy + dy * entry : F32))
      +air = Bool.pick(F32, hit, Sky.fog(fl, distance, oy, (oy + dy * distance : F32)), front)
      # Fog the background before tinting it: a hidden block and the sky
      # behind it must pass through the same water. Foreground haze reduces
      # the tint so a lake beyond the air's visibility limit stays hidden.
      +down = drop((oy + dy * distance : F32))
      +lit = Sky.mix(bottom, 0, Bool.pick(F32, hit, (1.0 - light(down) : F32), 0.0))
      +base = Sky.mix(Sky.mix(lit, sky, air), ink_at(ink, sun_y, down), (opacity((entry > 0.0 : F32), lit_path(depth, dy)) * (1.0 - front) : F32))
      # A lake beyond the air's visibility limit must also fade to sky.
      (w, surface(water_top && reflection_on(fl), (front >= 1.0 : F32), fl, fog(fog_on(fl), base, ink_at(ink, sun_y, drop(oy)), sky, front, depth),
        sky, front, sun_x, sun_y, sun_z, m))
