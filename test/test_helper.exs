# Golden tests compare against fixtures produced by the local-only Taprats
# reference harness (reference/oracle/). Without them, those tests are skipped.
ExUnit.configure(exclude: Enum.reject([:taprats], fn _ -> File.dir?("reference/oracle/fixtures") end))

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Girihelix.Repo, :manual)
