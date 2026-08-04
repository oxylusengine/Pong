local Config = {
  PLAYER_1_ID = 0,
  PLAYER_2_ID = 1,

  PLAYER_SPEED = 10,

  -- BALL
  BALL_SPEED = 9,

  -- NETWORK
  NET = {
    DEFAULT_IP = "127.0.0.1",
    DEFAULT_PORT = 4242,
    -- Pong is 1v1, the host is a player rather than a dedicated server.
    MAX_CLIENTS = 1,
    CONNECT_TIMEOUT_MS = 5000,
    TICK_RATE = 30,
  },
}

return Config
