defmodule Zstream.Unzip.Verifier do
  @moduledoc false

  use GenServer

  @name __MODULE__

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: @name)
  end

  def new do
    ref = make_ref()
    true = :ets.insert_new(@name, {ref, 0, 0})
    ref
  end

  def update({:data, data}, ref) do
    [{^ref, crc32, uncompressed_size} = orig] = :ets.lookup(@name, ref)

    new = {ref, :erlang.crc32(crc32, data), uncompressed_size + IO.iodata_length(data)}

    case :ets.select_replace(@name, [{orig, [], [{:const, new}]}]) do
      1 ->
        {[{:data, data}], ref}

      other ->
        raise "Not Updated #{other}"
    end
  end

  def done(ref) do
    [{^ref, crc32, uncompressed_size}] = :ets.lookup(@name, ref)
    {crc32, uncompressed_size}
  end

  @impl GenServer
  def init(_args) do
    table = :ets.new(@name, [:set, :public, :named_table])
    {:ok, table}
  end
end
