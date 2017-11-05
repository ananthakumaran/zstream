defmodule Zstream do
  alias Zstream.Protocol

  defmodule State do
    @entry_initial_state %{local_file_header_offset: nil, crc: nil, c_size: 0, size: 0}

    defstruct handle: nil, entries: [], offset: 0, current: @entry_initial_state

    def entry_initial_state do
      @entry_initial_state
    end
  end

  def entry(name, stream, options \\ []) do
    %{name: name, stream: stream, options: options}
  end

  def create(entries) do
    Stream.concat(
      Enum.map(entries, fn %{stream: stream, name: name, options: options} ->
        Stream.transform(stream, %{name: name, options: options}, &stream_entry/2)
      end)
    )
    |> Stream.concat([{:end}])
    |> Stream.transform(%State{}, &construct/2)
  end

  defp stream_entry(chunk, :body) do
    {[chunk], :body}
  end

  defp stream_entry(chunk, header) do
    {[{:head, header}, chunk], :body}
  end

  defp construct({:end}, state) do
    {compressed, state} = close_entry(state)
    central_directory_headers = Enum.map(state.entries, &Protocol.central_directory_header/1)
    central_directory_end = Protocol.central_directory_end(state.offset, IO.iodata_length(central_directory_headers), length(state.entries))
    {[compressed, central_directory_headers, central_directory_end], state}
  end

  defp construct({:head, header}, state) do
    {compressed, state} = close_entry(state)
    handle = :zlib.open()
    :ok = :zlib.deflateInit(handle, :default, :deflated, -15, 8, :default)
    state = put_in(state.handle, handle)
    state = update_in(state.current, &(Map.merge(&1, header)))
    state = put_in(state.current.crc, :zlib.crc32(state.handle, <<>>))
    state = put_in(state.current.local_file_header_offset, state.offset)
    local_file_header = Protocol.local_file_header(header.name, header.options)
    state = update_in(state.offset, &(&1 + IO.iodata_length(local_file_header)))
    {[[compressed, local_file_header]], state}
  end

  defp construct(chunk, state) do
    compressed = :zlib.deflate(state.handle, chunk)
    c_size = IO.iodata_length(compressed)
    state = update_in(state.current.c_size, &(&1 + c_size))
    state = update_in(state.current.crc, &(:zlib.crc32(state.handle, &1, chunk)))
    state = update_in(state.current.size, &(&1 + IO.iodata_length(chunk)))
    state = update_in(state.offset, &(&1 + c_size))
    {[compressed], state}
  end

  defp close_entry(state) do
    if state.handle do
      compressed = close_handle(state.handle)
      c_size = IO.iodata_length(compressed)
      state = update_in(state.offset, &(&1 + c_size))
      state = update_in(state.current.c_size, &(&1 + c_size))
      data_descriptor = Protocol.data_descriptor(state.current.crc, state.current.c_size, state.current.size)
      state = update_in(state.offset, &(&1 + IO.iodata_length(data_descriptor)))
      state = update_in(state.entries, &([state.current|&1]))
      state = put_in(state.current, State.entry_initial_state())
      {[compressed, data_descriptor], state}
    else
      {[], state}
    end
  end

  defp close_handle(handle) do
    last = :zlib.deflate(handle, [], :finish)
    :ok = :zlib.deflateEnd(handle)
    :ok = :zlib.close(handle)
    last
  end
end
