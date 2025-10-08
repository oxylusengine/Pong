#include <Core/EntryPoint.hpp>
#include <Core/App.hpp>

#include "GameLayer.hpp"

#include <filesystem>

namespace ox {
class PongApp : public ox::App {
public:
  PongApp(const ox::AppSpec& spec) : App(spec) { }
};

App* create_application(const AppCommandLineArgs& args) {
  AppSpec spec;
  spec.name = "Pong";
  spec.working_directory = std::filesystem::current_path().string();
  spec.command_line_args = args;
  spec.assets_path = "Assets";
  spec.headless = false;
  const WindowInfo::Icon icon = { };
  spec.window_info = {
	  .title = spec.name,
	  .icon = icon,
	  .width = 1720,
	  .height = 900,
#ifdef OX_PLATFORM_LINUX
	  .flags = WindowFlag::Centered,
#else
	  .flags = WindowFlag::Centered | WindowFlag::Resizable,
#endif
  };

  const auto app = new PongApp(spec);
  app->push_layer(std::make_unique<rog::GameLayer>());

  return app;
}
}