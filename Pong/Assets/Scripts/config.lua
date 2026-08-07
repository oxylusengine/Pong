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
    -- How hard the opponent's paddle chases its interpolated target. Gain is per second, the clamp
    -- keeps a late packet from turning the catch-up into a dash.
    PADDLE_FOLLOW_GAIN = 12,
    PADDLE_FOLLOW_SPEED_SCALE = 2,
    -- How far past the send interval we stretch playback of a pair of paddle reports, so ordinary
    -- arrival jitter lands the next one before we run out of segment.
    PADDLE_INTERP_STRETCH = 1.25,
    -- How hard the client steers the ball back onto the host's snapshot, and the error past which
    -- it gives up steering and just teleports.
    BALL_CORRECTION_GAIN = 10,
    BALL_SNAP_DISTANCE = 1.5,
  },
}

-- Derived, so retuning the tick rate carries the playback window with it.
Config.NET.PADDLE_INTERP_WINDOW = Config.NET.PADDLE_INTERP_STRETCH / Config.NET.TICK_RATE

return Config
