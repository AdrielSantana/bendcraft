# PROOF.bend: every law of LAWS.bend, closed. `bend PROOF.bend` prints
# "All terms check" when the rules hold, and fails on the first that does
# not. Concrete laws reduce to the same value; the day period is proved
# for every word by induction over its low bits, below.

import Base
import ./LAWS.bend as Laws
import ./src/day.bend as Day

def Laws.pick_origin(): {==}
def Laws.pick_far_corner(): {==}
def Laws.pick_far_corner_y(): {==}
def Laws.pick_far_corner_z(): {==}
def Laws.pick_inside(): {==}
def Laws.pick_inside_z(): {==}
def Laws.ring_window_spans_the_slots(): {==}
def Laws.ring_rows_are_consecutive(): {==}
def Laws.place_sets_the_bit(): {==}
def Laws.break_clears_the_bit(): {==}
def Laws.break_of_air_is_nothing(): {==}
def Laws.nib_roundtrip(): {==}
def Laws.nib_keeps_the_one_below(): {==}
def Laws.nib_keeps_the_one_above(): {==}
def Laws.nib_top_of_the_word(): {==}
def Laws.nib_device_agrees(): {==}
def Laws.nib_device_agrees_high(): {==}
def Laws.top_is_grass(): {==}
def Laws.under_the_top_is_dirt(): {==}
def Laws.deep_is_stone(): {==}
def Laws.low_top_is_sand(): {==}
def Laws.high_top_is_snow(): {==}
def Laws.packed_word_reads_back(): {==}
def Laws.packed_word_reads_back_dirt(): {==}
def Laws.trunk_is_wood(): {==}
def Laws.leaves_over_the_trunk(): {==}
def Laws.grass_under_the_trunk(): {==}
def Laws.keys_off_the_mouse_bits(): {==}
def Laws.unknown_key_is_no_bit(): {==}
def Laws.stat_keeps_the_looks(): {==}
def Laws.stat_ms_reads_back(): {==}
def Laws.stat_fps_reads_back(): {==}
def Laws.stat_stops_at_its_room(): {==}
def Laws.stat_zero_is_the_game(): {==}

def Laws.day_wraps_to_dawn(): {==}
def Laws.stat_keeps_high_looks(): {==}
def Laws.stat_high_ms_reads_back(): {==}
def Laws.stat_high_fps_reads_back(): {==}
def Laws.stat_high_zero_is_the_game(): {==}

# A power of two has no set bit below its exponent. Adding it cannot
# change the low bits selected by the phase mask; the upper bits vanish.
def mask(n: Nat, k: Nat) -> Word(n):
  match n:
    case 0n:
      WNil{}
    case 1n+p:
      match k:
        case 0n:
          WCon{False{}, Word.zero(p)}
        case 1n+j:
          WCon{True{}, mask(p, j)}

def period(n: Nat, k: Nat) -> Word(n):
  match n:
    case 0n:
      WNil{}
    case 1n+p:
      match k:
        case 0n:
          WCon{True{}, Word.zero(p)}
        case 1n+j:
          WCon{False{}, period(p, j)}

def zero_mask(n: Nat, a: Word(n)) -> {Word.and(n, a, Word.zero(n)) == Word.zero(n) : Word(n)}:
  match n:
    case 0n:
      {==}
    case 1n+p:
      match a:
        case WCon{b, t}:
          match b:
            case False{}:
              %zero_mask(p, t) : {WCon{False{}, Word.and(p, t, Word.zero(p))} == WCon{False{}, _} : Word(1n+p)}
              {==}
            case True{}:
              %zero_mask(p, t) : {WCon{False{}, Word.and(p, t, Word.zero(p))} == WCon{False{}, _} : Word(1n+p)}
              {==}

def period_mask(+n: Nat, +k: Nat, +a: Word(n)) -> {Word.and(n, Word.add(n, a, period(n, k)), mask(n, k)) == Word.and(n, a, mask(n, k)) : Word(n)}:
  match n:
    case 0n:
      {==}
    case 1n+p:
      match k:
        case 0n:
          %Equal.sym(Word(1n+p), Word.and(1n+p, a, Word.zero(1n+p)), Word.zero(1n+p), zero_mask(1n+p, a)) : {Word.and(1n+p, Word.add(1n+p, a, period(1n+p, 0n)), mask(1n+p, 0n)) == _ : Word(1n+p)}
          zero_mask(1n+p, Word.add(1n+p, a, period(1n+p, 0n)))
        case 1n+j:
          match a:
            case WCon{b, t}:
              match b:
                case False{}:
                  %period_mask(p, j, t) : {WCon{False{}, Word.and(p, Word.add(p, t, period(p, j)), mask(p, j))} == WCon{False{}, _} : Word(1n+p)}
                  {==}
                case True{}:
                  %period_mask(p, j, t) : {WCon{True{}, Word.and(p, Word.add(p, t, period(p, j)), mask(p, j))} == WCon{True{}, _} : Word(1n+p)}
                  {==}

def Laws.day_returns_after_a_full_turn(t):
  match t:
    case U32{w}:
      %period_mask(32n, 20n, w) : {U32{Word.and(32n, Word.add(32n, w, period(32n, 20n)), mask(32n, 20n))} == U32{_} : U32}
      {==}
