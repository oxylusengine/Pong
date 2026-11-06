#include "Game.hpp"

#include <Asset/AssetFile.hpp>
#include <Asset/AssetManager.hpp>
#include <Core/App.hpp>
#include <Core/Input.hpp>
#include <Core/VFS.hpp>
#include <Render/RenderContext.hpp>
#include <RmlUi/Core.h>
#include <span>
#include <utility>
#include <vir/Module.hpp>

#include "CRT.hpp"

namespace pong {
auto Game::init() -> std::expected<void, std::string> {
  ZoneScoped;

  if (!ox::App::mod<ox::DotNetScripting>().is_loaded()) {
    return std::unexpected("The game's C# scripts didn't load, see the log for why");
  }

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
  // before DotNetScripting deinits, the scene's C# script lives in it
  main_scene.reset();
  frame_program.reset();
  scene_target = {};

  return {};
}

auto Game::update(const ox::Timestep& timestep) -> void {
  ZoneScoped;

  main_scene->runtime_update(timestep);

  elapsed_ms += static_cast<f32>(timestep.get_millis());

  auto& render_context = ox::App::get_rendercontext();
  auto& window = ox::App::get_window();

  const auto frame = render_context.new_frame();
  if (!frame) {
    // a minimized window has no swapchain to draw into
    if (frame.error() != VK_NOT_READY) {
      OX_LOG_ERROR("Couldn't start a frame ({})", std::to_underlying(frame.error()));
    }

    return;
  }

  if ((!frame_program || frame_program_generation != frame->generation) && !prepare_frame(*frame)) {
    return;
  }

  main_scene->set_rml_dpi_ratio(window.get_dpi_scale());
  const auto rendered = main_scene->render(
    scene_target.attachment_info(),
    glm::ivec2{0, 0},
    window.get_logical_size(),
    window.get_real_size()
  );
  if (!rendered) {
    OX_LOG_ERROR("Couldn't render the scene ({})", std::to_underlying(rendered.error()));
    return;
  }

  const auto size = glm::vec2(frame->extent.width, frame->extent.height);
  const auto constants = CrtConstants(size, size, elapsed_ms);
  frame_program->set_bytes(crt_constants, std::span<const u8>(constants.struct_data));

  const auto ticket = render_context.execute(*frame_program);
  if (!ticket) {
    if (ticket.error() == VK_ERROR_OUT_OF_DATE_KHR) {
      frame_program.reset();
      render_context.handle_resize();
      return;
    }

    OX_LOG_ERROR("Couldn't present the frame ({})", std::to_underlying(ticket.error()));
    return;
  }

  // anything released this frame waits for everything the frame submitted
  render_context.seal_retirements(*ticket);
}

auto Game::prepare_frame(const ox::SwapchainInfo& swapchain) -> bool {
  ZoneScoped;

  auto& render_context = ox::App::get_rendercontext();
  frame_program.reset();
  scene_target = ox::Texture::create({
    .format = swapchain.format,
    .extent = vir::Extent3D{swapchain.extent.width, swapchain.extent.height, 1},
    .usage = vir::ImageUsageFlags::ColorAttachment | vir::ImageUsageFlags::Sampled | vir::ImageUsageFlags::TransferSrc |
             vir::ImageUsageFlags::TransferDst,
  });
  // the program reads it at rest, so it has to be there before the scene first draws into it
  const auto black = vir::ClearValue::rgba_f32(0.0f, 0.0f, 0.0f, 1.0f);
  if (const auto cleared = scene_target.clear(black, vir::Access::FragmentSampled); !cleared) {
    OX_LOG_ERROR("Couldn't clear the scene's target ({})", std::to_underlying(cleared.error()));
    return false;
  }

  auto module = vir::Module{};
  crt_constants = module.declare_bytes_var("crt constants", static_cast<u32>(CrtConstants::TOTAL_SIZE));
  auto image = render_context.acquire_next_image(module);
  image = record_crt(module, scene_target.import(module, vir::Access::FragmentSampled), image, crt_constants);
  module.present(image);

  auto compiled = render_context.compile(std::move(module));
  if (!compiled) {
    OX_LOG_ERROR("Couldn't compile the frame ({})", std::to_underlying(compiled.error()));
    return false;
  }

  frame_program = std::make_unique<vir::Program>(std::move(*compiled));
  frame_program_generation = swapchain.generation;
  return true;
}
} // namespace pong
