local vfs = App:get_vfs()
local WORKING_DIR = vfs:is_mounted_dir(vfs:PROJECT_DIR()) and vfs:PROJECT_DIR() or vfs:APP_DIR()

local Config = require_script(WORKING_DIR, "Scripts/config.lua")

local UI = {}
UI.__index = UI

UI.GameState = {
  MainMenu = 1,
  Lobby = 2,
  Playing = 3,
  Scoring = 4,
  Online = 5,
  OnlineLobby = 6,
}

local function input_value(element)
  return Element.As.ElementFormControlInput(element).value
end

function UI.new(scene, net, on_start_match, on_stop_match)
  local self = setmetatable({}, UI)

  self.scene = scene
  self.net = net
  self.on_start_match = on_start_match
  self.on_stop_match = on_stop_match

  self.is_ai = false
  -- Which paddle this machine drives. nil in local play, where we drive both.
  self.local_player_id = nil
  self.current_state = UI.GameState.MainMenu
  self.ui_doc = nil
  self.p1_ready = false
  self.p2_ready = false
  self.data_model = nil

  -- Shown in the lobby, remembered from whatever was typed in the online menu.
  self.joined_address = nil

  self:build()

  return self
end

function UI:display_only(panel)
  self.main_menu.style.display = (panel == self.main_menu) and 'flex' or 'none'
  self.lobby.style.display = (panel == self.lobby) and 'flex' or 'none'
  self.online_menu.style.display = (panel == self.online_menu) and 'flex' or 'none'
  self.online_lobby.style.display = (panel == self.online_lobby) and 'flex' or 'none'
  self.game_ui.style.display = (panel == self.game_ui) and 'flex' or 'none'
  self.game_end_ui.style.display = 'none'
end

function UI:set_online_status(text)
  self.online_status.inner_rml = text or ""
end

local function set_ready_class(element, is_ready)
  element:SetClass("ready", is_ready)
  element:SetClass("not-ready", not is_ready)
end

function UI:refresh_lobby()
  local p1_ready, p2_ready = self.net:ready_states()

  self.net_p1_status.inner_rml = p1_ready and "READY" or "Not ready"
  set_ready_class(self.net_p1_status, p1_ready)

  if self.net.peer_connected then
    self.net_p2_status.inner_rml = p2_ready and "READY" or "Not ready"
    set_ready_class(self.net_p2_status, p2_ready)
  else
    self.net_p2_status.inner_rml = "Waiting for opponent..."
    set_ready_class(self.net_p2_status, false)
  end

  self.btn_net_ready.inner_rml = self.net.local_ready and "Cancel Ready" or "Ready"

  local can_start = self.net:is_host() and self.net:both_ready()
  self.btn_net_start.style.display = can_start and 'block' or 'none'
end

function UI:return_to_online_menu(reason)
  self.local_player_id = nil

  if self.on_stop_match then
    self.on_stop_match(self.scene)
  end

  self.net:leave()

  self.current_state = UI.GameState.Online
  self:display_only(self.online_menu)
  self:set_online_status(reason)
  self:refresh_lobby()
end

-- Ports outside this range cannot be bound, catch it before enet does.
function UI:read_port()
  local port = tonumber(input_value(self.port_input))
  if not port or port ~= math.floor(port) or port < 1 or port > 65535 then
    return nil
  end

  return port
end

