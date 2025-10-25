local vfs = App:get_vfs()
WORKING_DIR = vfs:APP_DIR()

screen_size = {}

Components = {
  PlayerComponent,
  BallComponent,
}

Config = require_script(WORKING_DIR, 'Scripts/config.lua')
Assets = require_script(WORKING_DIR, 'Scripts/assets.lua')

function on_add(scene)
  Components.PlayerComponent = Component.define(scene, "PlayerComponent", {
    id = { type = "u32", default = 0 },
  })
  Components.BallComponent = Component.define(scene, "BallComponent", {
    speed = Config.BALL_SPEED,
    radius = 32, -- TODO: IDK how big is the ball in pixels
  })
end

function create_player(scene, player_id, starting_point)
  local am = App.mod.AssetManager

  local player = scene:create_entity("player", true)
  player:add(Components.PlayerComponent, { id = player_id })
  player:add(Core.SpriteComponent)

  local sc = player:get_mut(Core.SpriteComponent)
  local mat = am:get_mut_material(sc.material)
  mat:set_albedo_texture(Assets.player_sprite_asset)
  mat:set_sampling_mode(SamplingMode.NearestClamped)

  local player_tc = player:get_mut(Core.TransformComponent)
  player_tc:set_position(starting_point)
  player:modified(Core.TransformComponent)

  player:add(Core.BoxColliderComponent, {
    friction = 0,
    restitution = 1,
  })
  player:add(Core.RigidBodyComponent, {
    type = 1, -- kinematic
    gravity_factor = 0,
    friction = 0,
    restitution = 1,
    linear_drag = 0,
    angular_drag = 0,
  })
  player:modified(Core.RigidBodyComponent)

  return player
end

function reset_ball(tc)
  tc:set_x(0)
  tc:set_y(0)
end

function add_starting_velocity(ball, speed)
  local body = Physics.get_body(ball)
  body:set_linear_velocity(vec3.new(speed, 0, 0))
end

function create_ball(scene)
  local am = App.mod.AssetManager

  local ball = scene:create_entity("ball", true)
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
  })
  ball:modified(Core.RigidBodyComponent)

  return ball
end

function on_scene_start(scene)
  screen_size = vec2.new(0, 0)

  Assets.load_assets(WORKING_DIR)

  local player1 = create_player(scene, Config.PLAYER_1_ID, vec3.new(5, 0.0, 0))
  local player2 = create_player(scene, Config.PLAYER_2_ID, vec3.new(-5, 0.0, 0))
  local ball = create_ball(scene)

  add_starting_velocity(ball, ball:get(Components.BallComponent).speed)

  scene:world():system("ball_system", { Core.TransformComponent, Components.BallComponent }, { flecs.OnUpdate },
    function(it)
      local tc = it:field(0, Core.TransformComponent)
      local bc = it:field(1, Components.BallComponent)

      for i = 1, it:count(), 1 do
        local tc_data = tc:at(i - 1)
        local bc_data = bc:at(i - 1)

        local entity = it:entity(i - 1)
        local body = Physics.get_body(entity)

        -- check if its out of screen bounds then bounce
        if (tc_data.position.y - bc_data.radius) <= 0.0 then
          local ball_velocity = body:get_linear_velocity()
          ball_velocity.y = ball_velocity.y * -1
          body:set_linear_velocity(ball_velocity)
        end

        if (tc_data.position.y + bc_data.radius) >= screen_size.y then
          local ball_velocity = body:get_linear_velocity()
          ball_velocity.y = ball_velocity.y * -1
          body:set_linear_velocity(ball_velocity)
        end
      end
    end
  )
end

function on_viewport_render(scene)

end

function on_scene_render(scene, extent, format)
  screen_size = vec2.new(extent.x, extent.y)
end

function on_contact_added(scene, body1, body2)

end
