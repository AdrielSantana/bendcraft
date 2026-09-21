import Base
import ./sky.bend as Sky

# A ray accumulates only the wet intervals before its first solid hit.
# The entry distance gives air fog its endpoint, including a submerged eye
# (entry zero), vertical banks and gaps left by edits.
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
def tint(+bottom: U32, +depth: F32, +sun_y: F32) -> U32:
  +colour = Sky.mix(Sky.rgb(7, 28, 43), Sky.rgb(26, 113, 132), Sky.daylight(sun_y))
  Sky.mix(bottom, colour, (0.18 + 0.72 * depth / (depth + 4.0) : F32))

def shade(on: Bool, +fl: U32, +sky: U32, +oy: F32, +dy: F32, +sun_y: F32,
          tr: Trace, r: Array<U32> & U32) -> Array<U32> & U32:
  match on:
    case False{}: r
    case True{}:
      Trace{+entry, depth} = tr
      (w, bottom) = r
      (w, Sky.mix(tint(bottom, depth, sun_y), sky, Sky.fog(fl, entry, oy, (oy + dy * entry : F32))))
