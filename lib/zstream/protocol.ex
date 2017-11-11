defmodule Zstream.Protocol do
  @moduledoc false

  use Bitwise

  # Specification is available at
  # https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT

  @comment "Created by Zstream"

  def local_file_header(name, options) do
    [
    << 0x04034b50 :: little-size(32) >>, # local file header signature
    << 20 :: little-size(16) >>, # version needed to extract
    general_purpose_bit_flag(),
    << compression_method(options) :: little-size(16) >>, # compression method
    << dos_time(Keyword.fetch!(options, :mtime)) :: little-size(16) >>, # last mod file time
    << dos_date(Keyword.fetch!(options, :mtime)) :: little-size(16) >>, # last mod file date
    << 0 :: little-size(32) >>, # crc-32
    << 0 :: little-size(32) >>, # compressed size
    << 0 :: little-size(32) >>, # uncompressed size
    << byte_size(name) :: little-size(16) >>, # file name length
    << 0 :: little-size(16) >>, # extra field length
    name
    ]
  end

  def data_descriptor(crc32, compressed_size, uncompressed_size) do
    [
    << 0x08074b50 :: little-size(32) >>, # signature
    << crc32 :: little-size(32) >>,
    << compressed_size :: little-size(32) >>,
    << uncompressed_size :: little-size(32) >>
    ]
  end

  def central_directory_header(entry) do
    [
    << 0x02014b50 :: little-size(32) >>, # central file header signature
    << 52 :: little-size(16) >>, # version made by
    << 20 :: little-size(16) >>, # version needed to extract
    general_purpose_bit_flag(),
    << compression_method(entry.options) :: little-size(16) >>, # compression method
    << dos_time(Keyword.fetch!(entry.options, :mtime)) :: little-size(16) >>, # last mod file time
    << dos_date(Keyword.fetch!(entry.options, :mtime)) :: little-size(16) >>, # last mod file date
    << entry.crc :: little-size(32) >>, # crc-32
    << entry.c_size :: little-size(32) >>, # compressed size
    << entry.size :: little-size(32) >>, # uncompressed size
    << byte_size(entry.name) :: little-size(16) >>, # file name length
    << 0 :: little-size(16) >>, # extra field length
    << 0 :: little-size(16) >>, # file comment length
    << 0 :: little-size(16) >>, # disk number start
    << 0 :: little-size(16) >>, # internal file attributes
    << external_file_attributes() :: little-size(32) >>,
    << entry.local_file_header_offset :: little-size(32) >>,
    entry.name # file name
    ]
  end

  def central_directory_end(offset, size, entries_count) do
    [
    << 0x06054b50 :: little-size(32) >>, # end of central dir signature
    << 0 :: little-size(16) >>, # number of this disk
    << 0 :: little-size(16) >>, # number of the disk with the start of the central directory
    << entries_count :: little-size(16) >>, # total number of entries in the central directory on this disk
    << entries_count :: little-size(16) >>, # total number of entries in the central directory
    << size :: little-size(32) >>, # size of the central directory
    << offset :: little-size(32) >>, # offset of start of central directory with respect to the starting disk number
    << byte_size(@comment) :: little-size(16) >>, # .ZIP file comment length
    @comment
    ]
  end

  defp general_purpose_bit_flag do
    # bit 3 use data descriptor
    # bit 11 UTF-8 encoding of filename & comment fields
    << 0x0008 ||| 0x0800 :: little-size(16) >>
  end

  defp external_file_attributes do
    unix_perms = 0o644
    file_type_file = 0o10
    (file_type_file <<< 12 ||| (unix_perms &&& 0o7777)) <<< 16
  end

  defp compression_method(options) do
    {coder, _opts} = Keyword.fetch!(options, :coder)
    coder.compression_method()
  end

  defp dos_time(t) do
    round((t.second / 2) + (t.minute <<< 5) + (t.hour <<< 11))
  end

  defp dos_date(t) do
    round(t.day + (t.month <<< 5) + ((t.year - 1980) <<< 9))
  end
end
