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
import ./src/inventory.bend as Inventory
import ./src/water.bend as Water

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
# Dry ground has grass; submerged soil has dirt, low ground sand and high
# ground snow. The packed word the loader writes reads back the same.

law top_is_grass:
  {World.tnib(11, 12) == 0 : U32}

law submerged_grass_heights_are_dirt:
  {List.map(~U32, ~U32, ~(+h => World.tnib((h - 1 : U32), h)), [7, 8, 9, 10, 11])
    == [1, 1, 1, 1, 1] : List<U32>}

law packed_lake_floor_is_dirt:
  {World.nib_get(World.types_word(1, 10, 0, 0), 9) == 1 : U32}

law under_the_top_is_dirt:
  {World.tnib(7, 10) == 1 : U32}

law deep_is_stone:
  {World.tnib(5, 10) == 2 : U32}

law low_top_is_sand:
  {World.tnib(5, 6) == 3 : U32}

law high_top_is_snow:
  {World.tnib(25, 26) == 7 : U32}

law packed_word_reads_back:
  {World.nib_get(World.types_word(1, 12, 0, 0), 11) == 0 : U32}

law packed_word_reads_back_dirt:
  {World.nib_get(World.types_word(0, 10, 0, 0), 7) == 1 : U32}

# A shoreline trunk at 12..15 is wood, its leaves are at 16 and 17.

law trunk_is_wood:
  {World.nib_get(World.types_word(1, 12, 61440, 196608), 14) == 4 : U32}

law leaves_over_the_trunk:
  {World.nib_get(World.types_word(2, 12, 61440, 196608), 16) == 5 : U32}

law grass_under_the_trunk:
  {World.nib_get(World.types_word(1, 12, 61440, 196608), 11) == 0 : U32}

# All 32 column heights: only dry grass can root a generated tree.
law trees_reject_submerged_ground:
  {List.map(~U32, ~Bool, ~(h => World.tree_ground(h)), [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11])
    == [False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}] : List<Bool>}

law trees_accept_dry_grass:
  {List.map(~U32, ~Bool, ~(h => World.tree_ground(h)), [12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24])
    == [True{}, True{}, True{}, True{}, True{}, True{}, True{}, True{}, True{}, True{}, True{}, True{}, True{}] : List<Bool>}

law trees_reject_snow_heights:
  {List.map(~U32, ~Bool, ~(h => World.tree_ground(h)), [25, 26, 27, 28, 29, 30, 31])
    == [False{}, False{}, False{}, False{}, False{}, False{}, False{}] : List<Bool>}

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
  {Render.stat_fps(Render.stat_flags(31, 164, 60), Render.stat_items(0, 60)) == 60 : U32}

law stat_stops_at_its_room:
  {(Render.stat_ms(Render.stat_flags(31, 5000, 900)), Render.stat_fps(Render.stat_flags(31, 5000, 900), Render.stat_items(0, 900))) == (999, 255) : U32 & U32}

law stat_zero_is_the_game:
  {Render.stat_flags(31, 0, 0) == 31 : U32}

# The integer phase is the sole input to the sun's trigonometry. A whole
# turn returns it for every clock word, including U32 wrap.

law day_wraps_to_dawn:
  {Day.advance(1048575, 1) == 0 : U32}

law stat_keeps_high_looks:
  {(Render.stat_flags(4261412895, 164, 60) .&. 4261412991 : U32) == 4261412895 : U32}

law stat_high_ms_reads_back:
  {Render.stat_ms(Render.stat_flags(4261412895, 164, 60)) == 164 : U32}

law stat_high_fps_reads_back:
  {Render.stat_fps(Render.stat_flags(4261412895, 164, 60), Render.stat_items(0, 60)) == 60 : U32}

law stat_high_zero_is_the_game:
  {Render.stat_flags(4261412895, 0, 0) == 4261412895 : U32}

law day_returns_after_a_full_turn:
  for t: U32
  {Day.advance(t, Day.length()) == Day.phase(t) : U32}

# A cell and its inventory count keep the same total after every action,
# and after any list of actions, including attempts to spend from zero.
law inventory_transfer_conserves:
  for put: Bool
  for solid: Bool
  for n: Nat
  {Inventory.stock(Inventory.transfer(put, solid, n)) == Inventory.stock(Inventory.Transfer{solid, n, False{}}) : Nat}

law inventory_trace_conserves:
  for actions: List<Bool>
  for m: Inventory.Transfer
  {Inventory.stock(Inventory.trace(actions, m)) == Inventory.stock(m) : Nat}

law inventory_zero_cannot_place:
  {Inventory.transfer(True{}, False{}, 0n) == Inventory.Transfer{False{}, 0n, False{}} : Inventory.Transfer}

law inventory_air_gives_nothing:
  for n: Nat
  {Inventory.transfer(False{}, False{}, n) == Inventory.Transfer{False{}, n, False{}} : Inventory.Transfer}

