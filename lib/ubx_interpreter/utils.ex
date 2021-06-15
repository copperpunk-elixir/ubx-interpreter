defmodule UbxInterpreter.Utils do
  require Logger
  use Bitwise

    @spec deconstruct_message(list(), list(), list(), list()) :: map()
  def deconstruct_message(byte_types, multipliers, keys, payload) do
    # byte_types = get_bytes_for_msg(msg_type)
    {_payload_rem, _multipliers, _keys, values} =
      Enum.reduce(byte_types, {payload, multipliers, keys, %{}}, fn bytes,
                                                                    {remaining_buffer,
                                                                     remaining_multipliers,
                                                                     remaining_keys, values} ->
        bytes_abs = abs(bytes) |> round()
        {buffer, remaining_buffer} = Enum.split(remaining_buffer, bytes_abs)
        [multiplier | remaining_multipliers] = remaining_multipliers
        [key | remaining_keys] = remaining_keys

        if multiplier == 0 or is_nil(key) do
          {remaining_buffer, remaining_multipliers, remaining_keys, values}
        else
          value = ViaUtils.Enum.list_to_int(buffer, bytes_abs)

          value =
            if is_float(bytes) do
              ViaUtils.Math.fp_from_uint(value, bytes_abs * 8)
            else
              if bytes > 0 do
                value
              else
                ViaUtils.Math.twos_comp(value, bytes_abs * 8)
              end
            end
            |> Kernel.*(multiplier)

          {remaining_buffer, remaining_multipliers, remaining_keys, Map.put(values, key, value)}
        end
      end)

    values
  end

  @spec construct_message(integer(), integer(), list(), list()) :: binary()
  def construct_message(msg_class, msg_id, byte_types, values) do
    {payload, payload_length} =
      Enum.reduce(Enum.zip(values, byte_types), {<<>>, 0}, fn {value, bytes},
                                                              {payload, payload_length} ->
        bytes_abs = abs(bytes) |> round()

        value_bin =
          if is_float(bytes) do
            ViaUtils.Math.uint_from_fp(value, round(bytes_abs * 8))
          else
            ViaUtils.Math.int_little_bin(value, bytes_abs * 8)
          end

        {payload <> value_bin, payload_length + bytes_abs}
      end)

    payload_len_msb = payload_length >>> 8 &&& 0xFF
    payload_len_lsb = payload_length &&& 0xFF
    checksum_buffer = <<msg_class, msg_id, payload_len_lsb, payload_len_msb>> <> payload
    checksum = calculate_ubx_checksum(:binary.bin_to_list(checksum_buffer))
    <<0xB5, 0x62>> <> checksum_buffer <> checksum
  end

  @spec construct_proto_message(integer(), integer(), binary()) :: binary()
  def construct_proto_message(msg_class, msg_id, payload) do
    payload_list = :binary.bin_to_list(payload)
    payload_length = length(payload_list)
    # Logger.debug("payload len: #{payload_length}")
    payload_len_msb = payload_length >>> 8 &&& 0xFF
    payload_len_lsb = payload_length &&& 0xFF
    # Logger.debug("msb/lsb: #{payload_len_msb}/#{payload_len_lsb}")
    checksum_buffer = [msg_class, msg_id, payload_len_lsb, payload_len_msb] ++ payload_list
    checksum = calculate_ubx_checksum(checksum_buffer)
    <<0xB5, 0x62>> <> :binary.list_to_bin(checksum_buffer) <> checksum
  end

  @spec calculate_ubx_checksum(list()) :: binary()
  def calculate_ubx_checksum(buffer) do
    {ck_a, ck_b} =
      Enum.reduce(buffer, {0, 0}, fn x, {ck_a, ck_b} ->
        ck_a = ck_a + x
        ck_b = ck_b + ck_a
        {ck_a &&& 0xFF, ck_b &&& 0xFF}
      end)

    <<ck_a, ck_b>>
  end
end
