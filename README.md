# Zstream

[![CI](https://github.com/ananthakumaran/zstream/workflows/.github/workflows/ci.yml/badge.svg)](https://github.com/ananthakumaran/zstream/actions?query=workflow%3A.github%2Fworkflows%2Fci.yml)
[![Module Version](https://img.shields.io/hexpm/v/zstream.svg)](https://hex.pm/packages/zstream)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/zstream/)
[![Total Download](https://img.shields.io/hexpm/dt/zstream.svg)](https://hex.pm/packages/zstream)
[![License](https://img.shields.io/hexpm/l/zstream.svg)](https://github.com/ananthakumaran/zstream/blob/master/LICENSE)
[![Last Updated](https://img.shields.io/github/last-commit/ananthakumaran/zstream.svg)](https://github.com/ananthakumaran/zstream/commits/master)

An Elixir library to read and write ZIP file in a streaming
fashion. It could consume data from any stream and write to any stream
with constant memory overhead.

## Installation

The package can be installed by adding `:zstream` to your list of dependencies
in `mix.exs`:

```elixir
def deps do
  [
    {:zstream, "~> 0.5.0"}
  ]
end
```

## Examples

```elixir
Zstream.zip([
  Zstream.entry("report.csv", Stream.map(records, &CSV.dump/1)),
  Zstream.entry("catfilm.mp4", File.stream!("/catfilm.mp4", [], 512), coder: Zstream.Coder.Stored)
])
|> Stream.into(File.stream!("/archive.zip"))
|> Stream.run
```

```elixir
File.stream!("archive.zip", [], 512)
|> Zstream.unzip()
|> Enum.reduce(%{}, fn
  {:entry, %Zstream.Entry{name: file_name} = entry}, state -> state
  {:data, :eof}, state -> state
  {:data, data}, state -> state
end)
```

## Features

### zip

* compression (deflate, stored)
* encryption (traditional)
* zip64

### unzip

* compression (deflate, stored)
* zip64

## License

Copyright (c) 2017 Anantha Kumaran

This library is MIT licensed. See the [LICENSE](https://github.com/ananthakumaran/zstream/blob/master/LICENSE) for details.
