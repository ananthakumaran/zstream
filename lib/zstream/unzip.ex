defmodule Zstream.Unzip do
  @moduledoc false
  alias Zstream.Entry
  alias Zstream.Unzip.{Extra, Verifier}

  defmodule Error do
    defexception [:message]
  end

  use Bitwise

  defmodule LocalHeader do
    @moduledoc false
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
              decoder_state: nil,
              verifier: nil
  end

  def unzip(stream, _options \\ []) do
    Stream.concat([stream, [:eof]])
    |> Stream.transform(%State{}, &execute_state_machine/2)
  end

  # Specification is available at
  # https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT
  defp execute_state_machine(:eof, state) do
    if state.next == :done do
      {[], state}
    else
      raise Error, "Unexpected end of input"
    end
  end

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

        :next_header ->
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
        verifier = Verifier.new()

        if bit_set?(local_header.general_purpose_bit_flag, 3) do
          raise Error, "Zip files with data descriptor record are not supported"
        end

        execute_state_machine(rest, %{
          state
          | local_header: local_header,
            next: :filename_extra_field,
            decoder: decoder,
            decoder_state: decoder_state,
            verifier: verifier
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
    state = %{state | next: :file_data}
    local_header = state.local_header

    entry = %Entry{
      name: local_header.file_name,
      compressed_size: local_header.compressed_size,
      size: local_header.uncompressed_size,
      mtime: dos_time(local_header.last_modified_file_date, local_header.last_modified_file_time),
      extras: Extra.parse(extra_field, [])
    }

    zip64_extended_information =
      Enum.find(entry.extras, &match?(%Extra.Zip64ExtendedInformation{}, &1))

    entry =
      if zip64_extended_information do
        %{
          entry
          | size: zip64_extended_information.size,
            compressed_size: zip64_extended_information.compressed_size
        }
      else
        entry
      end

    state =
      if zip64_extended_information do
        state =
          put_in(state.local_header.compressed_size, zip64_extended_information.compressed_size)

        put_in(state.local_header.uncompressed_size, zip64_extended_information.size)
      else
        state
      end

    {results, new_state} = execute_state_machine(rest, state)

    {Stream.concat([{:entry, entry}], results), new_state}
  end

  def file_data(data, state) do
    size = IO.iodata_length(data)

    if size + state.data_sent < state.local_header.compressed_size do
      {data, state} = decode(data, state)
      {data, %{state | data_sent: state.data_sent + size}}
    else
      data = IO.iodata_to_binary(data)
      length = state.local_header.compressed_size - state.data_sent
      file_chunk = binary_part(data, 0, length)
      {data_stream, state} = decode_close(file_chunk, state)
      start = length
      rest = binary_part(data, start, size - start)

      state = %{state | data_sent: 0, next: :next_header}
      {results, state} = execute_state_machine(rest, state)
      {Stream.concat([data_stream, [{:data, :eof}], results]), state}
    end
  end

  def next_header(data, state) do
    data = IO.iodata_to_binary(data)

    case :binary.match(data, <<0x4B50::little-size(16)>>, scope: {0, 28}) do
      :nomatch ->
        raise Error, "Invalid zip file, could not find any signature header"

      {start, 2} ->
        <<signature::little-size(32), _::binary>> =
          rest = binary_part(data, start, byte_size(data) - start)

        case signature do
          0x04034B50 ->
            execute_state_machine(rest, %{state | next: :local_file_header})

          # archive extra data record
          0x08064B50 ->
            {[], %{state | next: :done}}

          # central directory header
          0x02014B50 ->
            {[], %{state | next: :done}}
        end
    end
  end

  def done(_, state) do
    {[], state}
  end

  defp decode(data, state) do
    decoder = state.decoder
    decoder_state = state.decoder_state
    {data_stream, decoder_state} = decoder.decode(data, decoder_state)

    data_stream = Stream.transform(data_stream, state.verifier, &Verifier.update/2)

    state = put_in(state.decoder_state, decoder_state)
    {data_stream, state}
  end

  defp decode_close(data, state) do
    {data_stream, state} = decode(data, state)

    data_stream =
      data_stream
      |> Extra.stream_with_finalizer(
        state,
        fn state ->
          extra_data = state.decoder.close(state.decoder_state)
          Verifier.update({:data, extra_data}, state.verifier)
        end
      )
      |> Extra.stream_with_finalizer(state, &verify_file_integrity/1)

    state = put_in(state.decoder, nil)
    state = put_in(state.decoder_state, nil)
    state = put_in(state.verifier, nil)

    {data_stream, state}
  end

  defp verify_file_integrity(state) do
    {crc32, uncompressed_size} = Verifier.done(state.verifier)

    unless crc32 == state.local_header.crc32 do
      raise Error, "Invalid crc32, expected: #{state.local_header.crc32}, actual: #{crc32}"
    end

    unless uncompressed_size == state.local_header.uncompressed_size do
      raise Error,
            "Invalid size, expected: #{state.local_header.uncompressed_size}, actual: #{
              uncompressed_size
            }"
    end

    {[], state}
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

  defp parse_local_header(_), do: raise(Error, "Invalid local header")

  defp bit_set?(bits, n) do
    (bits &&& 1 <<< n) > 0
  end

  defp dos_time(date, time) do
    <<year::size(7), month::size(4), day::size(5)>> = <<date::size(16)>>
    <<hour::size(5), minute::size(6), second::size(5)>> = <<time::size(16)>>

    {:ok, datetime} =
      NaiveDateTime.new(
        1980 + year,
        month,
        day,
        hour,
        minute,
        min(second * 2, 59)
      )

    datetime
  end
end
