# PROOF.bend: every law of LAWS.bend, closed. `bend PROOF.bend` prints
# "All terms check" when the rules hold, and fails on the first that does
# not. Each law here is decided by computation: both sides reduce to the
# same value, and {==} closes it.

import Base
import ./LAWS.bend as Laws

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
