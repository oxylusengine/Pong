#pragma once

#include <Scene/Scene.hpp>
#include <Scripting/DotNetScripting.hpp>

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

  u32 frame_count = 0;
  f32 elapsed_ms = 0.f;
};
} // namespace pong
