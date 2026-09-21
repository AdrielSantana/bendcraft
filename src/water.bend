import Base
import ./sky.bend as Sky
import ./util.bend as Util

# Array indices wrap at 2^17 words: only 14 column-address bits matter.
# The next 13 carry milliseconds in an 8.192-second ripple loop; bit 31
# belongs to the readout. None of these high bits changes a world load.
def phase(t: U32) -> U32: (t .&. 8191 : U32)
def frame_base(+base: U32, clock: U32) -> U32:
  ((base .&. 2147500031) .|. (phase(clock) * 16384) : U32)
def clock(base: U32) -> U32: (base / 16384 % 8192 : U32)
def lattice(base: U32, x: U32, z: U32) -> U32:
  ((base + x * 128 + z) .&. 16383 : U32)

# A ray accumulates only the wet intervals before its first solid hit.
# Entry locates the first surface; it is zero for a submerged eye and
# cannot stand in for the whole ray's distance when computing fog.
type Trace is Data:
  Trace{entry: F32, depth: F32}

# The primary ray uses six bits for its 60-step count. Bit six records
# entry through the first water top, without widening the DDA state.
def mark_top(steps: U32, top: Bool) -> U32:
  (steps .|. Bool.pick(U32, top, 64, 0) : U32)

def top(code: U32) -> Bool: Util.on(code, 256)
def steps(code: U32) -> U32: (code / 4 % 64 : U32)

def crossed_top(on: Bool, wet: Bool, +t: F32, next: F32, axis: F32, sy: F32, tr: Trace, n: U32) -> U32:
  match on:
    case False{}: n
    case True{}:
      Trace{entry, depth} = tr
      mark_top(n, wet && (depth <= 0.0 : F32) && (t > 0.0 : F32) && (next > t : F32)
        && F32.is_eq(axis, 1.0) && (sy < 0.0 : F32))

def crossed(on: Bool, +wet: Bool, +t: F32, +next: F32, tr: Trace) -> Trace:
  match on:
    case False{}: tr
    case True{}:
      Trace{+entry, +depth} = tr
      Trace{Bool.pick(F32, wet && (depth <= 0.0 : F32), t, entry),
        (depth + Bool.pick(F32, wet, F32.max((next - t : F32), 0.0), 0.0) : F32)}

# Depth absorption and the reflected sky take no second world ray.
def colour(sun_y: F32) -> U32:
  Sky.mix(Sky.rgb(7, 28, 43), Sky.rgb(26, 113, 132), Sky.daylight(sun_y))

def opacity(+depth: F32) -> F32:
  (0.18 + 0.72 * depth / (depth + 4.0) : F32)

def tint(bottom: U32, depth: F32, sun_y: F32) -> U32:
  Sky.mix(bottom, colour(sun_y), opacity(depth))

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

type Reflection is Data:
  Reflection{x: F32, y: F32, z: F32, cosine: F32}

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

# Schlick's air/water approximation, with about 2% reflection head-on.
# Disabling Fresnel leaves that normal-incidence reflectance constant.
def fresnel(on: Bool, cosine: F32) -> F32:
  match on:
    case False{}: 0.02
    case True{}:
      +c = (1.0 - F32.clamp(cosine, 0.0, 1.0) : F32)
      +c2 = (c * c : F32)
      (0.02 + 0.98 * c2 * c2 * c : F32)

def reflected_sky(+fl: U32, +dx: F32, +dy: F32, +dz: F32, +sx: F32, +sy: F32, +sz: F32) -> U32:
  +ry = (0.0 - dy : F32)
  Sky.bodies(fl, Sky.atmosphere(fl, dx, ry, dz, sx, sy, sz), dx, ry, dz, sx, sy, sz)

def reflected_colour(+fl: U32, c: U32, sky: U32, front: F32,
                     +sx: F32, +sy: F32, +sz: F32, r: Reflection) -> U32:
  Reflection{+rx, +ry, +rz, cosine} = r
  Sky.mix(c, Sky.mix(Sky.bodies(fl, Sky.atmosphere(fl, rx, ry, rz, sx, sy, sz), rx, ry, rz, sx, sy, sz), sky, front),
    fresnel(fresnel_on(fl), cosine))

def surface(on: Bool, hidden: Bool, +fl: U32, c: U32, sky: U32, front: F32,
            base: U32, x: F32, z: F32, distance: F32,
            dx: F32, dy: F32, dz: F32, sx: F32, sy: F32, sz: F32) -> U32:
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
          reflected_colour(fl, c, sky, front, sx, sy, sz,
            reflected(ripples_on(fl), base, x, z, distance, dx, dy, dz))

# Full extinction at 24 wet blocks hides the 60-step limit even on a
# diagonal. Sky and solid rays converge to the same daylight-aware colour.
def fog(on: Bool, c: U32, ink: U32, sky: U32, front: F32, depth: F32) -> U32:
  match on:
    case False{}: c
    case True{}:
      +d = F32.clamp((depth / 24.0 : F32), 0.0, 1.0)
      Sky.mix(c, Sky.mix(ink, sky, front), (d * d : F32))

def shade(on: Bool, +fl: U32, +sky: U32, ring_base: U32, ox: F32, +oy: F32, oz: F32, +dx: F32, +dy: F32, +dz: F32,
          sun_x: F32, +sun_y: F32, sun_z: F32, water_top: Bool,
          +distance: F32, hit: Bool, tr: Trace, r: Array<U32> & U32) -> Array<U32> & U32:
  match on:
    case False{}: r
    case True{}:
      Trace{+entry, +depth} = tr
      (w, bottom) = r
      +ink = colour(sun_y)
      # Fog the whole solid distance, including air after leaving water.
      # A sky miss already has its atmospheric colour and celestial discs.
      +front = Sky.fog(fl, entry, oy, (oy + dy * entry : F32))
      +air = Bool.pick(F32, hit, Sky.fog(fl, distance, oy, (oy + dy * distance : F32)), front)
      # Fog the background before tinting it: a hidden block and the sky
      # behind it must pass through the same water. Foreground haze reduces
      # the tint so a lake beyond the air's visibility limit stays hidden.
      +base = Sky.mix(Sky.mix(bottom, sky, air), ink, (opacity(depth) * (1.0 - front) : F32))
      # A lake beyond the air's visibility limit must also fade to sky.
      (w, surface(water_top && reflection_on(fl), (front >= 1.0 : F32), fl, fog(fog_on(fl), base, ink, sky, front, depth),
        sky, front, ring_base, (ox + dx * entry : F32), (oz + dz * entry : F32), entry, dx, dy, dz, sun_x, sun_y, sun_z))
