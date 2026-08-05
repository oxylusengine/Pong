local vfs = App:get_vfs()
local WORKING_DIR = vfs:is_mounted_dir(vfs:PROJECT_DIR()) and vfs:PROJECT_DIR() or vfs:APP_DIR()

local Config = require_script(WORKING_DIR, "Scripts/config.lua")

local NetworkController = {}
NetworkController.__index = NetworkController

NetworkController.Mode = {
  SinglePlayer = 1,
  Host = 2,
  Client = 3
}

local function track(list, subscription)
  if subscription then
    list[#list + 1] = subscription
  else
    Oxlog.error("Failed to subscribe to a network event.")
  end
end

local function clear_subscriptions(list)
  for _, subscription in ipairs(list) do
    subscription:unsubscribe()
  end
  for i = #list, 1, -1 do
    list[i] = nil
  end
end

local function fire(callback, ...)
  if callback then
    callback(...)
  end
end

function NetworkController.new()
  local self = setmetatable({}, NetworkController)

  self.server = nil
  self.client = nil
  self.current_mode = NetworkController.Mode.SinglePlayer

  -- Assigned by ui.lua / scene.lua.
  self.on_peer_connected = nil
  self.on_peer_disconnected = nil
  self.on_lobby_update = nil
  self.on_match_start = nil
  self.on_score = nil
  self.on_round_reset = nil
  self.on_session_end = nil

  -- Lobby state. Player 1 is always the host, player 2 whoever joined.
  self.peer_connected = false
  self.local_ready = false
  self.remote_ready = false

  self.peer_client_id = nil
  -- Latest paddle direction received from the client, host only.
  self.remote_input_dir = 0
  -- Latest world state received from the host, client only.
  self.latest_state = nil

  -- init() subscriptions live for as long as the online menu is open, session ones only for as long
  -- as a server is up.
  self.base_subscriptions = {}
  self.session_subscriptions = {}

  -- Disconnect events are emitted from inside enet's service loop, so hosts can never be destroyed
  -- straight from a handler. Teardown always waits for the next tick.
  self.pending_client_teardown = false
  self.pending_server_teardown = false

  return self
end

function NetworkController:is_host()
  return self.current_mode == NetworkController.Mode.Host
end

function NetworkController:is_client()
  return self.current_mode == NetworkController.Mode.Client
end

function NetworkController:is_online()
  return self.current_mode ~= NetworkController.Mode.SinglePlayer
end

-- Returns the ready flags in player order, whichever side we happen to be on.
function NetworkController:ready_states()
  if self:is_client() then
    return self.remote_ready, self.local_ready
  end
  return self.local_ready, self.remote_ready
end

function NetworkController:both_ready()
  local p1_ready, p2_ready = self:ready_states()
  return self.peer_connected and p1_ready and p2_ready
end

function NetworkController:reset_lobby()
  self.peer_connected = false
  self.local_ready = false
  self.remote_ready = false
  self.peer_client_id = nil
  self.remote_input_dir = 0
  self.latest_state = nil
end

function NetworkController:broadcast_lobby()
  if not self.server then
    return
  end

  self.server:broadcast("lobby", {
    self.local_ready and 1 or 0,
    self.remote_ready and 1 or 0,
  }, true)
end

function NetworkController:init()
  -- The online menu can be entered more than once per run, so never stack subscriptions.
  clear_subscriptions(self.base_subscriptions)

  local es = App:get_event_system()

  track(self.base_subscriptions, es:subscribe_server_connect_event(function(e)
    -- The bus is shared by every scene, so only act on our own client's events.
    if e.client ~= self.client then
      return
    end

    Oxlog.info("Connected to server. NetID: " .. e.net_id)

    self.current_mode = NetworkController.Mode.Client
    self.peer_connected = true

    fire(self.on_peer_connected)
  end))

  track(self.base_subscriptions, es:subscribe_server_disconnect_event(function(e)
    if e.client ~= self.client then
      return
    end

    self.pending_client_teardown = true
    self:reset_lobby()

    if e.reason == NetClientStatus.TimedOut then
      Oxlog.warn("Connection attempt timed out.")
      fire(self.on_session_end, "Could not reach host.")
    else
      Oxlog.info("Lost connection to server.")
      fire(self.on_session_end, "Disconnected from host.")
    end
  end))
end

function NetworkController:deinit()
  clear_subscriptions(self.base_subscriptions)
  clear_subscriptions(self.session_subscriptions)
  self:reset_lobby()

  self:destroy_client()
  self:destroy_server()
end

function NetworkController:register_host_procs(server)
  server:register_proc("ready", function(client_id, params)
    self.remote_ready = (params[1] or 0) ~= 0

    self:broadcast_lobby()
    fire(self.on_lobby_update)
  end)

  server:register_proc("input", function(client_id, params)
    self.remote_input_dir = params[1] or 0
  end)
end

function NetworkController:register_client_procs(client)
  client:register_proc("lobby", function(_, params)
    self.remote_ready = (params[1] or 0) ~= 0
    self.local_ready = (params[2] or 0) ~= 0

    fire(self.on_lobby_update)
  end)

  client:register_proc("start", function()
    fire(self.on_match_start)
  end)

  client:register_proc("state", function(_, params)
    self.latest_state = {
      p1_y = params[1] or 0,
      p2_y = params[2] or 0,
      ball_x = params[3] or 0,
      ball_y = params[4] or 0,
      ball_vx = params[5] or 0,
      ball_vy = params[6] or 0,
    }
  end)

  client:register_proc("score", function(_, params)
    fire(self.on_score, params[1] or 0, params[2] or 0, params[3] or 0)
  end)

  client:register_proc("round", function()
    fire(self.on_round_reset)
  end)
end

function NetworkController:start_host(port)
  local nm = App.mod.NetworkManager
  local es = App:get_event_system()

  self.server = nm:create_server(port, Config.NET.MAX_CLIENTS)
  if not self.server then
    Oxlog.error("Failed to host on port " .. port .. ".")
    return false
  end

  self.server:set_tick_rate(Config.NET.TICK_RATE)
  self.current_mode = NetworkController.Mode.Host
  self:reset_lobby()

  self:register_host_procs(self.server)

  track(self.session_subscriptions, es:subscribe_client_connect_event(function(e)
    if e.server ~= self.server then
      return
    end

    Oxlog.info("Client connected " .. e.client_id)

    self.peer_client_id = e.client_id
    self.peer_connected = true
    self.remote_ready = false

    -- The joiner has no idea what the host already toggled, tell it.
    self:broadcast_lobby()
    fire(self.on_peer_connected)
  end))

  track(self.session_subscriptions, es:subscribe_client_disconnect_event(function(e)
    if e.server ~= self.server then
      return
    end

    Oxlog.info("Client disconnected " .. e.client_id)

    self.peer_client_id = nil
    self.peer_connected = false
    self.remote_ready = false
    self.remote_input_dir = 0

    fire(self.on_peer_disconnected, "Opponent left the game.")
  end))

  return true
end

function NetworkController:connect_to_server(ip, port)
  local nm = App.mod.NetworkManager

  self:destroy_client()
  self.client = nm:create_client()
  if not self.client then
    Oxlog.error("Failed to create a client.")
    return false
  end

  self.client:set_tick_rate(Config.NET.TICK_RATE)
  self:reset_lobby()

  -- Procs have to exist before the first packet lands, so register before connecting.
  self:register_client_procs(self.client)

  if not self.client:connect(ip, port, Config.NET.CONNECT_TIMEOUT_MS) then
    Oxlog.error("Failed to start connecting to " .. ip .. ":" .. port .. ".")
    self:destroy_client()
    return false
  end

  return true
end

function NetworkController:destroy_server()
  local nm = App.mod.NetworkManager
  self.pending_server_teardown = false
  self.current_mode = NetworkController.Mode.SinglePlayer
  if self.server then
    nm:destroy_server(self.server)
  end
  self.server = nil
end

function NetworkController:destroy_client()
  local nm = App.mod.NetworkManager
  self.pending_client_teardown = false
  if self.client then
    nm:destroy_client(self.client)
  end
  self.client = nil
end

-- Leaves the current session but keeps the online menu subscriptions alive. Safe to call from a
-- network event handler, the actual hosts go away on the next tick.
function NetworkController:leave()
  clear_subscriptions(self.session_subscriptions)
  self:reset_lobby()

  self.pending_client_teardown = self.client ~= nil
  self.pending_server_teardown = self.server ~= nil

  self.current_mode = NetworkController.Mode.SinglePlayer
end

function NetworkController:set_local_ready(is_ready)
  if not self:is_online() then
    return
  end

  self.local_ready = is_ready

  if self:is_host() then
    self:broadcast_lobby()
  elseif self.client then
    self.client:call_server("ready", { is_ready and 1 or 0 }, true)
  end

  fire(self.on_lobby_update)
end

function NetworkController:request_start_match()
  if not self:is_host() or not self:both_ready() then
    return false
  end

  self.server:broadcast("start", {}, true)
  fire(self.on_match_start)

  return true
end

function NetworkController:send_input(dir)
  if self.client then
    self.client:call_server("input", { dir }, false)
  end
end

function NetworkController:remote_input()
  return self.remote_input_dir
end

-- Returns the state only once per update received. Applying the same snapshot every frame would
-- pin the ball in place instead of letting it dead reckon between ticks.
function NetworkController:consume_state()
  local state = self.latest_state
  self.latest_state = nil

  return state
end

function NetworkController:broadcast_state(p1_y, p2_y, ball_position, ball_velocity)
  if not self.server then
    return
  end

  self.server:broadcast("state", {
    p1_y,
    p2_y,
    ball_position.x,
    ball_position.y,
    ball_velocity.x,
    ball_velocity.y,
  }, false)
end

function NetworkController:broadcast_score(p1_score, p2_score, won_player_id)
  if self.server then
    self.server:broadcast("score", { p1_score, p2_score, won_player_id }, true)
  end
end

function NetworkController:broadcast_round_reset()
  if self.server then
    self.server:broadcast("round", {}, true)
  end
end

-- Returns true on a network tick boundary, which is what rate limits state and input sends.
function NetworkController:tick()
  if self.pending_client_teardown then
    self:destroy_client()
  end

  if self.pending_server_teardown then
    self:destroy_server()
  end

  local net_tick = false

  if self.server then
    net_tick = self.server:tick(App:get_timestep()) or net_tick
  end

  if self.client then
    net_tick = self.client:tick(App:get_timestep()) or net_tick
  end

  return net_tick
end

return NetworkController
