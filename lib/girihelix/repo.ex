defmodule Girihelix.Repo do
  use AshPostgres.Repo,
    otp_app: :girihelix

  @impl true
  def installed_extensions do
    # Add extensions here, and the migration generator will install them.
    ["ash-functions"]
  end

  # Don't open unnecessary transactions
  # will default to `false` in 4.0
  @impl true
  def prefer_transaction? do
    false
  end

  # The LOWEST PostgreSQL this application supports, not the version this machine
  # happens to be running. Igniter derives its initial value from the local
  # `postgres -V`, which is why it is set by hand here: pinning the floor to 17.10
  # would refuse to start against any older server for no reason.
  @impl true
  def min_pg_version do
    %Version{major: 14, minor: 0, patch: 0}
  end
end