function UI:build()
  local ui_document_path = vfs:resolve_physical_dir(WORKING_DIR, "UI/ui.rml")

  self.rml_context = rmlui.contexts[self.scene:get_rml_context_name()]
  rmlui_ext.ClearStyleCache()
  rmlui_ext.ClearTemplateCache()

  self.data_model = self.rml_context:OpenDataModel("game_state", {
    p1_score = 0,
    p2_score = 0,
    won_player_id = 0,
    countdown_value = '0.0',
  })

  self.ui_doc = self.rml_context:LoadDocument(ui_document_path)
  self.ui_doc:Show()

  local doc = self.ui_doc
  self.main_menu = doc:GetElementById("main_menu")
  self.lobby = doc:GetElementById("lobby")
  self.online_menu = doc:GetElementById("online_menu")
  self.online_lobby = doc:GetElementById("online_lobby")
  self.online_status = doc:GetElementById("online_status")
  self.lobby_address = doc:GetElementById("lobby_address")
  self.net_p1_status = doc:GetElementById("net_p1_status")
  self.net_p2_status = doc:GetElementById("net_p2_status")
  self.btn_net_ready = doc:GetElementById("btn_net_ready")
  self.btn_net_start = doc:GetElementById("btn_net_start")
  self.ip_input = doc:GetElementById("ip_input")
  self.port_input = doc:GetElementById("port_input")
  self.game_ui = doc:GetElementById("game_ui")
  self.game_end_ui = doc:GetElementById("game_end_ui")
  self.p1_status = doc:GetElementById("p1_status")
  self.p2_status = doc:GetElementById("p2_status")
  self.btn_start = doc:GetElementById("btn_start")

  doc:GetElementById("btn_local_ai"):AddEventListener("click", function()
    self.current_state = UI.GameState.Playing
    self.is_ai = true
    self.local_player_id = nil

    self:display_only(self.game_ui)

    if self.on_start_match then
      self.on_start_match(self.scene)
    end
  end)

  doc:GetElementById("btn_local_coop"):AddEventListener("click", function()
    self:display_only(self.lobby)
    self.current_state = UI.GameState.Lobby
  end)

  -- Fired on both machines once the host starts the match. The host owns player 1, the joiner
  -- owns player 2.
  self.net.on_match_start = function()
    self.is_ai = false
    self.local_player_id = self.net:is_host() and Config.PLAYER_1_ID or Config.PLAYER_2_ID
    self.current_state = UI.GameState.Playing

    self:set_online_status("")
    self:display_only(self.game_ui)

    if self.on_start_match then
      self.on_start_match(self.scene)
    end
  end

  self.net.on_peer_connected = function()
    if self.net:is_client() then
      self.lobby_address.inner_rml = "Connected to " .. (self.joined_address or "host")
    end

    self:set_online_status("")
    self.current_state = UI.GameState.OnlineLobby

    self:display_only(self.online_lobby)
    self:refresh_lobby()
  end

  self.net.on_lobby_update = function() self:refresh_lobby() end
  self.net.on_peer_disconnected = function(reason) self:return_to_online_menu(reason) end
  self.net.on_session_end = function(reason) self:return_to_online_menu(reason) end

  -- on_score / on_round_reset belong to the gameplay side, scene.lua owns those.

  doc:GetElementById("btn_online"):AddEventListener("click", function()
    -- Leaving the online menu tears the subscriptions down, so re-arm them on every entry.
    -- init is idempotent.
    self.net:init()

    self:display_only(self.online_menu)
    self:set_online_status("")
    self.current_state = UI.GameState.Online
  end)

  doc:GetElementById("btn_lobby_back"):AddEventListener("click", function()
    self.p1_ready = false
    self.p2_ready = false

    -- Reset UI text and colors
    self.p1_status.inner_rml = "Player 1: Press Up/Down to Ready"
    set_ready_class(self.p1_status, false)

    self.p2_status.inner_rml = "Player 2: Press W/S to Ready"
    set_ready_class(self.p2_status, false)

    self.btn_start.style.display = 'none'

    self:display_only(self.main_menu)
    self.current_state = UI.GameState.MainMenu
  end)

  doc:GetElementById("btn_host"):AddEventListener("click", function()
    local port = self:read_port()
    if not port then
      self:set_online_status("Port must be a whole number between 1 and 65535.")
      return
    end

    if not self.net:start_host(port) then
      self:set_online_status("Could not host on port " .. port .. ".")
      return
    end

    self.joined_address = nil
    self.lobby_address.inner_rml = "Hosting on port " .. port
    self.current_state = UI.GameState.OnlineLobby

    self:display_only(self.online_lobby)
    self:refresh_lobby()
  end)

  doc:GetElementById("btn_join"):AddEventListener("click", function()
    local port = self:read_port()
    if not port then
      self:set_online_status("Port must be a whole number between 1 and 65535.")
      return
    end

    local ip = input_value(self.ip_input)
    if ip == "" then
      self:set_online_status("Enter the host's IP address.")
      return
    end

    self.joined_address = ip .. ":" .. port

    if not self.net:connect_to_server(ip, port) then
      self:set_online_status("Could not start connecting to " .. self.joined_address .. ".")
      return
    end

    self:set_online_status("Connecting to " .. self.joined_address .. "...")
  end)

  self.btn_net_ready:AddEventListener("click", function()
    self.net:set_local_ready(not self.net.local_ready)
  end)

  self.btn_net_start:AddEventListener("click", function()
    self.net:request_start_match()
  end)

  doc:GetElementById("btn_net_leave"):AddEventListener("click", function()
    self:return_to_online_menu("")
  end)

  doc:GetElementById("btn_online_back"):AddEventListener("click", function()
    self.net:deinit()

    self:display_only(self.main_menu)
    self.current_state = UI.GameState.MainMenu
  end)

  doc:GetElementById("btn_exit"):AddEventListener("click", function()
    App:get():should_stop()
  end)

  self.btn_start:AddEventListener("click", function()
    self.current_state = UI.GameState.Playing
    self.is_ai = false
    self.local_player_id = nil

    self:display_only(self.game_ui)

    if self.on_start_match then
      self.on_start_match(self.scene)
    end
  end)

  Oxlog.info("Initalized UI for " .. self.scene:get_rml_context_name() .. ".")
end

function UI:deinit()
  if self.ui_doc then
    self.ui_doc:Close()
    self.ui_doc = nil
  end
  if self.rml_context then
    self.rml_context:CloseDataModel("game_state")
  end
  self.data_model = nil
end

function UI:reload()
  self:deinit()
  self:build()
end

function UI:update()
  local input = App.mod.Input

  -- Hot reload
  if input:get_key_pressed(ScanCode.R) then
    self:reload()
  end

  if self.current_state == UI.GameState.Lobby then
    local state_changed = false

    if not self.p1_ready and (input:get_key_pressed(ScanCode.Up) or input:get_key_pressed(ScanCode.Down)) then
      self.p1_ready = true
      self.p1_status.inner_rml = "Player 1: READY"
      set_ready_class(self.p1_status, true)
      state_changed = true
    end

    if not self.p2_ready and (input:get_key_pressed(ScanCode.W) or input:get_key_pressed(ScanCode.S)) then
      self.p2_ready = true
      self.p2_status.inner_rml = "Player 2: READY"
      set_ready_class(self.p2_status, true)
      state_changed = true
    end

    if state_changed and self.p1_ready and self.p2_ready then
      self.btn_start.style.display = 'block'
    end
  end
end

function UI:draw_debuggers()
  if self.net.client then
    OxUI.draw_network_stats(self.net.client)
  end
end

function UI:display_game_end_ui()
  self.game_end_ui.style.display = 'flex'
end

function UI:hide_game_end_ui()
  self.game_end_ui.style.display = 'none'
end

return UI
