local NetworkController = {
  server = nil,
  client = nil
}

NetworkController.Mode = {
  SinglePlayer = 1,
  Host = 2,
  Client = 3
}
NetworkController.current_mode = NetworkController.Mode.SinglePlayer

NetworkController.on_session_start = nil
NetworkController.on_session_end = nil

local subscriptions = {}

local function track(subscription)
  if subscription then
    subscriptions[#subscriptions + 1] = subscription
  else
    Oxlog.error("Failed to subscribe to a network event.")
  end
end

local function clear_subscriptions()
  for _, subscription in ipairs(subscriptions) do
    subscription:unsubscribe()
  end
  subscriptions = {}
end

local function session_start(mode)
  NetworkController.current_mode = mode

  if NetworkController.on_session_start then
    NetworkController.on_session_start(mode)
  end
end

local pending_client_teardown = false

local function session_end(reason)
  if NetworkController.on_session_end then
    NetworkController.on_session_end(reason)
  end
end

function NetworkController.init()
  local es = App:get_event_system()

  track(es:subscribe_server_connect_event(function(e)
    Oxlog.info("Connected to server. NetID: " .. e.net_id)
    session_start(NetworkController.Mode.Client)
  end))

  track(es:subscribe_server_disconnect_event(function(e)
    pending_client_teardown = true

    if e.reason == NetClientStatus.TimedOut then
      Oxlog.warn("Connection attempt timed out.")
      session_end("Could not reach host.")
    else
      Oxlog.info("Lost connection to server.")
      session_end("Disconnected from host.")
    end
  end))
end

function NetworkController.deinit()
  clear_subscriptions()

  NetworkController.destroy_client()
  NetworkController.destroy_server()
end

function NetworkController.start_host(port, max_clients)
  local nm = App.mod.NetworkManager
  local es = App:get_event_system()

  NetworkController.server = nm:create_server(port, max_clients)
  if not NetworkController.server then
    Oxlog.error("Failed to host on port " .. port .. ".")
    return false
  end

  NetworkController.current_mode = NetworkController.Mode.Host

  track(es:subscribe_client_connect_event(function(e)
    Oxlog.info("Client connected " .. e.client_id)
    session_start(NetworkController.Mode.Host)
  end))

  track(es:subscribe_client_disconnect_event(function(e)
    Oxlog.info("Client disconnected " .. e.client_id)
    session_end("Opponent left the game.")
  end))

  return true
end

function NetworkController.connect_to_server(ip, port)
  local nm = App.mod.NetworkManager

  NetworkController.destroy_client()
  NetworkController.client = nm:create_client()
  if not NetworkController.client then
    Oxlog.error("Failed to create a client.")
    return false
  end

  if not NetworkController.client:connect(ip, port, 5000) then
    Oxlog.error("Failed to start connecting to " .. ip .. ":" .. port .. ".")
    NetworkController.destroy_client()
    return false
  end

  return true
end

function NetworkController.destroy_server()
  local nm = App.mod.NetworkManager
  NetworkController.current_mode = NetworkController.Mode.SinglePlayer
  if NetworkController.server then
    nm:destroy_server(NetworkController.server)
  end
  NetworkController.server = nil
end

function NetworkController.destroy_client()
  local nm = App.mod.NetworkManager
  pending_client_teardown = false
  if NetworkController.client then
    nm:destroy_client(NetworkController.client)
  end
  NetworkController.client = nil
end

function NetworkController.tick()
  if pending_client_teardown then
    pending_client_teardown = false
    NetworkController.destroy_client()
  end

  if NetworkController.server then
    NetworkController.server:tick(App:get_timestep())
  end

  if NetworkController.client then
    NetworkController.client:tick(App:get_timestep())
  end
end

return NetworkController
