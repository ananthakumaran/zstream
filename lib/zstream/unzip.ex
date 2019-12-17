defmodule Zstream.Unzip do
  defmodule LocalHeader do
    defstruct [
      :version_need_to_extract,
      :general_purpose_bit_flag,
      :compression_method,
      :last_modified_file_time,
      :last_modified_file_date,
      :crc32,
      :uncompressed_size,
      :compressed_size,
      :file_name_length,
      :extra_field_length,
      :file_name,
      :extra_field
    ]
  end

  defmodule State do
    @moduledoc false
    defstruct next: :local_file_header,
              buffer: "",
              local_header: nil,
              data_sent: 0,
              decoder: nil,
              decoder_state: nil
  end

  def unzip(stream, _options \\ []) do
    Stream.transform(stream, %State{}, &execute_state_machine/2)
  end

  # Specification is available at
  # https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT
  defp execute_state_machine(data, state) do
    data =
      if state.buffer not in ["", []] do
        [state.buffer, data]
      else
        data
      end

    size = IO.iodata_length(data)

    enough_data? =
      case state.next do
        :local_file_header ->
          size >= 30

        :filename_extra_field ->
          size >= state.local_header.file_name_length + state.local_header.extra_field_length

        :done ->
          true

        :file_data ->
          true
      end

    if enough_data? do
      apply(__MODULE__, state.next, [data, %{state | buffer: ""}])
    else
      {[], %{state | buffer: data}}
    end
  end

  def local_file_header(data, state) do
    data = IO.iodata_to_binary(data)

    case parse_local_header(data) do
      {:ok, local_header, rest} ->
        {decoder, decoder_state} = Zstream.Decoder.init(local_header.compression_method)

        execute_state_machine(rest, %{
          state
          | local_header: local_header,
            next: :filename_extra_field,
            decoder: decoder,
            decoder_state: decoder_state
        })

      :done ->
        state = %{state | next: :done}
        {[], state}
    end
  end

  def filename_extra_field(data, state) do
    data = IO.iodata_to_binary(data)
    start = 0
    length = state.local_header.file_name_length
    file_name = binary_part(data, start, length)
    start = start + length
    length = state.local_header.extra_field_length
    extra_field = binary_part(data, start, length)
    start = start + length
    rest = binary_part(data, start, byte_size(data) - start)
    state = put_in(state.local_header.file_name, file_name)
    state = put_in(state.local_header.extra_field, extra_field)
    state = %{state | buffer: "", next: :file_data}
    {results, new_state} = execute_state_machine(rest, state)
    {[state.local_header | results], new_state}
  end

  def file_data(data, state) do
    size = IO.iodata_length(data)

    if size + state.data_sent < state.local_header.compressed_size do
      {data, state} = decode(data, state)
      {[data], %{state | data_sent: state.data_sent + size, buffer: ""}}
    else
      data = IO.iodata_to_binary(data)
      length = state.local_header.compressed_size - state.data_sent
      file_chunk = binary_part(data, 0, length)
      {file_chunk, state} = decode_close(file_chunk, state)
      start = length
      rest = binary_part(data, start, size - start)

      state = %{state | data_sent: 0, buffer: "", next: :local_file_header}
      {results, state} = execute_state_machine(rest, state)
      {[file_chunk | [:eof | results]], state}
    end
  end

  def done(_, state) do
    {[], state}
  end

  defp decode(data, state) do
    decoder = state.decoder
    decoder_state = state.decoder_state
    {data, decoder_state} = decoder.decode(data, decoder_state)
    state = put_in(state.decoder_state, decoder_state)
    {data, state}
  end

  defp decode_close(data, state) do
    {data, state} = decode(data, state)
    data = [data, state.decoder.close(state.decoder_state)]
    state = put_in(state.decoder, nil)
    state = put_in(state.decoder_state, nil)
    {data, state}
  end

  # local file header signature
  defp parse_local_header(
         <<0x04034B50::little-size(32), version_need_to_extract::little-size(16),
           general_purpose_bit_flag::little-size(16), compression_method::little-size(16),
           last_modified_file_time::little-size(16), last_modified_file_date::little-size(16),
           crc32::little-size(32), compressed_size::little-size(32),
           uncompressed_size::little-size(32), file_name_length::little-size(16),
           extra_field_length::little-size(16), rest::binary>>
       ) do
    {:ok,
     %LocalHeader{
       version_need_to_extract: version_need_to_extract,
       general_purpose_bit_flag: general_purpose_bit_flag,
       compression_method: compression_method,
       last_modified_file_time: last_modified_file_time,
       last_modified_file_date: last_modified_file_date,
       crc32: crc32,
       compressed_size: compressed_size,
       uncompressed_size: uncompressed_size,
       file_name_length: file_name_length,
       extra_field_length: extra_field_length
     }, rest}
  end

  defp parse_local_header(<<0x02014B50::little-size(32), rest::binary>>), do: :done

  defp parse_local_header(_), do: raise(ArgumentError, "Invalid local header")
end
