defmodule Zstream.Coder.Deflate do
  @behaviour Zstream.Coder
  @moduledoc """
  Implements the Deflate coder
  """

  def init(_opts) do
    z = :zlib.open()
    :ok = :zlib.deflateInit(z, :default, :deflated, -15, 8, :default)
    z
  end

  def encode(chunk, z) do
    {:zlib.deflate(z, chunk), z}
  end

  def close(z) do
    last = :zlib.deflate(z, [], :finish)
    :ok = :zlib.deflateEnd(z)
    :ok = :zlib.close(z)
    last
  end

  def compression_method, do: 8
end
