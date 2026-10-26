#pragma once

#include <Asset/Texture.hpp>
#include <Scene/Scene.hpp>
#include <Scripting/DotNetScripting.hpp>
#include <vir/Program.hpp>

namespace pong {
class Game {
public:
  constexpr static auto MODULE_NAME = "Pong";
  // the scene's C# script has to be loaded before the scene names it
  using module_dependencies = std::tuple<ox::DotNetScripting>;

  auto init() -> std::expected<void, std::string>;
  auto deinit() -> std::expected<void, std::string>;
  auto update(const ox::Timestep& timestep) -> void;

  std::unique_ptr<ox::Scene> main_scene = nullptr;
  // what the scene renders into, and the program that draws it onto the swapchain image through the CRT pass, both
  // made again whenever the swapchain is replaced
  ox::Texture scene_target = {};
  std::unique_ptr<vir::Program> frame_program = nullptr;
  u64 frame_program_generation = 0;
  vir::ValueID crt_constants = vir::ValueID::Invalid;

  f32 elapsed_ms = 0.0f;

private:
  auto prepare_frame(const ox::SwapchainInfo& swapchain) -> bool;
};
} // namespace pong
