[
  import_deps: [:ash_phoenix, :reactor, :ecto, :ecto_sql, :phoenix, :ash, :ash_postgres],
  subdirectories: ["priv/*/migrations"],
  plugins: [Spark.Formatter, Phoenix.LiveView.HTMLFormatter, Styler],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}", "priv/*/seeds.exs"]
]
