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

  test "unzip" do
    verify_unzip("uncompressed")
    verify_unzip("compressed-standard")
    verify_unzip("compressed-flags-set")
    verify_unzip("trail")
    verify_unzip("padding")
  end

  test "unsupported unzip" do
    verify_unzip_error(
      "compressed-OSX-Finder/archive.zip",
      "Zip files with data descriptor record are not supported"
    )

    verify_unzip_error(
      "invalid/archive.zip",
      "Invalid local header"
    )

    verify_unzip_error(
      "zipbomb/42-password-42.zip",
      "Unsupported compression method 99"
    )
  end

  test "zip bomb" do
    files = [
      "zipbomb/zbsm.zip",
      "zipbomb/42-passwordless.zip",
      "zipbomb/338.zip",
      "zipbomb/droste.zip",
      "zipbomb/zip-bomb.zip"
    ]

    Enum.each(files, fn path ->
      file(path)
      |> Zstream.unzip()
      |> Stream.run()
    end)
  end

  test "password" do
    password = Base.encode64(:crypto.strong_rand_bytes(12))

    verify_password(
      [
        Zstream.entry("kafan", file("kafan.txt"),
          encryption_coder: {Zstream.EncryptionCoder.Traditional, password: password}
        ),
        Zstream.entry("kafka_uncompressed", file("kafan.txt"),
          coder: Zstream.Coder.Stored,
          encryption_coder: {Zstream.EncryptionCoder.Traditional, password: password}
        )
      ],
      password
    )

    verify_password(
      [
        Zstream.entry("कफ़न", file("kafan.txt"),
          encryption_coder: {Zstream.EncryptionCoder.Traditional, password: password}
        )
      ],
      password
    )

    verify_password(
      [
        Zstream.entry("empty_file", [],
          encryption_coder: {Zstream.EncryptionCoder.Traditional, password: password}
        ),
        Zstream.entry("empty_file_1", [],
          coder: Zstream.Coder.Stored,
          encryption_coder: {Zstream.EncryptionCoder.Traditional, password: password}
        )
      ],
      password
    )

    verify_password(
      [
        Zstream.entry("moby.txt", file("moby_dick.txt"),
          coder: Zstream.Coder.Stored,
          encryption_coder: {Zstream.EncryptionCoder.Traditional, password: password}
        ),
        Zstream.entry("deep/moby.txt", file("moby_dick.txt"),
          coder: Zstream.Coder.Stored,
          encryption_coder: {Zstream.EncryptionCoder.Traditional, password: password}
        ),
        Zstream.entry(
          "deep/deep/deep/deep/moby.txt",
          file("moby_dick.txt"),
          coder: Zstream.Coder.Stored,
          encryption_coder: {Zstream.EncryptionCoder.Traditional, password: password}
        )
      ],
      password
    )

    verify_password(
      [
        Zstream.entry("empty_folder/.keep", [],
          encryption_coder: {Zstream.EncryptionCoder.Traditional, password: password}
        )
      ],
      password
    )
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

    {:ok, decoded_entries} = :zip.unzip(compressed, [:memory, :verbose])
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
    verify_using_os_binary(entries, zip64: true)
  end

  defp verify_password(entries, password) do
    verify_password_with_options(entries, password)
    verify_password_with_options(entries, password, zip64: true)
  end

  defp verify_password_with_options(entries, password, options \\ []) do
    Temp.track!()
    path = Temp.path!(%{suffix: ".zip"})

    Zstream.zip(entries, options)
    |> Stream.into(File.stream!(path))
    |> Stream.run()

    {response, exit_code} = System.cmd("zipinfo", [path])
    Logger.debug(response)
    assert exit_code == 0

    {response, exit_code} = System.cmd("unzip", ["-P", password, "-t", path])
    Logger.debug(response)
    assert exit_code == 0

    File.rm!(path)
  end

  defp verify_using_os_binary(entries, options \\ []) do
    Temp.track!()
    path = Temp.path!(%{suffix: ".zip"})

    Zstream.zip(entries, options)
    |> Stream.into(File.stream!(path))
    |> Stream.run()

    {response, exit_code} = System.cmd("zipinfo", [path])
    Logger.debug(response)
    assert exit_code == 0

    {response, exit_code} = System.cmd("unzip", ["-t", path])
    Logger.debug(response)
    assert exit_code == 0

    File.rm!(path)
  end

  defp verify_unzip(path) do
    file(path <> "/archive.zip")
    |> Zstream.unzip()
    |> Enum.reduce(
      %{buffer: "", file_name: nil},
      fn
        {:entry, %Zstream.Entry{name: file_name} = entry}, state ->
          Logger.info(inspect(entry))
          state = put_in(state.file_name, file_name)
          put_in(state.buffer, "")

        {:data, :eof}, state ->
          unless String.ends_with?(state.file_name, "/") do
            actual = IO.iodata_to_binary(state.buffer)

            expected =
              File.read!(Path.join([__DIR__, "fixture", path, "inflated", state.file_name]))

            assert actual == expected
          end

          state

        {:data, data}, state ->
          put_in(state.buffer, [state.buffer, data])
      end
    )
  end

  defp verify_unzip_error(path, error) do
    assert_raise Zstream.Unzip.Error, error, fn ->
      file(path)
      |> Zstream.unzip()
      |> Enum.to_list()
    end
  end

  defp as_binary(stream) do
    stream
    |> Enum.to_list()
    |> IO.iodata_to_binary()
  end

  defp file(name) do
    File.stream!(Path.join([__DIR__, "fixture", name]), [], 100)
  end

  def random_bytes() do
    :crypto.strong_rand_bytes(1024 * 1024)
  end

  def assert_memory do
    total = (:erlang.memory() |> Keyword.fetch!(:total)) / (1024 * 1024)
    Logger.debug("Total memory: #{total}")
    assert total < 150
  end
end
