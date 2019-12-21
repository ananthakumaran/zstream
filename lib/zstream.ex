defmodule Zstream do
  @moduledoc """
  Module for reading and writing ZIP file stream

  ## Example

  ```
  Zstream.zip([
    Zstream.entry("report.csv", Stream.map(records, &CSV.dump/1)),
    Zstream.entry("catfilm.mp4", File.stream!("/catfilm.mp4", [], 512), coder: Zstream.Coder.Stored)
  ])
  |> Stream.into(File.stream!("/archive.zip"))
  |> Stream.run
  ```

  ```
  File.stream!("archive.zip", [], 512)
  |> Zstream.unzip()
  |> Enum.reduce(%{}, fn
    {:entry, %Zstream.Entry{name: file_name} = entry}, state -> state
    {:data, data}, state -> state
    {:data, :eof}, state -> state
  end)
  ```
  """

  defmodule Entry do
    @type t :: %__MODULE__{
            name: String.t(),
            compressed_size: integer(),
            mtime: NaiveDateTime.t(),
            size: integer(),
            extras: list()
          }
    defstruct [:name, :compressed_size, :mtime, :size, :extras]
  end

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

  @doc """
  Unzips file stream

  returns a new stream which emits the following tuples for each zip entry

  {`:entry`, `t:Zstream.Entry.t/0`} - Indicates a new file entry.

  {`:data`, `t:iodata/0` | `:eof`} - one or more data tuples will be emitted for each entry. `:eof` indicates end of data tuples for current entry.

  ### NOTES

  Unzip doesn't support all valid zip files. Zip file format allows
  the writer to write the file size info after the file data, which
  allows the writer to zip streams with unknown size. But this
  prevents the reader from unzipping the file in a streaming fashion,
  because to find the file size one has to go to the end of the
  stream. Ironcially, if you use Zstream to zip a file, the same file
  can't be unzipped using Zstream.

  * doesn't support file which uses data descriptor header
  * doesn't support encrypted file
  """
  defdelegate unzip(stream), to: Zstream.Unzip
end
