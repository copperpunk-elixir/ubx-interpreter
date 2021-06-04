defmodule UbxInterpreterTest do
  use ExUnit.Case
  require UbxInterpreter.ByteTypes, as: BT

  setup do
    Logger.add_backend(RingLogger)
    RingLogger.attach()
    {:ok, []}
  end

  test "Ubx Construct and Process" do
    msg_class = 1
    msg_id = 2
    byte_types = [BT.uint16, BT.uint16, BT.int16, BT.int16, BT.float, BT.float]
    values = [3, 4, -5, 6, 7.01, -8.02]
    msg = UbxInterpreter.Utils.construct_message(msg_class, msg_id, byte_types, values)

    ubx = UbxInterpreter.new()

    # Pretend that we just received this message via UART
    rx_data = :binary.bin_to_list(msg)
    {_ubx, payload} = UbxInterpreter.check_for_new_message(ubx, rx_data)
    rx_values = UbxInterpreter.Utils.deconstruct_message(byte_types, payload)

    Enum.each(0..length(values)-1, fn index ->
      assert_in_delta(Enum.at(values, index), Enum.at(rx_values, index), 0.001)
    end)
  end
end
