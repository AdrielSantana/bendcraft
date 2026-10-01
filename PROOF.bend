# PROOF.bend: every law of LAWS.bend, closed. `bend PROOF.bend` prints
# ALL PROOFS CHECK when the rules hold, and SOME PROOFS FAIL with the first
# that does not. Concrete laws reduce to the same value; the day period is proved
# for every word by induction over its low bits, and a cell's word for every
# cell through the naturals, below.

import Base
import ./LAWS.bend as Laws
import ./src/day.bend as Day
import ./src/inventory.bend as Inventory
import ./src/water.bend as Water
import ./src/world.bend as World
import bend-collections-laws-containers@1.0.0.0/proofs/lib/nat.bend as N
import bend-collections-laws-containers@1.0.0.0/proofs/lib/u32.bend as U
import bend-collections-laws-containers@1.0.0.0/proofs/lib/u32div.bend as UD
import bend-collections-laws-containers@1.0.0.0/proofs/lib/lemmas/proofs/nat_algebra.bend as NA
import bend-collections-laws-containers@1.0.0.0/proofs/lib/lemmas/proofs/natural_products.bend as PR
import bend-collections-laws-containers@1.0.0.0/proofs/lib/lemmas/proofs/word_multiplication.bend as Mul
import bend-collections-laws-containers@1.0.0.0/proofs/lib/lemmas/proofs/word_addition.bend as Add
import bend-collections-laws-containers@1.0.0.0/proofs/lib/lemmas/proofs/division_quotient.bend as DQ
import bend-collections-laws-containers@1.0.0.0/proofs/lib/lemmas/spec/numeric.bend as S
import bend-collections-laws-containers@1.0.0.0/spec/lib/common.bend as SC

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
def Laws.submerged_grass_heights_are_dirt(): {==}
def Laws.packed_lake_floor_is_dirt(): {==}
def Laws.under_the_top_is_dirt(): {==}
def Laws.deep_is_stone(): {==}
def Laws.low_top_is_sand(): {==}
def Laws.high_top_is_snow(): {==}
def Laws.packed_word_reads_back(): {==}
def Laws.packed_word_reads_back_dirt(): {==}
def Laws.trunk_is_wood(): {==}
def Laws.leaves_over_the_trunk(): {==}
def Laws.grass_under_the_trunk(): {==}
def Laws.trees_reject_submerged_ground(): {==}
def Laws.trees_accept_dry_grass(): {==}
def Laws.trees_reject_snow_heights(): {==}
def Laws.unknown_key_is_no_bit(): {==}
def Laws.wheel_goes_around(): {==}
def Laws.stat_reads_back(): {==}
def Laws.stat_stops_at_its_room(): {==}
def Laws.stat_zero_is_the_game(): {==}
def Laws.a_frame_a_second_shows(): {==}

def Laws.day_wraps_to_dawn(): {==}

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

def Laws.the_clock_runs_as_ever_with_no_key(t, ms): {==}

def Laws.h_runs_the_clock_64_times_as_fast(): {==}

def Laws.g_runs_it_back_no_further_than_dawn(): {==}

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


def Laws.water_fills_above_ground(): {==}
def Laws.water_stops_at_sea(): {==}
def Laws.water_generation_skips_solids(): {==}
def Laws.water_place_is_not_solid(): {==}
def Laws.solid_displaces_water(): {==}
def Laws.water_edit_keeps_neighbors(): {==}
def Laws.draining_water_keeps_solids(): {==}
def Laws.water_type_reads_back(): {==}
def Laws.water_cannot_replace_a_bank(): {==}

