#include "CRT.hpp"

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
} // namespace pong
