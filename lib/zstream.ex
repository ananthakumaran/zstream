defmodule Zstream do
  @moduledoc """
  Module for creating ZIP file stream

  ## Example

  ```
  Zstream.zip([
    Zstream.entry("report.csv", Stream.map(records, &CSV.dump/1)),
    Zstream.entry("catfilm.mp4", File.stream!("/catfilm.mp4"), coder: Zstream.Coder.Stored)
  ])
  |> Stream.into(File.stream!("/archive.zip"))
  |> Stream.run
  ```
  """

  @opaque entry :: map

  @doc """
  Creates a ZIP file entry with the given `name`

  The `enum` could be either lazy `Stream` or `List`. The elements in `enum`
  should be of type `iodata`

  ## Options

  * `:coder` (module | {module, list}) - The compressor that should be
    used to encode the data. Available options are

    `Zstream.Coder.Deflate` - use deflate compression

    `Zstream.Coder.Stored` - store without any compression

     Defaults to `Zstream.Coder.Deflate`

  * `:encryption_coder` ({module, keyword}) - The encryption module that should be
    used to encrypt the data. Available options are

    `Zstream.EncryptionCoder.Traditional` - use tranditional zip
    encryption scheme. `:password` key should be present in the
    options. Example `{Zstream.EncryptionCoder.Traditional, password:
    "secret"}`

    `Zstream.EncryptionCoder.None` - no encryption

     Defaults to `Zstream.EncryptionCoder.None`


  * `:mtime` (DateTime) - File last modication time. Defaults to system local time.
  """
  @spec entry(String.t(), Enumerable.t(), Keyword.t()) :: entry
  defdelegate entry(name, enum, options \\ []), to: Zstream.Zip

  @doc """
  Creates a ZIP file stream

  entries are consumed one by one in the given order
  """
  @spec zip([entry]) :: Enumerable.t()

  defdelegate zip(entries), to: Zstream.Zip
end
