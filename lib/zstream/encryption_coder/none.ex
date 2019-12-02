defmodule Zstream.EncryptionCoder.None do
  def init(_opts) do
    nil
  end

  def encode(chunk, nil) do
    {chunk, nil}
  end

  def close(nil) do
    []
  end

  def general_purpose_flag, do: 0
end
