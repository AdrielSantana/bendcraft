import Base

# One turn is 2^20 milliseconds (17 minutes 28.576 seconds). Keeping the
# phase as an integer avoids drift, including across saves and U32 wrap.
def length() -> U32: 1048576

def phase(t: U32) -> U32: (t .&. 1048575 : U32)

def advance(t: U32, ms: U32) -> U32: phase((t + ms : U32))

def morning() -> U32: 154747

def angle(t: U32) -> F32:
  (U32.to_f32(phase(t)) * (6.2831853 / 1048576.0) : F32)

def sun_x(t: U32) -> F32: (0.8 * F32.cos(angle(t)) : F32)
def sun_y(t: U32) -> F32: F32.sin(angle(t))
def sun_z(t: U32) -> F32: (0.6 * F32.cos(angle(t)) : F32)
