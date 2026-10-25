#include <Core/App.hpp>
#include <Core/DefaultModules.hpp>
#include <Core/Enum.hpp>
#include <SDL3/SDL_filesystem.h>

#include "Game.hpp"

#if defined(OX_PLATFORM_WINDOWS)
constexpr auto SCRIPTS_LIBRARY = "Pong.dll";
#elif defined(OX_PLATFORM_MACOSX)
constexpr auto SCRIPTS_LIBRARY = "Pong.dylib";
#else
constexpr auto SCRIPTS_LIBRARY = "Pong.so";
#endif

int main(int argc, char** argv) {
  auto app = ox::App(argc, argv);
  app.with_name("Pong")
    .with_window({
      .title = "Pong",
      .icon = {},
      .width = 1200,
      .height = 900,
      .flags = ox::WindowFlag::Centered | ox::WindowFlag::HighPixelDensity,
    })
    .with_assets_directory("Assets")
    .with(ox::DefaultModules{});

  // the C# scripts, published with NativeAOT next to the executable
  ox::App::mod<ox::DotNetScripting>().startup = ox::DotNetLoadInfo{
    .kind = ox::DotNetHostKind::Aot,
    .path = std::filesystem::path(SDL_GetBasePath()) / "scripts" / SCRIPTS_LIBRARY,
  };

  app.with<pong::Game>().run();

  return 0;
}