def Laws.full_levels_follow_the_mask(): {==}
def Laws.full_levels_of_a_dry_column(): {==}
def Laws.amount_reads_its_byte(): {==}
def Laws.amount_reads_its_byte_up(): {==}
def Laws.a_byte_reads_back(): {==}
def Laws.a_byte_set_keeps_the_others(): {==}
def Laws.the_device_reads_the_same_byte(): {==}
def Laws.water_placed_is_a_full_cell(): {==}
def Laws.solid_placed_holds_no_water(): {==}
def Laws.pour_sets_the_amount_and_the_bit(): {==}
def Laws.pour_keeps_the_amount(): {==}
def Laws.pour_of_nothing_clears_the_bit(): {==}
def Laws.pour_is_capped_at_255(): {==}
def Laws.a_poured_cell_is_partial(): {==}
def Laws.a_full_cell_is_not_partial(): {==}
def Laws.pour_into_a_solid_is_nothing(): {==}
def Laws.the_bucket_takes_the_cell_whole(): {==}
def Laws.the_bucket_takes_nothing_from_a_solid(): {==}
def Laws.a_pour_is_what_the_cell_lacks(): {==}
def Laws.a_pour_into_air_is_a_full_cell(): {==}
def Laws.a_pour_into_a_full_cell_is_nothing(): {==}
def Laws.a_pour_into_a_solid_is_nothing(): {==}
def Laws.the_bucket_is_the_ninth_slot(): {==}
def Laws.the_bucket_shows_its_full_cells(): {==}
def Laws.the_window_wraps_under_the_far_map(): {==}
def Laws.far_columns_live_above_the_window(): {==}
def Laws.the_render_reads_what_the_host_wrote(): {==}
def Laws.a_far_column_is_its_run_and_its_canopy(): {==}
def Laws.a_column_s_top_is_its_run_s_or_its_canopy_s(): {==}
def Laws.leaves_inside_the_run_are_the_run_s(): {==}
def Laws.a_far_ground_is_grass_dirt_and_stone(): {==}
def Laws.a_far_trunk_is_wood_under_its_leaves(): {==}
def Laws.the_far_sea_is_water_over_its_bed(): {==}
def Laws.the_far_sea_is_not_solid(): {==}
def Laws.the_far_sea_is_a_plane_over_its_bed(): {==}
def Laws.what_fits_is_the_room(): {==}
def Laws.what_fits_is_all_of_less(): {==}
def Laws.nothing_fits_in_full(): {==}
def Laws.nothing_fits_in_a_solid(): {==}
def Laws.a_solid_placed_on_water_shoves_its_amount(): {==}
def Laws.water_placed_shoves_nothing(): {==}
def Laws.a_break_shoves_nothing(): {==}
def Laws.water_fog_has_its_own_flag(): {==}
def Laws.water_fog_is_on_by_default(): {==}
def Laws.water_surface_packing_reads_back(): {==}
def Laws.water_top_stays_marked(): {==}
def Laws.water_reflection_has_its_own_flag(): {==}
def Laws.water_fresnel_has_its_own_flag(): {==}
def Laws.water_surface_looks_are_on_by_default(): {==}

def Laws.ripple_clock_returns_after_a_turn(t):
  match t:
    case U32{w}:
      %period_mask(32n, 13n, w) : {U32{Word.and(32n, Word.add(32n, w, period(32n, 13n)), mask(32n, 13n))} == U32{_} : U32}
      {==}

def Laws.ripple_clock_wraps_with_the_day(): {==}
def Laws.ripple_lattice_follows_recentering(): {==}
def Laws.ripple_flag_is_independent(): {==}
def Laws.mirror_look_reads_back(): {==}
def Laws.mirror_look_is_off_unasked(): {==}
def Laws.mirror_look_keeps_the_ring(): {==}
def Laws.caustic_look_reads_back(): {==}
def Laws.caustic_look_is_off_unasked(): {==}
def Laws.a_side_takes_half_the_difference(): {==}
def Laws.a_side_never_takes_past_the_giver(): {==}
def Laws.a_side_takes_nothing_from_less(): {==}
def Laws.a_lone_unit_stays(): {==}
def Laws.a_side_of_a_solid_takes_nothing(): {==}
def Laws.the_sides_reverse_on_an_odd_tick(): {==}
def Laws.a_tick_every_256_ms(): {==}
def Laws.the_tick_grid_survives_the_wrap(): {==}
def Laws.a_queued_slot_decodes_to_its_column(): {==}
def Laws.a_queued_slot_decodes_to_its_column_x(): {==}
def Laws.the_meadows_map_wraps_in_its_words(): {==}
def Laws.a_meadow_word_reads_back(): {==}
def Laws.the_leaf_plane_follows_the_meadows_map(): {==}
def Laws.a_leaf_mask_marks_the_solid_leaves(): {==}
def Laws.a_torch_is_not_solid(): {==}
def Laws.a_torch_rides_the_leaf_plane(): {==}
def Laws.the_break_under_a_torch_takes_it(): {==}
def Laws.water_puts_a_torch_out(): {==}
def Laws.the_light_follows_the_leaf_plane(): {==}
def Laws.a_torch_lights_its_cell_fourteen(): {==}
def Laws.a_word_of_torches_is_all_fourteen(): {==}
def Laws.no_torch_no_light(): {==}

