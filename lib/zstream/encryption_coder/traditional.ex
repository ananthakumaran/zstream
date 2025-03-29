defmodule Zstream.EncryptionCoder.Traditional do
  @moduledoc """
  Implements the tradition encryption.
  """

  @behaviour Zstream.EncryptionCoder

  import Bitwise

  defmodule State do
    @moduledoc false

    defstruct key0: 0x12345678,
              key1: 0x23456789,
              key2: 0x34567890,
              header: nil,
              header_sent: false
  end

  def init(options) do
    password = Keyword.fetch!(options, :password)

    header =
      :crypto.strong_rand_bytes(10) <>
        <<dos_time(Keyword.fetch!(options, :mtime))::little-size(16)>>

    state = %State{header: header}
    update_keys(state, password)
  end

  def encode(chunk, state) do
    {chunk, state} =
      if !state.header_sent do
        {[state.header, chunk], %{state | header_sent: true}}
      else
        {chunk, state}
      end

    encrypt(state, IO.iodata_to_binary(chunk))
  end

  def close(_state) do
    []
  end

  def general_purpose_flag, do: 0x0001

  defp encrypt(state, chunk), do: encrypt(state, chunk, <<>>)

  defp encrypt(state, <<>>, encrypted), do: {encrypted, state}

  defp encrypt(
         state = %State{key0: key0, key1: key1, key2: key2},
         <<char::binary-size(1), rest::binary>>,
         encrypted
       ) do
    <<byte::integer-size(8)>> = char
    temp = (key2 ||| 2) &&& 0x0000FFFF
    temp = (temp * Bitwise.bxor(temp, 1)) >>> 8 &&& 0x000000FF
    cipher = Bitwise.bxor(byte, temp)

    key0 = crc32(key0, char)
    key1 = (key1 + (key0 &&& 0x000000FF)) * 134_775_813 + 1 &&& 0xFFFFFFFF
    key2 = crc32(key2, <<key1 >>> 24::integer-size(8)>>)

    %{state | key0: key0, key1: key1, key2: key2}
    |> encrypt(rest, <<encrypted::binary, cipher::integer-size(8)>>)
  end

  defp update_keys(state, <<>>), do: state

  defp update_keys(
         state = %State{key0: key0, key1: key1, key2: key2},
         <<char::binary-size(1), rest::binary>>
       ) do
    key0 = crc32(key0, char)
    key1 = (key1 + (key0 &&& 0x000000FF)) * 134_775_813 + 1 &&& 0xFFFFFFFF
    key2 = crc32(key2, <<key1 >>> 24::integer-size(8)>>)

    state = %{state | key0: key0, key1: key1, key2: key2}
    update_keys(state, rest)
  end

  defp crc32(current, data) do
    Bitwise.bxor(:erlang.crc32(Bitwise.bxor(current, 0xFFFFFFFF), data), 0xFFFFFFFF)
  end

  defp dos_time(t) do
    div(t.second, 2) + (t.minute <<< 5) + (t.hour <<< 11)
  end
end
