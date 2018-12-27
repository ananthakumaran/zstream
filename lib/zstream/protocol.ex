defmodule Zstream.Protocol do
  @moduledoc """
  ZIP file format module, including support for Zip64. Adapted from the
  gist at

  https://gist.github.com/izelnakri/54361617af44b75895205f2a6c87cf27
  """
  use Bitwise

  @four_byte_max_uint 0xFFFFFFFF
  @two_byte_max_uint 0xFFFF

  @reader_version 20
  @writer_version 45

  @default_external_attributes 2_175_008_768

  # bit 3 use data descriptor
  # bit 11 UTF-8 encoding of filename & comment fields
  @general_purpose_bit_flag <<0x0008 ||| 0x0800::little-size(16)>>

  @comment_string "Created by Zstream"
  def comment_string, do: @comment_string

  @force_64 !!System.get_env("ZSTREAM_FORCE_ZIP_64")

  defp storage_mode(options) do
    {coder, _opts} = Keyword.fetch!(options, :coder)
    coder.compression_method()
  end

  def local_file_header(%{
        c_size: compressed_size,
        size: uncompressed_size,
        crc: crc32,
        options: options,
        name: filename
      })
      when compressed_size > @two_byte_max_uint or uncompressed_size > @four_byte_max_uint or
             @force_64 do
    mtime = Keyword.get(options, :mtime)

    extra_for_header =
      zip_64_extra_for_local_file_header(%{
        compressed_size: compressed_size,
        uncompressed_size: uncompressed_size
      })

    [
      # local file header signature 4 bytes  (0x04034b50)
      b4(0x04034B50),
      # version needed to extract   2 bytes
      b2(@reader_version),
      # general purpose bit flag    2 bytes
      @general_purpose_bit_flag,
      # compression method          2 bytes
      b2(options |> storage_mode()),
      # last mod file time          2 bytes
      b2(to_binary_dos_time(mtime)),
      # last mod file date          2 bytes
      b2(to_binary_dos_date(mtime)),
      # crc-32                      4 bytes
      b4(crc32),

      # NB. Store max int to signal Zip64 should be used.
      # compressed size             4 bytes
      b4(@four_byte_max_uint),
      # uncompressed size           4 bytes
      b4(@four_byte_max_uint),
      # file name length            2 bytes
      b2(byte_size(filename)),
      # extra field length          2 bytes
      b2(extra_for_header |> byte_size),
      # file name            (variable size)
      filename,
      extra_for_header
    ]
  end

  def local_file_header(%{
        c_size: compressed_size,
        size: uncompressed_size,
        crc: crc32,
        options: options,
        name: filename
      }) do
    mtime = Keyword.get(options, :mtime)

    [
      # local file header signature 4 bytes  (0x04034b50)
      b4(0x04034B50),
      # version needed to extract   2 bytes
      b2(@reader_version),
      # general purpose bit flag    2 bytes
      @general_purpose_bit_flag,
      # compression method          2 bytes
      b2(options |> storage_mode()),
      # last mod file time          2 bytes
      b2(to_binary_dos_time(mtime)),
      # last mod file date          2 bytes
      b2(to_binary_dos_date(mtime)),
      # crc-32                      4 bytes
      b4(crc32),
      # compressed size             4 bytes
      b4(compressed_size),
      # uncompressed size           4 bytes
      b4(uncompressed_size),
      # file name length            2 bytes
      b2(byte_size(filename)),
      # extra field length          2 bytes
      b2(0),
      # file name            (variable size)
      filename
    ]
  end

  def data_descriptor(
        crc32,
        compressed_size,
        uncompressed_size
      )
      when compressed_size > @four_byte_max_uint or uncompressed_size > @four_byte_max_uint or
             @force_64 do
    [
      # Although not originally assigned a signature, the value 0x08074b50
      # has commonly been adopted as a signature value
      b4(0x08074B50),
      # crc-32                          4 bytes
      b4(crc32),
      # compressed size                 8 bytes for ZIP64
      b8(compressed_size),
      # uncompressed size               8 bytes for ZIP64
      b8(uncompressed_size)
    ]
  end

  def data_descriptor(
        crc32,
        compressed_size,
        uncompressed_size
      ) do
    [
      # Although not originally assigned a signature, the value 0x08074b50
      # has commonly been adopted as a signature value
      b4(0x08074B50),
      # crc-32                          4 bytes
      b4(crc32),
      # compressed size                 4 bytes
      b4(compressed_size),
      # uncompressed size               4 bytes
      b4(uncompressed_size)
    ]
  end

  def central_directory_header(%{
        c_size: compressed_size,
        crc: crc32,
        local_file_header_offset: local_file_header_location,
        name: filename,
        options: options,
        size: uncompressed_size
      })
      when local_file_header_location > @four_byte_max_uint or
             compressed_size > @four_byte_max_uint or uncompressed_size > @four_byte_max_uint or
             @force_64 do
    mtime = Keyword.get(options, :mtime)

    extra_for_header =
      zip_64_extra_for_central_directory_file_header(%{
        local_file_header_location: local_file_header_location,
        compressed_size: compressed_size,
        uncompressed_size: uncompressed_size
      })

    [
      # central file header signature   4 bytes
      b4(0x02014B50),
      # version made by                 2 bytes
      b2(@writer_version),
      # version needed to extract       2 bytes
      b2(@reader_version),
      # general purpose bit flag        2 bytes
      @general_purpose_bit_flag,
      # compression method              2 bytes
      b2(options |> storage_mode()),
      # last mod file time              2 bytes
      b2(to_binary_dos_time(mtime)),
      # last mod file date              2 bytes
      b2(to_binary_dos_date(mtime)),
      # crc-32                          4 bytes
      b4(crc32),
      # compressed size                 4 bytes
      b4(@four_byte_max_uint),
      # uncompressed size               4 bytes
      b4(@four_byte_max_uint),
      # file name length                2 bytes
      b2(byte_size(filename)),
      # extra field length              2 bytes
      b2(extra_for_header |> byte_size),
      # file comment length             2 bytes
      b2(0),
      # disk number start               2 bytes
      b2(@two_byte_max_uint),
      # internal file attributes        2 bytes
      b2(0),
      # external file attributes        4 bytes
      b4(@default_external_attributes),
      # relative offset of local header 4 bytes
      b4(@four_byte_max_uint),
      # file name                (variable size)
      filename,
      # extra field              (variable size)
      extra_for_header
    ]
  end

  def central_directory_header(%{
        c_size: compressed_size,
        crc: crc32,
        local_file_header_offset: local_file_header_location,
        name: filename,
        options: options,
        size: uncompressed_size
      }) do
    mtime = Keyword.get(options, :mtime)

    [
      # central file header signature   4 bytes
      b4(0x02014B50),
      # version made by                 2 bytes
      b2(@writer_version),
      # version needed to extract       2 bytes
      b2(@reader_version),
      # general purpose bit flag        2 bytes
      @general_purpose_bit_flag,
      # compression method              2 bytes
      b2(options |> storage_mode()),
      # last mod file time              2 bytes
      b2(to_binary_dos_time(mtime)),
      # last mod file date              2 bytes
      b2(to_binary_dos_date(mtime)),
      # crc-32                          4 bytes
      b4(crc32),
      # compressed size                 4 bytes
      b4(compressed_size),
      # uncompressed size               4 bytes
      b4(uncompressed_size),
      # file name length                2 bytes
      b2(byte_size(filename)),
      # extra field length              2 bytes
      b2(0),
      # file comment length             2 bytes
      b2(0),
      # disk number start               2 bytes
      b2(0),
      # internal file attributes        2 bytes
      b2(0),
      # external file attributes        4 bytes
      b4(@default_external_attributes),
      # relative offset of local header 4 bytes
      b4(local_file_header_location),
      # file name                (variable size)
      filename
    ]
  end

  def end_of_central_directory(
        start_of_central_directory_location,
        central_directory_size,
        num_files_in_archive
      )
      when central_directory_size > @four_byte_max_uint or
             start_of_central_directory_location > @four_byte_max_uint or
             start_of_central_directory_location + central_directory_size > @four_byte_max_uint or
             num_files_in_archive > @two_byte_max_uint or @force_64 do
    [
      # signature                                    4 bytes  (0x06064b50)
      b4(0x06064B50),
      # size of zip64 end of central                 8 bytes
      b8(44),
      # version made by                              2 bytes
      b2(@writer_version),
      # version needed to extract                    2 bytes
      b2(@reader_version),
      # number of this disk                          4 bytes
      b4(0),
      # number of the disk                           4 bytes
      b4(0),
      # total number of entries on this disk         8 bytes
      b8(num_files_in_archive),
      # total number of entries in central directory 8 bytes
      b8(num_files_in_archive),
      # size of the central directory                8 bytes
      b8(central_directory_size),
      # the starting disk number                     8 bytes
      b8(start_of_central_directory_location),
      # zip64 end of central dir locator signature   4 bytes
      b4(0x07064B50),
      # number of the disk from zip64 start to eocd  4 bytes
      b4(0),
      # relative offset of the zip64                 8 bytes
      b8(start_of_central_directory_location + central_directory_size),
      # total number of disks                        4 bytes
      b4(1),
      # end of central dir signature                 4 bytes
      b4(0x06054B50),
      # number of this disk                          2 bytes
      b2(0),
      # disk with from central directory             2 bytes
      b2(0),

      # NB. Store max values to signal Zip64 should be used instead.
      # total number of entries on disk              2 bytes
      b2(@two_byte_max_uint),
      # total number of entries in central directory 2 bytes
      b2(@two_byte_max_uint),
      # size of the central directory                4 bytes
      b4(@four_byte_max_uint),
      # offset of start of central from disk start   4 bytes
      b4(@four_byte_max_uint),
      # .ZIP file comment length                     2 bytes
      b2(byte_size(@comment_string)),
      # .ZIP file comment                     (variable size)
      @comment_string
    ]
  end

  def end_of_central_directory(
        start_of_central_directory_location,
        central_directory_size,
        num_files_in_archive
      ) do
    [
      # end of central dir signature                 4 bytes  (0x06054b50
      b4(0x06054B50),
      # number of this disk                          2 bytes
      b2(0),
      # disk with from central directory             2 bytes
      b2(0),
      # total number of entries on disk              2 bytes
      b2(num_files_in_archive),
      # total number of entries in central directory 2 bytes
      b2(num_files_in_archive),
      # size of the central directory                4 bytes
      b4(central_directory_size),
      # offset of start of central from disk start   4 bytes
      b4(start_of_central_directory_location),
      # .ZIP file comment length                     2 bytes
      b2(byte_size(@comment_string)),
      # .ZIP file comment                     (variable size)
      @comment_string
    ]
  end

  defp zip_64_extra_for_local_file_header(%{
         compressed_size: compressed_size,
         uncompressed_size: uncompressed_size
       }) do
    [
      # 2 bytes    Tag for this "extra" block type
      b2(0x0001),
      # 2 bytes    Size of this "extra" block. For us it will always be 16 (2x8)
      b2(16),
      # 8 bytes    Original uncompressed file size
      b8(uncompressed_size),
      # 8 bytes    Size of compressed data
      b8(compressed_size)
    ]
    |> Enum.join()
  end

  defp zip_64_extra_for_central_directory_file_header(%{
         compressed_size: compressed_size,
         uncompressed_size: uncompressed_size,
         local_file_header_location: local_file_header_location
       }) do
    [
      # 2 bytes    Tag for this "extra" block type
      b2(0x0001),
      # 2 bytes    Size of this "extra" block. For us it will always be 28
      b2(24),
      # 8 bytes    Original uncompressed file size
      b8(uncompressed_size),
      # 8 bytes    Size of compressed data
      b8(compressed_size),
      # 8 bytes    Offset of local header record
      b8(local_file_header_location),
      # 4 bytes    Number of the disk on which this file starts
      b4(0)
    ]
    |> Enum.join()
  end

  defp b2(x), do: <<x::little-integer-size(16)>>

  defp b4(x), do: <<x::little-integer-size(32)>>

  defp b8(x), do: <<x::little-integer-size(64)>>

  defp to_binary_dos_time(time),
    do: round(time.second / 2 + (time.minute <<< 5) + (time.hour <<< 11))

  defp to_binary_dos_date(date),
    do: round(date.day + (date.month <<< 5) + ((date.year - 1980) <<< 9))
end
