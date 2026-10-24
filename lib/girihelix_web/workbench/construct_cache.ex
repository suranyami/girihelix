defmodule GirihelixWeb.Workbench.ConstructCache do
  @moduledoc """
  The shared construction cache: a memory ETS tier over a persistent DETS tier.

  A construction is expensive (heavy tilings take tens of seconds), while a
  style, palette or `tiles` change only alters the drawing. `fetch/3` therefore
  builds a key at most once and returns the cached entry afterwards.

  The GenServer owns the table so it can be named, public and read-concurrent,
  and so puts and evictions are serialised. Builds happen in the caller, never
  in the server, so the requesting LiveView keeps its progress messages.

  ## Tiers

    * The memory tier is a named public ETS table capped at `:memory_entries`
      (four by default), evicted least recently used.
    * The disk tier is a DETS table capped at `:disk_bytes` (1 GB by default),
      evicted oldest first by `:inserted_at`. A `fetch/3` that misses ETS looks
      in DETS, promotes the hit into memory and returns it without building.
    * Disable the disk tier with `disk?: false`; a DETS file that cannot be
      opened or repaired is deleted, rebuilt empty and logged, leaving the
      memory tier working.

  ## Versioning

  The cache stores a `:"__version__"` entry holding
  `{schema_version, Application.spec(:girihelix, :vsn)}` and namespaces every
  stored key with the same pair. A mismatch at boot clears the disk tier before
  it serves anything, so a deploy never reads an old frame shape.

  ## Eviction

  A put evicts the least recently used memory entries (smallest `:accessed_at`,
  ties broken by key) until at most `:memory_entries` remain. Before a disk
  write the server evicts the oldest inserted disk entries until the new entry
  fits. `get/2` and a `fetch/3` hit touch `:accessed_at`, so a read keeps its
  memory entry resident. An entry larger than `:disk_bytes` stays memory-only.
  """

  use GenServer

  require Logger

  @schema_version 1
  @version_key :__version__

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
    * `:dets_file` — the DETS file path (default `construct_cache.dets` under
      the configured `:cache_dir`, or `var/cache` in the working directory)
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

  Timestamps use the wall clock in microseconds, so disk eviction order is
  meaningful across restarts. The entry carries its external size, so the disk
  tier can decide whether it fits without re-measuring it.
  """
  @spec entry(term(), list(), term(), pos_integer()) :: entry()
  def entry(key, frames, failure, cells) do
    now = System.system_time(:microsecond)

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
  hit in either tier returns without calling `build_fun`; a disk hit is
  promoted into memory and touches its recency.
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

  @doc "Stores `entry` under `key` in memory and, when it fits, on disk."
  @spec put(GenServer.server(), term(), entry()) :: :ok
  def put(server, key, entry), do: GenServer.call(server, {:put, key, entry})

  @doc """
  Returns the entry for `key` from either tier and touches its `:accessed_at`,
  or `nil` when neither tier has it. A disk hit is promoted into memory.
  """
  @spec get(GenServer.server(), term()) :: entry() | nil
  def get(server, key), do: GenServer.call(server, {:get, key})

  @doc "Clears the memory tier. The disk tier is left for `clear_disk/1`."
  @spec reset(GenServer.server()) :: :ok
  def reset(server), do: GenServer.call(server, :reset)

  @doc "Clears the disk tier and rewrites its version entry."
  @spec clear_disk(GenServer.server()) :: :ok
  def clear_disk(server), do: GenServer.call(server, :clear_disk)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

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
      dets: nil,
      dets_file: Keyword.get(opts, :dets_file),
      disk_bytes: Keyword.get(opts, :disk_bytes, @default_disk_bytes),
      disk_index: %{},
      disk_total: 0
    }

    {:ok, open_disk(state, Keyword.get(opts, :disk?, @default_disk?))}
  end

  @impl true
  def terminate(_reason, %{dets: nil}), do: :ok
  def terminate(_reason, %{dets: dets}), do: :dets.close(dets)

  @impl true
  def handle_call({:put, key, entry}, _from, state) do
    :ets.insert(state.ets, {key, entry})
    evict_memory(state)

    {:reply, :ok, put_disk(state, key, entry)}
  end

  def handle_call({:get, key}, _from, state) do
    case touch(state.ets, key) do
      nil ->
        {entry, state} = promote(state, key)
        {:reply, entry, state}

      entry ->
        {:reply, entry, state}
    end
  end

  def handle_call(:reset, _from, state) do
    :ets.delete_all_objects(state.ets)

    {:reply, :ok, state}
  end

  def handle_call(:clear_disk, _from, state), do: {:reply, :ok, reset_dets(state)}

  defp ets_name(name) when is_atom(name), do: :"#{name}_ets"

  defp touch(ets, key) do
    case :ets.lookup(ets, key) do
      [{^key, entry}] -> touch_entry(ets, key, entry)
      [] -> nil
    end
  end

  defp touch_entry(ets, key, entry) do
    touched = %{entry | accessed_at: now()}
    :ets.insert(ets, {key, touched})
    touched
  end

  defp evict_memory(state), do: evict_oldest(state.ets, :ets.info(state.ets, :size) - state.memory_entries)

  defp evict_oldest(_ets, excess) when excess <= 0, do: :ok

  defp evict_oldest(ets, excess) do
    ets
    |> :ets.tab2list()
    |> Enum.sort_by(fn {key, entry} -> {entry.accessed_at, key} end)
    |> Enum.take(excess)
    |> Enum.each(fn {key, _entry} -> :ets.delete(ets, key) end)
  end

  # -- disk tier -------------------------------------------------------------

  # A promotion returns the entry (or nil) and the possibly-degraded state: a
  # runtime DETS failure disables the disk tier so later calls take the
  # memory-only path instead of crashing.
  defp promote(%{dets: nil} = state, _key), do: {nil, state}

  defp promote(state, key) do
    case :dets.lookup(state.dets, disk_key(key)) do
      [
        {_stored_key,
         %{
           frames: _,
           failure: _,
           cells: _,
           size: _,
           inserted_at: _,
           accessed_at: _
         } = entry}
      ] ->
        promoted = %{entry | accessed_at: now()}
        :ets.insert(state.ets, {key, promoted})
        evict_memory(state)
        {promoted, state}

      [{stored_key, _malformed}] ->
        # A stored object without the entry shape cannot be served; drop it
        # rather than failing the read.
        {nil, remove_disk(state, stored_key)}

      [] ->
        {nil, state}

      {:error, reason} ->
        {nil, degrade_disk(state, state.dets_file, reason)}
    end
  end

  defp put_disk(%{dets: nil} = state, _key, _entry), do: state

  defp put_disk(%{disk_bytes: cap} = state, key, %{size: size}) when size > cap do
    # The oversized replacement must not leave a stale, smaller copy on disk.
    remove_disk(state, disk_key(key))
  end

  defp put_disk(state, key, %{size: size} = entry) do
    stored_key = disk_key(key)

    state =
      state
      |> drop_index(stored_key)
      |> evict_disk(size)

    store_dets(state, stored_key, entry, size)
  end

  defp store_dets(%{dets: nil} = state, _stored_key, _entry, _size) do
    # Eviction may have degraded the tier on a delete error; the entry stays
    # memory-only rather than writing to a closed table.
    state
  end

  defp store_dets(state, stored_key, entry, size) do
    case :dets.insert(state.dets, {stored_key, entry}) do
      :ok ->
        index =
          Map.put(state.disk_index, stored_key, %{
            size: size,
            inserted_at: entry.inserted_at
          })

        %{state | disk_index: index, disk_total: state.disk_total + size}

      {:error, reason} ->
        degrade_disk(state, state.dets_file, reason)
    end
  end

  defp evict_disk(%{disk_total: total, disk_bytes: cap} = state, incoming) when total + incoming <= cap, do: state

  defp evict_disk(state, incoming) do
    case oldest_disk(state) do
      nil -> state
      {stored_key, _meta} -> evict_disk(remove_disk(state, stored_key), incoming)
    end
  end

  defp remove_disk(%{dets: nil} = state, _stored_key), do: state

  defp remove_disk(state, stored_key) do
    case :dets.delete(state.dets, stored_key) do
      :ok -> drop_index(state, stored_key)
      {:error, reason} -> degrade_disk(state, state.dets_file, reason)
    end
  end

  defp oldest_disk(%{disk_index: index}) when map_size(index) == 0, do: nil

  defp oldest_disk(%{disk_index: index}) do
    Enum.min_by(index, fn {stored_key, meta} -> {meta.inserted_at, stored_key} end)
  end

  defp drop_index(state, stored_key) do
    case Map.pop(state.disk_index, stored_key) do
      {nil, _index} ->
        state

      {meta, index} ->
        %{state | disk_index: index, disk_total: state.disk_total - meta.size}
    end
  end

  defp disk_key(key), do: {current_version(), key}

  defp now, do: System.system_time(:microsecond)

  # -- DETS lifecycle --------------------------------------------------------

  defp open_disk(state, false), do: state

  defp open_disk(state, _enabled) do
    path = state.dets_file || default_dets_file()
    dets = :"#{state.ets}_dets"

    with :ok <- File.mkdir_p(Path.dirname(path)),
         {:ok, opened} <- open_dets(dets, path) do
      load_disk(%{state | dets: opened, dets_file: path})
    else
      {:error, reason} -> degrade_disk(state, path, reason)
    end
  end

  defp open_dets(dets, path) do
    case :dets.open_file(dets, file: String.to_charlist(path), type: :set, access: :read_write) do
      {:ok, opened} ->
        {:ok, opened}

      {:error, reason} ->
        Logger.warning(
          "construction cache: cannot open #{path} (#{inspect(reason)}); " <>
            "deleting it and starting an empty disk tier"
        )

        _ = :dets.close(dets)
        _ = File.rm(path)
        :dets.open_file(dets, file: String.to_charlist(path), type: :set, access: :read_write)
    end
  end

  defp load_disk(state) do
    version = current_version()

    case :dets.lookup(state.dets, @version_key) do
      [{@version_key, ^version}] -> index_disk(state)
      _ -> reset_dets(state)
    end
  end

  defp index_disk(state) do
    {index, total, malformed} =
      :dets.foldl(
        fn
          {@version_key, _}, acc ->
            acc

          {stored_key, %{size: size, inserted_at: inserted_at}}, {index, total, malformed} ->
            {Map.put(index, stored_key, %{size: size, inserted_at: inserted_at}), total + size, malformed}

          {stored_key, _other}, {index, total, malformed} ->
            {index, total, [stored_key | malformed]}

          _other, acc ->
            acc
        end,
        {%{}, 0, []},
        state.dets
      )

    state = %{state | disk_index: index, disk_total: total}

    # Objects that cannot be interpreted are removed, so the index and the
    # file agree, then the cap is enforced against the current `:disk_bytes`.
    state =
      Enum.reduce(malformed, state, fn stored_key, state -> remove_disk(state, stored_key) end)

    evict_disk(state, 0)
  end

  defp reset_dets(%{dets: nil} = state), do: state

  defp reset_dets(state) do
    with :ok <- :dets.delete_all_objects(state.dets),
         :ok <- :dets.insert(state.dets, {@version_key, current_version()}) do
      %{state | disk_index: %{}, disk_total: 0}
    else
      {:error, reason} -> degrade_disk(state, state.dets_file, reason)
    end
  end

  defp degrade_disk(state, path, reason) do
    Logger.warning("construction cache: disk tier disabled at #{path} (#{inspect(reason)})")

    _ = state.dets && :dets.close(state.dets)

    %{state | dets: nil, dets_file: path, disk_index: %{}, disk_total: 0}
  end

  defp default_dets_file do
    dir = Application.get_env(:girihelix, :cache_dir) || Path.join(File.cwd!(), "var/cache")
    Path.join(dir, "construct_cache.dets")
  end

  defp current_version, do: {@schema_version, app_vsn()}

  defp app_vsn do
    case Application.spec(:girihelix, :vsn) do
      nil -> "unknown"
      vsn -> to_string(vsn)
    end
  end
end
