import Base
import ./sky.bend as Sky
import ./util.bend as Util

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

def surface(on: Bool, hidden: Bool, +fl: U32, c: U32, sky: U32, front: F32,
            dx: F32, +dy: F32, dz: F32, sx: F32, sy: F32, sz: F32) -> U32:
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
          Sky.mix(c, Sky.mix(reflected_sky(fl, dx, dy, dz, sx, sy, sz), sky, front),
            fresnel(fresnel_on(fl), (0.0 - dy : F32)))

# Full extinction at 24 wet blocks hides the 60-step limit even on a
# diagonal. Sky and solid rays converge to the same daylight-aware colour.
def fog(on: Bool, c: U32, ink: U32, sky: U32, front: F32, depth: F32) -> U32:
  match on:
    case False{}: c
    case True{}:
      +d = F32.clamp((depth / 24.0 : F32), 0.0, 1.0)
      Sky.mix(c, Sky.mix(ink, sky, front), (d * d : F32))

def shade(on: Bool, +fl: U32, +sky: U32, +oy: F32, dx: F32, +dy: F32, dz: F32,
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
        sky, front, dx, dy, dz, sun_x, sun_y, sun_z))
