// converted to slang from https://github.com/artzox/CRT-Standalone/blob/main/CRT-Standalone.fx

import common;
import gpu;

// Resources only. Mixing plain data into a ParameterBlock pushes it into an implicit uniform
// buffer in a separate binding slot, so the per-frame scalars go through push constants instead.
struct CRTParameters {
  Texture2D<f32x4> source;
  Sampler linear_sampler;
};

struct PushConstants {
  f32x2 output_size;
  f32x2 texture_size;
  f32 timer; // In milliseconds
};

// Pre-Blur
static const float crt_preblur_h_sigma = 0.0;
static const float crt_preblur_h_radius = 6.0;
static const float crt_preblur_v_sigma = 0.0;
static const float crt_preblur_v_radius = 6.0;
static const int crt_preblur_luma_only = 1;
static const float crt_preblur_bilateral = 0.0;

// Mask
// Triad width is specified at 4K and scaled down by crt_mask_apply, so 12.0 lands on a
// 3px triad (one pixel per phosphor stripe) at 1080p instead of washing out sub-pixel.
static const float crt_triad_width = 12.0;
static const float crt_mask_strength = 0.85;
// Compensates for the light the mask and beam envelope swallow; both are applied in linear space.
static const float crt_mask_boost = 2.0;
static const float crt_phosphor_sharpness = 3.0;
static const float3 crt_phosphor_colour = float3(1.0, 1.0, 1.0);
static const int crt_mask_type = 0;
static const float crt_slot_mask_strength = 0.5;
static const float crt_mask_dither = 0.0;

// Scanlines
static const float crt_scanline_width = 4.0;
static const float crt_scanline_strength = 0.8;
// Tighter beam -> darker gutters between scanlines, and more bloom spread on bright pixels.
static const float crt_beam_min_sigma = 0.4;
static const float crt_beam_max_sigma = 0.9;
static const float crt_beam_shape = 2.0;
static const float crt_spot_size = 0.0;
// Per-row brightness/width variation from HV supply ripple. A static texture, not motion:
// drift is held at upstream's default of 0 so the pattern never moves.
static const float crt_scanline_roll_strength = 0.03;
static const float crt_scanline_roll_drift = 0.0;

// Gamma & BCS
static const float crt_gamma_in = 2.2;
static const float crt_gamma_out = 2.2;
static const float crt_brightness = 0.1;
static const float crt_contrast = 0.15;
static const float crt_saturation = 0.2;

// Glow & Halation
static const float crt_glow_strength = 0.0;
static const float crt_glow_h_radius = 12.0;
static const float crt_glow_v_radius = 3.0;
static const float crt_glow_sigma = 1.2;
static const float crt_halation_strength = 0.0;
static const float crt_halation_threshold = 0.6;
static const float crt_halation_radius = 6.0;
static const float crt_halation_sigma = 3.0;

f32 gauss(f32 x, f32 sigma) { return exp(-(x * x) / (2.0 * sigma * sigma)); }

f32 crt_erf(f32 x) {
  f32 t = 1.0 / (1.0 + 0.3275911 * abs(x));
  f32 p = t * (0.254829592 + t * (-0.284496736 + t * (1.421413741 + t * (-1.453152027 + t * 1.061405429))));
  return sign(x) * (1.0 - p * exp(-(x * x)));
}

f32 gauss_integral(f32 f, f32 hw, f32 sigma) {
  f32 s = max(sigma * 1.41421356, 0.0001);
  return 0.5 * (crt_erf((f + hw) / s) - crt_erf((f - hw) / s));
}

// --- Per-Scanline Row Variation ---

// Standalone integer hash, used by crt_scanline_roll.
u32 crt_row_hash(u32 x) {
  x ^= x >> 16u;
  x *= 0x45D9F3Bu;
  x ^= x >> 16u;
  return x;
}

