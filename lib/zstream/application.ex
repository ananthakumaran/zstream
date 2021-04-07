defmodule Zstream.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      Zstream.Unzip.Verifier
    ]

    opts = [strategy: :one_for_one, name: Zstream.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
