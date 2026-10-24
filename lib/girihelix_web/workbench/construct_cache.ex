defmodule GirihelixWeb.Workbench.ConstructCache do
  @moduledoc """
  The shared construction cache: a named public ETS table with an LRU-ish cap.

  A construction is expensive (heavy tilings take tens of seconds), while a
  style, palette or `tiles` change only alters the drawing. `fetch/3` therefore
  builds a key at most once and returns the cached entry afterwards.

  The GenServer owns the table so it can be named, public and read-concurrent,
  and so puts and evictions are serialised. Builds happen in the caller, never
  in the server, so the requesting LiveView keeps its progress messages.

  This task implements the memory tier only. The `:disk?`, `:dets_file` and
  `:disk_bytes` options are accepted and carried in state for the disk tier
  that follows.

  ## Eviction

  A put evicts the least recently used entries (smallest `:accessed_at`, ties
  broken by key) until at most `:memory_entries` remain. `get/2` and a
  `fetch/3` hit touch `:accessed_at`, so a read keeps its entry resident.
  """

  use GenServer

  @default_memory_entries 4
  @default_disk? false
  @default_disk_bytes 1_000_000_000

  @type entry :: %{
          required(:key) => term(),
          required(:frames) => list(),
          required(:failure) => term(),
          required(:cells) => pos_integer(),
          required(:size) => non_neg_integer(),
          required(:inserted_at) => integer(),
          required(:accessed_at) => integer()
        }

  @doc """
  Starts a cache.

  Options:

    * `:name` — the registered server name (default `#{inspect(__MODULE__)}`)
    * `:ets_name` — the named public table (default derived from `:name`)
    * `:memory_entries` — the memory tier's cap (default #{@default_memory_entries})
    * `:disk?` — whether the disk tier is enabled (default #{@default_disk?})
    * `:dets_file` — the DETS file path, used by the disk tier
    * `:disk_bytes` — the disk tier's byte cap (default #{@default_disk_bytes})

  `:name` must be an atom.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    opts = Keyword.put_new_lazy(opts, :ets_name, fn -> ets_name(name) end)

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Builds a normalized entry for `key`.

  The entry carries its external size, so the disk tier can decide whether it
  fits without re-measuring it.
  """
  @spec entry(term(), list(), term(), pos_integer()) :: entry()
  def entry(key, frames, failure, cells) do
    now = System.monotonic_time()

    %{
      key: key,
      frames: frames,
      failure: failure,
      cells: cells,
      size: :erlang.external_size(frames),
      inserted_at: now,
      accessed_at: now
    }
  end

  @doc """
  Returns the entry for `key`, building it with `build_fun` on a miss.

  `build_fun` runs in the caller and is called at most once per cached key. A
  hit touches `:accessed_at`.
  """
  @spec fetch(GenServer.server(), term(), (-> entry())) :: entry()
  def fetch(server, key, build_fun) do
    case get(server, key) do
      nil ->
        entry = build_fun.()
        :ok = put(server, key, entry)
        entry

      entry ->
        entry
    end
  end

  @doc "Stores `entry` under `key`, evicting down to the memory cap."
  @spec put(GenServer.server(), term(), entry()) :: :ok
  def put(server, key, entry), do: GenServer.call(server, {:put, key, entry})

  @doc "Returns the entry for `key` and touches its `:accessed_at`, or `nil`."
  @spec get(GenServer.server(), term()) :: entry() | nil
  def get(server, key), do: GenServer.call(server, {:get, key})

  @doc "Clears the memory tier."
  @spec reset(GenServer.server()) :: :ok
  def reset(server), do: GenServer.call(server, :reset)

  @impl true
  def init(opts) do
    ets = Keyword.fetch!(opts, :ets_name)

    :ets.new(ets, [
      :named_table,
      :public,
      :set,
      read_concurrency: true,
      write_concurrency: true
    ])

    state = %{
      ets: ets,
      memory_entries: Keyword.get(opts, :memory_entries, @default_memory_entries),
      disk?: Keyword.get(opts, :disk?, @default_disk?),
      dets_file: Keyword.get(opts, :dets_file),
      disk_bytes: Keyword.get(opts, :disk_bytes, @default_disk_bytes)
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:put, key, entry}, _from, state) do
    :ets.insert(state.ets, {key, entry})
    evict(state)

    {:reply, :ok, state}
  end

  def handle_call({:get, key}, _from, state) do
    {:reply, touch(state.ets, key), state}
  end

  def handle_call(:reset, _from, state) do
    :ets.delete_all_objects(state.ets)

    {:reply, :ok, state}
  end

  defp ets_name(name) when is_atom(name), do: :"#{name}_ets"

  defp touch(ets, key) do
    case :ets.lookup(ets, key) do
      [{^key, entry}] -> touch_entry(ets, key, entry)
      [] -> nil
    end
  end

  defp touch_entry(ets, key, entry) do
    touched = %{entry | accessed_at: System.monotonic_time()}
    :ets.insert(ets, {key, touched})
    touched
  end

  defp evict(state), do: evict_oldest(state.ets, :ets.info(state.ets, :size) - state.memory_entries)

  defp evict_oldest(_ets, excess) when excess <= 0, do: :ok

  defp evict_oldest(ets, excess) do
    ets
    |> :ets.tab2list()
    |> Enum.sort_by(fn {key, entry} -> {entry.accessed_at, key} end)
    |> Enum.take(excess)
    |> Enum.each(fn {key, _entry} -> :ets.delete(ets, key) end)
  end
end
