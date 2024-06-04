defmodule Zstream.Zip.Extra do
  @moduledoc false

  #    -Zip64 Extended Information Extra Field (0x0001):

  #       The following is the layout of the zip64 extended
  #       information "extra" block. If one of the size or
  #       offset fields in the Local or Central directory
  #       record is too small to hold the required data,
  #       a Zip64 extended information record is created.
  #       The order of the fields in the zip64 extended
  #       information record is fixed, but the fields MUST
  #       only appear if the corresponding Local or Central
  #       directory record field is set to 0xFFFF or 0xFFFFFFFF.

  #       Note: all fields stored in Intel low-byte/high-byte order.

  #         Value      Size       Description
  #         -----      ----       -----------
  # (ZIP64) 0x0001     2 bytes    Tag for this "extra" block type
  #         Size       2 bytes    Size of this "extra" block
  #         Original
  #         Size       8 bytes    Original uncompressed file size
  #         Compressed
  #         Size       8 bytes    Size of compressed data
  #         Relative Header
  #         Offset     8 bytes    Offset of local header record
  #         Disk Start
  #         Number     4 bytes    Number of the disk on which
  #                               this file starts

  #       This entry in the Local header MUST include BOTH original
  #       and compressed file size fields. If encrypting the
  #       central directory and bit 13 of the general purpose bit
  #       flag is set indicating masking, the value stored in the
  #       Local Header for the original file size will be zero.

  def zip64_extended_info(size, c_size, offset) do
    <<0x0001::little-size(16), 28::little-size(16), size::little-size(64),
      c_size::little-size(64), offset::little-size(64), 0::little-size(32)>>
  end
end
