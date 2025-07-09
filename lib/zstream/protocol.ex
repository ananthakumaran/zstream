defmodule Zstream.Protocol do
  @moduledoc false

  import Bitwise
  alias Zstream.Zip.Extra

  # Specification is available at
  # https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT

  @comment "Created by Zstream"

  defp get_encryption_coder(options), do: get_in(options, [:encryption_coder, Access.elem(0)])

  def local_file_header(name, local_file_header_offset, options) do
    extra_field =
      zip64?(
        options,
        <<>>,
        Extra.zip64_extended_info(0, 0, local_file_header_offset)
      )

    encryption_coder = get_encryption_coder(options)

    final_extra_field =
      if encryption_coder && function_exported?(encryption_coder, :extra_field_data, 1) do
        [extra_field, encryption_coder.extra_field_data(options)]
      else
        extra_field
      end

    version_needed_to_extract =
      if encryption_coder && function_exported?(encryption_coder, :version_needed_to_extract, 0) do
        encryption_coder.version_needed_to_extract()
      else
        zip64?(options, 20, 45)
      end

    [
      <<
        # local file header signature
        0x04034B50::little-size(32),
        # version needed to extract
        version_needed_to_extract::little-size(16),
        general_purpose_bit_flag(options)::little-size(16),
        # compression method
        compression_method(options)::little-size(16),
        # last mod file time
        dos_time(Keyword.fetch!(options, :mtime))::little-size(16),
        # last mod file date
        dos_date(Keyword.fetch!(options, :mtime))::little-size(16),
        # crc-32
        0::little-size(32),
        # compressed size
        0::little-size(32),
        # uncompressed size
        0::little-size(32),
        # file name length
        byte_size(name)::little-size(16),
        # extra field length
        IO.iodata_length(final_extra_field)::little-size(16)
      >>,
      name,
      final_extra_field
    ]
  end

  def data_descriptor(crc32, compressed_size, uncompressed_size, options) do
    encryption_coder = get_encryption_coder(options)

    crc =
      if encryption_coder &&
           function_exported?(encryption_coder, :crc_exposed?, 1) &&
           !encryption_coder.crc_exposed?(options) do
        0
      else
        crc32
      end

    if Keyword.fetch!(options, :zip64) do
      # signature
      <<0x08074B50::little-size(32), crc::little-size(32), compressed_size::little-size(64),
        uncompressed_size::little-size(64)>>
    else
      # signature
      <<0x08074B50::little-size(32), crc::little-size(32), compressed_size::little-size(32),
        uncompressed_size::little-size(32)>>
    end
  end

  def central_directory_header(entry) do
    options = entry.options

    extra_field =
      zip64?(
        options,
        <<>>,
        Extra.zip64_extended_info(entry.size, entry.c_size, entry.local_file_header_offset)
      )

    encryption_coder = get_encryption_coder(options)

    final_extra_field =
      if encryption_coder && function_exported?(encryption_coder, :extra_field_data, 1) do
        [extra_field, encryption_coder.extra_field_data(options)]
      else
        extra_field
      end

    version_needed_to_extract =
      if encryption_coder && function_exported?(encryption_coder, :version_needed_to_extract, 0) do
        encryption_coder.version_needed_to_extract()
      else
        zip64?(options, 20, 45)
      end

    crc_exposed? =
      if encryption_coder && function_exported?(encryption_coder, :crc_exposed?, 1) do
        encryption_coder.crc_exposed?(options)
      else
        true
      end

    [
      <<
        # central file header signature
        0x02014B50::little-size(32),
        # version made by
        52::little-size(16),
        # version needed to extract
        version_needed_to_extract::little-size(16),
        general_purpose_bit_flag(entry.options)::little-size(16),
        # compression method
        compression_method(entry.options)::little-size(16),
        # last mod file time
        dos_time(Keyword.fetch!(entry.options, :mtime))::little-size(16),
        # last mod file date
        dos_date(Keyword.fetch!(entry.options, :mtime))::little-size(16),
        # crc-32
        if(crc_exposed?, do: entry.crc, else: 0)::little-size(32),
        # compressed size
        zip64?(options, entry.c_size, 0xFFFFFFFF)::little-size(32),
        # uncompressed size
        zip64?(options, entry.size, 0xFFFFFFFF)::little-size(32),
        # file name length
        byte_size(entry.name)::little-size(16),
        # extra field length
        IO.iodata_length(final_extra_field)::little-size(16),
        # file comment length
        0::little-size(16),
        # disk number start
        zip64?(options, 0, 0xFFFF)::little-size(16),
        # internal file attributes
        0::little-size(16),
        external_file_attributes()::little-size(32),
        zip64?(options, entry.local_file_header_offset, 0xFFFFFFFF)::little-size(32)
      >>,
      # file name
      entry.name,
      final_extra_field
    ]
  end

  def zip64_end_of_central_directory_record(offset, size, entries_count, options) do
    if Keyword.fetch!(options, :zip64) do
      <<
        # signature
        0x06064B50::little-size(32),
        # size of zip64 end of central directory record
        44::little-size(64),
        # version made by
        52::little-size(16),
        # version needed to extract
        45::little-size(16),
        # number of this disk
        0::little-size(32),
        # number of the disk with the start of the central directory
        0::little-size(32),
        # total number of entries in the central directory on this disk
        entries_count::little-size(64),
        # total number of entries in the central directory
        entries_count::little-size(64),
        # size of the central directory
        size::little-size(64),
        # offset of start of central directory with respect to the starting disk number
        offset::little-size(64)
      >>
    else
      <<>>
    end
  end

  def zip64_end_of_central_directory_locator(offset, options) do
    if Keyword.fetch!(options, :zip64) do
      <<
        # signature
        0x07064B50::little-size(32),
        # number of the disk with the start of the zip64 end of central directory
        0::little-size(32),
        # relative offset of the zip64 end of central directory record
        offset::little-size(64),
        # total number of disks
        1::little-size(32)
      >>
    else
      <<>>
    end
  end

  def end_of_central_directory(offset, size, entries_count) do
    <<
      # end of central dir signature
      0x06054B50::little-size(32),
      # number of this disk
      0::little-size(16),
      # number of the disk with the start of the central directory
      0::little-size(16),
      # total number of entries in the central directory on this disk
      Enum.min([entries_count, 0xFFFF])::little-size(16),
      # total number of entries in the central directory
      Enum.min([entries_count, 0xFFFF])::little-size(16),
      # size of the central directory
      Enum.min([size, 0xFFFFFFFF])::little-size(32),
      # offset of start of central directory with respect to the starting disk number
      Enum.min([offset, 0xFFFFFFFF])::little-size(32),
      # .ZIP file comment length
      byte_size(@comment)::little-size(16),
      @comment
    >>
  end

  defp general_purpose_bit_flag(options) do
    {encryption_coder, _opts} = Keyword.fetch!(options, :encryption_coder)

    # encryption bit set based on coder
    # bit 3 use data descriptor
    # bit 11 UTF-8 encoding of filename & comment fields
    encryption_coder.general_purpose_flag() ||| 0x0008 ||| 0x0800
  end

  defp external_file_attributes do
    unix_perms = 0o644
    file_type_file = 0o10
    (file_type_file <<< 12 ||| (unix_perms &&& 0o7777)) <<< 16
  end

  defp compression_method(options) do
    {coder, _opts} = Keyword.fetch!(options, :coder)

    encryption_coder = get_encryption_coder(options)

    if encryption_coder && function_exported?(encryption_coder, :compression_method, 0) do
      encryption_coder.compression_method()
    else
      coder.compression_method()
    end
  end

  defp dos_time(t) do
    div(t.second, 2) + (t.minute <<< 5) + (t.hour <<< 11)
  end

  defp dos_date(t) do
    round(t.day + (t.month <<< 5) + ((t.year - 1980) <<< 9))
  end

  defp zip64?(options, normal, zip64) do
    if Keyword.fetch!(options, :zip64) do
      zip64
    else
      normal
    end
  end
end
