#pragma once

#include <Scene/Scene.hpp>

namespace pong {
class Game {
public:
  constexpr static auto MODULE_NAME = "Pong";

  auto init() -> std::expected<void, std::string>;
  auto deinit() -> std::expected<void, std::string>;
  auto update(const ox::Timestep& timestep) -> void;

  std::unique_ptr<ox::Scene> main_scene = nullptr;
};
} // namespace rog
