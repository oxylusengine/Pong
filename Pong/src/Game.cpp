#include "Game.hpp"

#include <Asset/AssetManager.hpp>
#include <Core/App.hpp>
#include <Core/Input.hpp>
#include <Core/Project.hpp>
#include <UI/ImGuiRenderer.hpp>
#include <UI/SceneHierarchyViewer.hpp>
#include <imgui.h>
#include <vuk/vsl/Core.hpp>

namespace pong {
auto Game::init() -> std::expected<void, std::string> {
  ZoneScoped;

  auto& vfs = ox::App::get_vfs();
  auto& asset_man = ox::App::mod<ox::AssetManager>();

  auto scenes_dir = vfs.resolve_physical_dir(ox::VFS::APP_DIR, "Scenes");
  auto scripts_dir = vfs.resolve_physical_dir(ox::VFS::APP_DIR, "Scripts");

  // This could be replaced by an API from Oxylus that can iterate over the given assets directory and
  // import the assets
  // Other assets are being loaded on runtime from lua.
  asset_man.import_asset(scripts_dir + "/scene.lua.oxasset");

  main_scene = std::make_unique<ox::Scene>("MainScene");

  main_scene->load_from_file(scenes_dir + "/main_scene.oxscene");

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

  auto& vk_context = ox::App::get_vkcontext();
  auto& imgui_renderer = ox::App::mod<ox::ImGuiRenderer>();
  auto& window = ox::App::get_window();

  auto swapchain_attachment = vk_context.new_frame();
  swapchain_attachment = vuk::clear_image(std::move(swapchain_attachment), vuk::Black<ox::f32>);

  vuk::Format format = swapchain_attachment->format;
  vuk::Extent3D extent = swapchain_attachment->extent;

  imgui_renderer.begin_frame(timestep.get_seconds(), {window.get_logical_width(), window.get_logical_height()});

  main_scene->on_render(extent, format);

  auto renderer_instance = main_scene->get_renderer_instance();
  const ox::Renderer::RenderInfo render_info = {};
  auto scene_view_image = renderer_instance->render(std::move(swapchain_attachment), render_info);

  scene_view_image = imgui_renderer.end_frame(vk_context, std::move(scene_view_image));

  vk_context.end_frame(scene_view_image);
}
} // namespace pong
