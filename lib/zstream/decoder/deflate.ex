defmodule Zstream.Decoder.Deflate do
  @moduledoc false
  @behaviour Zstream.Decoder

  def init() do
    z = :zlib.open()
    :ok = :zlib.inflateInit(z, -15)
    :zlib.setBufSize(z, 1024 * 1024)
    z
  end

  def decode_safe(chunk, z) do
    chunk = IO.iodata_to_binary(chunk)

    stream =
      Stream.resource(
        fn ->
          :zlib.safeInflate(z, chunk)
        end,
        fn
          :complete ->
            {:halt, :complete}

          {:continue, uncompressed} ->
            {[{:data, uncompressed}], :zlib.safeInflate(z, [])}

          {:finished, uncompressed} ->
            {[{:data, uncompressed}], :complete}
        end,
        fn _ -> :ok end
      )

    {stream, z}
  end

  def decode(chunk, z) do
    chunk = IO.iodata_to_binary(chunk)

    stream =
      Stream.resource(
        fn ->
          :zlib.inflateChunk(z, chunk)
        end,
        fn
          :complete ->
            {:halt, :complete}

          {:more, uncompressed} ->
            {[{:data, uncompressed}], :zlib.inflateChunk(z)}

          uncompressed ->
            {[{:data, uncompressed}], :complete}
        end,
        fn _ -> :ok end
      )

    {stream, z}
  end

  def close(z) do
    :ok = :zlib.inflateEnd(z)
    :ok = :zlib.close(z)
    ""
  end
end
