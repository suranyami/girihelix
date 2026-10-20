defmodule Girihelix.Engine.PlanarMap.JavaSort do
  @moduledoc """
  Java's list sort, as Taprats runs it under `Collections.sort` with a
  comparator: TimSort, rebuilt here comparison for comparison.

  The planar map's comparators treat differences under `1.0e-7` as none, so
  they are not transitive, and the sorted order then depends on exactly which
  pairs get compared, in which order. Any other stable sort can give a
  different order. This module makes the same comparisons, in the same order,
  with the same outcomes as Java, so it returns Java's order for any
  comparator, consistent or not.

  The algorithm follows Tim Peters' design notes (`listsort.txt`) with Java's
  parameters:

  - Below 32 elements, one natural run is found from the start (a strictly
    descending run is reversed), and binary insertion sorts the rest.
  - From 32 elements, natural runs are padded by binary insertion to a minimum
    length computed from the size, pushed on a stack and merged under the
    corrected stack invariant that also checks the fourth run from the top
    (de Gouw et al., 2015). Each merge trims both ends by galloping, then merges
    from whichever end has the shorter run, switching into galloping mode
    after 7 consecutive wins, a threshold that adapts across the whole sort.

  Java throws "Comparison method violates its general contract!" when a merge
  runs one side dry where a consistent comparator could not. Taprats crashes
  there. This module stops at the same point and reports
  `{:error, :inconsistent_order}` instead; `sort!/3` raises it.
  """

  import Bitwise

  @min_merge 32
  @min_gallop 7

  @type comparison :: :lt | :eq | :gt

  @doc """
  Sorts `list` by `key_fun` under `compare`, exactly as Java's list sort would.

  Returns `{:error, :inconsistent_order}` where Java would throw because the
  comparator broke its contract.
  """
  @spec sort([a], (a -> key), (key, key -> comparison())) ::
          {:ok, [a]} | {:error, :inconsistent_order}
        when a: term(), key: term()
  def sort(list, key_fun, compare), do: sort_list(list, length(list), key_fun, compare)

  @doc "As `sort/3`, but returns the bare list and raises `ArgumentError` naming the reason."
  @spec sort!([a], (a -> key), (key, key -> comparison())) :: [a] when a: term(), key: term()
  def sort!(list, key_fun, compare), do: list |> sort(key_fun, compare) |> unwrap!()

  defp unwrap!({:ok, sorted}), do: sorted
  defp unwrap!({:error, reason}), do: raise(ArgumentError, "java sort: #{reason}")

  defp sort_list(list, n, _key_fun, _compare) when n < 2, do: {:ok, list}

  defp sort_list(list, n, key_fun, compare) do
    state = %{
      a: list |> Enum.map(&{key_fun.(&1), &1}) |> :array.from_list(),
      c: fn {ka, _}, {kb, _} -> compare.(ka, kb) end,
      mg: @min_gallop,
      runs: [],
      failure: nil
    }

    state |> sort_array(n) |> outcome()
  end

  defp outcome(%{failure: nil, a: sorted}), do: {:ok, sorted |> :array.to_list() |> Enum.map(&elem(&1, 1))}

  defp outcome(%{failure: reason}), do: {:error, reason}

  defp sort_array(state, n) when n < @min_merge do
    {state, run_len} = count_run(state, 0, n)
    binary_sort(state, 0, n, run_len)
  end

  defp sort_array(state, n), do: state |> collect_runs(0, n, min_run(n, 0)) |> force_collapse()

  # -- Natural runs and binary insertion

  defp count_run(state, lo, hi) when lo + 1 == hi, do: {state, 1}

  defp count_run(%{a: a, c: c} = state, lo, hi), do: run_direction(c.(at(a, lo + 1), at(a, lo)), state, lo, hi)

  defp run_direction(:lt, %{a: a} = state, lo, hi) do
    run_hi = extend_run(state, lo + 2, hi, :descending)
    {%{state | a: write(a, lo, a |> slice(lo, run_hi - lo) |> Enum.reverse())}, run_hi - lo}
  end

  defp run_direction(_not_lt, state, lo, hi), do: {state, extend_run(state, lo + 2, hi, :ascending) - lo}

  defp extend_run(_state, i, hi, _direction) when i >= hi, do: i

  defp extend_run(%{a: a, c: c} = state, i, hi, direction),
    do: continue_run(direction, c.(at(a, i), at(a, i - 1)), state, i, hi)

  defp continue_run(:descending, :lt, state, i, hi), do: extend_run(state, i + 1, hi, :descending)

  defp continue_run(:ascending, result, state, i, hi) when result != :lt, do: extend_run(state, i + 1, hi, :ascending)

  defp continue_run(_direction, _result, _state, i, _hi), do: i

  defp binary_sort(state, lo, hi, lo), do: binary_sort(state, lo, hi, lo + 1)
  defp binary_sort(state, _lo, hi, start) when start >= hi, do: state

  defp binary_sort(%{a: a} = state, lo, hi, start) do
    pivot = at(a, start)
    left = insertion_slot(state, pivot, lo, start)

    binary_sort(
      %{state | a: write(a, left, [pivot | slice(a, left, start - left)])},
      lo,
      hi,
      start + 1
    )
  end

  defp insertion_slot(%{a: a, c: c} = state, pivot, left, right) when left < right do
    mid = (left + right) >>> 1
    slot_step(c.(pivot, at(a, mid)), state, pivot, left, right, mid)
  end

  defp insertion_slot(_state, _pivot, left, _right), do: left

  defp slot_step(:lt, state, pivot, left, _right, mid), do: insertion_slot(state, pivot, left, mid)

  defp slot_step(_not_lt, state, pivot, _left, right, mid), do: insertion_slot(state, pivot, mid + 1, right)

  # -- The run stack

  defp min_run(n, r) when n >= @min_merge, do: min_run(n >>> 1, r ||| (n &&& 1))
  defp min_run(n, r), do: n + r

  # A failed merge stops the sort where Java would throw.
  defp collect_runs(%{failure: :inconsistent_order} = state, _lo, _remaining, _min_run), do: state
  defp collect_runs(state, _lo, 0, _min_run), do: state

  defp collect_runs(state, lo, remaining, min_run) do
    {state, run_len} = count_run(state, lo, lo + remaining)
    {state, run_len} = pad_run(state, lo, run_len, min_run, min(remaining, min_run))
    state = merge_collapse(%{state | runs: [{lo, run_len} | state.runs]})
    collect_runs(state, lo + run_len, remaining - run_len, min_run)
  end

  defp pad_run(state, lo, run_len, min_run, force) when run_len < min_run,
    do: {binary_sort(state, lo, lo + force, lo + run_len), force}

  defp pad_run(state, _lo, run_len, _min_run, _force), do: {state, run_len}

  # The stack is held top first: the newest run, then the one below it.
  defp merge_collapse(%{failure: :inconsistent_order} = state), do: state
  defp merge_collapse(%{runs: runs} = state), do: collapse(collapse_choice(runs), state)

  defp collapse(:none, state), do: state
  defp collapse(pair, state), do: state |> merge_at(pair) |> merge_collapse()

  defp collapse_choice([{_, top}, {_, next}, {_, third}, {_, fourth} | _])
       when third <= next + top or fourth <= third + next, do: deeper_pair(third, top)

  defp collapse_choice([{_, top}, {_, next}, {_, third} | _]) when third <= next + top, do: deeper_pair(third, top)

  defp collapse_choice([{_, top}, {_, next} | _]) when next <= top, do: :top
  defp collapse_choice(_runs), do: :none

  defp deeper_pair(third, top) when third < top, do: :below
  defp deeper_pair(_third, _top), do: :top

  defp force_collapse(%{failure: :inconsistent_order} = state), do: state
  defp force_collapse(%{runs: runs} = state), do: force(force_choice(runs), state)

  defp force(:none, state), do: state
  defp force(pair, state), do: state |> merge_at(pair) |> force_collapse()

  defp force_choice([{_, top}, _, {_, third} | _]) when third < top, do: :below
  defp force_choice([_, _ | _]), do: :top
  defp force_choice(_runs), do: :none

  defp merge_at(%{runs: [run2, run1 | rest]} = state, :top),
    do: merge_runs(%{state | runs: [joined(run1, run2) | rest]}, run1, run2)

  defp merge_at(%{runs: [top, run2, run1 | rest]} = state, :below),
    do: merge_runs(%{state | runs: [top, joined(run1, run2) | rest]}, run1, run2)

  defp joined({base1, len1}, {_base2, len2}), do: {base1, len1 + len2}

  # -- Merging two adjacent runs

  defp merge_runs(%{a: a, c: c} = state, {base1, len1}, {base2, len2}) do
    k = gallop(:right, c, at(a, base2), a, base1, len1, 0)
    trim_tail(state, base1 + k, len1 - k, base2, len2)
  end

  defp trim_tail(state, _base1, 0, _base2, _len2), do: state

  defp trim_tail(%{a: a, c: c} = state, base1, len1, base2, len2),
    do: merge_trimmed(state, base1, len1, base2, gallop(:left, c, at(a, base1 + len1 - 1), a, base2, len2, len2 - 1))

  defp merge_trimmed(state, _base1, _len1, _base2, 0), do: state

  defp merge_trimmed(state, base1, len1, base2, len2) when len1 <= len2, do: merge_lo(state, base1, len1, base2, len2)

  defp merge_trimmed(state, base1, len1, base2, len2), do: merge_hi(state, base1, len1, base2, len2)

  # -- Merging from the low end: the first run is copied out to `tmp`

  defp merge_lo(%{a: a} = state, base1, len1, base2, len2) do
    m = %{
      a: put(a, base1, at(a, base2)),
      tmp: :array.from_list(slice(a, base1, len1)),
      c: state.c,
      c1: 0,
      c2: base2 + 1,
      dest: base1 + 1,
      len1: len1,
      len2: len2 - 1,
      mg: state.mg
    }

    lo_start(m, state)
  end

  defp lo_start(%{len2: 0} = m, state), do: %{state | a: copy(m.a, m.dest, m.tmp, m.c1, m.len1)}
  defp lo_start(%{len1: 1} = m, state), do: %{state | a: lo_last(m)}
  defp lo_start(m, state), do: m |> lo_linear(0, 0) |> lo_finish(state)

  defp lo_last(m), do: m.a |> copy(m.dest, m.a, m.c2, m.len2) |> put(m.dest + m.len2, at(m.tmp, m.c1))

  defp lo_linear(%{a: a, tmp: tmp, c: c} = m, count1, count2),
    do: lo_pick(c.(at(a, m.c2), at(tmp, m.c1)), m, count1, count2)

  defp lo_pick(:lt, m, _count1, count2), do: lo_linear_next(lo_take_run2(m), 0, count2 + 1)
  defp lo_pick(_not_lt, m, count1, _count2), do: lo_linear_next(lo_take_tmp(m), count1 + 1, 0)

  defp lo_linear_next(%{len2: 0} = m, _count1, _count2), do: m
  defp lo_linear_next(%{len1: 1} = m, _count1, _count2), do: m

  defp lo_linear_next(%{mg: mg} = m, count1, count2) when count1 < mg and count2 < mg, do: lo_linear(m, count1, count2)

  defp lo_linear_next(m, _count1, _count2), do: lo_gallop(m)

  defp lo_gallop(%{a: a, tmp: tmp, c: c} = m) do
    count1 = gallop(:right, c, at(a, m.c2), tmp, m.c1, m.len1, 0)

    m = %{
      m
      | a: copy(a, m.dest, tmp, m.c1, count1),
        dest: m.dest + count1,
        c1: m.c1 + count1,
        len1: m.len1 - count1
    }

    lo_gallop_run2(m, count1)
  end

  defp lo_gallop_run2(%{len1: len1} = m, _count1) when len1 <= 1, do: m
  defp lo_gallop_run2(m, count1), do: lo_gallop_tmp(lo_take_run2(m), count1)

  defp lo_gallop_tmp(%{len2: 0} = m, _count1), do: m

  defp lo_gallop_tmp(%{a: a, c: c} = m, count1) do
    count2 = gallop(:left, c, at(m.tmp, m.c1), a, m.c2, m.len2, 0)

    m = %{
      m
      | a: copy(a, m.dest, a, m.c2, count2),
        dest: m.dest + count2,
        c2: m.c2 + count2,
        len2: m.len2 - count2
    }

    lo_gallop_last(m, count1, count2)
  end

  defp lo_gallop_last(%{len2: 0} = m, _count1, _count2), do: m
  defp lo_gallop_last(m, count1, count2), do: lo_gallop_next(lo_take_tmp(m), count1, count2)

  defp lo_gallop_next(%{len1: 1} = m, _count1, _count2), do: m

  defp lo_gallop_next(m, count1, count2) when count1 >= @min_gallop or count2 >= @min_gallop,
    do: lo_gallop(%{m | mg: m.mg - 1})

  defp lo_gallop_next(m, _count1, _count2), do: lo_linear(%{m | mg: max(m.mg - 1, 0) + 2}, 0, 0)

  defp lo_take_run2(m), do: %{m | a: put(m.a, m.dest, at(m.a, m.c2)), dest: m.dest + 1, c2: m.c2 + 1, len2: m.len2 - 1}

  defp lo_take_tmp(m), do: %{m | a: put(m.a, m.dest, at(m.tmp, m.c1)), dest: m.dest + 1, c1: m.c1 + 1, len1: m.len1 - 1}

  defp lo_finish(m, state), do: lo_tail(m, %{state | mg: max(m.mg, 1)})

  defp lo_tail(%{len1: 1} = m, state), do: %{state | a: lo_last(m)}
  defp lo_tail(%{len1: 0}, state), do: %{state | failure: :inconsistent_order}
  defp lo_tail(m, state), do: %{state | a: copy(m.a, m.dest, m.tmp, m.c1, m.len1)}

  # -- Merging from the high end: the second run is copied out to `tmp`

  defp merge_hi(%{a: a} = state, base1, len1, base2, len2) do
    dest = base2 + len2 - 1
    c1 = base1 + len1 - 1

    m = %{
      a: put(a, dest, at(a, c1)),
      tmp: :array.from_list(slice(a, base2, len2)),
      c: state.c,
      base1: base1,
      c1: c1 - 1,
      c2: len2 - 1,
      dest: dest - 1,
      len1: len1 - 1,
      len2: len2,
      mg: state.mg
    }

    hi_start(m, state)
  end

  defp hi_start(%{len1: 0} = m, state), do: %{state | a: hi_rest(m)}
  defp hi_start(%{len2: 1} = m, state), do: %{state | a: hi_last(m)}
  defp hi_start(m, state), do: m |> hi_linear(0, 0) |> hi_finish(state)

  defp hi_rest(m), do: copy(m.a, m.dest - (m.len2 - 1), m.tmp, 0, m.len2)

  defp hi_last(m) do
    dest = m.dest - m.len1
    m.a |> copy(dest + 1, m.a, m.c1 - m.len1 + 1, m.len1) |> put(dest, at(m.tmp, m.c2))
  end

  defp hi_linear(%{a: a, tmp: tmp, c: c} = m, count1, count2),
    do: hi_pick(c.(at(tmp, m.c2), at(a, m.c1)), m, count1, count2)

  defp hi_pick(:lt, m, count1, _count2), do: hi_linear_next(hi_take_run1(m), count1 + 1, 0)
  defp hi_pick(_not_lt, m, _count1, count2), do: hi_linear_next(hi_take_tmp(m), 0, count2 + 1)

  defp hi_linear_next(%{len1: 0} = m, _count1, _count2), do: m
  defp hi_linear_next(%{len2: 1} = m, _count1, _count2), do: m

  defp hi_linear_next(%{mg: mg} = m, count1, count2) when count1 < mg and count2 < mg, do: hi_linear(m, count1, count2)

  defp hi_linear_next(m, _count1, _count2), do: hi_gallop(m)

  defp hi_gallop(%{a: a, c: c} = m) do
    count1 = m.len1 - gallop(:right, c, at(m.tmp, m.c2), a, m.base1, m.len1, m.len1 - 1)
    dest = m.dest - count1
    c1 = m.c1 - count1
    m = %{m | a: copy(a, dest + 1, a, c1 + 1, count1), dest: dest, c1: c1, len1: m.len1 - count1}
    hi_gallop_tmp(m, count1)
  end

  defp hi_gallop_tmp(%{len1: 0} = m, _count1), do: m
  defp hi_gallop_tmp(m, count1), do: hi_gallop_run1(hi_take_tmp(m), count1)

  defp hi_gallop_run1(%{len2: 1} = m, _count1), do: m

  defp hi_gallop_run1(%{a: a, tmp: tmp, c: c} = m, count1) do
    count2 = m.len2 - gallop(:left, c, at(a, m.c1), tmp, 0, m.len2, m.len2 - 1)
    dest = m.dest - count2
    c2 = m.c2 - count2

    m = %{
      m
      | a: copy(a, dest + 1, tmp, c2 + 1, count2),
        dest: dest,
        c2: c2,
        len2: m.len2 - count2
    }

    hi_gallop_last(m, count1, count2)
  end

  defp hi_gallop_last(%{len2: len2} = m, _count1, _count2) when len2 <= 1, do: m
  defp hi_gallop_last(m, count1, count2), do: hi_gallop_next(hi_take_run1(m), count1, count2)

  defp hi_gallop_next(%{len1: 0} = m, _count1, _count2), do: m

  defp hi_gallop_next(m, count1, count2) when count1 >= @min_gallop or count2 >= @min_gallop,
    do: hi_gallop(%{m | mg: m.mg - 1})

  defp hi_gallop_next(m, _count1, _count2), do: hi_linear(%{m | mg: max(m.mg - 1, 0) + 2}, 0, 0)

  defp hi_take_run1(m), do: %{m | a: put(m.a, m.dest, at(m.a, m.c1)), dest: m.dest - 1, c1: m.c1 - 1, len1: m.len1 - 1}

  defp hi_take_tmp(m), do: %{m | a: put(m.a, m.dest, at(m.tmp, m.c2)), dest: m.dest - 1, c2: m.c2 - 1, len2: m.len2 - 1}

  defp hi_finish(m, state), do: hi_tail(m, %{state | mg: max(m.mg, 1)})

  defp hi_tail(%{len2: 1} = m, state), do: %{state | a: hi_last(m)}
  defp hi_tail(%{len2: 0}, state), do: %{state | failure: :inconsistent_order}
  defp hi_tail(m, state), do: %{state | a: hi_rest(m)}

  # -- Galloping: an exponential search from `hint`, then a binary search
  #
  # `:left` finds the first slot whose element `key` is not greater than; `:right`
  # finds the first slot whose element `key` is less than.

  defp gallop(mode, c, key, arr, base, len, hint) do
    search = {mode, c, key, arr, base}
    gallop_from(probe(search, hint), search, len, hint)
  end

  defp gallop_from(true, search, len, hint) do
    {last, ofs} = gallop_up(search, hint, len - hint, 0, 1)
    narrow(search, last + hint + 1, ofs + hint)
  end

  defp gallop_from(false, search, _len, hint) do
    {last, ofs} = gallop_down(search, hint, hint + 1, 0, 1)
    narrow(search, hint - ofs + 1, hint - last)
  end

  defp gallop_up(search, hint, max_ofs, last, ofs) when ofs < max_ofs,
    do: up_step(probe(search, hint + ofs), search, hint, max_ofs, last, ofs)

  defp gallop_up(_search, _hint, max_ofs, last, ofs), do: {last, min(ofs, max_ofs)}

  defp up_step(true, search, hint, max_ofs, _last, ofs), do: gallop_up(search, hint, max_ofs, ofs, ofs * 2 + 1)

  defp up_step(false, _search, _hint, max_ofs, last, ofs), do: {last, min(ofs, max_ofs)}

  defp gallop_down(search, hint, max_ofs, last, ofs) when ofs < max_ofs,
    do: down_step(probe(search, hint - ofs), search, hint, max_ofs, last, ofs)

  defp gallop_down(_search, _hint, max_ofs, last, ofs), do: {last, min(ofs, max_ofs)}

  defp down_step(false, search, hint, max_ofs, _last, ofs), do: gallop_down(search, hint, max_ofs, ofs, ofs * 2 + 1)

  defp down_step(true, _search, _hint, max_ofs, last, ofs), do: {last, min(ofs, max_ofs)}

  defp narrow(search, last, ofs) when last < ofs do
    m = last + ((ofs - last) >>> 1)
    narrow_step(probe(search, m), search, last, ofs, m)
  end

  defp narrow(_search, _last, ofs), do: ofs

  defp narrow_step(true, search, _last, ofs, m), do: narrow(search, m + 1, ofs)
  defp narrow_step(false, search, last, _ofs, m), do: narrow(search, last, m)

  # Whether `key` lies beyond the element at offset `i`.
  defp probe({mode, c, key, arr, base}, i), do: beyond?(mode, c.(key, at(arr, base + i)))

  defp beyond?(:left, :gt), do: true
  defp beyond?(:left, _not_gt), do: false
  defp beyond?(:right, :lt), do: false
  defp beyond?(:right, _not_lt), do: true

  # -- The working buffer

  defp at(arr, i), do: :array.get(i, arr)
  defp put(arr, i, value), do: :array.set(i, value, arr)

  defp slice(arr, from, count), do: Enum.map(from..(from + count - 1)//1, &at(arr, &1))

  defp write(arr, from, values),
    do: values |> Enum.with_index(from) |> Enum.reduce(arr, fn {value, i}, acc -> put(acc, i, value) end)

  defp copy(dst, dst_from, src, src_from, count), do: write(dst, dst_from, slice(src, src_from, count))
end
