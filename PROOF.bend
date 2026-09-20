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
def Laws.keys_off_the_mouse_bits(): {==}
def Laws.unknown_key_is_no_bit(): {==}
