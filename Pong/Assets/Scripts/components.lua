local Components = {
  PlayerComponent,
  BallComponent,
}

local vfs = App:get_vfs()
WORKING_DIR = vfs:is_mounted_dir(vfs:PROJECT_DIR()) and vfs:PROJECT_DIR() or vfs:APP_DIR()
Config = require_script(WORKING_DIR, "Scripts/config.lua")

function Components.init(scene)
  Components.PlayerComponent = Component.define(scene, "PlayerComponent", {
    id = { type = "u32", default = 0 },
    speed = Config.PLAYER_SPEED,
    score = 0,
    is_ai = false,
    ai_target_error = 0.5
  })
  Components.BallComponent = Component.define(scene, "BallComponent", {
    speed = Config.BALL_SPEED,
  })
end

return Components
