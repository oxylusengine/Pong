#include "Game.hpp"

#include <Asset/AssetManager.hpp>
#include <Core/App.hpp>
#include <Core/Input.hpp>
#include <Core/Project.hpp>
#include <UI/ImGuiRenderer.hpp>
#include <UI/SceneHierarchyViewer.hpp>
#include <imgui.h>

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
}

auto Game::render(vuk::Extent3D extent, vuk::Format format) -> void {
  ZoneScoped;

  auto& imgui = ox::App::mod<ox::ImGuiRenderer>();

  main_scene->on_render(extent, format);

  auto renderer_instance = main_scene->get_renderer_instance();
  if (renderer_instance != nullptr) {
    const ox::Renderer::RenderInfo render_info = {
      .extent = extent,
      .format = format,
    };
    auto scene_view_image = renderer_instance->render(render_info);

    const ImGuiViewport* viewport = ImGui::GetMainViewport();
    ImGui::SetNextWindowPos(viewport->WorkPos);
    ImGui::SetNextWindowSize(viewport->WorkSize);

    constexpr ImGuiWindowFlags flags = ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_NoMove |
                                       ImGuiWindowFlags_NoSavedSettings | ImGuiWindowFlags_NoTitleBar |
                                       ImGuiWindowFlags_NoCollapse;

    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2{});

    if (ImGui::Begin("SceneView", nullptr, flags)) {
      ImGui::Image(
        imgui.add_image(std::move(scene_view_image)),
        ImVec2{static_cast<ox::f32>(extent.width), static_cast<ox::f32>(extent.height)}
      );
    }
    ImGui::End();

    ImGui::PopStyleVar();
  }
}
} // namespace pong
