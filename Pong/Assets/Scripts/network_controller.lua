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

function NetworkController.start_host(port, max_clients)
  local nm = App.mod.NetworkManager

  NetworkController.current_mode = NetworkController.Mode.Host
  NetworkController.server = nm:create_server(port, max_clients)

  local es = App:get_event_system()
  es:subscribe_client_connect_event(function(e)
    Oxlog.info("Client connected " .. e.client_id)
  end)

  es:subscribe_client_disconnect_event(function(e)
    Oxlog.info("Client disconnected " .. e.client_id)
  end)
end

function NetworkController.init()
  local nm = App.mod.NetworkManager
  NetworkController.client = nm:create_client()
end

function NetworkController.deinit()
  NetworkController.destroy_client()
  NetworkController.destroy_server()
end

function NetworkController.connect_to_server(ip, port)
  NetworkController.current_mode = NetworkController.Mode.Client
  NetworkController.client:connect(ip, port, 5000)
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
  if NetworkController.client then
    nm:destroy_client(NetworkController.client)
  end
  NetworkController.client = nil
end

function NetworkController.tick()
  if NetworkController.server then
    NetworkController.server:tick(App:get_timestep())
  end

  if NetworkController.client then
    NetworkController.client:tick(App:get_timestep())
  end
end

return NetworkController
