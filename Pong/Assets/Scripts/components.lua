-- Component ids are per flecs world, so every scene needs its own set. Sharing one module table
-- hands scene A the ids of whichever scene defined them last, and its entities then carry
-- components nothing in that world queries.
local Components = {}
Components.__index = Components

local vfs = App:get_vfs()
local WORKING_DIR = vfs:is_mounted_dir(vfs:PROJECT_DIR()) and vfs:PROJECT_DIR() or vfs:APP_DIR()
local Config = require_script(WORKING_DIR, "Scripts/config.lua")

function Components.new(scene)
  local self = setmetatable({}, Components)

  self.PlayerComponent = Component.define(scene, "PlayerComponent", {
    id = { type = "u32", default = 0 },
    speed = Config.PLAYER_SPEED,
    score = 0,
    is_ai = false,
    ai_target_error = 0.5
  })
  self.BallComponent = Component.define(scene, "BallComponent", {
    speed = Config.BALL_SPEED,
  })

  return self
end

return Components
