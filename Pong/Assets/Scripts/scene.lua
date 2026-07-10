local vfs = App:get_vfs()
WORKING_DIR = vfs:PROJECT_DIR()

Config = require_script(WORKING_DIR, "Scripts/config.lua")
Components = require_script(WORKING_DIR, "Scripts/components.lua")
Assets = require_script(WORKING_DIR, "Scripts/assets.lua")
UI = require_script(WORKING_DIR, "Scripts/ui.lua")
NetworkController = require_script(WORKING_DIR, "Scripts/network_controller.lua")

local spawn_timer = 0.0

local ball = {}
local player1 = {}
local player2 = {}

function on_add(scene)
  Components.init(scene)
end

function create_player(scene, player_id, starting_point)
  local am = App.mod.AssetManager

  local player = scene:create_entity("player", true)
  player:add(Components.PlayerComponent, { id = player_id, speed = Config.PLAYER_SPEED })
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

function create_ball(scene)
  local am = App.mod.AssetManager

  ball = scene:create_entity("ball", true)
  local tc = ball:get_mut(Core.TransformComponent)
  tc:set_scale(vec3.new(0.5, 0.5, 0.5))
  ball:add(Components.BallComponent)
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
  local top_wall = scene:create_entity("top_wall")
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

  local bottom_wall = scene:create_entity("bottom_wall")
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

function start_match(scene)
  create_walls(scene)

  player1 = create_player(scene, Config.PLAYER_1_ID, vec3.new(5, 0.0, 0))
  player2 = create_player(scene, Config.PLAYER_2_ID, vec3.new(-5, 0.0, 0))

  local p2_pc = player2:get_mut(Components.PlayerComponent)
  p2_pc:set_is_ai(UI.is_ai)
  p2_pc:set_ai_target_error(0.15)

  ball = create_ball(scene)

  add_starting_velocity(ball, ball:get(Components.BallComponent).speed)

  UI.current_state = UI.GameState.Playing
end

function reset_ball(scene, entity, body)
  body:set_position(scene, vec3.new(0, 0, 0))
  body:set_linear_velocity(vec3.new(0, 0, 0))

  spawn_timer = 2.0
end

function add_score(player)
  local pc = player:get_mut(Components.PlayerComponent)
  local new_score = pc.score + 1
  pc:set_score(new_score)

  if pc.id == Config.PLAYER_1_ID then
    UI.data_model.p1_score = new_score
  end
  if pc.id == Config.PLAYER_2_ID then
    UI.data_model.p2_score = new_score
  end

  UI.data_model.won_player_id = pc.id + 1

  Oxlog.info("Added score to player! ID:" .. pc.id .. " NewScore: " .. new_score)
end

function on_scene_render(scene)
  if not scene:is_running() then
    return
  end

  UI.draw_debuggers()
end

function on_scene_update(scene, dt)
  UI.update(scene, start_match)

  if UI.current_state == UI.GameState.Scoring then
    spawn_timer = spawn_timer - dt

    local current_number = math.ceil(spawn_timer)

    if current_number > 0 then
      UI.data_model.countdown_value = string.format("%d", current_number)
    else
      UI.data_model.countdown_value = ""
    end

    UI.display_game_end_ui()

    if spawn_timer <= 0.0 then
      UI.current_state = UI.GameState.Playing

      UI.hide_game_end_ui()

      local body = Physics.get_body(ball)
      local bc_data = ball:get(Components.BallComponent)

      body:set_linear_velocity(vec3.new(bc_data.speed, 0, 0))
    end
  end
end

function on_scene_start(scene)
  Assets.load_assets(WORKING_DIR)

  UI.init(scene, start_match)

  scene
      :world()
      :system("ball_system", { Core.TransformComponent, Components.BallComponent }, { flecs.OnUpdate }, function(it)
        if UI.current_state ~= UI.GameState.Playing then return end

        local tc = it:field(0, Core.TransformComponent)
        local bc = it:field(1, Components.BallComponent)

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
            UI.current_state = UI.GameState.Scoring
            add_score(player1)
            reset_ball(scene, entity, body)
          end
          if tc_data.position.x < -6 then
            UI.current_state = UI.GameState.Scoring
            add_score(player2)
            reset_ball(scene, entity, body)
          end
        end
      end)

  scene
      :world()
      :system("player_system", { Core.TransformComponent, Components.PlayerComponent }, { flecs.OnUpdate }, function(it)
        local tc = it:field(0, Core.TransformComponent)
        local pc = it:field(1, Components.PlayerComponent)

        for i = 1, it:count(), 1 do
          local tc_data = tc:at(i - 1)
          local pc_data = pc:at(i - 1)

          local entity = it:entity(i - 1)
          local body = Physics.get_body(entity)
          local player_velocity = vec3.new(0)

          if not pc_data.is_ai then
            local input = App.mod.Input
            if pc_data.id == Config.PLAYER_1_ID then
              if input:get_key_held(ScanCode.Up) then player_velocity.y = pc_data.speed end
              if input:get_key_held(ScanCode.Down) then player_velocity.y = -pc_data.speed end
            elseif pc_data.id == Config.PLAYER_2_ID then
              if input:get_key_held(ScanCode.W) then player_velocity.y = pc_data.speed end
              if input:get_key_held(ScanCode.S) then player_velocity.y = -pc_data.speed end
            end
          else
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
          end

          body:set_linear_velocity(player_velocity)
        end
      end)

  scene
      :world()
      :system("server_tick", { Core.LightComponent }, { flecs.OnUpdate }, function(it)
        NetworkController.tick()
      end)
end

function on_contact_added(scene, body1, body2)
  local ball_body = nil
  local paddle_body = nil
  local paddle_entity = nil

  local e1 = Physics.get_entity_from_body(body1, scene:world())
  local e2 = Physics.get_entity_from_body(body2, scene:world())

  if e1:has(Components.BallComponent) and e2:has(Components.PlayerComponent) then
    ball_body = body1
    paddle_body = body2
    paddle_entity = e2
  elseif e2:has(Components.BallComponent) and e1:has(Components.PlayerComponent) then
    ball_body = body2
    paddle_body = body1
    paddle_entity = e1
  end

  if ball_body and paddle_body then
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
  UI.deinit()
  NetworkController.deinit()
end
