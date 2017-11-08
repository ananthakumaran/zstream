defmodule Zstream.Coder do
  @callback init(options :: Keyword.t) :: term

  @callback encode(iodata, state :: term) :: {iodata, term}

  @callback close(state :: term) :: iodata

  @callback compression_method() :: integer
end
