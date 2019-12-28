defmodule Zstream.Unzip.Extra do
  @moduledoc false
  use Bitwise

  defmodule Unknown do
    @type t :: %__MODULE__{
            signature: String.t(),
            tsize: integer(),
            data: iodata()
          }

    defstruct [:signature, :tsize, :data]
  end

  defmodule ExtendedTimestamp do
    @type t :: %__MODULE__{
            mtime: DateTime.t() | nil,
            atime: DateTime.t() | nil,
            ctime: DateTime.t() | nil
          }

    defstruct [:mtime, :atime, :ctime]
  end

  defmodule Zip64ExtendedInformation do
    @type t :: %__MODULE__{
            size: integer(),
            compressed_size: integer()
          }

    defstruct [:size, :compressed_size]
  end

  #        -Extended Timestamp Extra Field:
  #         ==============================

  #         The following is the layout of the extended-timestamp extra block.
  #         (Last Revision 19970118)

  #         Local-header version:

  #         Value         Size        Description
  #         -----         ----        -----------
  # (time)  0x5455        Short       tag for this extra block type ("UT")
  #         TSize         Short       total data size for this block
  #         Flags         Byte        info bits
  #         (ModTime)     Long        time of last modification (UTC/GMT)
  #         (AcTime)      Long        time of last access (UTC/GMT)
  #         (CrTime)      Long        time of original creation (UTC/GMT)

  #         The central-header extra field contains the modification time only,
  #         or no timestamp at all.  TSize is used to flag its presence or
  #         absence.  But note:

  #             If "Flags" indicates that Modtime is present in the local header
  #             field, it MUST be present in the central header field, too!
  #             This correspondence is required because the modification time
  #             value may be used to support trans-timezone freshening and
  #             updating operations with zip archives.

  #         The time values are in standard Unix signed-long format, indicating
  #         the number of seconds since 1 January 1970 00:00:00.  The times
  #         are relative to Coordinated Universal Time (UTC), also sometimes
  #         referred to as Greenwich Mean Time (GMT).  To convert to local time,
  #         the software must know the local timezone offset from UTC/GMT.

  #         The lower three bits of Flags in both headers indicate which time-
  #         stamps are present in the LOCAL extra field:

  #               bit 0           if set, modification time is present
  #               bit 1           if set, access time is present
  #               bit 2           if set, creation time is present
  #               bits 3-7        reserved for additional timestamps; not set

  #         Those times that are present will appear in the order indicated, but
  #         any combination of times may be omitted.  (Creation time may be
  #         present without access time, for example.)  TSize should equal
  #         (1 + 4*(number of set bits in Flags)), as the block is currently
  #         defined.  Other timestamps may be added in the future.

  def parse(<<0x5455::little-size(16), _tsize::little-size(16), rest::binary>>, acc) do
    <<flag::little-size(8), rest::binary>> = rest
    timestamp = %ExtendedTimestamp{}

    {timestamp, rest} =
      if bit_set?(flag, 0) do
        <<mtime::little-size(32), rest::binary>> = rest
        {%{timestamp | mtime: DateTime.from_unix!(mtime)}, rest}
      else
        {timestamp, rest}
      end

    {timestamp, rest} =
      if bit_set?(flag, 1) do
        <<atime::little-size(32), rest::binary>> = rest
        {%{timestamp | atime: DateTime.from_unix!(atime)}, rest}
      else
        {timestamp, rest}
      end

    {timestamp, rest} =
      if bit_set?(flag, 2) do
        <<ctime::little-size(32), rest::binary>> = rest
        {%{timestamp | ctime: DateTime.from_unix!(ctime)}, rest}
      else
        {timestamp, rest}
      end

    parse(rest, [timestamp | acc])
  end

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

  def parse(
        <<0x0001::little-size(16), tsize::little-size(16), size::little-size(64),
          compressed_size::little-size(64), rest::binary>>,
        acc
      ) do
    tsize = tsize - 16
    <<_data::binary-size(tsize), rest::binary>> = rest

    zip64_extended_information = %Zip64ExtendedInformation{
      size: size,
      compressed_size: compressed_size
    }

    parse(rest, [zip64_extended_information | acc])
  end

  def parse(<<signature::little-size(16), tsize::little-size(16), rest::binary>>, acc) do
    <<data::binary-size(tsize), rest::binary>> = rest

    parse(rest, [
      %Unknown{signature: Integer.to_string(signature, 16), tsize: tsize, data: data} | acc
    ])
  end

  def parse(<<>>, acc), do: Enum.reverse(acc)

  defp bit_set?(bits, n) do
    (bits &&& 1 <<< n) > 0
  end
end
