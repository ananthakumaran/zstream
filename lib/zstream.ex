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

  alias Zstream.Protocol

  defmodule State do
    @moduledoc false

    @entry_initial_state %{
      local_file_header_offset: nil,
      crc: nil,
      c_size: 0,
      size: 0,
      options: []
    }

    defstruct zlib_handle: nil,
              entries: [],
              offset: 0,
              current: @entry_initial_state,
              coder: nil,
              coder_state: nil

    def entry_initial_state do
      @entry_initial_state
    end
  end

  @opaque entry :: map

  @default [coder: {Zstream.Coder.Deflate, []}]

  @doc """
  Creates a ZIP file entry with the given `name`

  The `enum` could be either lazy `Stream` or `List`. The elements in
  `enum` should be of type `iodata`

  ## Options

  * `:coder` (module | {module, list}) - The compressor that should be
    used to encode the data. Available options are

    `Zstream.Coder.Deflate` - use deflate compression

    `Zstream.Coder.Stored` - store without any compression

     Defaults to `Zstream.Coder.Deflate`

  * `:mtime` (DateTime) - File last modication time. Defaults to system
    local time.
  """
  @spec entry(String.t(), Enumerable.t(), Keyword.t()) :: entry
  def entry(name, enum, options \\ []) do
    local_time = :calendar.local_time() |> NaiveDateTime.from_erl!()

    options =
      Keyword.merge(@default, mtime: local_time)
      |> Keyword.merge(options)
      |> update_in([:coder], &normalize_coder/1)

    %{name: name, stream: enum, options: options}
  end

  @doc """
  Creates a ZIP file stream

  entries are consumed one by one in the given order
  """
  @spec zip([entry]) :: Enumerable.t()
  def zip(entries) do
    Stream.concat([
      [{:start}],
      Stream.flat_map(entries, fn %{stream: stream, name: name, options: options} ->
        Stream.concat(
          [{:head, %{name: name, options: options}}],
          stream
        )
      end),
      [{:end}]
    ])
    |> Stream.transform(fn -> %State{} end, &construct/2, &free_resource/1)
  end

  defp normalize_coder(module) when is_atom(module), do: {module, []}
  defp normalize_coder({module, args}), do: {module, args}

  defp construct({:start}, state) do
    state = put_in(state.zlib_handle, :zlib.open())
    {[], state}
  end

  defp construct({:end}, state) do
    {compressed, state} = close_entry(state)
    :ok = :zlib.close(state.zlib_handle)
    state = put_in(state.zlib_handle, nil)
    central_directory_headers = Enum.map(state.entries, &Protocol.central_directory_header/1)

    central_directory_end =
      Protocol.end_of_central_directory(
        state.offset,
        IO.iodata_length(central_directory_headers),
        length(state.entries)
      )

    {[compressed, central_directory_headers, central_directory_end], state}
  end

  defp construct({:head, header}, state) do
    {compressed, state} = close_entry(state)
    {coder, coder_opts} = Keyword.fetch!(header.options, :coder)
    state = put_in(state.coder, coder)
    state = put_in(state.coder_state, state.coder.init(coder_opts))
    state = update_in(state.current, &Map.merge(&1, header))
    state = put_in(state.current.options, header.options)
    state = put_in(state.current.crc, :zlib.crc32(state.zlib_handle, <<>>))
    state = put_in(state.current.local_file_header_offset, state.offset)
    local_file_header = Protocol.local_file_header(state.current)
    state = update_in(state.offset, &(&1 + IO.iodata_length(local_file_header)))
    {[[compressed, local_file_header]], state}
  end

  defp construct(chunk, state) do
    {compressed, coder_state} = state.coder.encode(chunk, state.coder_state)
    c_size = IO.iodata_length(compressed)
    state = put_in(state.coder_state, coder_state)
    state = update_in(state.current.c_size, &(&1 + c_size))
    state = update_in(state.current.crc, &:zlib.crc32(state.zlib_handle, &1, chunk))
    state = update_in(state.current.size, &(&1 + IO.iodata_length(chunk)))
    state = update_in(state.offset, &(&1 + c_size))

    case compressed do
      [] -> {[], state}
      _ -> {[compressed], state}
    end
  end

  defp close_entry(state) do
    if state.coder do
      compressed = state.coder.close(state.coder_state)
      c_size = IO.iodata_length(compressed)
      state = put_in(state.coder, nil)
      state = put_in(state.coder_state, nil)
      state = update_in(state.offset, &(&1 + c_size))
      state = update_in(state.current.c_size, &(&1 + c_size))

      data_descriptor =
        Protocol.data_descriptor(state.current.crc, state.current.c_size, state.current.size)

      state = update_in(state.offset, &(&1 + IO.iodata_length(data_descriptor)))
      state = update_in(state.entries, &[state.current | &1])
      state = put_in(state.current, State.entry_initial_state())
      {[compressed, data_descriptor], state}
    else
      {[], state}
    end
  end

  defp free_resource(state) do
    state =
      if state.coder do
        _compressed = state.coder.close(state.coder_state)
        state = put_in(state.coder, nil)
        put_in(state.coder_state, nil)
      else
        state
      end

    if state.zlib_handle do
      :ok = :zlib.close(state.zlib_handle)
      put_in(state.zlib_handle, nil)
    else
      state
    end
  end
end
