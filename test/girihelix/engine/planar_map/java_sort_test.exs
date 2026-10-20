defmodule Girihelix.Engine.PlanarMap.JavaSortTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.PlanarMap.JavaSort
  alias Girihelix.Engine.PlanarMap.Order

  defp compare(a, b) when a < b, do: :lt
  defp compare(a, b) when a > b, do: :gt
  defp compare(_a, _b), do: :eq

  # Equal within a window of 2: not transitive, like Taprats' 1e-7 window.
  defp windowed(a, b) when abs(a - b) < 2, do: :eq
  defp windowed(a, b) when a < b, do: :lt
  defp windowed(_a, _b), do: :gt

  defp shuffled(n), do: Enum.map(0..(n - 1)//1, &{rem(&1 * 7919, 13), &1})

  for n <- [0, 1, 2, 31, 32, 33, 64, 1000] do
    test "sorts #{n} tagged integers stably" do
      list = shuffled(unquote(n))

      assert JavaSort.sort(list, &elem(&1, 0), &compare/2) ==
               {:ok, Enum.sort_by(list, &elem(&1, 0))}
    end
  end

  test "sorts 1000 distinct integers in random order" do
    list = Enum.shuffle(1..1000)

    assert JavaSort.sort(list, & &1, &compare/2) == {:ok, Enum.to_list(1..1000)}
  end

  test "sorts long ascending, descending and sawtooth inputs" do
    sawtooth = Enum.flat_map(1..40, fn _ -> Enum.to_list(1..25) end)

    assert JavaSort.sort(Enum.to_list(1..500), & &1, &compare/2) == {:ok, Enum.to_list(1..500)}

    assert JavaSort.sort(Enum.to_list(500..1//-1), & &1, &compare/2) ==
             {:ok, Enum.to_list(1..500)}

    assert JavaSort.sort(sawtooth, & &1, &compare/2) == {:ok, Enum.sort(sawtooth)}
  end

  test "a strictly descending run of 31 comes out reversed" do
    assert JavaSort.sort(Enum.to_list(31..1//-1), & &1, &compare/2) == {:ok, Enum.to_list(1..31)}
  end

  # Derivation, with `windowed/2` (equal when less than 2 apart):
  #
  # 1. The run: 0 is less than 3, so the run is strictly descending. Then 5 is
  #    not less than 0, so the run stops at [3, 0] and is reversed: [0, 3].
  # 2. Pivot 5, slots 0..2: mid 1 holds 3, and 5 is not less than 3 (2 apart),
  #    so go right. Insert at 2: [0, 3, 5].
  # 3. Pivot 1.5, slots 0..3: mid 1 holds 3, and 1.5 equals 3, so go right;
  #    mid 2 holds 5, and 1.5 is less than 5, so go left. Insert at 2:
  #    [0, 3, 1.5, 5]. The pivot never meets 0, which it also equals.
  test "a non-transitive comparator gives Java's binary-insertion order" do
    assert JavaSort.sort([3, 0, 5, 1.5], & &1, &windowed/2) == {:ok, [0, 3, 1.5, 5]}
  end

  # These 32 keys, on a 1e-8 grid, made Java 21's `Collections.sort` throw
  # "Comparison method violates its general contract!" under the edge
  # comparator: a merge ran one side dry. Taprats would crash there; the port
  # reports it.
  @contract_keys Enum.map(
                   [45, 46, 51, 17, 12, 17, 43, 2, 52, 37, 31, 32, 10, 31, 45, 18] ++
                     [56, 4, 35, 39, 49, 60, 56, 32, 43, 42, 17, 54, 30, 3, 8, 46],
                   &(&1 * 1.0e-8)
                 )

  test "reports an inconsistent order where Java's merge detects the broken contract" do
    assert JavaSort.sort(@contract_keys, & &1, &Order.compare_min_x/2) ==
             {:error, :inconsistent_order}
  end

  test "sort!/3 raises there, naming the reason" do
    assert_raise ArgumentError, ~r/inconsistent_order/, fn ->
      JavaSort.sort!(@contract_keys, & &1, &Order.compare_min_x/2)
    end
  end

  test "keys are compared through the key function" do
    assert JavaSort.sort([%{k: 2}, %{k: 1}], & &1.k, &compare/2) == {:ok, [%{k: 1}, %{k: 2}]}
  end
end
