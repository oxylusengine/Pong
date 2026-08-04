#include "Game.hpp"

#include <Asset/AssetFile.hpp>
#include <Asset/AssetManager.hpp>
#include <Core/App.hpp>
#include <Core/Input.hpp>
#include <Core/Project.hpp>
#include <Render/RenderContext.hpp>
#include <Render/Utils/VukCommon.hpp>
#include <RmlUi/Core.h>
#include <UI/ImGuiRenderer.hpp>
#include <UI/RmlUI.hpp>
#include <UI/SceneHierarchyViewer.hpp>
#include <imgui.h>
#include <vuk/runtime/CommandBuffer.hpp>
#include <vuk/vsl/Core.hpp>

namespace pong {
auto apply_crt(
  vuk::Value<vuk::ImageAttachment>&& src, vuk::Value<vuk::ImageAttachment>&& dst, u32 frame_count, f32 elapsed_ms
) -> vuk::Value<vuk::ImageAttachment> {
  ZoneScoped;

  auto crt_pass = vuk::make_pass(
    "crt",
    [elapsed_ms](
      vuk::CommandBuffer& cmd_list, //
      VUK_IA(vuk::eColorWrite) target,
      VUK_IA(vuk::eFragmentSampled) source
    ) {
      cmd_list //
        .bind_graphics_pipeline("crt")
        .set_rasterization({})
        .set_color_blend(target, vuk::BlendPreset::eOff)
        .set_dynamic_state(vuk::DynamicStateFlagBits::eViewport | vuk::DynamicStateFlagBits::eScissor)
        .set_viewport(0, vuk::Rect2D::framebuffer())
        .set_scissor(0, vuk::Rect2D::framebuffer())
        .bind_image(0, 0, source)
        .bind_sampler(0, 1, vuk::LinearSamplerClamped)
        .push_constants(
          vuk::ShaderStageFlagBits::eFragment,
          0,
          ox::PushConstants(
            glm::vec2(target->extent.width, target->extent.height),
            glm::vec2(source->extent.width, source->extent.height),
            elapsed_ms
          )
        )
        .draw(3, 1, 0, 0);

      return std::make_tuple(target, source);
    }
  );

  auto [result, _] = crt_pass(std::move(dst), std::move(src));
  return result;
}

auto Game::init() -> std::expected<void, std::string> {
  ZoneScoped;

  auto& vfs = ox::App::get_vfs();
  auto& asset_man = ox::App::mod<ox::AssetManager>();

  auto scenes_dir = vfs.resolve_physical_dir(ox::VFS::APP_DIR, "Scenes");
  auto scripts_dir = vfs.resolve_physical_dir(ox::VFS::APP_DIR, "Scripts");
  auto fonts_dir = vfs.resolve_physical_dir(ox::VFS::APP_DIR, "Fonts");
  auto shaders_dir = vfs.resolve_physical_dir(ox::VFS::APP_DIR, "Shaders");

  auto shader_file = ox::AssetFile::unpack(shaders_dir / "game.oxpack");
  if (!shader_file.has_value()) {
    return std::unexpected("Failed to unpack game.oxpack!");
  }

  auto& render_context = ox::App::get_rendercontext();
  for (const auto& entry : shader_file->entries) {
    const auto* pipeline_data = std::get_if<ox::ShaderPipelineData>(&entry.data);
    if (!pipeline_data) {
      continue;
    }

    render_context.create_pipeline(*pipeline_data);
  }

  for (const auto* font : {"FiraSans-Regular.ttf", "FiraSans-Bold.ttf"}) {
    if (!Rml::LoadFontFace((fonts_dir / font).string())) {
      return std::unexpected(std::format("Failed to load RmlUI font face '{}'!", font));
    }
  }

  // This could be replaced by an API from Oxylus that can iterate over the given assets directory and
  // import the assets
  // Other assets are being loaded on runtime from lua.
  asset_man.import_asset(scripts_dir / "scene.lua.oxasset");

  main_scene = std::make_unique<ox::Scene>("MainScene");

  main_scene->load_from_file(scenes_dir / "main_scene.oxscene");

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
