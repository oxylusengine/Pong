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

local rml_main_context

local p1_status
local p2_status
local main_menu
local lobby
local online_menu
local online_status
local ip_input
local game_end_ui
local btn_start

function UI.init(scene, on_start_match)
  local ui_document_path = vfs:resolve_physical_dir(WORKING_DIR, "UI/ui.rml")
  rml_main_context = rmlui.contexts['main']
  rmlui_ext.ClearStyleCache(UI.ui_doc)
  rmlui_ext.ClearTemplateCache(UI.ui_doc)

  UI.data_model = rml_main_context:OpenDataModel("game_state", {
    p1_score = 0,
    p2_score = 0,
    won_player_id = 0,
    countdown_value = '0.0',
  })

  UI.ui_doc = rml_main_context:LoadDocument(ui_document_path)
  UI.ui_doc:Show()

  main_menu = UI.ui_doc:GetElementById("main_menu")
  lobby = UI.ui_doc:GetElementById("lobby")
  online_menu = UI.ui_doc:GetElementById("online_menu")
  online_status = UI.ui_doc:GetElementById("online_status")
  ip_input = UI.ui_doc:GetElementById("ip_input")
  game_ui = UI.ui_doc:GetElementById("game_ui")
  game_end_ui = UI.ui_doc:GetElementById("game_end_ui")
  p1_status = UI.ui_doc:GetElementById("p1_status")
  p2_status = UI.ui_doc:GetElementById("p2_status")
  btn_start = UI.ui_doc:GetElementById("btn_start")

  local function display_main_menu()
    main_menu.style.display = 'flex'
    lobby.style.display = 'none'
    online_menu.style.display = 'none'
    game_ui.style.display = 'none'
    game_end_ui.display = 'none'
  end

  local function display_lobby_menu()
    main_menu.style.display = 'none'
    lobby.style.display = 'flex'
    online_menu.style.display = 'none'
    game_ui.style.display = 'none'
    game_end_ui.display = 'none'
  end

  local function display_online_menu()
    main_menu.style.display = 'none'
    lobby.style.display = 'none'
    online_menu.style.display = 'flex'
    game_ui.style.display = 'none'
    game_end_ui.display = 'none'
  end

  local function display_game_ui()
    main_menu.style.display = 'none'
    lobby.style.display = 'none'
    online_menu.style.display = 'none'
    game_ui.style.display = 'flex'
    game_end_ui.display = 'none'
  end

  UI.ui_doc:GetElementById("btn_local_ai"):AddEventListener("click", function()
    UI.current_state = UI.GameState.Playing
    UI.is_ai = true

    display_game_ui()

    if on_start_match then
      on_start_match(scene)
    end
  end)

  UI.ui_doc:GetElementById("btn_local_coop"):AddEventListener("click", function()
    display_lobby_menu()
    UI.current_state = UI.GameState.Lobby
  end)

  local function set_online_status(text)
    online_status.inner_rml = text or ""
  end

  -- Fired on both machines once the two sides are linked, so this is where an online
  -- match actually begins. The host owns player 1, whoever joined owns player 2.
  local function on_session_start(mode)
    UI.is_ai = false
    UI.local_player_id = (mode == NetworkController.Mode.Host) and Config.PLAYER_1_ID or Config.PLAYER_2_ID
    UI.current_state = UI.GameState.Playing

    set_online_status("")
    display_game_ui()

    if on_start_match then
      on_start_match(scene)
    end
  end

  local function on_session_end(reason)
    UI.local_player_id = nil
    UI.current_state = UI.GameState.Online

    display_online_menu()
    set_online_status(reason)
  end

  UI.ui_doc:GetElementById("btn_online"):AddEventListener("click", function()
    NetworkController.on_session_start = on_session_start
    NetworkController.on_session_end = on_session_end
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
    p1_status:SetClass("ready", false)
    p1_status:SetClass("not-ready", true)

    p2_status.inner_rml = "Player 2: Press W/S to Ready"
    p2_status:SetClass("ready", false)
    p2_status:SetClass("not-ready", true)

    btn_start.style.display = 'none'

    display_main_menu()
    UI.current_state = UI.GameState.MainMenu
  end)

  UI.ui_doc:GetElementById("btn_host"):AddEventListener("click", function()
    local port = 4242
    local max_clients = 2
    NetworkController.start_host(port, max_clients)
  end)

  UI.ui_doc:GetElementById("btn_join"):AddEventListener("click", function()
    local IP = "127.0.0.1"
    local port = 4242
    NetworkController.connect_to_server(IP, 4242)
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

    display_game_ui()

    if on_start_match then
      on_start_match(scene)
    end
  end)

  Oxlog.info("Initalized UI.")
end

function UI.deinit()
  UI.ui_doc:Close()
  UI.data_model = rml_main_context:CloseDataModel("game_state")
end

function UI.update(scene, on_start_match)
  local input = App.mod.Input

  -- Hot reload
  if input:get_key_pressed(ScanCode.R) then
    UI.deinit()
    UI.init(scene, on_start_match)
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
