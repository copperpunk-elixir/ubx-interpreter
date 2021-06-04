defmodule UbxInterpreter.ByteTypes do
  defmacro uint8, do: 1
  defmacro int8, do: -1
  defmacro uint16, do: 2
  defmacro int16, do: -2
  defmacro uint32, do: 4
  defmacro int32, do: -4
  defmacro uint64, do: 8
  defmacro int64, do: -8
  defmacro float, do: 4.0
  defmacro double, do: 8.0
end
