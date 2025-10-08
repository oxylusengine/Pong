#pragma once
#include <Core/Layer.hpp>
#include <Scene/Scene.hpp>

namespace rog {
class GameLayer : public ox::Layer {
public:
  GameLayer();
  ~GameLayer() override = default;
  void on_attach() override;
  void on_detach() override;
  void on_update(const ox::Timestep& delta_time) override;
  void on_render(vuk::Extent3D extent, vuk::Format format) override;

  static GameLayer* get() { return instance_; }

private:
  static GameLayer* instance_;

  std::unique_ptr<ox::Scene> main_scene = nullptr;
};
} // namespace rog
