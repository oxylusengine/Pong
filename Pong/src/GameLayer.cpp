#include "GameLayer.hpp"

#include <Asset/AssetManager.hpp>
#include <Core/App.hpp>
#include <Core/Input.hpp>
#include <Core/Project.hpp>
#include <UI/ImGuiLayer.hpp>
#include <UI/SceneHierarchyViewer.hpp>
#include <imgui.h>

namespace rog {
GameLayer* GameLayer::instance_ = nullptr;

GameLayer::GameLayer() : Layer("Game Layer") {
  ZoneScoped;
  instance_ = this;
}

void GameLayer::on_attach() {
  ZoneScoped;

  const auto* app = ox::App::get();
  auto* vfs = app->get_vfs();
  auto* asset_man = app->get_asset_manager();

  auto scenes_dir = vfs->resolve_physical_dir(ox::VFS::APP_DIR, "Scenes");
  auto models_dir = vfs->resolve_physical_dir(ox::VFS::APP_DIR, "Models");
  auto scripts_dir = vfs->resolve_physical_dir(ox::VFS::APP_DIR, "Scripts");

  asset_man->import_asset(models_dir + "/map.glb.oxasset");
  asset_man->import_asset(models_dir + "/player.glb.oxasset");
  asset_man->import_asset(scripts_dir + "/camera.lua.oxasset");
  asset_man->import_asset(scripts_dir + "/scene.lua.oxasset");

  main_scene = std::make_unique<ox::Scene>("MainScene");
  main_scene->load_from_file(scenes_dir + "/main_scene.oxscene");

  main_scene->runtime_start();
}

void GameLayer::on_detach() {
  ZoneScoped;
  main_scene->runtime_stop();
}

void GameLayer::on_update(const ox::Timestep& delta_time) {
  ZoneScoped;

  main_scene->runtime_update(delta_time);
}

void GameLayer::on_render(vuk::Extent3D extent, vuk::Format format) {
  ZoneScoped;

  ox::SceneHierarchyViewer scene_hierarchy_viewer(main_scene.get());
  bool visible = true;
  scene_hierarchy_viewer.render("SceneHierarchyViewer", &visible);

  const auto* app = ox::App::get();

  main_scene->on_render(extent, format);

  auto renderer_instance = main_scene->get_renderer_instance();
  if (renderer_instance != nullptr) {
    const ox::Renderer::RenderInfo render_info = {
        .extent = extent,
        .format = format,
        .picking_texel = {},
    };
    auto scene_view_image = renderer_instance->render(render_info);

    ImGui::Begin("SceneView");
    ImGui::Image(app->get_imgui_layer()->add_image(std::move(scene_view_image)),
                 ImVec2{extent.width / 2.f, extent.height / 2.f});
    ImGui::End();
  }
}
} // namespace rog
