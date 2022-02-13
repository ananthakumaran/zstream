defmodule Zstream.EncryptionCoder.Traditional do
  @moduledoc """
  Implements the tradition encryption.
  """

  @behaviour Zstream.EncryptionCoder

  use Bitwise

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

  defp encrypt(state, chunk), do: encrypt(state, chunk, [])

  defp encrypt(state, <<>>, encrypted), do: {Enum.reverse(encrypted), state}

  defp encrypt(state, <<char::binary-size(1)>> <> rest, encrypted) do
    <<byte::integer-size(8)>> = char
    temp = (state.key2 ||| 2) &&& 0x0000FFFF
    temp = (temp * Bitwise.bxor(temp, 1)) >>> 8 &&& 0x000000FF
    cipher = <<Bitwise.bxor(byte, temp)::integer-size(8)>>
    state = update_keys(state, <<byte::integer-size(8)>>)
    encrypt(state, rest, [cipher | encrypted])
  end

  defp update_keys(state, <<>>), do: state

  defp update_keys(state, <<char::binary-size(1)>> <> rest) do
    state = put_in(state.key0, crc32(state.key0, char))

    state =
      put_in(
        state.key1,
        (state.key1 + (state.key0 &&& 0x000000FF)) * 134_775_813 + 1 &&& 0xFFFFFFFF
      )

    state =
      put_in(
        state.key2,
        crc32(state.key2, <<state.key1 >>> 24::integer-size(8)>>)
      )

    update_keys(state, rest)
  end

  defp crc32(current, data) do
    Bitwise.bxor(:erlang.crc32(Bitwise.bxor(current, 0xFFFFFFFF), data), 0xFFFFFFFF)
  end

  defp dos_time(t) do
    round(t.second / 2 + (t.minute <<< 5) + (t.hour <<< 11))
  end
end
