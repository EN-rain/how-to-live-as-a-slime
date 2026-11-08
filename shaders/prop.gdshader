shader_type spatial;
// Prop material: flat-shaded lit surface plus noise dissolve with a glowing edge
// that only evaluates when the prop is actively being digested (uDissolve > 0.001).
render_mode cull_back, specular_disabled;

group_uniforms Surface;
uniform vec3 uColor : source_color = vec3(0.8, 0.8, 0.8);
uniform float uRoughness : hint_range(0.0, 1.0, 0.01) = 0.55;
uniform float uMetallic : hint_range(0.0, 1.0, 0.01) = 0.05;
uniform bool uFlatShading = true;

group_uniforms Dissolve;
uniform vec3 uGlow : source_color = vec3(0.25, 1.0, 0.7);
uniform float uGlowStrength = 2.5;
uniform float uNoiseScale = 3.0;
uniform float uThresholdScale = 1.25;
uniform float uThresholdBias = 0.1;
uniform float uEdgeWidth = 0.1;

group_uniforms;

// Driven by Prop.gd while being eaten: 0 = intact, 1 = gone
uniform float uDissolve = 0.0;

varying vec3 vObjPos;

float dh(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float dvn(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(dh(i), dh(i + vec3(1.0, 0.0, 0.0)), f.x), mix(dh(i + vec3(0.0, 1.0, 0.0)), dh(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(dh(i + vec3(0.0, 0.0, 1.0)), dh(i + vec3(1.0, 0.0, 1.0)), f.x), mix(dh(i + vec3(0.0, 1.0, 1.0)), dh(i + vec3(1.0, 1.0, 1.0)), f.x), f.y),
		f.z);
}

void vertex() {
	vObjPos = VERTEX;
}

void fragment() {
	ALBEDO = uColor;
	ROUGHNESS = uRoughness;
	METALLIC = uMetallic;
	if (uFlatShading) {
		NORMAL = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	}
	// Skip 3D trilinear noise on intact props (99% of props at rest)
	if (uDissolve > 0.001) {
		float dn = dvn(vObjPos * uNoiseScale);
		float dth = uDissolve * uThresholdScale - uThresholdBias;
		if (dn < dth) {
			discard;
		}
		float dedge = 1.0 - smoothstep(0.0, uEdgeWidth, dn - dth);
		EMISSION = uGlow * dedge * uGlowStrength;
	}
}
