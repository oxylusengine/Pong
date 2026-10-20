#pragma once

#include <Core/App.hpp>
#include <Render/Utils/VukCommon.hpp>
#include <vuk/runtime/CommandBuffer.hpp>
#include <vuk/vsl/Core.hpp>

namespace pong {
auto apply_crt(
  vuk::Value<vuk::ImageAttachment>&& src, vuk::Value<vuk::ImageAttachment>&& dst, u32 frame_count, f32 elapsed_ms
) -> vuk::Value<vuk::ImageAttachment>;
}
