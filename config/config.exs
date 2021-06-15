import Config
config :logger, backends: [RingLogger]

config :logger, RingLogger, max_size: 50_000

config :logger,
  level: :debug

config :ring_logger,
  format: "$time $metadata[$level] $levelpad$message\n",
  level: :debug,
  metadata: []
