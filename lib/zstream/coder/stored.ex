defmodule Zstream.Coder.Stored do
  @moduledoc """
  Implements the Stored(uncompressed) coder.
  """

  @behaviour Zstream.Coder

  def init(_opts) do
    nil
  end

  def encode(chunk, nil) do
    {chunk, nil}
  end

  def close(nil) do
    []
  end

  def compression_method, do: 0
end
