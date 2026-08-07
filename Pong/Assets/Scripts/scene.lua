local vfs = App:get_vfs()
WORKING_DIR = vfs:is_mounted_dir(vfs:PROJECT_DIR()) and vfs:PROJECT_DIR() or vfs:APP_DIR()

Config = require_script(WORKING_DIR, "Scripts/config.lua")
Assets = require_script(WORKING_DIR, "Scripts/assets.lua")

local Components = require_script(WORKING_DIR, "Scripts/components.lua")
local UI = require_script(WORKING_DIR, "Scripts/ui.lua")
local NetworkController = require_script(WORKING_DIR, "Scripts/network_controller.lua")

local components = nil
local ui = nil
local net = nil

local spawn_timer = 0.0

local ball = nil
local player1 = nil
local player2 = nil

-- Everything start_match spawns, so a second match doesn't stack another set of entities.
local match_entities = {}

function on_add(scene)
  components = Components.new(scene)
end

local function track_entity(entity)
  match_entities[#match_entities + 1] = entity
  return entity
end

function create_player(scene, player_id, starting_point)
  local am = App.mod.AssetManager

  local player = track_entity(scene:create_entity("player", true))
  player:add(components.PlayerComponent, { id = player_id, speed = Config.PLAYER_SPEED })
  player:add(Core.SpriteComponent)

  local sc = player:get_mut(Core.SpriteComponent)
  local mat = am:get_mut_material(sc.material)
  mat:set_albedo_texture(Assets.player_sprite_asset)
  mat:set_sampling_mode(SamplingMode.NearestClamped)
  am:set_material_dirty(sc.material)

  local player_tc = player:get_mut(Core.TransformComponent)
  player_tc:set_position(starting_point)
  player_tc:set_scale(vec3.new(0.5, 2, 1))
  player:modified(Core.TransformComponent)

  player:add(Core.BoxColliderComponent, {
    friction = 0,
    restitution = 1,
    size = vec3.new(0.25, 1, 0.25),
  })
  player:add(Core.RigidBodyComponent, {
    type = 1, -- kinematic
    gravity_factor = 0,
    friction = 0,
    restitution = 1,
    linear_drag = 0,
    angular_drag = 0,
    allow_sleep = false,
    continuous = true,
  })
  player:modified(Core.RigidBodyComponent)

  return player
end

function add_starting_velocity(ball, speed)
  local body = Physics.get_body(ball)
  body:set_linear_velocity(vec3.new(speed, 0, 0))
end

function create_background(scene)
  local am = App.mod.AssetManager

  background = scene:create_entity("background", true)
  local tc = background:get_mut(Core.TransformComponent)
  tc:set_scale(vec3.new(24, 18, 0.5))
  tc:set_position(vec3.new(0, 0, -1))
  background:modified(Core.TransformComponent)
  background:add(Core.SpriteComponent)
  local sc = background:get_mut(Core.SpriteComponent)
  local mat = am:get_mut_material(sc.material)
  mat:set_albedo_texture(Assets.background_asset)
  mat:set_sampling_mode(SamplingMode.NearestClamped)
  am:set_material_dirty(sc.material)
end

function create_ball(scene)
  local am = App.mod.AssetManager

  ball = track_entity(scene:create_entity("ball", true))
  local tc = ball:get_mut(Core.TransformComponent)
  tc:set_scale(vec3.new(0.5, 0.5, 0.5))
  ball:add(components.BallComponent)
  ball:add(Core.SpriteComponent)

  local sc = ball:get_mut(Core.SpriteComponent)
  local mat = am:get_mut_material(sc.material)
  mat:set_albedo_texture(Assets.ball_sprite_asset)
  mat:set_sampling_mode(SamplingMode.NearestClamped)
  am:set_material_dirty(sc.material)

  ball:add(Core.SphereColliderComponent, {
    radius = 0.25,
    friction = 0.0,
    restitution = 1,
  })
  ball:add(Core.RigidBodyComponent, {
    gravity_factor = 0,
    friction = 0,
    restitution = 1,
    linear_drag = 0,
    angular_drag = 0,
    allowed_dofs = AllowedDOFs.TranslationX | AllowedDOFs.TranslationY,
    allow_sleep = false,
    continuous = true,
  })
  ball:modified(Core.RigidBodyComponent)

  return ball
end

function create_walls(scene)
  local top_wall = track_entity(scene:create_entity("top_wall"))
  top_wall:get_mut(Core.TransformComponent):set_position(vec3.new(0, 5, 0))
  top_wall:add(Core.BoxColliderComponent, {
    friction = 0,
    restitution = 1,
    size = vec3.new(10, 0.2, 1),
  })
  top_wall:add(Core.RigidBodyComponent, {
    type = 1,
    gravity_factor = 0,
    friction = 0,
    restitution = 1,
    linear_drag = 0,
    angular_drag = 0,
    continuous = true,
  })
  top_wall:modified(Core.RigidBodyComponent)

  local bottom_wall = track_entity(scene:create_entity("bottom_wall"))
  bottom_wall:get_mut(Core.TransformComponent):set_position(vec3.new(0, -5, 0))
  bottom_wall:add(Core.BoxColliderComponent, {
    friction = 0,
    restitution = 1,
    size = vec3.new(10, 0.2, 1),
  })
  bottom_wall:add(Core.RigidBodyComponent, {
    type = 1,
    gravity_factor = 0,
    friction = 0,
    restitution = 1,
    linear_drag = 0,
    angular_drag = 0,
    continuous = true,
  })
  bottom_wall:modified(Core.RigidBodyComponent)
end

function stop_match(scene)
  for i = #match_entities, 1, -1 do
    match_entities[i]:destruct()
    match_entities[i] = nil
  end

  ball = nil
  player1 = nil
  player2 = nil
  spawn_timer = 0.0

  ui.data_model.p1_score = 0
  ui.data_model.p2_score = 0
  ui.data_model.won_player_id = 0
  ui.data_model.countdown_value = ''
  ui:hide_game_end_ui()
end

function start_match(scene)
  -- Matches can be replayed within one run, start from a clean slate every time.
  stop_match(scene)

  create_walls(scene)

  player1 = create_player(scene, Config.PLAYER_1_ID, vec3.new(5, 0.0, 0))
  player2 = create_player(scene, Config.PLAYER_2_ID, vec3.new(-5, 0.0, 0))

  local p2_pc = player2:get_mut(components.PlayerComponent)
  p2_pc:set_is_ai(ui.is_ai)
  p2_pc:set_ai_target_error(0.15)

  ball = create_ball(scene)

  add_starting_velocity(ball, ball:get(components.BallComponent).speed)

  ui.current_state = UI.GameState.Playing
end

function reset_ball(scene, entity, body)
  body:set_position(scene, vec3.new(0, 0, 0))
  body:set_linear_velocity(vec3.new(0, 0, 0))

  spawn_timer = 2.0
end

function add_score(player)
  local pc = player:get_mut(components.PlayerComponent)
  local new_score = pc.score + 1
  pc:set_score(new_score)

  if pc.id == Config.PLAYER_1_ID then
    ui.data_model.p1_score = new_score
  end
  if pc.id == Config.PLAYER_2_ID then
    ui.data_model.p2_score = new_score
  end

  ui.data_model.won_player_id = pc.id + 1

  if net:is_host() then
    net:broadcast_score(
      player1:get(components.PlayerComponent).score,
      player2:get(components.PlayerComponent).score,
      pc.id + 1
    )
  end

  Oxlog.info("Added score to player! ID:" .. pc.id .. " NewScore: " .. new_score)
end

-- Online each machine drives a single paddle, so it answers to both key sets.
function read_paddle_input(scene, player_id)
  if not scene.input_focused then
    return 0
  end

  local input = App.mod.Input
  local online = net:is_online()
  local dir = 0

  if online or player_id == Config.PLAYER_1_ID then
    if input:get_key_held(ScanCode.Up) then dir = 1 end
    if input:get_key_held(ScanCode.Down) then dir = -1 end
  end

  if online or player_id == Config.PLAYER_2_ID then
    if input:get_key_held(ScanCode.W) then dir = 1 end
    if input:get_key_held(ScanCode.S) then dir = -1 end
  end

  return dir
end

local function apply_host_state(scene)
  local state = net:consume_state()
  if not state or not ball then
    return
  end

  local ball_body = Physics.get_body(ball)
  local position = ball_body:get_position()
  local diff_x = state.ball_x - position.x
  local diff_y = state.ball_y - position.y

  if (diff_x * diff_x + diff_y * diff_y) > (Config.NET.BALL_SNAP_DISTANCE * Config.NET.BALL_SNAP_DISTANCE) then
    ball_body:set_position(scene, vec3.new(state.ball_x, state.ball_y, 0))
    ball_body:set_linear_velocity(vec3.new(state.ball_vx, state.ball_vy, 0))
  else
    ball_body:set_linear_velocity(vec3.new(
      state.ball_vx + diff_x * Config.NET.BALL_CORRECTION_GAIN,
      state.ball_vy + diff_y * Config.NET.BALL_CORRECTION_GAIN,
      0
    ))
  end
end

local function broadcast_world_state()
  if not ball or not player1 then
    return
  end

  local ball_body = Physics.get_body(ball)

  net:broadcast_state(
    Physics.get_body(player1):get_position().y,
    ball_body:get_position(),
    ball_body:get_linear_velocity()
  )
end

function on_scene_render(scene)
  if not scene:is_running() then
    return
  end

  ui:draw_debuggers()
end

function on_scene_update(scene, dt)
  -- Play mode enables the update phases before runtime_start, so this can fire before on_scene_start.
  if not ui or not net then
    return
  end

  local net_tick = net:tick()

  ui:update()

  if net:is_client() then
    apply_host_state(scene)

    if net_tick and player2 then
      net:send_paddle(Physics.get_body(player2):get_position().y)
    end
  end

  if ui.current_state == UI.GameState.Scoring then
    spawn_timer = spawn_timer - dt

    local current_number = math.ceil(spawn_timer)

    if current_number > 0 then
      ui.data_model.countdown_value = string.format("%d", current_number)
    else
      ui.data_model.countdown_value = ""
    end

    ui:display_game_end_ui()

    -- The host decides when the next round starts, clients wait for the `round` call.
    if spawn_timer <= 0.0 and not net:is_client() and ball then
      ui.current_state = UI.GameState.Playing

      ui:hide_game_end_ui()

      local body = Physics.get_body(ball)
      local bc_data = ball:get(components.BallComponent)

      body:set_linear_velocity(vec3.new(bc_data.speed, 0, 0))

      net:broadcast_round_reset()
    end
  end

  if net_tick and net:is_host() then
    broadcast_world_state()
  end
end

function on_scene_start(scene)
  Assets.load_assets(WORKING_DIR)

  create_background(scene)

  net = NetworkController.new()
  ui = UI.new(scene, net, start_match, stop_match)

  net.on_score = function(p1_score, p2_score, won_player_id)
    ui.data_model.p1_score = p1_score
    ui.data_model.p2_score = p2_score
    ui.data_model.won_player_id = won_player_id

    ui.current_state = UI.GameState.Scoring
    spawn_timer = 2.0
  end

  net.on_round_reset = function()
    ui.current_state = UI.GameState.Playing
    spawn_timer = 0.0

    ui:hide_game_end_ui()
  end

  scene
      :world()
      :system("ball_system", { Core.TransformComponent, components.BallComponent }, { flecs.OnUpdate }, function(it)
        if not ui or ui.current_state ~= UI.GameState.Playing then return end
        -- Goals and the anti-stall nudge are authority calls, the host owns them.
        if net:is_client() then return end

        local tc = it:field(0, Core.TransformComponent)
        local bc = it:field(1, components.BallComponent)

        for i = 1, it:count(), 1 do
          local tc_data = tc:at(i - 1)
          local bc_data = bc:at(i - 1)

          local entity = it:entity(i - 1)
          local body = Physics.get_body(entity)

          local current_velocity = body:get_linear_velocity()
          local MIN_X_SPEED = 1.5
          if math.abs(current_velocity.x) < MIN_X_SPEED then
            local escape_direction = (tc_data.position.x > 0) and -1 or 1

            local corrected_x = escape_direction * MIN_X_SPEED
            body:set_linear_velocity(vec3.new(corrected_x, current_velocity.y, 0))

            Oxlog.warn("Vertical lock detected! Injected horizontal velocity nudge.")
          end

          if tc_data.position.x > 6 then
            ui.current_state = UI.GameState.Scoring
            add_score(player1)
            reset_ball(scene, entity, body)
          end
          if tc_data.position.x < -6 then
            ui.current_state = UI.GameState.Scoring
            add_score(player2)
            reset_ball(scene, entity, body)
          end
        end
      end)

  scene
      :world()
      :system("player_system", { Core.TransformComponent, components.PlayerComponent }, { flecs.OnUpdate }, function(it)
        if not ui or not net then return end

        local tc = it:field(0, Core.TransformComponent)
        local pc = it:field(1, components.PlayerComponent)

        for i = 1, it:count(), 1 do
          local tc_data = tc:at(i - 1)
          local pc_data = pc:at(i - 1)

          local entity = it:entity(i - 1)
          local body = Physics.get_body(entity)
          local player_velocity = vec3.new(0)

          -- In local play we drive both paddles, online only the one this machine owns.
          local is_local = ui.local_player_id == nil or pc_data.id == ui.local_player_id

          if pc_data.is_ai then
            if ball then
              local ball_tc = ball:get(Core.TransformComponent)
              local ball_y = ball_tc.position.y
              local paddle_y = tc_data.position.y

              local diff_y = ball_y - paddle_y

              if math.abs(diff_y) > pc_data.ai_target_error then
                if diff_y > 0 then
                  player_velocity.y = pc_data.speed
                else
                  player_velocity.y = -pc_data.speed
                end
              end
            end
          elseif is_local then
            player_velocity.y = read_paddle_input(scene, pc_data.id) * pc_data.speed
          else
            local target_y, target_vy = net:opponent_paddle()

            if target_y then
              local diff_y = target_y - tc_data.position.y
              local follow_speed = pc_data.speed * Config.NET.PADDLE_FOLLOW_SPEED_SCALE
              local chase = target_vy + diff_y * Config.NET.PADDLE_FOLLOW_GAIN

              player_velocity.y = math.max(-follow_speed, math.min(follow_speed, chase))
            end
          end

          body:set_linear_velocity(player_velocity)
        end
      end)
end

function on_contact_added(scene, body1, body2)
  local ball_body = nil
  local paddle_body = nil
  local paddle_entity = nil

  local e1 = Physics.get_entity_from_body(body1, scene:world())
  local e2 = Physics.get_entity_from_body(body2, scene:world())

  if e1:has(components.BallComponent) and e2:has(components.PlayerComponent) then
    ball_body = body1
    paddle_body = body2
    paddle_entity = e2
  elseif e2:has(components.BallComponent) and e1:has(components.PlayerComponent) then
    ball_body = body2
    paddle_body = body1
    paddle_entity = e1
  end

  if ball_body and paddle_body then
    -- Bounces are part of the simulation, so only the authority computes them.
    if net:is_client() then
      return
    end

    local ball_pos = ball_body:get_position()
    local paddle_pos = paddle_body:get_position()

    local diff_y = ball_pos.y - paddle_pos.y

    local paddle_half_height = 0.5
    local relative_intersect = diff_y / paddle_half_height

    relative_intersect = math.max(-1, math.min(1, relative_intersect))

    local MAX_BOUNCE_ANGLE = math.rad(60)
    local bounce_angle = relative_intersect * MAX_BOUNCE_ANGLE

    local direction_x = (paddle_pos.x < 0) and 1 or -1

    local ball_speed = Config.BALL_SPEED

    local new_vel_x = direction_x * ball_speed * math.cos(bounce_angle)
    local new_vel_y = ball_speed * math.sin(bounce_angle)

    ball_body:set_linear_velocity(vec3.new(new_vel_x, new_vel_y, 0))
  end
end

function on_scene_stop()
  if ui then
    ui:deinit()
    ui = nil
  end
  if net then
    net:deinit()
    net = nil
  end
end
