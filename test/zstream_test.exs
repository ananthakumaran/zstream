defmodule ZstreamTest do
  require Logger
  use ExUnit.Case
  doctest Zstream

  test "zip" do
    verify([
      Zstream.entry("kafan", file("kafan.txt")),
      Zstream.entry("kafka_uncompressed", file("kafan.txt"), coder: Zstream.Coder.Stored)
    ])

    verify([
      Zstream.entry("कफ़न", file("kafan.txt"))
    ])

    verify([
      Zstream.entry("empty_file", []),
      Zstream.entry("empty_file_1", [], coder: Zstream.Coder.Stored)
    ])

    verify([
      Zstream.entry("moby.txt", file("moby_dick.txt"), coder: Zstream.Coder.Stored),
      Zstream.entry("deep/moby.txt", file("moby_dick.txt"), coder: Zstream.Coder.Stored),
      Zstream.entry("deep/deep/deep/deep/moby.txt", file("moby_dick.txt"),
        coder: Zstream.Coder.Stored
      )
    ])

    verify([
      Zstream.entry("empty_folder/.keep", [])
    ])
  end

  test "stream" do
    big_file = Stream.repeatedly(&random_bytes/0) |> Stream.take(200)

    assert_memory()

    Zstream.zip([
      Zstream.entry("big_file", big_file),
      Zstream.entry("big_file_2", big_file, coder: Zstream.Coder.Stored)
    ])
    |> Stream.run()

    assert_memory()
  end

  defmodule MockCoder do
    @behaviour Zstream.Coder
    def init(_opts), do: nil
    def encode(chunk, nil), do: {chunk, nil}

    def close(nil) do
      send(self(), :closed)
      []
    end

    def compression_method, do: 0
  end

  test "resource handling" do
    stream = Stream.unfold(5, fn i -> {to_string(100 / i), i - 1} end)

    try do
      [Zstream.entry("numbers", stream, coder: MockCoder)]
      |> Zstream.zip()
      |> Stream.run()
    rescue
      ArithmeticError -> :ok
    end

    assert_received :closed
  end

  defp verify(entries) do
    compressed =
      Zstream.zip(entries)
      |> as_binary

    {:ok, decoded_entries} = unzip(compressed)
    entries = Enum.reject(entries, fn e -> String.ends_with?(e.name, "/") end)
    assert length(entries) == length(decoded_entries)
    entries = Enum.sort_by(entries, & &1.name)
    decoded_entries = Enum.sort_by(decoded_entries, fn {name, _} -> IO.iodata_to_binary(name) end)

    Enum.zip(entries, decoded_entries)
    |> Enum.each(fn {entry, {decoded_filename, decoded_data}} ->
      assert entry.name == IO.iodata_to_binary(decoded_filename)
      assert as_binary(entry.stream) == decoded_data
    end)

    verify_using_os_binary(entries)
  end

  defp verify_using_os_binary(entries) do
    Temp.track!()
    path = Temp.path!(%{suffix: ".zip"})

    Zstream.zip(entries)
    |> Stream.into(File.stream!(path))
    |> Stream.run()

    {response, exit_code} = System.cmd("unzip", ["-t", path])
    Logger.debug(response)
    assert exit_code == 0

    {response, exit_code} = System.cmd("zipinfo", [path])
    Logger.debug(response)
    assert exit_code == 0

    File.rm!(path)
  end

  defp as_binary(stream) do
    stream
    |> Enum.to_list()
    |> IO.iodata_to_binary()
  end

  defp file(name) do
    File.stream!(Path.join([__DIR__, "fixture", name]))
  end

  def random_bytes() do
    :crypto.strong_rand_bytes(1024 * 1024)
  end

  def assert_memory do
    total = (:erlang.memory() |> Keyword.fetch!(:total)) / (1024 * 1024)
    Logger.debug("Total memory: #{total}")
    assert total < 150
  end

  defp unzip(compressed) do
    case :zip.unzip(compressed, [:memory, :verbose]) do
      {:ok, _} = r -> r
      # :zip can't handle Zip64, so fallback to system unzip in case that's
      # the problem.
      {:error, _} -> system_unzip(compressed)
    end
  end

  defp system_unzip(compressed) do
    with {tmp, _} <- System.cmd("mktemp", []),
         :ok <- File.write(tmp, compressed),
         {"Archive:  " <> out, _} = System.cmd("unzip", ["-c", tmp]) do
      [_header | lines] =
        out
        |> String.replace_suffix("\n\n", "\n")
        |> String.split(["extracting: ", "inflating: "])

      entries =
        lines
        |> Enum.map(fn file_output ->
          [name, contents] = String.split(file_output, "\n", parts: 2)

          # Do some ugly newline mangling to account for reading from
          # unzip stdout.
          contents =
            contents
            |> String.replace(~r/\n  \z/, "")
            |> String.replace(~r/\n\n \z/, "\n")

          {name |> String.trim(), contents}
        end)

      {:ok, entries}
    end
  end
end