// Per-scanline brightness variation. Spatially correlated low-frequency hash -- adjacent rows
// similar, not random. Models HV supply ripple and phosphor coating unevenness in real CRTs.
f32 crt_scanline_roll(f32 row) {
  f32 r = floor(row);

  // Cast through i32: row 0 asks for row -1, and converting a negative float straight to u32 is
  // undefined in SPIR-V. Going via i32 gives the two's-complement wrap the hash expects.
  u32 seed0 = crt_row_hash(u32(i32(r)));
  u32 seed1 = crt_row_hash(u32(i32(r + 1.0)));
  u32 seedm = crt_row_hash(u32(i32(r - 1.0)));

  f32 v0 = f32(seed0 & 0xFFFFu) / 32767.5 - 1.0;
  f32 v1 = f32(seed1 & 0xFFFFu) / 32767.5 - 1.0;
  f32 vm = f32(seedm & 0xFFFFu) / 32767.5 - 1.0;

  // Weighted average: 50% current row, 25% each neighbour.
  return v0 * 0.5 + (v1 + vm) * 0.25;
}

f32x3 crt_rgb_to_ycbcr(f32x3 rgb) {
  f32 Y = 0.2990 * rgb.r + 0.5870 * rgb.g + 0.1140 * rgb.b;
  f32 Cb = -0.1687 * rgb.r - 0.3313 * rgb.g + 0.5000 * rgb.b;
  f32 Cr = 0.5000 * rgb.r - 0.4187 * rgb.g - 0.0813 * rgb.b;
  return f32x3(Y, Cb, Cr);
}

f32x3 crt_ycbcr_to_rgb(f32x3 ycbcr) {
  return f32x3(ycbcr.x + 1.4020 * ycbcr.z, ycbcr.x - 0.3441 * ycbcr.y - 0.7141 * ycbcr.z, ycbcr.x + 1.7720 * ycbcr.y);
}

// --- Megatron Cubic Bezier BCS System ---

static const float4x4 kCubicBezier = float4x4(
  1.0f, 0.0f, 0.0f, 0.0f, -3.0f, 3.0f, 0.0f, 0.0f, 3.0f, -6.0f, 3.0f, 0.0f, -1.0f, 3.0f, -3.0f, 1.0f
);

f32 Bezier(f32 t, f32x4 cp) {
  f32x4 tv = f32x4(1.0, t, t * t, t * t * t);
  return dot(tv, mul(kCubicBezier, cp));
}

static const f32x4 kTopBrightness = f32x4(0.0, 1.0, 1.0, 1.0);
static const f32x4 kMidBrightness = f32x4(0.0, 1.0 / 3.0, 2.0 / 3.0, 1.0);
static const f32x4 kBotBrightness = f32x4(0.0, 0.0, 0.0, 1.0);

static const f32x4 kTopContrast = f32x4(0.0, 0.0, 1.0, 1.0);
static const f32x4 kMidContrast = f32x4(0.0, 1.0 / 3.0, 2.0 / 3.0, 1.0);
static const f32x4 kBotContrast = f32x4(0.0, 1.0, 0.0, 1.0);

f32x3 apply_bcs(f32x3 c, f32 brightness, f32 contrast, f32 saturation) {
  f32 ch_max = max(max(c.r, c.g), c.b);
  f32 Y_lin = max(ch_max, 0.0);
  f32 Y_peak = max(Y_lin, 1.0);
  f32 Y_norm = Y_lin / Y_peak;
  f32 Y_g = pow(Y_norm, 1.0 / 2.4);

  f32 Y_b = (brightness >= 0.0) ? Bezier(Y_g, lerp(kMidBrightness, kTopBrightness, brightness))
                                : Bezier(Y_g, lerp(kMidBrightness, kBotBrightness, -brightness));

  f32 Y_c = (contrast >= 0.0) ? Bezier(Y_b, lerp(kMidContrast, kTopContrast, contrast))
                              : Bezier(Y_b, lerp(kMidContrast, kBotContrast, -contrast));

  f32 Y_out = pow(max(Y_c, 0.0), 2.4) * Y_peak;

  f32x3 rgb = (Y_lin > 0.0001) ? c * (Y_out / Y_lin) : c;
  rgb = max(rgb, 0.0);

  f32 luma = dot(rgb, f32x3(0.2125, 0.7154, 0.0721));
  f32 sat = 0.5 + saturation * 0.5;
  rgb = lerp(luma, rgb, sat * 2.0);
  return max(rgb, 0.0);
}

// --- Mask Calculation ---

