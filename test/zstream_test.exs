defmodule ZstreamTest do
  use ExUnit.Case
  doctest Zstream

  test "compress" do
    Zstream.create([
      Zstream.entry("LICENSE", File.stream!("LICENSE")),
      Zstream.entry("LICENSE_UNCOMPRESSED", File.stream!("LICENSE"), coder: {Zstream.Coder.Stored, []})
    ])
    |> Stream.into(File.stream!("test.zip"))
    |> Stream.run
  end
end
