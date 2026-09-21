# LAWS.bend: the rules of Bendcraft the checker proves. A human writes this
# file; PROOF.bend closes each law, and `bend PROOF.bend` is the gate.
#
# What belongs here is what the checker can decide: integer and bit rules,
# stated on the values the game actually uses. The float physics (a player
# never inside a block, a jump that lands) is checked by test/physics.bend,
# not proved.

import Base
import ./src/world.bend as World
import ./src/player.bend as Player
import ./src/render.bend as Render
import ./src/day.bend as Day

# --- the pick word: (lx * 32 + y) * 128 + lz, and back --------------------
# (the checker computes integers, not floats: the laws are on the integer
# packing, and pk is that packing of the floored coordinates)

law pick_origin:
  {Player.ix_x(Player.pk_u(0, 0, 0)) == 0 : U32}

law pick_far_corner:
  {Player.ix_x(Player.pk_u(127, 31, 127)) == 127 : U32}

law pick_far_corner_y:
  {Player.ix_y(Player.pk_u(127, 31, 127)) == 31 : U32}

law pick_far_corner_z:
  {Player.ix_z(Player.pk_u(127, 31, 127)) == 127 : U32}

law pick_inside:
  {Player.ix_y(Player.pk_u(64, 19, 65)) == 19 : U32}

law pick_inside_z:
  {Player.ix_z(Player.pk_u(64, 19, 65)) == 65 : U32}

# --- the ring: a 128x128 window falls one-to-one on the 16384 columns ------
# world column (x, z) at slot (x * 128 + z) * 8, read mod 2^17 by the array;
# the far corner of a window is 16383 columns after the near one, and the
# column after the end of a row is the next one, so the window's 16384
# columns are the 16384 column slots, each once

law ring_window_spans_the_slots:
  {(World.col_at((1048512 * 128 + 1048512 : U32), 127, 127) - World.col_at((1048512 * 128 + 1048512 : U32), 0, 0) : U32) == (16383 * 8 : U32) : U32}

law ring_rows_are_consecutive:
  {(World.col_at((1048512 * 128 + 1048512 : U32), 1, 0) - World.col_at((1048512 * 128 + 1048512 : U32), 0, 127) : U32) == 8 : U32}

# --- an edit is one bit ----------------------------------------------------

law place_sets_the_bit:
  {World.setbit(1023, 1048576, True{}) == 1049599 : U32}

law break_clears_the_bit:
  {World.setbit(1049599, 1048576, False{}) == 1023 : U32}

law break_of_air_is_nothing:
  {World.setbit(1023, 1048576, False{}) == 1023 : U32}

# --- a block's type: four bits in the column's words -----------------------
# nib_set writes one nibble and keeps the others; nib_get reads it back;
# nib_at, the device's read with a select in place of a shift, agrees

law nib_roundtrip:
  {World.nib_get(World.nib_set(0, 5, 7), 5) == 7 : U32}

law nib_keeps_the_one_below:
  {World.nib_get(World.nib_set(4294967295, 5, 0), 4) == 15 : U32}

law nib_keeps_the_one_above:
  {World.nib_get(World.nib_set(4294967295, 5, 0), 6) == 15 : U32}

law nib_top_of_the_word:
  {World.nib_get(World.nib_set(0, 7, 9), 7) == 9 : U32}

law nib_device_agrees:
  {World.nib_at(World.nib_set(0, 6, 9), 6) == 9 : U32}

law nib_device_agrees_high:
  {World.nib_at(World.nib_set(0, 7, 3), 7) == 3 : U32}

# --- what the terrain is made of ---------------------------------------------
# a column of height 10: grass on top, three of dirt, stone below; a low
# column is capped with sand, a high one with snow; and the packed word
# the loader writes reads back the same

law top_is_grass:
  {World.tnib(9, 10) == 0 : U32}

law under_the_top_is_dirt:
  {World.tnib(7, 10) == 1 : U32}

