defmodule Zstream.Coder.Stored do
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
