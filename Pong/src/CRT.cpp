#include "CRT.hpp"

#include <Core/App.hpp>
#include <Render/RenderContext.hpp>
#include <Render/Utils/Samplers.hpp>
#include <vir/Module.hpp>

namespace pong {
auto record_crt(vir::Module& module, vir::ValueID source, vir::ValueID target, vir::ValueID constants) -> vir::ValueID {
  ZoneScoped;

  auto& render_context = ox::App::get_rendercontext();
  return module //
    .begin_rendering({{target, vir::Access::ColorWrite}, {source, vir::Access::FragmentSampled}})
    .with_name("crt")
    .bind_graphics_pipeline(render_context.pipeline("crt"))
    .set_viewport(0, vir::Rect2D::framebuffer())
    .set_scissor(0, vir::Rect2D::framebuffer())
    .bind_image(0, 0, source)
    .bind_sampler(0, 1, render_context.cached_sampler_handle(ox::LinearSamplerClamped))
    .push_constants_from(constants)
    .draw(3, 1)
    .end_rendering()[0];
}
} // namespace pong