law deep_is_stone:
  {World.tnib(5, 10) == 2 : U32}

law low_top_is_sand:
  {World.tnib(5, 6) == 3 : U32}

law high_top_is_snow:
  {World.tnib(25, 26) == 7 : U32}

law packed_word_reads_back:
  {World.nib_get(World.types_word(1, 10, 0, 0), 9) == 0 : U32}

law packed_word_reads_back_dirt:
  {World.nib_get(World.types_word(0, 10, 0, 0), 7) == 1 : U32}

# a trunk on a column of height 10 sits at 10..13 as wood, its leaves at
# 14 and 15; one column out the leaves are at 12..14

law trunk_is_wood:
  {World.nib_get(World.types_word(1, 10, 15360, 49152), 12) == 4 : U32}

law leaves_over_the_trunk:
  {World.nib_get(World.types_word(1, 10, 15360, 49152), 14) == 5 : U32}

law grass_under_the_trunk:
  {World.nib_get(World.types_word(1, 10, 15360, 49152), 9) == 0 : U32}

# --- the keys never touch the mouse's bits of `held` (16384, 32768) --------

law keys_off_the_mouse_bits:
  {((Player.kmask(119) .|. Player.kmask(97) .|. Player.kmask(115) .|. Player.kmask(100)
     .|. Player.kmask(63232) .|. Player.kmask(63233) .|. Player.kmask(63234) .|. Player.kmask(63235)
     .|. Player.kmask(106) .|. Player.kmask(108) .|. Player.kmask(112) .|. Player.kmask(27) .|. Player.kmask(32)) .&. 49152 : U32) == 0 : U32}

law unknown_key_is_no_bit:
  {Player.kmask(65) == 0 : U32}

# --- the readout rides above the looks --------------------------------------
# the flags word keeps its five looks and neither debug bit under any
# numbers; the numbers read back; past their room they stop at 99.9 and 255

law stat_keeps_the_looks:
  {(Render.stat_flags(31, 164, 60) % 128 : U32) == 31 : U32}

law stat_ms_reads_back:
  {Render.stat_ms(Render.stat_flags(31, 164, 60)) == 164 : U32}

law stat_fps_reads_back:
  {Render.stat_fps(Render.stat_flags(31, 164, 60)) == 60 : U32}

law stat_stops_at_its_room:
  {Render.stat_flags(31, 5000, 900) == 33551263 : U32}

law stat_zero_is_the_game:
  {Render.stat_flags(31, 0, 0) == 31 : U32}

# The integer phase is the sole input to the sun's trigonometry. A whole
# turn returns it at each quarter, at the default morning and at U32 wrap.

law day_returns_at_dawn:
  {Day.advance(0, Day.length()) == Day.phase(0) : U32}

law day_returns_at_noon:
  {Day.advance(262144, Day.length()) == Day.phase(262144) : U32}

law day_returns_at_dusk:
  {Day.advance(524288, Day.length()) == Day.phase(524288) : U32}

law day_returns_at_night:
  {Day.advance(786432, Day.length()) == Day.phase(786432) : U32}

law day_returns_at_morning:
  {Day.advance(Day.morning(), Day.length()) == Day.phase(Day.morning()) : U32}

law day_returns_across_word_wrap:
  {Day.advance(4294967295, Day.length()) == Day.phase(4294967295) : U32}

law day_wraps_to_dawn:
  {Day.advance(1048575, 1) == 0 : U32}

law stat_keeps_high_looks:
  {(Render.stat_flags(4261412895, 164, 60) .&. 4261412991 : U32) == 4261412895 : U32}

law stat_high_ms_reads_back:
  {Render.stat_ms(Render.stat_flags(4261412895, 164, 60)) == 164 : U32}

law stat_high_fps_reads_back:
  {Render.stat_fps(Render.stat_flags(4261412895, 164, 60)) == 60 : U32}

law stat_high_zero_is_the_game:
  {Render.stat_flags(4261412895, 0, 0) == 4261412895 : U32}