law inventory_occupied_cannot_spend:
  for n: Nat
  {Inventory.transfer(True{}, True{}, n) == Inventory.Transfer{True{}, n, False{}} : Inventory.Transfer}

law inventory_break_place_restores:
  for n: Nat
  {Inventory.again(True{}, Inventory.transfer(False{}, True{}, n)) == Inventory.Transfer{True{}, n, True{}} : Inventory.Transfer}

law inventory_keeps_slot_count:
  for xs: List<&2, Nat>
  for i: Nat
  for +put: Bool
  for +solid: Bool
  {List.length(&2, Nat, Inventory.edited(Inventory.edit(xs, i, put, solid))) == List.length(&2, Nat, xs) : Nat}

# Seven-bit HUD counts occupy sel's spare bits and one extra word. These
# boundary and mixed-slot packings use the same host and device defs.
def hud_sample() -> List<&2, Nat>:
  [0n, 1n, 9n, 10n, 99n, 100n, 1001n, 42n]

def hud_sample_at(i: U32) -> U32:
  Inventory.hud_count(Inventory.hud_lo(7, hud_sample()), Inventory.hud_hi(hud_sample()), i)

law inventory_hud_slots_read_back:
  {[hud_sample_at(0), hud_sample_at(1), hud_sample_at(2), hud_sample_at(3), hud_sample_at(4), hud_sample_at(5), hud_sample_at(6), hud_sample_at(7)] == [0, 1, 9, 10, 99, 100, 100, 42] : List<U32>}

law inventory_hud_keeps_selection:
  {(Inventory.hud_lo(7, hud_sample()) % 8 : U32) == 7 : U32}

law inventory_hud_empty_is_zero:
  {(Inventory.hud_lo(0, Inventory.empty()), Inventory.hud_hi(Inventory.empty())) == (0, 0) : U32 & U32}

law inventory_hud_99_is_exact:
  {Inventory.display(99n) == 99 : U32}

law inventory_hud_large_is_capped:
  {Inventory.display(1001n) == 100 : U32}

law save_and_quit_survive_the_step:
  {Player.io_edges(65535) == 4352 : U32}

# Splitting the FPS word leaves the inventory and four future looks intact.
law stat_items_keeps_counts:
  {(Render.stat_items(268435455, 255) .&. 268435455 : U32) == 268435455 : U32}

law stat_fps_crosses_the_split:
  {Render.stat_fps(Render.stat_flags(0, 0, 16), Render.stat_items(0, 16)) == 16 : U32}

law stat_keeps_water_room:
  {(Render.stat_flags(31457280, 999, 255) .&. 31457280 : U32) == 31457280 : U32}

law stat_water_room_is_not_a_number:
  {Render.stat_on(31457280, 0) == False{} : Bool}

law stat_high_fps_is_visible:
  {Render.stat_on(0, Render.stat_items(0, 16)) == True{} : Bool}

# The still-water mask never turns water into a solid. These integer laws
# cover generation and displacement; no flow is simulated yet.
law water_fills_above_ground:
  {World.flood(10, 0) == 3072 : U32}

law water_stops_at_sea:
  {World.flood(12, 0) == 0 : U32}

law water_generation_skips_solids:
  {World.flood(10, 1024) == 2048 : U32}

law water_place_is_not_solid:
  {World.masks(World.edit_col(World.Col{0, 0, 0, 0, 0, 0}, 31, True{}, 8)) == (0, 2147483648) : U32 & U32}

law solid_displaces_water:
  {World.masks(World.edit_col(World.Col{0, 0, 0, 0, 0, 1024}, 10, True{}, 6)) == (1024, 0) : U32 & U32}

law water_edit_keeps_neighbors:
  {World.masks(World.edit_col(World.Col{16, 0, 0, 0, 0, 32}, 10, True{}, 8)) == (16, 1056) : U32 & U32}

law draining_water_keeps_solids:
  {World.masks(World.edit_col(World.Col{16, 0, 0, 0, 0, 1056}, 10, False{}, 0)) == (16, 32) : U32 & U32}

law water_type_reads_back:
  {World.nib_get(World.nib_set(0, 7, 8), 7) == 8 : U32}

law water_cannot_replace_a_bank:
  {World.edit_col(World.Col{1024, 0, 1536, 0, 0, 2048}, 10, True{}, 8) == World.Col{1024, 0, 1536, 0, 0, 2048} : World.Col}

law water_fog_has_its_own_flag:
  {Water.fog_on(2097152) == False{} : Bool}

law water_fog_is_on_by_default:
  {Water.fog_on(Render.looks()) == True{} : Bool}

law readout_keeps_water_fog:
  {Water.fog_on(Render.stat_flags(4194304, 999, 255)) == True{} : Bool}
