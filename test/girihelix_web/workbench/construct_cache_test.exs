defmodule GirihelixWeb.Workbench.ConstructCacheTest do
  use ExUnit.Case, async: true

  alias GirihelixWeb.Workbench.ConstructCache

  defp start_cache(opts \\ []) do
    name = :"cache_#{System.unique_integer([:positive])}"
    ets = :"cache_tab_#{System.unique_integer([:positive])}"
    start_supervised!({ConstructCache, [name: name, ets_name: ets] ++ opts})
    {name, ets}
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

    for key <- [:a, :b, :c, :d, :e] do
      ConstructCache.put(cache, key, ConstructCache.entry(key, [key], nil, 2))
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

  test "reset clears the tier" do
    {cache, _ets} = start_cache()
    ConstructCache.put(cache, :k, ConstructCache.entry(:k, [:k], nil, 2))
    assert ConstructCache.get(cache, :k)
    ConstructCache.reset(cache)
    refute ConstructCache.get(cache, :k)
  end
end
