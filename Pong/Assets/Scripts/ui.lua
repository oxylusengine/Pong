local UI = {}

local vfs = App:get_vfs()
local WORKING_DIR = vfs:is_mounted_dir(vfs:PROJECT_DIR()) and vfs:PROJECT_DIR() or vfs:APP_DIR()

NetworkController = require_script(WORKING_DIR, "Scripts/network_controller.lua")

UI.is_ai = false
UI.GameState = {
  MainMenu = 1,
  Lobby = 2,
  Playing = 3,
  Scoring = 4,
  Online = 5,
  OnlineLobby = 6,
}

-- Which paddle this machine drives. nil in local play, where we drive both.
UI.local_player_id = nil

UI.current_state = UI.GameState.MainMenu
UI.ui_doc = {}
UI.p1_ready = false
UI.p2_ready = false
UI.data_model = {
  p1_score = 0,
  p2_score = 0,
  won_player_id = 0,
  countdown_value = ''
}

local rml_scene_context

local p1_status
local p2_status
local main_menu
local lobby
local online_menu
local online_lobby
local online_status
local lobby_address
local net_p1_status
local net_p2_status
local btn_net_ready
local btn_net_start
local ip_input
local port_input
local game_end_ui
local btn_start

-- Shown in the lobby, remembered from whatever was typed in the online menu.
local joined_address = nil

local function input_value(element)
  return Element.As.ElementFormControlInput(element).value
end

