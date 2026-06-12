local UI = {}

local vfs = App:get_vfs()
local WORKING_DIR = vfs:PROJECT_DIR()

UI.GameState = {
  MainMenu = 1,
  Lobby = 2,
  Playing = 3,
}

UI.current_state = UI.GameState.MainMenu
UI.p1_ready = false
UI.p2_ready = false

local main_menu_doc
local p1_status
local p2_status
local main_menu
local lobby
local btn_start

function UI.init(scene, on_start_match)
  local ui_document_path = vfs:resolve_physical_dir(WORKING_DIR, "UI/main_menu.rml")
  local rml_main_context = rmlui.contexts['main']
  main_menu_doc = rml_main_context:LoadDocument(ui_document_path)
  main_menu_doc:Show()

  main_menu = main_menu_doc:GetElementById("main_menu")
  lobby = main_menu_doc:GetElementById("lobby")
  p1_status = main_menu_doc:GetElementById("p1_status")
  p2_status = main_menu_doc:GetElementById("p2_status")
  btn_start = main_menu_doc:GetElementById("btn_start")

  main_menu_doc:GetElementById("btn_local_coop"):AddEventListener("click", function()
    main_menu.style.display = 'none'
    lobby.style.display = 'flex'
    UI.current_state = UI.GameState.Lobby
  end)

  main_menu_doc:GetElementById("btn_back"):AddEventListener("click", function()
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

    lobby.style.display = 'none'
    main_menu.style.display = 'flex'
    UI.current_state = UI.GameState.MainMenu
  end)

  main_menu_doc:GetElementById("btn_exit"):AddEventListener("click", function()
    App:get():should_stop()
  end)

  main_menu_doc:GetElementById("btn_start"):AddEventListener("click", function()
    UI.current_state = UI.GameState.Playing
    main_menu_doc:Hide() -- Hide the UI when playing

    if on_start_match then
      on_start_match(scene)
    end
  end)
end

function UI.update(scene, on_start_match)
  local input = App.mod.Input

  -- Hot reload logic
  if input:get_key_pressed(KeyCode.R) then
    main_menu_doc:Close()
    UI.init(scene, on_start_match)
  end

  -- Lobby input polling
  if UI.current_state == UI.GameState.Lobby then
    local state_changed = false

    if not UI.p1_ready and (input:get_key_pressed(KeyCode.Up) or input:get_key_pressed(KeyCode.Down)) then
      UI.p1_ready = true
      p1_status.inner_rml = "Player 1: READY"
      p1_status:SetClass("not-ready", false)
      p1_status:SetClass("ready", true)
      state_changed = true
    end

    if not UI.p2_ready and (input:get_key_pressed(KeyCode.W) or input:get_key_pressed(KeyCode.S)) then
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