# --- a cell's word reads back, for every cell ------------------------------
# A word is worth a natural (U32.to_nat), and there the packing is a
# number's digits: a * d + b is that sum while it fits the word, its low
# digit is b and the rest a. That a word's product, sum, quotient and
# remainder are the naturals' is proved in bend-collections (BendHub,
# github.com/Giulio2002/bend-collections), whose lemmas the imports name.

# a digit r under its base d, over q digits under n: q * d + r < n * d
def digit_lt(+q: Nat, +n: Nat, +d: Nat, +r: Nat, hq: {Nat.is_lt(q, n) == True{} : Bool}, hr: {Nat.is_lt(r, d) == True{} : Bool}) -> {Nat.is_lt(Nat.add(Nat.mul(q, d), r), Nat.mul(n, d)) == True{} : Bool}:
  match q n:
    case 0n 0n:
      Empty.absurd({Nat.is_lt(Nat.add(Nat.mul(0n, d), r), Nat.mul(0n, d)) == True{} : Bool}, N.lt_zero_absurd(0n, hq))
    case 1n+p 0n:
      Empty.absurd({Nat.is_lt(Nat.add(Nat.mul(1n+p, d), r), Nat.mul(0n, d)) == True{} : Bool}, N.lt_zero_absurd(1n+p, hq))
    case 0n 1n+m:
      N.lt_le_trans(r, d, Nat.add(d, Nat.mul(m, d)), hr, N.le_add_right(d, Nat.mul(m, d)))
    case 1n+p 1n+m:
      %Equal.sym(Nat, Nat.add(Nat.add(d, Nat.mul(p, d)), r), Nat.add(d, Nat.add(Nat.mul(p, d), r)), NA.add_assoc(d, Nat.mul(p, d), r)) : {Nat.is_lt(_, Nat.add(d, Nat.mul(m, d))) == True{} : Bool}
      N.lt_add_left(Nat.add(Nat.mul(p, d), r), Nat.mul(m, d), d, digit_lt(p, m, d, r, hq, hr))

# a word made of a natural under 2^k, k <= 32, is worth that natural
def val(+v: Nat, +k: Nat, +hk: {Nat.is_le(k, 32n) == True{} : Bool}, +hv: {Nat.is_lt(v, SC.pow2(k)) == True{} : Bool}) -> {U32.to_nat(U32{S.from_nat(32n, v)}) == v : Nat}:
  Equal.trans(Nat, U32.to_nat(U32{S.from_nat(32n, v)}), S.unsigned(32n, S.from_nat(32n, v)), v, U.to_nat_word(S.from_nat(32n, v)), U.from_nat_value_k(32n, k, v, hk, hv))

def mul_val(+a: U32, +b: U32, +k: Nat, +hk: {Nat.is_le(k, 32n) == True{} : Bool}, +hv: {Nat.is_lt(Nat.mul(U32.to_nat(a), U32.to_nat(b)), SC.pow2(k)) == True{} : Bool}) -> {U32.to_nat(U32.mul(a, b)) == Nat.mul(U32.to_nat(a), U32.to_nat(b)) : Nat}:
  Equal.trans(Nat, U32.to_nat(U32.mul(a, b)), U32.to_nat(U32{S.from_nat(32n, Nat.mul(U32.to_nat(a), U32.to_nat(b)))}), Nat.mul(U32.to_nat(a), U32.to_nat(b)),
    Equal.cong(U32, Nat, t => U32.to_nat(t), U32.mul(a, b), U32{S.from_nat(32n, Nat.mul(U32.to_nat(a), U32.to_nat(b)))}, Mul.u32_refines(a, b)),
    val(Nat.mul(U32.to_nat(a), U32.to_nat(b)), k, hk, hv))

