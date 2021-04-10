defmodule Zstream.Decoder.Deflate do
  @moduledoc false
  @behaviour Zstream.Decoder

  def init() do
    z = :zlib.open()
    :ok = :zlib.inflateInit(z, -15)
    z
  end

  def decode(chunk, z) do
    acc = :zlib.safeInflate(z, IO.iodata_to_binary(chunk))

    chunks =
      Stream.unfold(acc, fn
        {:continue, data} ->
          {{:data, data}, :zlib.safeInflate(z, [])}

        {:finished, data} ->
          {{:data, data}, nil}

        nil ->
          nil
      end)

    {chunks, z}
  end

  def close(z) do
    :ok = :zlib.inflateEnd(z)
    :ok = :zlib.close(z)
    []
  end
end
