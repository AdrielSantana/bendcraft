import Base

# One turn is 2^20 milliseconds (17 minutes 28.576 seconds). The clock
# counts milliseconds across the days, the weather's input, and its word
# wraps after 4096 whole turns, so the phase, the sun's, never jumps.
def length() -> U32: 1048576

def phase(t: U32) -> U32: (t .&. 1048575 : U32)

def advance(t: U32, ms: U32) -> U32: (t + ms : U32)

# the clock ms on, 64 times as fast forward (fast) or back (back), and
# back no further than the first dawn: the keys H and G held, for a demo
def run(+t: U32, +ms: U32, +fast: Bool, +back: Bool) -> U32:
  Bool.pick(U32, back, (t - U32.min(t, (ms * 64 : U32)) : U32), advance(t, Bool.pick(U32, fast, (ms * 64 : U32), ms)))

def morning() -> U32: 154747

def angle(t: U32) -> F32:
  (U32.to_f32(phase(t)) * (6.2831853 / 1048576.0) : F32)

def sun_x(t: U32) -> F32: (0.8 * F32.cos(angle(t)) : F32)
def sun_y(t: U32) -> F32: F32.sin(angle(t))
def sun_z(t: U32) -> F32: (0.6 * F32.cos(angle(t)) : F32)
