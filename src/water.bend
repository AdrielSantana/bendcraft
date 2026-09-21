import Base
import ./sky.bend as Sky
import ./util.bend as Util

# A ray accumulates only the wet intervals before its first solid hit.
# Entry locates the first surface; it is zero for a submerged eye and
# cannot stand in for the whole ray's distance when computing fog.
type Trace is Data:
  Trace{entry: F32, depth: F32}

def crossed(on: Bool, +wet: Bool, +t: F32, +next: F32, tr: Trace) -> Trace:
  match on:
    case False{}: tr
    case True{}:
      Trace{+entry, +depth} = tr
      Trace{Bool.pick(F32, wet && (depth <= 0.0 : F32), t, entry),
        (depth + Bool.pick(F32, wet, F32.max((next - t : F32), 0.0), 0.0) : F32)}

# Still water starts with depth absorption. Reflection and ripples will
# have separate flags when added; this look takes no second ray.
def colour(sun_y: F32) -> U32:
  Sky.mix(Sky.rgb(7, 28, 43), Sky.rgb(26, 113, 132), Sky.daylight(sun_y))

def opacity(+depth: F32) -> F32:
  (0.18 + 0.72 * depth / (depth + 4.0) : F32)

def tint(bottom: U32, depth: F32, sun_y: F32) -> U32:
  Sky.mix(bottom, colour(sun_y), opacity(depth))

def fog_on(fl: U32) -> Bool: Util.on(fl, 4194304)

# Full extinction at 24 wet blocks hides the 60-step limit even on a
# diagonal. Sky and solid rays converge to the same daylight-aware colour.
def fog(on: Bool, c: U32, ink: U32, sky: U32, front: F32, depth: F32) -> U32:
  match on:
    case False{}: c
    case True{}:
      +d = F32.clamp((depth / 24.0 : F32), 0.0, 1.0)
      Sky.mix(c, Sky.mix(ink, sky, front), (d * d : F32))

def shade(on: Bool, +fl: U32, +sky: U32, +oy: F32, +dy: F32, +sun_y: F32,
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
      (w, fog(fog_on(fl), base, ink, sky, front, depth))
