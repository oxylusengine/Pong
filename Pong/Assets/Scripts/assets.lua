-- Each handle holds a ref on its asset and drops it when collected, so they live in this table for
-- as long as the sprites are in use.
Assets = {
  player_sprite_asset = nil,
  ball_sprite_asset = nil,
  background_asset = nil,
}

function Assets.load_assets()
  local asset_man = App.mod.AssetManager

  Assets.player_sprite_asset = asset_man:acquire("Sprites/player.png")
  Assets.ball_sprite_asset = asset_man:acquire("Sprites/ball.png")
  Assets.background_asset = asset_man:acquire("Sprites/space_background.png")
end

return Assets
