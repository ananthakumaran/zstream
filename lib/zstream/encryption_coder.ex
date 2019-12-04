defmodule Zstream.EncryptionCoder do
  @moduledoc false

  @callback init(options :: Keyword.t()) :: term

  @callback encode(chunk :: iodata, state :: term) :: {iodata, term}

  @callback close(state :: term) :: iodata

  @callback general_purpose_flag() :: integer
end
