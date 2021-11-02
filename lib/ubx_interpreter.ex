defmodule UbxInterpreter do
  alias UbxInterpreter.Utils, as: Utils
  require Logger
  use Bitwise

  @moduledoc """
  Constructs or deconstructs messages that conform to U-blox UBX binary protocol.
  NOTE: This documentation is incomplete. It will be finished as soon as possible.
  """

  @max_payload_length 1000

  @start_byte_1 0xB5
  @start_byte_2 0x62

  @got_none 0
  @got_start_byte1 1
  @got_start_byte2 2
  @got_class 3
  @got_id 4
  @got_length1 5
  @got_length2 6
  @got_payload 7
  @got_chka 8

  @doc false
  defstruct state: @got_none,
            msg_class: -1,
            msg_id: -1,
            msg_len: -1,
            chka: 0,
            chkb: 0,
            count: 0,
            payload_rev: [],
            payload_ready: false,
            remaining_data: []

  # Public API
  @doc """
  Create a new UbxInterpreter struct that can parse new data and
  store the most recently received output.
  """
  @spec new() :: struct()
  def new() do
    %UbxInterpreter{}
  end

  @doc """
  Appends the latest data to any leftover data from the previous `check_for_new_message` operation.

  Arguments are the `%UbxInterpreter{}` struct and the newest data from the whichever source this struct is associated (must already by converted from binary to list).

  Returns `{%UbxInterpreter{}, [list of payload bytes]}`. If no valid UBX message was found, the payload list will be empty.
  This list is the raw payload contents. In order to convert to usable values, the `deconstruct_message_to_map` or `deconstruct_message_to_list` function must be called.

  NOTE: After a valid message has been received, the `clear` function must be called if you do not want the payload values to persist.
  Otherwise this function will continue to return a populated payload list even if a new valid message has not been received.

  Example:
  ```
  {ubx_interpreter, payload_list} = UbxInterpreter.check_for_new_message(ubx_interpreter, new_data_list)
  values_list = deconstruct_message_to_list(byte_types_list, multipliers_list, payload_list)
  ubx_interpreter = UbxInterpreter.clear(ubx_interpreter)
  ```
  """
  @spec check_for_new_message(struct(), list()) :: tuple()
  def check_for_new_message(ubx, data) do
    ubx = parse_data(ubx, data)

    if ubx.payload_ready do
      payload = Enum.reverse(ubx.payload_rev)
      {ubx, payload}
    else
      {ubx, []}
    end
  end

  @doc """
  Similar to `check_for_new_message`, expect if a valid message is found, the `process_fn` function will be called. The arguments
  passed to `process_fn` include the message class, message ID, and the message payload, plus any `additional_fn_args`.

  This makes it easier to parse and process multiple messages contained within the same data stream. For example, you might have a GPS receiver that is outputing
  two different messages, and you want to send the contents of each message to a different GenServer.

  Example:
  ```
   ubx_interpreter =
      UbxInterpreter.check_for_new_messages_and_process(
        ubx_interpreter,
        data_list,
        &process_data_fn/3,
        []
      )
  ```
  """
  @spec check_for_new_messages_and_process(struct(), list(), fun(), list()) :: struct()
  def check_for_new_messages_and_process(ubx, data, process_fn, additional_fn_args \\ []) do
    ubx = parse_data(ubx, data)

    if ubx.payload_ready do
      msg_class = ubx.msg_class
      msg_id = ubx.msg_id
      payload = Enum.reverse(ubx.payload_rev)
      apply(process_fn, [msg_class, msg_id, payload] ++ additional_fn_args)

      clear(ubx)
      |> check_for_new_messages_and_process([], process_fn, additional_fn_args)
    else
      ubx
    end
  end

  @doc false
  @spec parse_data(struct(), list()) :: struct()
  def parse_data(ubx, data) do
    data = ubx.remaining_data ++ data

    if Enum.empty?(data) do
      ubx
    else
      {[byte], remaining_data} = Enum.split(data, 1)
      ubx = parse_byte(ubx, byte)

      cond do
        ubx.payload_ready -> %{ubx | remaining_data: remaining_data}
        Enum.empty?(remaining_data) -> %{ubx | remaining_data: []}
        true -> parse_data(%{ubx | remaining_data: []}, remaining_data)
      end
    end
  end

  @doc false
  @spec parse_byte(struct(), integer()) :: struct()
  def parse_byte(ubx, byte) do
    state = ubx.state

    cond do
      state == @got_none and byte == @start_byte_1 ->
        %{ubx | state: @got_start_byte1}

      state == @got_start_byte1 ->
        if byte == @start_byte_2 do
          %{ubx | state: @got_start_byte2, chka: 0, chkb: 0, payload_rev: []}
        else
          %{ubx | state: @got_none}
        end

      state == @got_start_byte2 ->
        msgclass = byte
        {chka, chkb} = add_to_checksum(ubx, byte)
        %{ubx | state: @got_class, msg_class: msgclass, chka: chka, chkb: chkb}

      state == @got_class ->
        msgid = byte
        {chka, chkb} = add_to_checksum(ubx, byte)
        %{ubx | state: @got_id, msg_id: msgid, chka: chka, chkb: chkb}

      state == @got_id ->
        msglen = byte
        {chka, chkb} = add_to_checksum(ubx, byte)
        %{ubx | state: @got_length1, msg_len: msglen, chka: chka, chkb: chkb}

      state == @got_length1 ->
        msglen = ubx.msg_len + Bitwise.<<<(byte, 8)

        if msglen <= @max_payload_length do
          {chka, chkb} = add_to_checksum(ubx, byte)
          %{ubx | state: @got_length2, msg_len: msglen, count: 0, chka: chka, chkb: chkb}
        else
          Logger.error("payload overload")
          %{ubx | state: @got_none}
        end

      state == @got_length2 ->
        {chka, chkb} = add_to_checksum(ubx, byte)
        payload_rev = [byte] ++ ubx.payload_rev
        count = ubx.count + 1
        state = if count == ubx.msg_len, do: @got_payload, else: ubx.state
        %{ubx | state: state, chka: chka, chkb: chkb, count: count, payload_rev: payload_rev}

      state == @got_payload ->
        state = if byte == ubx.chka, do: @got_chka, else: @got_none
        %{ubx | state: state}

      state == @got_chka ->
        state = @got_none
        payload_ready = if byte == ubx.chkb, do: true, else: false
        %{ubx | state: state, payload_ready: payload_ready}

      true ->
        # This byte is out of place
        %{ubx | state: @got_none}
    end
  end

  @doc false
  @spec add_to_checksum(struct(), integer()) :: tuple()
  def add_to_checksum(ubx, byte) do
    chka = Bitwise.&&&(ubx.chka + byte, 0xFF)
    chkb = Bitwise.&&&(ubx.chkb + chka, 0xFF)
    {chka, chkb}
  end

  @doc false
  @spec payload(struct()) :: list()
  def payload(ubx) do
    Enum.reverse(ubx.payload_rev)
  end

  @doc """
  Empties the stored payload list
  """
  @spec clear(struct()) :: struct()
  def clear(ubx) do
    %{ubx | payload_ready: false}
  end

  @doc false
  @spec msg_class_and_id(struct()) :: tuple()
  def msg_class_and_id(ubx) do
    {ubx.msg_class, ubx.msg_id}
  end

  @spec payload_length(struct()) :: integer()
  def payload_length(ubx) do
    ubx.msg_len
  end

  @doc """
  Converts a list of payload bytes to a map containing usable values. The message contents are defined according to the `byte_types` and `multipliers` arguments.

  First the payload is split up into a list of values, separated according to their lenght in bytes.<br>Acceptable `byte_types` values and their corresponding primitive data type are as follows:
  * 1 (uint8)
  * 2 (uint16)
  * 4 (uint32)
  * 8 (uint64)
  * -1 (int8)
  * -2 (int16)
  * -4 (int32)
  * -8 (int64)
  * 4.0 (float)
  * 8.0 (double)

  NOTE: UBX messages do not typically contain `float` or `double` values represented in single-precision or double-precision form. Rather they use integer values with known multiplier to
  convert them to their decimal values. However, there is no reason we can't store them like this, so if you want to make a custom UBX message that uses `float` or `double`, go for it!

  Once each value has been converted from a list of bytes to an `integer`, `float`, or `double`, it is then multiplied by the corresponding number in the `multipliers` list.

  Finally it is stored in a map using the key specified by the `keys` list.

  Example:
  -coming soon-
  """
  @spec deconstruct_message_to_map(list(), list(), list(), list()) :: map()
  defdelegate deconstruct_message_to_map(byte_types, multipliers, keys, payload), to: Utils

  @spec deconstruct_message_to_list(list(), list(), list()) :: list()
  defdelegate deconstruct_message_to_list(byte_types, multipliers, payload), to: Utils

  @spec construct_message_from_map(integer(), integer(), list(), list(), list(), map()) ::
          binary()
  defdelegate construct_message_from_map(
                msg_class,
                msg_id,
                byte_types,
                multipliers,
                key,
                values_map
              ),
              to: Utils

  @spec construct_message_from_list(integer(), integer(), list(), list()) :: binary()
  defdelegate construct_message_from_list(msg_class, msg_id, byte_types, values_list), to: Utils

  @spec construct_proto_message(integer(), integer(), binary()) :: binary()
  defdelegate construct_proto_message(msg_class, msg_id, payload), to: Utils

  @spec calculate_ubx_checksum(list()) :: binary()
  defdelegate calculate_ubx_checksum(buffer), to: Utils
end
