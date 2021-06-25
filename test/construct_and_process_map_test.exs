
defmodule ConstructAndProcessMap do
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
    byte_types = [BT.uint16(), BT.uint16(), BT.int16(), BT.int16(), BT.int32(), BT.int32()]
    # NOTE: Standard UBX messages don't use floats or doubles, but that doesn't mean we can't
    multipliers = [0.005, 0.001, 0.01, 0.1, 0.0001, 0.00001]
    keys = [:a, :b, :c, :d, :e, :f]
    values = %{d: 3, e: 4, f: -5.123, c: -6, b: 7.01, a: 8.02}
# values = %{a: 3, b: 4, c: -5, d: -6, e: 7.01, f: -8.02}
    msg = UbxInterpreter.Utils.construct_message_from_map(msg_class, msg_id, byte_types, multipliers, keys, values)

    # Act as though we just received this message in binary form (like we would with UART)
    rx_data = :binary.bin_to_list(msg)
    {_ubx, payload} = UbxInterpreter.check_for_new_message(ubx, rx_data)
    values_rx = UbxInterpreter.Utils.deconstruct_message_to_map(byte_types, multipliers, keys, payload)
    Logger.debug("values_rx: #{inspect(values_rx)}")
    Enum.each(values_rx, fn {key, value} ->
      assert_in_delta(value, Map.get(values, key), 0.001)
    end)
  end
end