def add_val(+a: U32, +b: U32, +k: Nat, +hk: {Nat.is_le(k, 32n) == True{} : Bool}, +hv: {Nat.is_lt(Nat.add(U32.to_nat(a), U32.to_nat(b)), SC.pow2(k)) == True{} : Bool}) -> {U32.to_nat(U32.add(a, b)) == Nat.add(U32.to_nat(a), U32.to_nat(b)) : Nat}:
  Equal.trans(Nat, U32.to_nat(U32.add(a, b)), U32.to_nat(U32{S.from_nat(32n, Nat.add(U32.to_nat(a), U32.to_nat(b)))}), Nat.add(U32.to_nat(a), U32.to_nat(b)),
    Equal.cong(U32, Nat, t => U32.to_nat(t), U32.add(a, b), U32{S.from_nat(32n, Nat.add(U32.to_nat(a), U32.to_nat(b)))}, Add.u32_refines(a, b)),
    val(Nat.add(U32.to_nat(a), U32.to_nat(b)), k, hk, hv))

def pack_bound(+a: U32, +c: U32, +b: U32, +k: Nat, em: {U32.to_nat(U32.mul(a, c)) == Nat.mul(U32.to_nat(a), U32.to_nat(c)) : Nat}, hv: {Nat.is_lt(Nat.add(Nat.mul(U32.to_nat(a), U32.to_nat(c)), U32.to_nat(b)), SC.pow2(k)) == True{} : Bool}) -> {Nat.is_lt(Nat.add(U32.to_nat(U32.mul(a, c)), U32.to_nat(b)), SC.pow2(k)) == True{} : Bool}:
  %Equal.sym(Nat, U32.to_nat(U32.mul(a, c)), Nat.mul(U32.to_nat(a), U32.to_nat(c)), em) : {Nat.is_lt(Nat.add(_, U32.to_nat(b)), SC.pow2(k)) == True{} : Bool}
  hv

# a * c + b in words is a * c + b in naturals, while it stays under 2^k
def pack_val(+a: U32, +c: U32, +b: U32, +k: Nat, +hk: {Nat.is_le(k, 32n) == True{} : Bool}, +hv: {Nat.is_lt(Nat.add(Nat.mul(U32.to_nat(a), U32.to_nat(c)), U32.to_nat(b)), SC.pow2(k)) == True{} : Bool}) -> {U32.to_nat(U32.add(U32.mul(a, c), b)) == Nat.add(Nat.mul(U32.to_nat(a), U32.to_nat(c)), U32.to_nat(b)) : Nat}:
  +em = mul_val(a, c, k, hk, N.le_lt_trans(Nat.mul(U32.to_nat(a), U32.to_nat(c)), Nat.add(Nat.mul(U32.to_nat(a), U32.to_nat(c)), U32.to_nat(b)), SC.pow2(k), N.le_add_right(Nat.mul(U32.to_nat(a), U32.to_nat(c)), U32.to_nat(b)), hv))
  Equal.trans(Nat, U32.to_nat(U32.add(U32.mul(a, c), b)), Nat.add(U32.to_nat(U32.mul(a, c)), U32.to_nat(b)), Nat.add(Nat.mul(U32.to_nat(a), U32.to_nat(c)), U32.to_nat(b)),
    add_val(U32.mul(a, c), b, k, hk, pack_bound(a, c, b, k, em, hv)),
    Equal.cong(Nat, Nat, t => Nat.add(t, U32.to_nat(b)), U32.to_nat(U32.mul(a, c)), Nat.mul(U32.to_nat(a), U32.to_nat(c)), em))

def under(+a: U32, +b: U32, h: {U32.is_lt(a, b) == True{} : Bool}) -> {Nat.is_lt(U32.to_nat(a), U32.to_nat(b)) == True{} : Bool}:
  %U.is_lt_nat(a, b) : {_ == True{} : Bool}
  h

