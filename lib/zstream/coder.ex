defmodule Zstream.Coder do
  @moduledoc false

  @callback init(options :: Keyword.t) :: term

  @callback encode(chunk :: iodata, state :: term) :: {iodata, term}

  @callback close(state :: term) :: iodata

  @callback compression_method() :: integer
end
