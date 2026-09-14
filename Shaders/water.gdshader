shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// ---------------------------------------------------------
// OCEAN SHADER (Gerstner waves + noise distortion + depth color + fresnel)
// Attach to a MeshInstance3D using a highly subdivided PlaneMesh.
// The wave math here MUST match ocean_buoyancy.gd exactly,
// so physics floats in sync with what's rendered.
// ---------------------------------------------------------

uniform vec4 shallow_color : source_color = vec4(0.10, 0.55, 0.55, 1.0);
uniform vec4 deep_color : source_color = vec4(0.02, 0.10, 0.25, 1.0);
uniform float depth_fade_distance : hint_range(0.1, 50.0) = 8.0;

uniform sampler2D normal_map : hint_normal;
uniform float normal_scroll_speed = 0.05;
uniform float normal_tiling = 8.0;

uniform float fresnel_power : hint_range(0.1, 8.0) = 3.0;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.05;

// Godot 4 syntax: depth texture must be declared as a hinted uniform,
// not accessed via the old Godot 3 DEPTH_TEXTURE builtin constant.
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

// Gerstner wave parameters — 4 waves summed together. All directions
// are kept within a narrow angular spread of one dominant direction
// (varying mainly in wavelength/steepness instead of angle) so they
// don't cross at sharp angles and produce visible grid/line artifacts.
// Wave 1: big, slow, long-wavelength swell (dominant rolling motion)
uniform vec2 wave1_dir = vec2(1.0, 0.2);
uniform float wave1_steepness = 0.35;
uniform float wave1_length = 14.0;

// Wave 2: medium swell, slightly off-axis from wave 1
uniform vec2 wave2_dir = vec2(1.0, 0.45);
uniform float wave2_steepness = 0.22;
uniform float wave2_length = 7.0;

// Wave 3: smaller chop, slightly off-axis the other way
uniform vec2 wave3_dir = vec2(1.0, -0.1);
uniform float wave3_steepness = 0.15;
uniform float wave3_length = 3.5;

// Wave 4: fine ripple, closest back to the main direction
uniform vec2 wave4_dir = vec2(1.0, 0.3);
uniform float wave4_steepness = 0.08;
uniform float wave4_length = 1.6;

// How strongly the noise field distorts wave input position and
// adds extra chop. Raise for more chaotic/random-looking seas,
// lower if it starts looking jittery or glitchy.
uniform float distortion_strength = 2.5;
uniform float chop_strength = 0.4;

varying vec3 world_pos;
varying vec3 world_normal;

// Simple 2D value noise (hash-based) used to distort the wave input
// position so peaks/troughs stop lining up into an obvious repeating
// pattern. This is what makes the waves look irregular/random rather
// than a clean stack of sine curves.
float hash2(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = hash2(i);
    float b = hash2(i + vec2(1.0, 0.0));
    float c = hash2(i + vec2(0.0, 1.0));
    float d = hash2(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// Fractal sum of a few octaves of noise, slowly scrolling over time,
// used both to distort wave direction and to add extra chop.
float fbm_noise(vec2 p, float time) {
    float n = 0.0;
    n += value_noise(p * 1.0 + time * 0.05) * 0.5;
    n += value_noise(p * 2.3 - time * 0.08) * 0.25;
    n += value_noise(p * 4.1 + time * 0.13) * 0.125;
    return n;
}

// Single Gerstner wave displacement. Returns offset to add to position,
// and accumulates derivatives into tangent/binormal for normal calc.
vec3 gerstner_wave(vec2 dir, float steepness, float wavelength, vec2 pos, float time, inout vec3 tangent, inout vec3 binormal) {
    float k = 2.0 * PI / wavelength;
    float c = sqrt(9.8 / k); // wave speed from gravity
    vec2 d = normalize(dir);
    float f = k * (dot(d, pos) - c * time);
    float a = steepness / k;

    tangent += vec3(
        -d.x * d.x * steepness * sin(f),
        d.x * steepness * cos(f),
        -d.x * d.y * steepness * sin(f)
    );
    binormal += vec3(
        -d.x * d.y * steepness * sin(f),
        d.y * steepness * cos(f),
        -d.y * d.y * steepness * sin(f)
    );

    return vec3(
        d.x * a * cos(f),
        a * sin(f),
        d.y * a * cos(f)
    );
}

void vertex() {
    vec2 pos2d = VERTEX.xz;
    float time = TIME;

    // Distort the position fed into the Gerstner waves using noise.
    // This breaks the periodic sine pattern so wave crests don't line
    // up predictably - the core trick for making waves look random.
    float distortion = fbm_noise(pos2d * 0.15, time) * distortion_strength;
    vec2 distorted_pos = pos2d + vec2(distortion, distortion * 0.7);

    vec3 tangent = vec3(1.0, 0.0, 0.0);
    vec3 binormal = vec3(0.0, 0.0, 1.0);
    vec3 offset = vec3(0.0);

    offset += gerstner_wave(wave1_dir, wave1_steepness, wave1_length, distorted_pos, time, tangent, binormal);
    offset += gerstner_wave(wave2_dir, wave2_steepness, wave2_length, distorted_pos, time, tangent, binormal);
    offset += gerstner_wave(wave3_dir, wave3_steepness, wave3_length, distorted_pos, time, tangent, binormal);
    offset += gerstner_wave(wave4_dir, wave4_steepness, wave4_length, distorted_pos, time, tangent, binormal);

    // Extra small-scale chaotic bumps layered directly on top, not
    // tied to any single wave direction - pure noise-driven height.
    float chop_noise = fbm_noise(pos2d * 0.6, time * 1.5) - 0.5;
    offset.y += chop_noise * chop_strength;

    VERTEX += offset;
    NORMAL = normalize(cross(binormal, tangent));

    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
    // Scrolling normal detail for small ripples, layered over the
    // large-scale Gerstner normal computed in vertex().
    vec2 uv1 = UV * normal_tiling + vec2(TIME * normal_scroll_speed, TIME * normal_scroll_speed * 0.5);
    vec2 uv2 = UV * normal_tiling * 1.7 - vec2(TIME * normal_scroll_speed * 0.7, TIME * normal_scroll_speed * 0.3);
    vec3 n1 = texture(normal_map, uv1).rgb * 2.0 - 1.0;
    vec3 n2 = texture(normal_map, uv2).rgb * 2.0 - 1.0;
    vec3 detail_normal = normalize(vec3(n1.xy + n2.xy, n1.z + n2.z));

    NORMAL_MAP = detail_normal * 0.5 + 0.5;
    NORMAL_MAP_DEPTH = 0.6;

    // Depth-based color: use the depth texture to see how far
    // underwater geometry is beneath this fragment.
    float depth_tex = texture(depth_texture, SCREEN_UV).r;
    vec4 world_pos_from_depth = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_tex, 1.0);
    world_pos_from_depth.xyz /= world_pos_from_depth.w;
    float depth_diff = clamp((world_pos.y - world_pos_from_depth.y) / depth_fade_distance, 0.0, 1.0);

    ALBEDO = mix(shallow_color.rgb, deep_color.rgb, depth_diff);

    // Fresnel: more reflective at grazing angles.
    float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);
    SPECULAR = 0.5;
    ROUGHNESS = mix(roughness_val, 0.3, fresnel);
    METALLIC = 0.0;

    ALPHA = mix(0.85, 1.0, depth_diff);
}
