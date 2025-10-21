#include <Asset/AssetManager.hpp>
#include <Core/App.hpp>
#include <Core/EntryPoint.hpp>
#include <Core/Enum.hpp>
#include <Core/Input.hpp>
#include <Networking/NetworkManager.hpp>
#include <Physics/Physics.hpp>
#include <Scripting/LuaManager.hpp>
#include <UI/ImGuiRenderer.hpp>

#include "Game.hpp"

namespace ox {
class PongApp : public ox::App {
public:
  PongApp() : App() {}
};

App* create_application(const AppCommandLineArgs& args) {
  const auto app = new PongApp();
  app->with_name("Pong")
    .with_args(args)
    .with_window({
      .title = "Pong",
      .icon = {},
      .width = 1720,
      .height = 900,
      .flags = WindowFlag::Centered | WindowFlag::Resizable,
    })
    .with<AssetManager>()
    .with<AudioEngine>()
    .with<Physics>()
    .with<Input>()
    .with<NetworkManager>()
    .with<LuaManager>()
    .with<ImGuiRenderer>()
    .with<rog::Game>();

  return app;
}
} // namespace ox
