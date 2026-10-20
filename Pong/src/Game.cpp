#include "Game.hpp"

#include <Asset/AssetFile.hpp>
#include <Asset/AssetManager.hpp>
#include <Core/App.hpp>
#include <Core/Input.hpp>
#include <Core/VFS.hpp>
#include <Render/RenderContext.hpp>
#include <RmlUi/Core.h>
#include <UI/ImGuiRenderer.hpp>
#include <UI/RmlUI.hpp>
#include <imgui.h>

#include "CRT.hpp"

namespace pong {
auto Game::init() -> std::expected<void, std::string> {
  ZoneScoped;

  auto shaders_dir = ox::App::get_vfs().resolve_physical_dir(ox::VFS::APP_DIR, "Shaders");

  auto shader_file = ox::AssetFile::unpack(shaders_dir / "game.oxpack");
  if (!shader_file.has_value()) {
    return std::unexpected("Failed to unpack game.oxpack!");
  }

  auto& render_context = ox::App::get_rendercontext();
  render_context.load_shader_pack(shader_file.value());

  for (const auto* font : {"FiraSans-Regular.ttf", "FiraSans-Bold.ttf"}) {
    // the game's own fonts, cooked with the rest of its assets. Virtual, so RmlUi finds the pack once the source is
    // gone
    if (!Rml::LoadFontFace(std::format("{}/Fonts/{}", ox::VFS::ASSETS_DIR, font))) {
      return std::unexpected(std::format("Failed to load RmlUI font face '{}'!", font));
    }
  }

  // by the asset the cook registered rather than by file, so the scene still loads once a cooked format replaces it
  auto& asset_man = ox::App::mod<ox::AssetManager>();
  const auto main_scene_path = std::filesystem::path(ox::VFS::ASSETS_DIR) / "Scenes/main_scene.oxscene";
  const auto main_scene_uuid = asset_man.find_asset(main_scene_path);
  if (!main_scene_uuid) {
    return std::unexpected(
      std::format("'{}' isn't a registered asset, are the assets cooked?", main_scene_path.string())
    );
  }

  main_scene = std::make_unique<ox::Scene>("MainScene");
  if (!main_scene->load_from_asset(main_scene_uuid)) {
    return std::unexpected(std::format("Failed to load '{}'!", main_scene_path.string()));
  }
  main_scene->runtime_start();

  return {};
}

auto Game::deinit() -> std::expected<void, std::string> {
  ZoneScoped;

  main_scene->runtime_stop();

  return {};
}

auto Game::update(const ox::Timestep& timestep) -> void {
  ZoneScoped;

  main_scene->runtime_update(timestep);

  frame_count += 1;
  elapsed_ms += static_cast<f32>(timestep.get_millis());

  auto& vk_context = ox::App::get_rendercontext();
  auto& imgui_renderer = ox::App::mod<ox::ImGuiRenderer>();
  auto& window = ox::App::get_window();

  auto swapchain_attachment = vk_context.new_frame();
  swapchain_attachment = vuk::clear_image(std::move(swapchain_attachment), vuk::Black<f32>);

  auto scene_attachment = vuk::declare_ia(
    "scene",
    {
      .usage = vuk::ImageUsageFlagBits::eColorAttachment | vuk::ImageUsageFlagBits::eSampled,
      .extent = swapchain_attachment->extent,
      .sample_count = vuk::Samples::e1,
      .level_count = 1,
      .layer_count = 1,
    }
  );
  scene_attachment.same_format_as(swapchain_attachment);
  scene_attachment = vuk::clear_image(std::move(scene_attachment), vuk::Black<f32>);

  imgui_renderer.begin_frame(timestep.get_seconds(), window.get_logical_size(), window.get_real_size());

  main_scene->set_rml_dpi_ratio(window.get_dpi_scale());

  auto scene_view_image = main_scene->render(
    std::move(scene_attachment),
    glm::ivec2{0, 0},
    window.get_logical_size(),
    window.get_real_size()
  );

  scene_view_image = apply_crt(std::move(scene_view_image), std::move(swapchain_attachment), frame_count, elapsed_ms);

  scene_view_image = imgui_renderer.end_frame(vk_context, std::move(scene_view_image));

  vk_context.end_frame(scene_view_image);
}
} // namespace pong