function UI.init(scene, on_start_match, on_stop_match)
  local ui_document_path = vfs:resolve_physical_dir(WORKING_DIR, "UI/ui.rml")
  rml_scene_context = rmlui.contexts[scene:get_rml_context_name()]
  rmlui_ext.ClearStyleCache(UI.ui_doc)
  rmlui_ext.ClearTemplateCache(UI.ui_doc)

  UI.data_model = rml_scene_context:OpenDataModel("game_state", {
    p1_score = 0,
    p2_score = 0,
    won_player_id = 0,
    countdown_value = '0.0',
  })

  UI.ui_doc = rml_scene_context:LoadDocument(ui_document_path)
  UI.ui_doc:Show()

  main_menu = UI.ui_doc:GetElementById("main_menu")
  lobby = UI.ui_doc:GetElementById("lobby")
  online_menu = UI.ui_doc:GetElementById("online_menu")
  online_lobby = UI.ui_doc:GetElementById("online_lobby")
  online_status = UI.ui_doc:GetElementById("online_status")
  lobby_address = UI.ui_doc:GetElementById("lobby_address")
  net_p1_status = UI.ui_doc:GetElementById("net_p1_status")
  net_p2_status = UI.ui_doc:GetElementById("net_p2_status")
  btn_net_ready = UI.ui_doc:GetElementById("btn_net_ready")
  btn_net_start = UI.ui_doc:GetElementById("btn_net_start")
  ip_input = UI.ui_doc:GetElementById("ip_input")
  port_input = UI.ui_doc:GetElementById("port_input")
  game_ui = UI.ui_doc:GetElementById("game_ui")
  game_end_ui = UI.ui_doc:GetElementById("game_end_ui")
  p1_status = UI.ui_doc:GetElementById("p1_status")
  p2_status = UI.ui_doc:GetElementById("p2_status")
  btn_start = UI.ui_doc:GetElementById("btn_start")

  local function display_only(panel)
    main_menu.style.display = (panel == main_menu) and 'flex' or 'none'
    lobby.style.display = (panel == lobby) and 'flex' or 'none'
    online_menu.style.display = (panel == online_menu) and 'flex' or 'none'
    online_lobby.style.display = (panel == online_lobby) and 'flex' or 'none'
    game_ui.style.display = (panel == game_ui) and 'flex' or 'none'
    game_end_ui.style.display = 'none'
  end

  local function display_main_menu() display_only(main_menu) end
  local function display_lobby_menu() display_only(lobby) end
  local function display_online_menu() display_only(online_menu) end
  local function display_online_lobby() display_only(online_lobby) end
  local function display_game_ui() display_only(game_ui) end

  local function set_online_status(text)
    online_status.inner_rml = text or ""
  end

  local function set_ready_class(element, is_ready)
    element:SetClass("ready", is_ready)
    element:SetClass("not-ready", not is_ready)
  end

  local function refresh_lobby()
    local p1_ready, p2_ready = NetworkController.ready_states()

    net_p1_status.inner_rml = p1_ready and "READY" or "Not ready"
    set_ready_class(net_p1_status, p1_ready)

    if NetworkController.peer_connected then
      net_p2_status.inner_rml = p2_ready and "READY" or "Not ready"
      set_ready_class(net_p2_status, p2_ready)
    else
      net_p2_status.inner_rml = "Waiting for opponent..."
      set_ready_class(net_p2_status, false)
    end

    btn_net_ready.inner_rml = NetworkController.local_ready and "Cancel Ready" or "Ready"

    local can_start = NetworkController.is_host() and NetworkController.both_ready()
    btn_net_start.style.display = can_start and 'block' or 'none'
  end

  UI.ui_doc:GetElementById("btn_local_ai"):AddEventListener("click", function()
    UI.current_state = UI.GameState.Playing
    UI.is_ai = true
    UI.local_player_id = nil

    display_game_ui()

    if on_start_match then
      on_start_match(scene)
    end
  end)

  UI.ui_doc:GetElementById("btn_local_coop"):AddEventListener("click", function()
    display_lobby_menu()
    UI.current_state = UI.GameState.Lobby
  end)

  -- Fired on both machines once the host starts the match. The host owns player 1, the joiner
  -- owns player 2.
  local function on_match_start()
    UI.is_ai = false
    UI.local_player_id = NetworkController.is_host() and Config.PLAYER_1_ID or Config.PLAYER_2_ID
    UI.current_state = UI.GameState.Playing

    set_online_status("")
    display_game_ui()

    if on_start_match then
      on_start_match(scene)
    end
  end

  local function return_to_online_menu(reason)
    UI.local_player_id = nil

    if on_stop_match then
      on_stop_match(scene)
    end

    NetworkController.leave()

    UI.current_state = UI.GameState.Online
    display_online_menu()
    set_online_status(reason)
    refresh_lobby()
  end

  NetworkController.on_peer_connected = function()
    if NetworkController.is_client() then
      lobby_address.inner_rml = "Connected to " .. (joined_address or "host")
    end

    set_online_status("")
    UI.current_state = UI.GameState.OnlineLobby

    display_online_lobby()
    refresh_lobby()
  end

  NetworkController.on_lobby_update = refresh_lobby
  NetworkController.on_match_start = on_match_start
  NetworkController.on_peer_disconnected = return_to_online_menu
  NetworkController.on_session_end = return_to_online_menu

  -- on_score / on_round_reset belong to the gameplay side, scene.lua owns those.

  UI.ui_doc:GetElementById("btn_online"):AddEventListener("click", function()
    -- Leaving the online menu tears the subscriptions down, so re-arm them on every entry.
    -- NetworkController.init is idempotent.
    NetworkController.init()

    display_online_menu()
    set_online_status("")
    UI.current_state = UI.GameState.Online
  end)

  UI.ui_doc:GetElementById("btn_lobby_back"):AddEventListener("click", function()
    UI.p1_ready = false
    UI.p2_ready = false

    -- Reset UI text and colors
    p1_status.inner_rml = "Player 1: Press Up/Down to Ready"
    set_ready_class(p1_status, false)

    p2_status.inner_rml = "Player 2: Press W/S to Ready"
    set_ready_class(p2_status, false)

    btn_start.style.display = 'none'

    display_main_menu()
    UI.current_state = UI.GameState.MainMenu
  end)

  -- Ports outside this range cannot be bound, catch it before enet does.
  local function read_port()
    local port = tonumber(input_value(port_input))
    if not port or port ~= math.floor(port) or port < 1 or port > 65535 then
      return nil
    end

    return port
  end

  UI.ui_doc:GetElementById("btn_host"):AddEventListener("click", function()
    local port = read_port()
    if not port then
      set_online_status("Port must be a whole number between 1 and 65535.")
      return
    end

    if not NetworkController.start_host(port) then
      set_online_status("Could not host on port " .. port .. ".")
      return
    end

    joined_address = nil
    lobby_address.inner_rml = "Hosting on port " .. port
    UI.current_state = UI.GameState.OnlineLobby

    display_online_lobby()
    refresh_lobby()
  end)

  UI.ui_doc:GetElementById("btn_join"):AddEventListener("click", function()
    local port = read_port()
    if not port then
      set_online_status("Port must be a whole number between 1 and 65535.")
      return
    end

    local ip = input_value(ip_input)
    if ip == "" then
      set_online_status("Enter the host's IP address.")
      return
    end

    joined_address = ip .. ":" .. port

    if not NetworkController.connect_to_server(ip, port) then
      set_online_status("Could not start connecting to " .. joined_address .. ".")
      return
    end

    set_online_status("Connecting to " .. joined_address .. "...")
  end)

  btn_net_ready:AddEventListener("click", function()
    NetworkController.set_local_ready(not NetworkController.local_ready)
  end)

  btn_net_start:AddEventListener("click", function()
    NetworkController.request_start_match()
  end)

  UI.ui_doc:GetElementById("btn_net_leave"):AddEventListener("click", function()
    return_to_online_menu("")
  end)

  UI.ui_doc:GetElementById("btn_online_back"):AddEventListener("click", function()
    NetworkController.deinit()

    display_main_menu()
    UI.current_state = UI.GameState.MainMenu
  end)

  UI.ui_doc:GetElementById("btn_exit"):AddEventListener("click", function()
    App:get():should_stop()
  end)

  btn_start:AddEventListener("click", function()
    UI.current_state = UI.GameState.Playing
    UI.is_ai = false
    UI.local_player_id = nil

    display_game_ui()

    if on_start_match then
      on_start_match(scene)
    end
  end)

  Oxlog.info("Initalized UI.")
