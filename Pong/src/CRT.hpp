#pragma once

#include <Core/Types.hpp>
#include <Render/Utils/PushConstants.hpp>
#include <glm/vec2.hpp>
#include <vir/Fwd.hpp>

namespace pong {
// crt.slang's PushConstants: the output and source sizes in pixels, and the time in milliseconds
using CrtConstants = ox::PushConstants<glm::vec2, glm::vec2, f32>;

// draws `source` into `target` through the CRT shader, which reads its CrtConstants from `constants`, a bytes variable
// of CrtConstants::TOTAL_SIZE the program is handed each frame
auto record_crt(vir::Module& module, vir::ValueID source, vir::ValueID target, vir::ValueID constants) -> vir::ValueID;
} // namespace pong
