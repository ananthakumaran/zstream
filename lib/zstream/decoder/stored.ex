defmodule Zstream.Decoder.Stored do
  @moduledoc false
  @behaviour Zstream.Decoder

  def init() do
    nil
  end

  def decode(chunk, nil) do
    {[{:data, chunk}], nil}
  end

  def close(nil) do
    []
  end
end
