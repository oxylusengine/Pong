local vfs = App:get_vfs()
WORKING_DIR = vfs:PROJECT_DIR()

Components = {
  PlayerComponent,
  BallComponent,
}

Config = require_script(WORKING_DIR, 'Scripts/config.lua')
Assets = require_script(WORKING_DIR, 'Scripts/assets.lua')

ball = {}
player1 = {}
player2 = {}

function on_add(scene)
  Components.PlayerComponent = Component.define(scene, "PlayerComponent", {
    id = { type = "u32", default = 0 },
    speed = Config.PLAYER_SPEED,
    score = 0
  })
  Components.BallComponent = Component.define(scene, "BallComponent", {
    speed = Config.BALL_SPEED,
  })
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

  local player_tc = player:get_mut(Core.TransformComponent)
  player_tc:set_position(starting_point)
  player_tc:set_scale(vec3.new(0.5, 2, 1))
  player:modified(Core.TransformComponent)

  player:add(Core.BoxColliderComponent, {
    friction = 0,
    restitution = 1,
    size = vec3.new(0.25, 1, 1.0)
  })
  player:add(Core.RigidBodyComponent, {
    type = 1, -- kinematic
    gravity_factor = 0,
    friction = 0,
    restitution = 1,
    linear_drag = 0,
    angular_drag = 0,
    allow_sleep = false,
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

  local ball = scene:create_entity("ball", true)
  local tc = ball:get_mut(Core.TransformComponent)
  tc:set_scale(vec3.new(0.5, 0.5, 0.5))
  ball:add(Components.BallComponent)
  ball:add(Core.SpriteComponent)

  local sc = ball:get_mut(Core.SpriteComponent)
  local mat = am:get_mut_material(sc.material)
  mat:set_albedo_texture(Assets.ball_sprite_asset)
  mat:set_sampling_mode(SamplingMode.NearestClamped)

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
    size = vec3.new(10, 0.2, 1)
  })
  top_wall:add(Core.RigidBodyComponent, {
    type = 1,
    gravity_factor = 0,
    friction = 0,
    restitution = 1,
    linear_drag = 0,
    angular_drag = 0
  })
  top_wall:modified(Core.RigidBodyComponent)

  local bottom_wall = scene:create_entity("bottom_wall")
  bottom_wall:get_mut(Core.TransformComponent):set_position(vec3.new(0, -5, 0))
  bottom_wall:add(Core.BoxColliderComponent, {
    friction = 0,
    restitution = 1,
    size = vec3.new(10, 0.2, 1)
  })
  bottom_wall:add(Core.RigidBodyComponent, {
    type = 1,
    gravity_factor = 0,
    friction = 0,
    restitution = 1,
    linear_drag = 0,
    angular_drag = 0,
  })
  bottom_wall:modified(Core.RigidBodyComponent)
end

function on_scene_start(scene)
  Assets.load_assets(WORKING_DIR)

  create_walls(scene)

  player1 = create_player(scene, Config.PLAYER_1_ID, vec3.new(8, 0.0, 0))
  player2 = create_player(scene, Config.PLAYER_2_ID, vec3.new(-8, 0.0, 0))
  ball = create_ball(scene)

  add_starting_velocity(ball, ball:get(Components.BallComponent).speed)

  local reset_ball = function(body, speed)
    body:set_position(scene, vec3.new(0, 0, 0))
    body:set_linear_velocity(vec3.new(0, 0, 0))
    body:set_linear_velocity(vec3.new(speed, 0, 0)) -- starting velocity
  end

  local add_score = function(player)
    local pc = player:get_mut(Components.PlayerComponent)
    local new_score = pc.score + 1
    pc:set_score(new_score)
  end

  scene:world():system("ball_system", { Core.TransformComponent, Components.BallComponent }, { flecs.OnUpdate },
    function(it)
      local tc = it:field(0, Core.TransformComponent)
      local bc = it:field(1, Components.BallComponent)

      for i = 1, it:count(), 1 do
        local tc_data = tc:at(i - 1)
        local bc_data = bc:at(i - 1)

        local entity = it:entity(i - 1)
        local body = Physics.get_body(entity)

        local vel = body:get_linear_velocity()

        if (tc_data.position.x > 9) then
          reset_ball(body, bc_data.speed)
          add_score(player1)
        end
        if (tc_data.position.x < -9) then
          reset_ball(body, bc_data.speed)
          add_score(player2)
        end
      end
    end
  )

  scene:world():system("player_system", { Core.TransformComponent, Components.PlayerComponent }, { flecs.OnUpdate },
    function(it)
      local tc = it:field(0, Core.TransformComponent)
      local pc = it:field(1, Components.PlayerComponent)

      for i = 1, it:count(), 1 do
        local tc_data = tc:at(i - 1)
        local pc_data = pc:at(i - 1)

        local entity = it:entity(i - 1)
        local body = Physics.get_body(entity)

        local input = App.mod.Input

        local player_velocity = vec3.new(0)

        if input:get_key_held(KeyCode.W) then
          player_velocity = vec3.new(0, pc_data.speed, 0)
        end
        if input:get_key_held(KeyCode.S) then
          player_velocity = vec3.new(0, -pc_data.speed, 0)
        end

        body:set_linear_velocity(player_velocity)
      end
    end
  )
end

function on_scene_render(scene, extent, format)
  if ImGui.Begin("Physics Debug") then
    local ballbody = Physics.get_body(ball)
    local ballvel = ballbody:get_linear_velocity()
    ImGui.TextUnformatted("x:" .. tostring(ballvel.x))
    ImGui.TextUnformatted("y:" .. tostring(ballvel.y))
    ImGui.TextUnformatted("z:" .. tostring(ballvel.z))
  end
  ImGui.End()

  -- if ImGui.Begin("Player Score Debug View") then
  --   ImGui.TextUnformatted("Player 1:" .. player1:get_mut(Components.PlayerComponent).score)
  --   ImGui.TextUnformatted("Player 2:" .. player2:get_mut(Components.PlayerComponent).score)
  -- end
  -- ImGui.End()
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
        
        -- 1. Calculate relative impact point on paddle (from -0.5 to 0.5 roughly)
        local diff_y = ball_pos.y - paddle_pos.y
        
        -- 2. Normalize it based on paddle height
        -- Paddle height is 1.0
        local paddle_half_height = 0.5 
        local relative_intersect = diff_y / paddle_half_height
        
        -- Clamp it between -1 and 1 to prevent weird bugs if it hits the very corner
        relative_intersect = math.max(-1, math.min(1, relative_intersect))

        -- 3. Calculate new bounce angle
        local MAX_BOUNCE_ANGLE = math.rad(60) -- 60 degrees in radians
        local bounce_angle = relative_intersect * MAX_BOUNCE_ANGLE

        -- 4. Calculate new Velocity Vector
        -- We need to know which direction to shoot (Left or Right)
        -- If paddle is on the Left (x < 0), shoot Right (positive X)
        -- If paddle is on the Right (x > 0), shoot Left (negative X)
        local direction_x = (paddle_pos.x < 0) and 1 or -1
        
        local ball_speed = Config.BALL_SPEED
        
        local new_vel_x = direction_x * ball_speed * math.cos(bounce_angle)
        local new_vel_y = ball_speed * math.sin(bounce_angle)

        ball_body:set_linear_velocity(vec3.new(new_vel_x, new_vel_y, 0))
    end
end