end

function UI.deinit()
  UI.ui_doc:Close()
  UI.data_model = rml_scene_context:CloseDataModel("game_state")
end

function UI.update(scene, on_start_match, on_stop_match)
  local input = App.mod.Input

  -- Hot reload
  if input:get_key_pressed(ScanCode.R) then
    UI.deinit()
    UI.init(scene, on_start_match, on_stop_match)
  end

  if UI.current_state == UI.GameState.Lobby then
    local state_changed = false

    if not UI.p1_ready and (input:get_key_pressed(ScanCode.Up) or input:get_key_pressed(ScanCode.Down)) then
      UI.p1_ready = true
      p1_status.inner_rml = "Player 1: READY"
      p1_status:SetClass("not-ready", false)
      p1_status:SetClass("ready", true)
      state_changed = true
    end

    if not UI.p2_ready and (input:get_key_pressed(ScanCode.W) or input:get_key_pressed(ScanCode.S)) then
      UI.p2_ready = true
      p2_status.inner_rml = "Player 2: READY"
      p2_status:SetClass("not-ready", false)
      p2_status:SetClass("ready", true)
      state_changed = true
    end

    if state_changed and UI.p1_ready and UI.p2_ready then
      btn_start.style.display = 'block'
    end
  end
end

function UI.draw_debuggers()
  if NetworkController.client then
    OxUI.draw_network_stats(NetworkController.client)
  end
end

function UI.display_game_end_ui()
  game_end_ui.style.display = 'flex'
end

function UI.hide_game_end_ui()
  game_end_ui.style.display = 'none'
end

return UI
