# Zstream

[![Build Status](https://secure.travis-ci.org/ananthakumaran/zstream.svg)](http://travis-ci.org/ananthakumaran/zstream)
[![Hex.pm](https://img.shields.io/hexpm/v/zstream.svg)](https://hex.pm/packages/zstream)

An elixir library to create ZIP file in a streaming fashion. It could
consume data from any stream and write to any stream with constant
memory overhead

## Example

```elixir
Zstream.create([
  Zstream.entry("report.csv", Stream.map(records, &CSV.dump/1)),
  Zstream.entry("catfilm.mp4", File.stream!("/catfilm.mp4"), coder: Zstream.Coder.Stored)
])
|> Stream.into(File.stream!("/archive.zip"))
|> Stream.run
```

see [documenation](https://hexdocs.pm/zstream/) for more information.
