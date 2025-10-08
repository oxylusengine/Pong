Assets = {
  player_sprite_asset = {},
  ball_sprite_asset = {},
}

function Assets.load_assets(WORKING_DIR)
  local asset_man = App:get_asset_manager()
  local vfs = App:get_vfs();

  local sprites_dir = vfs:resolve_physical_dir(WORKING_DIR, "Sprites")

  Assets.player_sprite_asset = asset_man:import_asset(sprites_dir .. "/player.png.oxasset")
  asset_man:load_asset(Assets.player_sprite_asset)
  Assets.ball_sprite_asset = asset_man:import_asset(sprites_dir .. "/ball.png.oxasset")
  asset_man:load_asset(Assets.ball_sprite_asset)
end

return Assets
