#include "Game.hpp"

#include <Asset/AssetManager.hpp>
#include <Core/App.hpp>
#include <Core/Input.hpp>
#include <Core/Project.hpp>
#include <UI/ImGuiRenderer.hpp>
#include <UI/SceneHierarchyViewer.hpp>
#include <imgui.h>

namespace rog {
auto Game::init() -> std::expected<void, std::string> {
  ZoneScoped;

  const auto* app = ox::App::get();
  auto& vfs = app->get_vfs();

  auto scenes_dir = vfs.resolve_physical_dir(ox::VFS::APP_DIR, "Scenes");

#if 0
  auto models_dir = vfs->resolve_physical_dir(ox::VFS::APP_DIR, "Models");
  auto scripts_dir = vfs->resolve_physical_dir(ox::VFS::APP_DIR, "Scripts");

  asset_man->import_asset(models_dir + "/map.glb.oxasset");
  asset_man->import_asset(models_dir + "/player.glb.oxasset");
  asset_man->import_asset(scripts_dir + "/camera.lua.oxasset");
  asset_man->import_asset(scripts_dir + "/scene.lua.oxasset");
#endif

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
}

auto Game::render(vuk::Extent3D extent, vuk::Format format) -> void {
  ZoneScoped;

  ox::SceneHierarchyViewer scene_hierarchy_viewer(main_scene.get());
  bool visible = true;
  scene_hierarchy_viewer.render("SceneHierarchyViewer", &visible);

  const auto* app = ox::App::get();
  auto& imgui = ox::App::mod<ox::ImGuiRenderer>();

  main_scene->on_render(extent, format);

  auto renderer_instance = main_scene->get_renderer_instance();
  if (renderer_instance != nullptr) {
    const ox::Renderer::RenderInfo render_info = {
      .extent = extent,
      .format = format,
    };
    auto scene_view_image = renderer_instance->render(render_info);

    ImGui::Begin("SceneView");
    ImGui::Image(imgui.add_image(std::move(scene_view_image)), ImVec2{extent.width / 2.f, extent.height / 2.f});
    ImGui::End();
  }
}
} // namespace rog
