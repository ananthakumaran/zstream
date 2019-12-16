defmodule Zstream.Decoder.Stored do
  @behaviour Zstream.Decoder
  @moduledoc """
  Implements the Stored(uncompressed) decoder
  """

  def init() do
    nil
  end

  def decode(chunk, nil) do
    {chunk, nil}
  end

  def close(nil) do
    []
  end
end