def digit_nat(+p: U32, +qv: Nat, +d: U32, +r: U32, ep: {U32.to_nat(p) == Nat.add(Nat.mul(qv, U32.to_nat(d)), U32.to_nat(r)) : Nat}, hr: {Nat.is_lt(U32.to_nat(r), U32.to_nat(d)) == True{} : Bool}) -> {Nat.mod(U32.to_nat(p), U32.to_nat(d)) == U32.to_nat(r) : Nat}:
  %Equal.sym(Nat, U32.to_nat(p), Nat.add(Nat.mul(qv, U32.to_nat(d)), U32.to_nat(r)), ep) : {Nat.mod(_, U32.to_nat(d)) == U32.to_nat(r) : Nat}
  UD.mod_identify(qv, U32.to_nat(d), U32.to_nat(r), hr)

# p = qv * d + r with r < d: the low digit of p is r
def digit(+p: U32, +qv: Nat, +d: U32, +r: U32, +hd: {U32.is_zero(d) == False{} : Bool}, ep: {U32.to_nat(p) == Nat.add(Nat.mul(qv, U32.to_nat(d)), U32.to_nat(r)) : Nat}, hr: {Nat.is_lt(U32.to_nat(r), U32.to_nat(d)) == True{} : Bool}) -> {U32.mod(p, d) == r : U32}:
  U.injective(U32.mod(p, d), r, Equal.trans(Nat, U32.to_nat(U32.mod(p, d)), Nat.mod(U32.to_nat(p), U32.to_nat(d)), U32.to_nat(r), UD.mod_nat(p, d, hd), digit_nat(p, qv, d, r, ep, hr)))

def rest_nat(+p: U32, +q: U32, +d: U32, +rv: Nat, ep: {U32.to_nat(p) == Nat.add(Nat.mul(U32.to_nat(q), U32.to_nat(d)), rv) : Nat}, hr: {Nat.is_lt(rv, U32.to_nat(d)) == True{} : Bool}) -> {Nat.div(U32.to_nat(p), U32.to_nat(d)) == U32.to_nat(q) : Nat}:
  %Equal.sym(Nat, U32.to_nat(p), Nat.add(Nat.mul(U32.to_nat(q), U32.to_nat(d)), rv), ep) : {Nat.div(_, U32.to_nat(d)) == U32.to_nat(q) : Nat}
  DQ.identify(U32.to_nat(q), U32.to_nat(d), rv, hr)

# p = q * d + rv with rv < d: the digits of p over the low one are q
def rest(+p: U32, +q: U32, +d: U32, +rv: Nat, +hd: {U32.is_zero(d) == False{} : Bool}, ep: {U32.to_nat(p) == Nat.add(Nat.mul(U32.to_nat(q), U32.to_nat(d)), rv) : Nat}, hr: {Nat.is_lt(rv, U32.to_nat(d)) == True{} : Bool}) -> {U32.div(p, d) == q : U32}:
  U.injective(U32.div(p, d), q, Equal.trans(Nat, U32.to_nat(U32.div(p, d)), Nat.div(U32.to_nat(p), U32.to_nat(d)), U32.to_nat(q), UD.div_nat(p, d, hd), rest_nat(p, q, d, rv, ep, hr)))

# a word's value is under n
def Under(+a: U32, +n: Nat) -> Data:
  {Nat.is_lt(U32.to_nat(a), n) == True{} : Bool}

# (a * d1 + b) * d2 + c is a * (d1 * d2) + (b * d2 + c)
def spread(+a: Nat, +b: Nat, +c: Nat, +d1: Nat, +d2: Nat) -> {Nat.add(Nat.mul(Nat.add(Nat.mul(a, d1), b), d2), c) == Nat.add(Nat.mul(a, Nat.mul(d1, d2)), Nat.add(Nat.mul(b, d2), c)) : Nat}:
  %NA.add_assoc(Nat.mul(a, Nat.mul(d1, d2)), Nat.mul(b, d2), c) : {Nat.add(Nat.mul(Nat.add(Nat.mul(a, d1), b), d2), c) == _ : Nat}
  %NA.mul_assoc(a, d1, d2) : {Nat.add(Nat.mul(Nat.add(Nat.mul(a, d1), b), d2), c) == Nat.add(Nat.add(_, Nat.mul(b, d2)), c) : Nat}
  %NA.mul_add_right(Nat.mul(a, d1), b, d2) : {Nat.add(Nat.mul(Nat.add(Nat.mul(a, d1), b), d2), c) == Nat.add(_, c) : Nat}
  {==}

