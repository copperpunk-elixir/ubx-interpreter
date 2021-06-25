defmodule ConstructAndProcessList do
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
    msg = UbxInterpreter.Utils.construct_message_from_list(msg_class, msg_id, byte_types, values)

    # Act as though we just received this message in binary form (like we would with UART)
    rx_data = :binary.bin_to_list(msg)
    {_ubx, payload} = UbxInterpreter.check_for_new_message(ubx, rx_data)
    values_rx = UbxInterpreter.Utils.deconstruct_message_to_list(byte_types, multipliers, payload)

    Enum.each(Enum.with_index(values_rx), fn {value, index} ->
      expected_value = Enum.at(values, index) * Enum.at(multipliers, index)
      Logger.debug("value/rx_value: #{expected_value}/#{value}")
      assert_in_delta(value, expected_value, 0.001)
    end)
  end
end
