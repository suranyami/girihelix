defmodule Girihelix.Engine.Tilings.PlacedFeature do
  @moduledoc """
  A tile placed into the tiling's plane: which feature it is, and the transform
  carrying it there.

  `feature_id` indexes the tiling's feature list; `transform` is the
  affine transform whose exact six-double value identifies this placement. Where
  tolerance
  belongs it lives in `Feature.equal?/2`, which compares two features' point
  lists under `Loose.equals/2`; the transform here is part of the placement's
  identity, so equality for this struct is structural, exact — the six doubles
  must match — and carries no tolerance.
  """

  alias Girihelix.Engine.Geometry.Transform

  @enforce_keys [:feature_id, :transform]
  defstruct [:feature_id, :transform]

  @type t :: %__MODULE__{feature_id: integer(), transform: Transform.t()}

  @doc "Builds a placed feature."
  @spec new(integer(), Transform.t()) :: t()
  def new(feature_id, transform), do: %__MODULE__{feature_id: feature_id, transform: transform}
end