# the cell's word, (x * 32 + y) * 128 + z: its column part x * 32 + y
def col_val(+x: U32, +y: U32, hx: Under(x, 128n), hy: Under(y, 32n)) -> {U32.to_nat(U32.add(U32.mul(x, 32), y)) == Nat.add(Nat.mul(U32.to_nat(x), 32n), U32.to_nat(y)) : Nat}:
  pack_val(x, 32, y, 12n, {==}, digit_lt(U32.to_nat(x), 128n, 32n, U32.to_nat(y), hx, hy))

def col_lt(+x: U32, +y: U32, +hx: Under(x, 128n), +hy: Under(y, 32n)) -> {Nat.is_lt(U32.to_nat(U32.add(U32.mul(x, 32), y)), 4096n) == True{} : Bool}:
  %Equal.sym(Nat, U32.to_nat(U32.add(U32.mul(x, 32), y)), Nat.add(Nat.mul(U32.to_nat(x), 32n), U32.to_nat(y)), col_val(x, y, hx, hy)) : {Nat.is_lt(_, 4096n) == True{} : Bool}
  digit_lt(U32.to_nat(x), 128n, 32n, U32.to_nat(y), hx, hy)

def pow2_add(+a: Nat, +b: Nat) -> {Nat.mul(SC.pow2(a), SC.pow2(b)) == SC.pow2(Nat.add(a, b)) : Nat}:
  match a:
    case 0n:
      NA.add_zero(SC.pow2(b))
    case 1n+p:
      Equal.trans(Nat, Nat.mul(Nat.double(SC.pow2(p)), SC.pow2(b)), Nat.double(Nat.mul(SC.pow2(p), SC.pow2(b))), Nat.double(SC.pow2(Nat.add(p, b))),
        PR.double_product(SC.pow2(p), SC.pow2(b)),
        Equal.cong(Nat, Nat, t => Nat.double(t), Nat.mul(SC.pow2(p), SC.pow2(b)), SC.pow2(Nat.add(p, b)), pow2_add(p, b)))

# digit_lt on powers of two, d being 2^b: the bound stays a power, which
# the checker never counts out
def shift_lt(+q: Nat, +r: Nat, +a: Nat, +b: Nat, +d: Nat, hd: {SC.pow2(b) == d : Nat}, hq: {Nat.is_lt(q, SC.pow2(a)) == True{} : Bool}, hr: {Nat.is_lt(r, d) == True{} : Bool}) -> {Nat.is_lt(Nat.add(Nat.mul(q, d), r), SC.pow2(Nat.add(a, b))) == True{} : Bool}:
  %pow2_add(a, b) : {Nat.is_lt(Nat.add(Nat.mul(q, d), r), _) == True{} : Bool}
  %Equal.sym(Nat, SC.pow2(b), d, hd) : {Nat.is_lt(Nat.add(Nat.mul(q, d), r), Nat.mul(SC.pow2(a), _)) == True{} : Bool}
  digit_lt(q, SC.pow2(a), d, r, hq, hr)

def cell_val(+x: U32, +y: U32, +z: U32, +hx: Under(x, 128n), +hy: Under(y, 32n), hz: Under(z, 128n)) -> {U32.to_nat(World.pk_u(x, y, z)) == Nat.add(Nat.mul(U32.to_nat(U32.add(U32.mul(x, 32), y)), 128n), U32.to_nat(z)) : Nat}:
  pack_val(U32.add(U32.mul(x, 32), y), 128, z, Nat.add(12n, 7n), {==}, shift_lt(U32.to_nat(U32.add(U32.mul(x, 32), y)), U32.to_nat(z), 12n, 7n, U32.to_nat(128), {==}, col_lt(x, y, hx, hy), hz))

