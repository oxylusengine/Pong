local UI = {}

local vfs = App:get_vfs()
local WORKING_DIR = vfs:PROJECT_DIR()

UI.is_ai = false
UI.GameState = {
  MainMenu = 1,
  Lobby = 2,
  Playing = 3,
  Scoring = 4,
}

UI.current_state = UI.GameState.MainMenu
UI.ui_doc = {}
UI.p1_ready = false
UI.p2_ready = false
UI.p1_score = {}
UI.p2_score = {}
UI.data_model = {
  countdown_value = ''
}

local rml_main_context

local p1_status
local p2_status
local main_menu
local lobby
local online_menu
local btn_start

function UI.init(scene, on_start_match)
  local ui_document_path = vfs:resolve_physical_dir(WORKING_DIR, "UI/ui.rml")
  rml_main_context = rmlui.contexts['main']
  rmlui_ext.ClearStyleCache(UI.ui_doc)
  rmlui_ext.ClearTemplateCache(UI.ui_doc)

  UI.ui_doc = rml_main_context:LoadDocument(ui_document_path)
  UI.data_model = rml_main_context:OpenDataModel("game_state", {
    countdown_value = '0.0'
  })

  UI.ui_doc:Show()


  main_menu = UI.ui_doc:GetElementById("main_menu")
  lobby = UI.ui_doc:GetElementById("lobby")
  online_menu = UI.ui_doc:GetElementById("online_menu")
  game_ui = UI.ui_doc:GetElementById("game_ui")
  p1_status = UI.ui_doc:GetElementById("p1_status")
  p2_status = UI.ui_doc:GetElementById("p2_status")
  btn_start = UI.ui_doc:GetElementById("btn_start")

  UI.p1_score = UI.ui_doc:GetElementById("p1_score")
  UI.p2_score = UI.ui_doc:GetElementById("p2_score")

  local function display_main_menu()
    main_menu.style.display = 'flex'
    lobby.style.display = 'none'
    online_menu.style.display = 'none'
    game_ui.style.display = 'none'
  end

  local function display_lobby_menu()
    main_menu.style.display = 'none'
    lobby.style.display = 'flex'
    online_menu.style.display = 'none'
    game_ui.style.display = 'none'
  end

  local function display_online_menu()
    main_menu.style.display = 'none'
    lobby.style.display = 'none'
    online_menu.style.display = 'flex'
    game_ui.style.display = 'none'
  end

  local function display_game_ui()
    main_menu.style.display = 'none'
    lobby.style.display = 'none'
    online_menu.style.display = 'none'
    game_ui.style.display = 'flex'
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

  UI.ui_doc:GetElementById("btn_online"):AddEventListener("click", function()
    display_online_menu()
    UI.current_state = UI.GameState.Lobby
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

  UI.ui_doc:GetElementById("btn_online_back"):AddEventListener("click", function()
    -- TODO: maybe shutdown the server etc. here

    display_main_menu()
    UI.current_state = UI.GameState.MainMenu
  end)

  UI.ui_doc:GetElementById("btn_exit"):AddEventListener("click", function()
    App:get():should_stop()
  end)

  UI.ui_doc:GetElementById("btn_start"):AddEventListener("click", function()
    UI.current_state = UI.GameState.Playing

    display_game_ui()

    if on_start_match then
      on_start_match(scene)
    end
  end)

  Oxlog.info("Initalized UI.")
end

function UI.deinit()
  UI.data_model = rml_main_context:CloseDataModel("game_state")
end

function UI.update(scene, on_start_match)
  local input = App.mod.Input

  -- Hot reload logic
  if input:get_key_pressed(ScanCode.R) then
    UI.ui_doc:Close()
    UI.init(scene, on_start_match)
  end

  -- Lobby input polling
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

    -- If someone just readied up, check if we should show the Start button
    if state_changed and UI.p1_ready and UI.p2_ready then
      btn_start.style.display = 'block'
    end
  end
end

return UI
