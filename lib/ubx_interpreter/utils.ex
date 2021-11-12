defmodule UbxInterpreter.Utils do
  require Logger
  use Bitwise

  @spec deconstruct_message_to_list(list(), list(), list()) :: list()
  def deconstruct_message_to_list(byte_types, multipliers, payload) do
    {_payload_rem, _multipliers, values_reversed} =
      Enum.reduce(byte_types, {payload, multipliers, []}, fn bytes,
                                                             {remaining_buffer,
                                                              remaining_multipliers,
                                                              values_reversed} ->
        bytes_abs = abs(bytes) |> round()
        {buffer, remaining_buffer} = Enum.split(remaining_buffer, bytes_abs)
        [multiplier | remaining_multipliers] = remaining_multipliers

        if multiplier == 0 do
          {remaining_buffer, remaining_multipliers, values_reversed}
        else
          value = ViaUtils.Enum.list_to_int_little_end(buffer)

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

          {remaining_buffer, remaining_multipliers, [value] ++ values_reversed}
        end
      end)

    Enum.reverse(values_reversed)
  end

  @spec deconstruct_message_to_map(list(), list(), list(), list()) :: map()
  def deconstruct_message_to_map(byte_types, multipliers, keys, payload) do
    values = deconstruct_message_to_list(byte_types, multipliers, payload)
    Enum.zip(keys, values) |> Enum.into(%{})
  end

  @spec construct_message_from_map(integer(), integer(), list(), list(), list(), map()) ::
          binary()
  def construct_message_from_map(msg_class, msg_id, byte_types, multipliers, keys, values_map) do
    # Logger.debug("value-Map: #{inspect(values_map)}")
    {_remaining_values_map, _remaining_multipliers, values_list_reversed} =
      Enum.reduce(keys, {values_map, multipliers, []}, fn key,
                                                          {remaining_values_map,
                                                           remaining_multipliers,
                                                           values_reversed} ->
        [multiplier | remaining_multipliers] = remaining_multipliers
        {value_raw, remaining_values_map} = Map.pop(remaining_values_map, key, 0)
        # Logger.debug("key,raw,mult: #{key},#{value_raw},#{multiplier}")
        value = round(value_raw / multiplier)
        {remaining_values_map, remaining_multipliers, [value] ++ values_reversed}
      end)

    construct_message_from_list(msg_class, msg_id, byte_types, Enum.reverse(values_list_reversed))
  end

  @spec construct_message_from_list(integer(), integer(), list(), list()) :: binary()
  def construct_message_from_list(msg_class, msg_id, byte_types, values) do
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
