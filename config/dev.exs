import Config

config :logger, :console,
  format: "$time $metadata[$level] $message\n"
config :logger, backends: [{SlackLoggerBackend.Logger, :error}, :console]
