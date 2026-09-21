# PROOF.bend: every law of LAWS.bend, closed. `bend PROOF.bend` prints
# "All terms check" when the rules hold, and fails on the first that does
# not. Concrete laws reduce to the same value; the day period is proved
# for every word by induction over its low bits, below.

import Base
import ./LAWS.bend as Laws
import ./src/day.bend as Day
import ./src/inventory.bend as Inventory

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

def Laws.inventory_transfer_conserves(put, solid, n):
  match put solid:
    case False{} False{}: {==}
    case False{} True{}: {==}
    case True{} True{}: {==}
    case True{} False{}:
      match n:
        case 0n: {==}
        case 1n+p: {==}

def Laws.inventory_trace_conserves(actions, m):
  match actions:
    case Nil{}: {==}
    case Con{+put, rest}:
      match m:
        case Inventory.Transfer{+solid, +n, changed}:
          %Laws.inventory_transfer_conserves(put, solid, n) : {Inventory.stock(Inventory.trace(rest, Inventory.transfer(put, solid, n))) == _ : Nat}
          Laws.inventory_trace_conserves(rest, Inventory.transfer(put, solid, n))

def Laws.inventory_zero_cannot_place(): {==}
def Laws.inventory_air_gives_nothing(n): {==}
def Laws.inventory_occupied_cannot_spend(n): {==}
def Laws.inventory_break_place_restores(n): {==}

def replace_length(t: List<&2, Nat>, m: Inventory.Transfer) -> {List.length(&2, Nat, Inventory.edited(Inventory.replace(t, m))) == 1n+List.length(&2, Nat, t) : Nat}:
  match m:
    case Inventory.Transfer{solid, n, changed}: {==}

def prepend_length(h: Nat, e: Inventory.Edit) -> {List.length(&2, Nat, Inventory.edited(Inventory.prepend(h, e))) == 1n+List.length(&2, Nat, Inventory.edited(e)) : Nat}:
  match e:
    case Inventory.Edit{xs, changed}: {==}

def Laws.inventory_keeps_slot_count(xs, i, put, solid):
  match xs:
    case Nil{}: {==}
    case Con{+h, +t}:
      match i:
        case 0n:
          replace_length(t, Inventory.transfer(put, solid, h))
        case 1n+ +p:
          %Laws.inventory_keeps_slot_count(t, p, put, solid) : {List.length(&2, Nat, Inventory.edited(Inventory.prepend(h, Inventory.edit(t, p, put, solid)))) == 1n+_ : Nat}
          prepend_length(h, Inventory.edit(t, p, put, solid))

def Laws.inventory_hud_slots_read_back(): {==}
def Laws.inventory_hud_keeps_selection(): {==}
def Laws.inventory_hud_empty_is_zero(): {==}
def Laws.inventory_hud_99_is_exact(): {==}
def Laws.inventory_hud_large_is_capped(): {==}
def Laws.save_and_quit_survive_the_step(): {==}

def Laws.stat_items_keeps_counts(): {==}
def Laws.stat_fps_crosses_the_split(): {==}
def Laws.stat_keeps_water_room(): {==}
def Laws.stat_water_room_is_not_a_number(): {==}
def Laws.stat_high_fps_is_visible(): {==}
