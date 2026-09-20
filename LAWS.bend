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

# --- the ring: a 128x128 window falls one-to-one on the 16384 slots -------
# world column (x, z) at slot x * 128 + z, read mod 16384 by the array; the
# far corner of a window is 16383 slots after the near one, and the column
# after the end of a row is the slot after it, so the window's 16384
# columns are the 16384 slots, each once

law ring_window_spans_the_slots:
  {(World.col_at((1048512 * 128 + 1048512 : U32), 127, 127) - World.col_at((1048512 * 128 + 1048512 : U32), 0, 0) : U32) == 16383 : U32}

law ring_rows_are_consecutive:
  {(World.col_at((1048512 * 128 + 1048512 : U32), 1, 0) - World.col_at((1048512 * 128 + 1048512 : U32), 0, 127) : U32) == 1 : U32}

# --- an edit is one bit ----------------------------------------------------

law place_sets_the_bit:
  {World.setbit(1023, 1048576, True{}) == 1049599 : U32}

law break_clears_the_bit:
  {World.setbit(1049599, 1048576, False{}) == 1023 : U32}

law break_of_air_is_nothing:
  {World.setbit(1023, 1048576, False{}) == 1023 : U32}

# --- the keys never touch the mouse's bits of `held` (16384, 32768) --------

law keys_off_the_mouse_bits:
  {((Player.kmask(119) .|. Player.kmask(97) .|. Player.kmask(115) .|. Player.kmask(100)
     .|. Player.kmask(63232) .|. Player.kmask(63233) .|. Player.kmask(63234) .|. Player.kmask(63235)
     .|. Player.kmask(106) .|. Player.kmask(108) .|. Player.kmask(27) .|. Player.kmask(32)) .&. 49152 : U32) == 0 : U32}

law unknown_key_is_no_bit:
  {Player.kmask(65) == 0 : U32}