def cell_z(+x: U32, +y: U32, +z: U32, +hx: Under(x, 128n), +hy: Under(y, 32n), +hz: Under(z, 128n)) -> {World.ix_z(World.pk_u(x, y, z)) == z : U32}:
  digit(World.pk_u(x, y, z), U32.to_nat(U32.add(U32.mul(x, 32), y)), 128, z, {==}, cell_val(x, y, z, hx, hy, hz), hz)

def cell_col(+x: U32, +y: U32, +z: U32, +hx: Under(x, 128n), +hy: Under(y, 32n), +hz: Under(z, 128n)) -> {U32.div(World.pk_u(x, y, z), 128) == U32.add(U32.mul(x, 32), y) : U32}:
  rest(World.pk_u(x, y, z), U32.add(U32.mul(x, 32), y), 128, U32.to_nat(z), {==}, cell_val(x, y, z, hx, hy, hz), hz)

def cell_y(+x: U32, +y: U32, +z: U32, +hx: Under(x, 128n), +hy: Under(y, 32n), +hz: Under(z, 128n)) -> {World.ix_y(World.pk_u(x, y, z)) == y : U32}:
  %Equal.sym(U32, U32.div(World.pk_u(x, y, z), 128), U32.add(U32.mul(x, 32), y), cell_col(x, y, z, hx, hy, hz)) : {U32.mod(_, 32) == y : U32}
  digit(U32.add(U32.mul(x, 32), y), U32.to_nat(x), 32, y, {==}, col_val(x, y, hx, hy), hy)

def cell_x_val(+x: U32, +y: U32, +z: U32, +hx: Under(x, 128n), +hy: Under(y, 32n), hz: Under(z, 128n)) -> {U32.to_nat(World.pk_u(x, y, z)) == Nat.add(Nat.mul(U32.to_nat(x), Nat.mul(32n, 128n)), Nat.add(Nat.mul(U32.to_nat(y), 128n), U32.to_nat(z))) : Nat}:
  %spread(U32.to_nat(x), U32.to_nat(y), U32.to_nat(z), 32n, 128n) : {U32.to_nat(World.pk_u(x, y, z)) == _ : Nat}
  %col_val(x, y, hx, hy) : {U32.to_nat(World.pk_u(x, y, z)) == Nat.add(Nat.mul(_, 128n), U32.to_nat(z)) : Nat}
  cell_val(x, y, z, hx, hy, hz)

def cell_x(+x: U32, +y: U32, +z: U32, +hx: Under(x, 128n), +hy: Under(y, 32n), +hz: Under(z, 128n)) -> {World.ix_x(World.pk_u(x, y, z)) == x : U32}:
  rest(World.pk_u(x, y, z), x, 4096, Nat.add(Nat.mul(U32.to_nat(y), 128n), U32.to_nat(z)), {==}, cell_x_val(x, y, z, hx, hy, hz), digit_lt(U32.to_nat(y), 32n, 128n, U32.to_nat(z), hy, hz))

def Laws.cell_reads_back(x, y, z, hx, hy, hz):
  +nx = under(x, 128, hx)
  +ny = under(y, 32, hy)
  +nz = under(z, 128, hz)
  %cell_x(x, y, z, nx, ny, nz) : {(World.ix_x(World.pk_u(x, y, z)), (World.ix_y(World.pk_u(x, y, z)), World.ix_z(World.pk_u(x, y, z)))) == (_, (y, z)) : U32 & (U32 & U32)}
  %cell_y(x, y, z, nx, ny, nz) : {(World.ix_x(World.pk_u(x, y, z)), (World.ix_y(World.pk_u(x, y, z)), World.ix_z(World.pk_u(x, y, z)))) == (World.ix_x(World.pk_u(x, y, z)), (_, z)) : U32 & (U32 & U32)}
  %cell_z(x, y, z, nx, ny, nz) : {(World.ix_x(World.pk_u(x, y, z)), (World.ix_y(World.pk_u(x, y, z)), World.ix_z(World.pk_u(x, y, z)))) == (World.ix_x(World.pk_u(x, y, z)), (World.ix_y(World.pk_u(x, y, z)), _)) : U32 & (U32 & U32)}
  {==}
