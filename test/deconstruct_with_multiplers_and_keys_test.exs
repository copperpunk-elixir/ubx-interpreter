defmodule DeconstructWithMultipliersAndKeysTest do
  use ExUnit.Case
  require Logger

  setup do
    {:ok, []}
  end

  test "Deconstruct NavPvt" do
    values = [
      1,
      2,
      1000,
      1.0e6,
      -1.0e6,
      -2.0e6,
      -3.0e6,
      -4.0e6,
      5.0e6,
      12_345_678,
      -1,
      -2,
      -3,
      4,
      5,
      5,
      5,
      5,
      5,
      5,
      6
    ]

    values = Enum.map(values, fn x -> round(x) end)

    bytes = [1, 1, 2, 4, -4, -4, -4, -4, -4, 4, -1, -1, -1, -1, 4, 4, 4, 4, 4, 4, 4]
    msg_class = 0x01
    msg_id = 0x3C
    msg = UbxInterpreter.Utils.construct_message(msg_class, msg_id, bytes, values)

    multipliers = [
      0,
      0,
      0,
      1.0e-3,
      0,
      0,
      0,
      1.0e-2,
      1.0e-5,
      0,
      0,
      0,
      0,
      1.0e-4,
      0,
      0,
      0,
      0,
      0,
      0,
      1
    ]

    keys = [
      nil,
      nil,
      nil,
      :itow_s,
      nil,
      nil,
      nil,
      :rel_pos_length_m,
      :rel_pos_heading_deg,
      nil,
      nil,
      nil,
      nil,
      :rel_pos_hp_length_m,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      :flags
    ]

    ubx = UbxInterpreter.new()
    {ubx, payload_rx} = UbxInterpreter.check_for_new_message(ubx, :binary.bin_to_list(msg))
    values_rx = UbxInterpreter.Utils.deconstruct_message(bytes, multipliers, keys, payload_rx)
    Enum.each(values_rx, fn {key, value} ->
      key_index = Enum.find_index(keys,fn x -> key==x end )
      assert_in_delta(value, Enum.at(values, key_index)*Enum.at(multipliers,key_index), 0.001)
    end)
  end
end
