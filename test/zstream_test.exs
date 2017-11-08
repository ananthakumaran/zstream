defmodule ZstreamTest do
  require Logger
  use ExUnit.Case
  doctest Zstream

  test "zip" do
    verify([
      Zstream.entry("kafan", file("kafan.txt")),
      Zstream.entry("kafka_uncompressed", file("kafan.txt"), coder: {Zstream.Coder.Stored, []})
    ])

    verify([
      Zstream.entry("कफ़न", file("kafan.txt")),
    ])

    verify([
      Zstream.entry("empty_file", []),
      Zstream.entry("empty_file_1", [""], coder: {Zstream.Coder.Stored, []})
    ])

    verify([
      Zstream.entry("moby.txt", file("moby_dick.txt"), coder: {Zstream.Coder.Stored, []}),
      Zstream.entry("deep/moby.txt", file("moby_dick.txt"), coder: {Zstream.Coder.Stored, []}),
      Zstream.entry("deep/deep/deep/deep/moby.txt", file("moby_dick.txt"), coder: {Zstream.Coder.Stored, []})
    ])

    verify([
      Zstream.entry("empty_folder_1/", []),
      Zstream.entry("empty_folder/.keep", [])
    ])
  end

  def verify(entries) do
    compressed = Zstream.create(entries)
    |> as_binary

    {:ok, decoded_entries} = :zip.unzip(compressed, [:memory, :verbose])
    entries = Enum.reject(entries, fn e -> String.ends_with?(e.name, "/") end)

    assert length(entries) == length(decoded_entries)
    entries = Enum.sort_by(entries, &(&1.name))
    decoded_entries = Enum.sort_by(decoded_entries, fn {name, _} -> IO.iodata_to_binary(name) end)

    Enum.zip(entries, decoded_entries)
    |> Enum.each(fn {entry, {decoded_filename, decoded_data}} ->
      assert entry.name == IO.iodata_to_binary(decoded_filename)
      assert as_binary(entry.stream) == decoded_data
    end)

    verify_using_os_binary(entries)
  end

  def verify_using_os_binary(entries) do
    Temp.track!
    path = Temp.path!(%{suffix: ".zip"})
    Zstream.create(entries)
    |> Stream.into(File.stream!(path))
    |> Stream.run

    {response, exit_code} = System.cmd("unzip", ["-t", path])
    Logger.debug(response)
    File.rm!(path)
    assert exit_code == 0
  end

  def as_binary(stream) do
    stream
    |> Enum.to_list
    |> IO.iodata_to_binary
  end

  def file(name) do
    File.stream!(Path.join([__DIR__, "fixture", name]))
  end
end
