defmodule GirihelixWeb.Workbench.ConstructCacheTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias GirihelixWeb.Workbench.ConstructCache

  defp start_cache(opts \\ []) do
    name = :"cache_#{System.unique_integer([:positive])}"
    ets = :"cache_tab_#{System.unique_integer([:positive])}"
    start_supervised!({ConstructCache, [name: name, ets_name: ets] ++ opts})
    {name, ets}
  end

  defp tmp_dets_file do
    path =
      Path.join(System.tmp_dir!(), "construct_cache_#{System.unique_integer([:positive])}.dets")

    on_exit(fn -> File.rm(path) end)
    path
  end

  # Explicit timestamps keep the ordering assertions independent of the clock's
  # resolution on a fast machine.
  defp stamped(key, at, frames \\ nil) do
    %{ConstructCache.entry(key, frames || [key], nil, 2) | inserted_at: at, accessed_at: at}
  end

  test "a second fetch for one key does not build" do
    {cache, _ets} = start_cache()
    counter = :counters.new(1, [])

    build = fn ->
      :counters.add(counter, 1, 1)
      ConstructCache.entry(:k, [:frame], nil, 2)
    end

    assert ConstructCache.fetch(cache, :k, build).frames == [:frame]
    assert ConstructCache.fetch(cache, :k, build).frames == [:frame]
    assert :counters.get(counter, 1) == 1
  end

  test "the memory tier keeps four entries and evicts the least recently used" do
    {cache, ets} = start_cache()

    for {key, at} <- Enum.with_index([:a, :b, :c, :d, :e], 1) do
      ConstructCache.put(cache, key, stamped(key, at))
    end

    keys = ets |> :ets.tab2list() |> Enum.map(fn {_k, entry} -> entry.key end)
    assert length(keys) == 4
    refute :a in keys
    assert Enum.sort(keys) == [:b, :c, :d, :e]

    ConstructCache.get(cache, :b)
    ConstructCache.put(cache, :f, ConstructCache.entry(:f, [:f], nil, 2))
    keys = ets |> :ets.tab2list() |> Enum.map(fn {_k, entry} -> entry.key end)
    assert :b in keys
    refute :c in keys
    assert :f in keys
  end

  test "reset clears the memory tier" do
    {cache, _ets} = start_cache()
    ConstructCache.put(cache, :k, ConstructCache.entry(:k, [:k], nil, 2))
    assert ConstructCache.get(cache, :k)
    ConstructCache.reset(cache)
    refute ConstructCache.get(cache, :k)
  end

  test "a disk entry is promoted into memory without building" do
    path = tmp_dets_file()
    {cache, ets} = start_cache(disk?: true, dets_file: path, disk_bytes: 1_000)
    counter = :counters.new(1, [])

    :ok = ConstructCache.put(cache, :k, ConstructCache.entry(:k, [:frame], nil, 2))
    :ok = ConstructCache.reset(cache)
    assert :ets.lookup(ets, :k) == []

    build = fn ->
      :counters.add(counter, 1, 1)
      ConstructCache.entry(:k, [:rebuilt], nil, 2)
    end

    assert ConstructCache.fetch(cache, :k, build).frames == [:frame]
    assert :counters.get(counter, 1) == 0
    assert [{:k, entry}] = :ets.lookup(ets, :k)
    assert entry.frames == [:frame]
  end

  test "the disk tier evicts the oldest inserted entries beyond the cap" do
    path = tmp_dets_file()
    a = stamped(:a, 1, [String.duplicate("a", 100)])
    b = stamped(:b, 2, [String.duplicate("b", 100)])
    c = stamped(:c, 3, [String.duplicate("c", 100)])
    cap = a.size + b.size + c.size

    {cache, _ets} = start_cache(disk?: true, dets_file: path, disk_bytes: cap)
    for entry <- [a, b, c], do: ConstructCache.put(cache, entry.key, entry)

    # Touch the oldest so that recency and insertion order disagree: disk
    # eviction must follow `:inserted_at`.
    ConstructCache.get(cache, :a)

    d = stamped(:d, 4, [String.duplicate("d", 100)])
    :ok = ConstructCache.put(cache, :d, d)
    ConstructCache.reset(cache)

    refute ConstructCache.get(cache, :a)
    for key <- [:b, :c, :d], do: assert(ConstructCache.get(cache, key))
  end

  test "an entry larger than the disk cap is served from memory only" do
    path = tmp_dets_file()
    {cache, _ets} = start_cache(disk?: true, dets_file: path, disk_bytes: 20)
    big = ConstructCache.entry(:big, [String.duplicate("x", 100)], nil, 2)
    assert big.size > 20

    :ok = ConstructCache.put(cache, :big, big)
    assert ConstructCache.get(cache, :big).frames == big.frames

    ConstructCache.reset(cache)
    refute ConstructCache.get(cache, :big)

    # An oversized replacement also removes a smaller copy already on disk.
    small = ConstructCache.entry(:big, [String.duplicate("s", 5)], nil, 2)
    assert small.size <= 20
    ConstructCache.put(cache, :big, small)
    ConstructCache.put(cache, :big, big)
    assert ConstructCache.get(cache, :big).frames == big.frames

    ConstructCache.reset(cache)
    refute ConstructCache.get(cache, :big)
  end

  test "clear_disk empties the disk tier and leaves it usable" do
    path = tmp_dets_file()
    {cache, _ets} = start_cache(disk?: true, dets_file: path, disk_bytes: 1_000)

    :ok = ConstructCache.put(cache, :k, ConstructCache.entry(:k, [:frame], nil, 2))
    ConstructCache.reset(cache)
    assert ConstructCache.get(cache, :k).frames == [:frame]

    :ok = ConstructCache.clear_disk(cache)
    ConstructCache.reset(cache)
    refute ConstructCache.get(cache, :k)

    :ok = ConstructCache.put(cache, :next, ConstructCache.entry(:next, [:next], nil, 2))
    ConstructCache.reset(cache)
    assert ConstructCache.get(cache, :next).frames == [:next]
  end

  test "a mismatched version clears the disk tier on start" do
    path = tmp_dets_file()
    writer = :"writer_#{System.unique_integer([:positive])}"
    {:ok, writer} = :dets.open_file(writer, file: String.to_charlist(path), type: :set)
    :ok = :dets.insert(writer, {:__version__, {:stale_schema, "0.0.0"}})
    :ok = :dets.insert(writer, {:stale, ConstructCache.entry(:stale, [:old], nil, 2)})
    :ok = :dets.close(writer)

    {cache, _ets} = start_cache(disk?: true, dets_file: path)
    refute ConstructCache.get(cache, :stale)
    :ok = stop_supervised(ConstructCache)

    reader = :"reader_#{System.unique_integer([:positive])}"
    {:ok, reader} = :dets.open_file(reader, file: String.to_charlist(path), type: :set)
    objects = :dets.foldl(fn object, acc -> [object | acc] end, [], reader)
    :ok = :dets.close(reader)

    assert [{:__version__, version}] = objects
    refute version == {:stale_schema, "0.0.0"}
  end

  test "an existing file with a matching version is indexed at boot" do
    path = tmp_dets_file()
    {cache, _ets} = start_cache(disk?: true, dets_file: path, disk_bytes: 1_000)
    :ok = ConstructCache.put(cache, :k, ConstructCache.entry(:k, [:frame], nil, 2))
    :ok = stop_supervised(ConstructCache)

    # A malformed object in a version-matching file must be dropped at boot,
    # not crash the indexing pass.
    writer = :"writer_#{System.unique_integer([:positive])}"
    {:ok, writer} = :dets.open_file(writer, file: String.to_charlist(path), type: :set)
    :ok = :dets.insert(writer, {:malformed, :not_an_entry})
    :ok = :dets.close(writer)

    {cache, _ets} = start_cache(disk?: true, dets_file: path, disk_bytes: 1_000)
    assert ConstructCache.get(cache, :k).frames == [:frame]
    :ok = stop_supervised(ConstructCache)

    reader = :"reader_#{System.unique_integer([:positive])}"
    {:ok, reader} = :dets.open_file(reader, file: String.to_charlist(path), type: :set)
    keys = :dets.foldl(fn {key, _}, acc -> [key | acc] end, [], reader)
    :ok = :dets.close(reader)

    refute :malformed in keys
    assert :__version__ in keys
  end

  test "a corrupt DETS file is deleted and the tier recovers" do
    path = tmp_dets_file()
    File.write!(path, "this is not a dets file")

    {result, log} =
      with_log(fn ->
        start_cache(disk?: true, dets_file: path, disk_bytes: 1_000)
      end)

    {cache, _ets} = result
    assert log =~ "construction cache"

    ConstructCache.put(cache, :k, ConstructCache.entry(:k, [:frame], nil, 2))
    ConstructCache.reset(cache)
    assert ConstructCache.get(cache, :k).frames == [:frame]
  end

  test "two concurrent first fetches build once" do
    {cache, _ets} = start_cache()
    counter = :counters.new(1, [])
    parent = self()

    build = fn ->
      :counters.add(counter, 1, 1)
      send(parent, :built)
      Process.sleep(100)
      ConstructCache.entry(:k, [:frame], nil, 2)
    end

    results =
      [build, build]
      |> Enum.map(fn fun -> Task.async(fn -> ConstructCache.fetch(cache, :k, fun) end) end)
      |> Enum.map(&Task.await/1)

    assert :counters.get(counter, 1) == 1
    assert Enum.map(results, & &1.frames) == [[:frame], [:frame]]
  end

  test "disk?: false keeps the tier working and creates no file" do
    path = tmp_dets_file()
    {cache, _ets} = start_cache(disk?: false, dets_file: path)

    ConstructCache.put(cache, :k, ConstructCache.entry(:k, [:frame], nil, 2))
    assert ConstructCache.get(cache, :k).frames == [:frame]

    ConstructCache.reset(cache)
    refute ConstructCache.get(cache, :k)
    refute File.exists?(path)
  end
end