f32x3 crt_mask_apply(f32x2 output_size, float2 fc, f32 tw_ref, f32 strength, f32 sharp, f32x3 phcol, int mask_type) {
  f32 tw = tw_ref * (output_size.x / 3840.0);
  f32 fw = fwidth(fc.x / tw);
  f32 edge = max(fw, 1.0 / max(sharp, 0.01));

  f32x3 mask = f32x3(1.0, 1.0, 1.0);

  // Standard Aperture Grille
  if (mask_type == 0) {
    f32 t = frac(fc.x / tw);
    f32 r = smoothstep(0.0, edge, t) * smoothstep(0.333, 0.333 - edge, t);
    f32 g = smoothstep(0.333, 0.333 + edge, t) * smoothstep(0.667, 0.667 - edge, t);
    f32 b = smoothstep(0.667, 0.667 + edge, t) * smoothstep(1.0, 1.0 - edge, t);
    mask = f32x3(r, g, b) * phcol;
  }

  return saturate(lerp(f32x3(1.0, 1.0, 1.0), mask, strength));
}

#include <fullscreen.slang>

[[shader("fragment")]]
f32x4 fs_main(VertexOutput input, uniform ParameterBlock<CRTParameters> params, uniform PushConstants config)
    : SV_Target {
  float2 fc = input.tex_coord * config.output_size;

  f32x3 c = params.source.Sample(params.linear_sampler, input.tex_coord).rgb;

  // Apply Brightness, Contrast, Saturation
  if (abs(crt_brightness) > 0.001 || abs(crt_contrast) > 0.001 || abs(crt_saturation) > 0.001) {
    c = apply_bcs(c, crt_brightness, crt_contrast, crt_saturation);
  }

  // Linearize Color Pass (Gamma In)
  f32x3 c_lin = pow(max(c, 0.0), f32x3(crt_gamma_in, crt_gamma_in, crt_gamma_in));

  // Apply Mask
  if (crt_mask_strength > 0.001) {
    f32x3 mask = crt_mask_apply(
      config.output_size,
      fc,
      crt_triad_width,
      crt_mask_strength,
      crt_phosphor_sharpness,
      crt_phosphor_colour,
      crt_mask_type
    );
    c_lin *= mask * crt_mask_boost;
  }

  // Scanline Calculation (Analytic Gaussian Beam Envelope)
  f32 scan_width = max(round(crt_scanline_width), 1.0);
  f32 scanline_y = floor(fc.y) + 0.5;
  f32 f = frac(scanline_y / scan_width) - 0.5;
  f32 hw = 0.5 / max(scan_width, 1.0);

  // Per-scanline variation: brightness AND sigma (beam width) vary per row. On a real CRT, HV
  // ripple affects both beam focus and brightness -- brighter rows are also slightly wider,
  // dimmer rows slightly narrower. roll_raw is in [-1,1]; roll scales brightness, sigma_roll width.
  f32 scanline_row = floor(scanline_y / scan_width);
  f32 roll_raw = (crt_scanline_roll_strength > 0.0001)
                     ? crt_scanline_roll(scanline_row + floor(config.timer * 0.001 * crt_scanline_roll_drift))
                     : 0.0;
  f32 roll = 1.0 + crt_scanline_roll_strength * roll_raw;
  // Sigma modulation is half the brightness variation so it doesn't dominate.
  f32 sigma_roll = 1.0 + crt_scanline_roll_strength * roll_raw * 0.5;

  f32 sigma_scale = 1.0 / max(scan_width, 1.0);
  f32 r_sigma = lerp(crt_beam_min_sigma, crt_beam_max_sigma, saturate(c_lin.r)) * sigma_scale * sigma_roll;
  f32 g_sigma = lerp(crt_beam_min_sigma, crt_beam_max_sigma, saturate(c_lin.g)) * sigma_scale * sigma_roll;
  f32 b_sigma = lerp(crt_beam_min_sigma, crt_beam_max_sigma, saturate(c_lin.b)) * sigma_scale * sigma_roll;

  f32 beam_r = gauss_integral(f, hw, r_sigma) * roll;
  f32 beam_g = gauss_integral(f, hw, g_sigma) * roll;
  f32 beam_b = gauss_integral(f, hw, b_sigma) * roll;

  c_lin *= lerp(f32x3(1.0, 1.0, 1.0), f32x3(beam_r, beam_g, beam_b), crt_scanline_strength);

  // Display Gamma Output Re-encoding
  f32x3 final_color = pow(max(c_lin, 0.0), f32x3(1.0 / crt_gamma_out, 1.0 / crt_gamma_out, 1.0 / crt_gamma_out));

  return f32x4(final_color, 1.0);
}
