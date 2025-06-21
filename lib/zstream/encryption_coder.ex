defmodule Zstream.EncryptionCoder do
  @moduledoc false

  @callback init(options :: Keyword.t()) :: term

  @callback encode(chunk :: iodata, state :: term) :: {iodata, term}

  @callback close(state :: term) :: iodata

  @callback general_purpose_flag() :: integer

  @optional_callbacks [
    compression_method: 0,
    extra_field_data: 1,
    version_needed_to_extract: 0,
    crc_exposed?: 1
  ]

  @callback compression_method() :: integer

  @callback extra_field_data(options :: Keyword.t()) :: binary

  @callback version_needed_to_extract() :: integer

  @callback crc_exposed?(options :: Keyword.t()) :: boolean
end
