defmodule Girihelix.Engine.Tilings.Catalogue do
  @moduledoc """
  The shipped tiling catalogue: every `.tiling` file under `priv/tilings/`,
  indexed at compile time.

  The registry is keyed by tiling name — the name
  declared in the file's `tiling` header. This module holds it as a
  compile-time index: `priv/tilings/index.json` is decoded with
  `Jason.decode!/1` at compile time into `@entries`/`@names`, and recompiles
  whenever the index changes (`@external_resource`). Paths are relative to the
  project root: the index is read at compile time and the files are read at
  load time as `priv/tilings/<file>`.

  `load/1` reads the named tiling through the parser, sanitising included: the
  two legacy-encoded files (`Mughal.tiling` a cp1252 byte, `pbn_7.tiling` a
  MacRoman byte) come back with valid UTF-8 descriptions. An unknown name is
  `{:error, :unknown_tiling}`; `load!/1` raises `ArgumentError` for an unknown
  or unparsable tiling. `all/0` loads every name, keeping failures as error
  tuples so the exhibit can show a parse failure alongside the successes.
  """

  alias Girihelix.Engine.Tilings.Parser
  alias Girihelix.Engine.Tilings.Tiling

  @external_resource "priv/tilings/index.json"

  # Directory-relative names work from the project root only. A release's
  # working directory holds the release, not the app's priv/ tree (it lives
  # at <release>/lib/<app>-<version>/priv/), so reads resolve through
  # :code.priv_dir/1 — evaluated at RUNTIME: the same call written as a module
  # attribute freezes the builder's _build path into the beam inside a release
  # image, where that path does not exist. Dev/test resolve through Mix's priv
  # symlink; the compile-time index read stays relative because compilation
  # always happens from the project root.
  defp tilings_dir do
    :girihelix |> :code.priv_dir() |> :filename.join(~c"tilings") |> List.to_string()
  end

  @entries Jason.decode!(File.read!("priv/tilings/index.json"))
  @names Enum.map(@entries, & &1["name"])
  @name_options Enum.map(@names, &String.to_atom/1)

  @doc """
  Lists the catalogue names, in index (name) order.
  """
  @spec names() :: [String.t()]
  def names, do: @names

  @doc """
  Lists the catalogue names as atoms for the workbench enum.

  The names are trusted local catalogue data, so `String.to_atom/1` is safe:
  60 atoms like `:"4.5"` and `:"Mughal I'timad"`.
  """
  @spec name_options() :: [atom()]
  def name_options, do: @name_options

  @doc """
  Loads the tiling with the given name.

  Finds the file in the index, reads and parses it through
  `Girihelix.Engine.Tilings.Parser.parse_file/1`. A read failure passes the
  posix error through, so a missing file is distinguishable from a malformed
  one. An unknown name is `{:error, :unknown_tiling}`.
  """
  @spec load(String.t()) :: {:ok, Tiling.t()} | {:error, :unknown_tiling | term()}
  def load(name) do
    case entry(name) do
      %{"file" => file} -> Parser.parse_file(tilings_dir() <> "/" <> file)
      nil -> {:error, :unknown_tiling}
    end
  end

  @doc """
  Loads the tiling with the given name, raising on failure.

  Raises `ArgumentError` for an unknown or unparsable tiling; the message
  carries the name and the failure reason.
  """
  @spec load!(String.t()) :: Tiling.t()
  def load!(name) do
    case load(name) do
      {:ok, tiling} -> tiling
      {:error, reason} -> raise ArgumentError, message: reason_message(name, reason)
    end
  end

  @doc """
  Loads everything the catalogue holds: every name in the index, returning
  `{name, result}` pairs. Failures stay failures — kept as `{:error, term}`
  per name so the exhibit can show a parse failure instead of dropping it.
  """
  @spec all() :: [{String.t(), {:ok, Tiling.t()} | {:error, term()}}]
  def all, do: Enum.map(@names, &{&1, load(&1)})

  # The index entry for a name: the map with that name, or nil when unknown.
  defp entry(name) do
    Enum.find(@entries, &(&1["name"] == name))
  end

  # The load!/1 error message: unknown names say so plainly; parse failures
  # carry the reason in the message.
  defp reason_message(name, :unknown_tiling), do: "unknown tiling: #{inspect(name)}"
  defp reason_message(name, reason), do: "cannot load tiling #{inspect(name)}: #{inspect(reason)}"
end
