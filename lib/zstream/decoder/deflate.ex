defmodule Zstream.Decoder.Deflate do
  @moduledoc false
  @behaviour Zstream.Decoder

  def init() do
    z = :zlib.open()
    :ok = :zlib.inflateInit(z, -15)
    :zlib.setBufSize(z, 512 * 1024)
    z
  end

  def decode(chunk, z) do
    chunk = IO.iodata_to_binary(chunk)
    inflate_loop(:zlib.inflateChunk(z, chunk), z, [])
  end

  defp inflate_loop({:more, uncompressed}, z, acc) do
    inflate_loop(:zlib.inflateChunk(z), z, [acc, uncompressed])
  end

  defp inflate_loop(uncompressed, z, acc) do
    {[acc, uncompressed], z}
  end

  def close(z) do
    :ok = :zlib.inflateEnd(z)
    :ok = :zlib.close(z)
    ""
  end
end
