defmodule UbxInterpreterTest do
  use ExUnit.Case
  require UbxInterpreter.ByteTypes, as: BT
  require Logger

  setup do
    RingLogger.attach
    {:ok, []}
  end

  test "Ubx Construct and Process" do
    ubx = UbxInterpreter.new()

    msg_class = 1
    msg_id = 2

    # We must specify the message definition, in terms of data types, i.e., number of bytes for each value
    byte_types = [BT.uint16(), BT.uint16(), BT.int16(), BT.int16(), BT.float(), BT.float()]
    # NOTE: Standard UBX messages don't use floats or doubles, but that doesn't mean we can't

    values = [3, 4, -5, 6, 7.01, -8.02]
    multipliers = List.duplicate(1, length(values))
    keys = Enum.to_list(1..length(values)+1)
    msg = UbxInterpreter.Utils.construct_message(msg_class, msg_id, byte_types, values)

    # Act as though we just received this message in binary form (like we would with UART)
    rx_data = :binary.bin_to_list(msg)
    {_ubx, payload} = UbxInterpreter.check_for_new_message(ubx, rx_data)
    values_rx = UbxInterpreter.Utils.deconstruct_message(byte_types, multipliers, keys, payload)

    Enum.each(values_rx, fn {key, value} ->
      key_index = Enum.find_index(keys, fn x -> key == x end)
      assert_in_delta(value, Enum.at(values, key_index) * Enum.at(multipliers, key_index), 0.001)
    end)
  end
end
