shader_type spatial;
// Studio floor. Two looks, switched by uDevTexture:
//  - on : prototype / "early development" floor (checker cells + minor lines + bold major lines, in world units)
//  - off: the HTML's original thin-line tiled grid
// Both use Three-style lighting (ambient + one directional, computed in display space), linear fog, and the blob shadow.
// The shadow lives in here (not a separate quad) so it ends up in the screen texture the slime refracts.
render_mode unshaded, fog_disabled;

group_uniforms Style;
uniform bool uDevTexture = true;

group_uniforms DevTexture;
uniform float uCellSize = 1.0;             // world units per checker cell
uniform float uMajorEvery = 4.0;           // a bold line every N cells
uniform vec3 uLightCell : source_color = vec3(0.46, 0.50, 0.54);
uniform vec3 uDarkCell : source_color = vec3(0.37, 0.41, 0.45);
uniform vec3 uMinorLine : source_color = vec3(0.30, 0.34, 0.38);
uniform vec3 uMajorLine : source_color = vec3(0.85, 0.91, 0.97);
uniform float uMinorWidth = 0.025;         // half-width, in cells
uniform float uMajorWidth = 0.02;          // half-width, in major cells
uniform float uMinorAlpha : hint_range(0.0, 1.0, 0.01) = 0.6;
uniform float uMajorAlpha : hint_range(0.0, 1.0, 0.01) = 0.85;
uniform float uFadeStart = 0.35;           // detail fades out when a cell shrinks below this many... (pixels^-1), kills moire in the distance
uniform float uFadeEnd = 0.8;

group_uniforms OriginalGrid;
uniform float uTiles = 100.0;
uniform float uPlaneSize = 400.0;          // size of the floor plane mesh, used to rebuild UVs from world position
uniform vec3 uBaseColor : source_color = vec3(0.435, 0.490, 0.549);
uniform vec3 uEdgeColor : source_color = vec3(0.824, 0.910, 0.980);
uniform float uEdgeAlpha : hint_range(0.0, 1.0, 0.01) = 0.55;
uniform float uMidAlpha : hint_range(0.0, 1.0, 0.01) = 0.18;
uniform float uEdgeHalfWidth = 0.00390625; // 2px of a 512px tile, drawn on each side of a tile seam
uniform float uMidHalfWidth = 0.001953125; // 1px of a 512px tile

group_uniforms Lighting;
uniform vec3 uAmbientColor : source_color = vec3(0.859, 0.918, 0.996);
uniform float uAmbientEnergy = 0.85;
uniform vec3 uLightColor : source_color = vec3(1.0, 1.0, 1.0);
uniform float uLightEnergy = 0.9;
uniform vec3 uLightDir = vec3(4.0, 8.0, 5.0); // direction TOWARD the light (keep in sync with the DirectionalLight3D)

group_uniforms Fog;
uniform vec3 uFogColor : source_color = vec3(0.337, 0.471, 0.565);
uniform float uFogNear = 25.0;
uniform float uFogFar = 90.0;

group_uniforms BlobShadow;
uniform vec3 uShadowColor : source_color = vec3(0.039, 0.078, 0.137);
uniform float uShadowInnerAlpha : hint_range(0.0, 1.0, 0.01) = 0.6;
uniform float uShadowMidAlpha : hint_range(0.0, 1.0, 0.01) = 0.35;
uniform float uShadowMidStop = 0.7;
uniform float uShadowInnerStop = 0.0625; // 4px of a 64px radius
uniform float uShadowRadius = 2.0;       // half-size of the HTML's 4x4 quad, at slime scale 1

group_uniforms;

// Driven by Slime.gd
uniform int uBlobCount = 1;
uniform vec3 uBlobPos[8];
uniform float uBlobScale[8];

varying vec3 vWorld;

vec3 srgb2lin(vec3 c) {
	vec3 hi = pow((c + vec3(0.055)) / 1.055, vec3(2.4));
	vec3 lo = c / 12.92;
	return mix(hi, lo, step(c, vec3(0.04045)));
}

vec3 lin2srgb(vec3 c) {
	c = max(c, vec3(0.0));
	vec3 hi = 1.055 * pow(c, vec3(1.0 / 2.4)) - vec3(0.055);
	vec3 lo = c * 12.92;
	return mix(hi, lo, step(c, vec3(0.0031308)));
}

// 1 on a line of half-width hw, centred on integer coordinates of w (anti-aliased with the pixel footprint).
float gridLine(vec2 w, float hw) {
	vec2 f = fract(w);
	vec2 fw = fwidth(w);
	float aa = max(max(fw.x, fw.y) * 0.75, 1e-5);
	float seam = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	return 1.0 - smoothstep(hw - aa, hw + aa, seam);
}

vec3 devAlbedo(vec2 worldXZ) {
	vec2 w = worldXZ / uCellSize;
	vec2 cell = floor(w);
	float checker = mod(cell.x + cell.y, 2.0);
	vec3 lightC = lin2srgb(uLightCell);
	vec3 darkC = lin2srgb(uDarkCell);
	vec3 col = mix(lightC, darkC, checker);

	float minor = gridLine(w, uMinorWidth);
	float major = gridLine(w / uMajorEvery, uMajorWidth);
	col = mix(col, lin2srgb(uMinorLine), minor * uMinorAlpha);
	col = mix(col, lin2srgb(uMajorLine), major * uMajorAlpha);

	// In the distance cells get sub-pixel: blend toward the average colour so it doesn't shimmer.
	vec2 fw = fwidth(w);
	float fade = smoothstep(uFadeStart, uFadeEnd, max(fw.x, fw.y));
	vec3 avg = mix(lightC, darkC, 0.5);
	return mix(col, avg, fade);
}

vec3 originalAlbedo(vec2 uv) {
	vec2 f = fract(uv * uTiles);
	vec2 fw = fwidth(uv * uTiles);
	float aa = max(fw.x, fw.y) * 0.75;
	float seam = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	float edge = 1.0 - smoothstep(uEdgeHalfWidth - aa, uEdgeHalfWidth + aa, seam);
	float midd = min(abs(f.x - 0.5), abs(f.y - 0.5));
	float mid = 1.0 - smoothstep(uMidHalfWidth - aa, uMidHalfWidth + aa, midd);

	vec3 base = lin2srgb(uBaseColor);
	vec3 edgeC = lin2srgb(uEdgeColor);
	vec3 albedo = mix(base, edgeC, mid * uMidAlpha);
	return mix(albedo, edgeC, edge * uEdgeAlpha);
}

void vertex() {
	vWorld = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 devCol = devAlbedo(vWorld.xz);
	vec3 origCol = originalAlbedo(vWorld.xz / uPlaneSize + vec2(0.5));
	vec3 albedo = uDevTexture ? devCol : origCol;

	// --- Three.js-style lighting on an up-facing surface, display space ---
	float ndl = max(normalize(uLightDir).y, 0.0);
	vec3 lit = albedo * (lin2srgb(uAmbientColor) * uAmbientEnergy + lin2srgb(uLightColor) * uLightEnergy * ndl);
	vec3 color = clamp(lit, vec3(0.0), vec3(1.0));

	// --- blob shadow (canvas radial gradient: inner circle r=4px, outer r=64px, up to 8 slimes) ---
	float max_shadow = 0.0;
	int bcount = clamp(uBlobCount, 0, 8);
	for (int i = 0; i < bcount; i++) {
		if (uBlobScale[i] <= 0.001) continue;
		float dist = length(vWorld.xz - uBlobPos[i].xz);
		float rn = dist / (uShadowRadius * uBlobScale[i]);
		float tt = clamp((rn - uShadowInnerStop) / (1.0 - uShadowInnerStop), 0.0, 1.0);
		float a = tt < uShadowMidStop
			? mix(uShadowInnerAlpha, uShadowMidAlpha, tt / uShadowMidStop)
			: mix(uShadowMidAlpha, 0.0, (tt - uShadowMidStop) / (1.0 - uShadowMidStop));
		max_shadow = max(max_shadow, a);
	}
	color = mix(color, lin2srgb(uShadowColor), max_shadow);

	// --- linear fog, Three smoothstep, display space ---
	float depth = -VERTEX.z;
	float fogF = smoothstep(uFogNear, uFogFar, depth);
	color = mix(color, lin2srgb(uFogColor), fogF);

	ALBEDO = srgb2lin(color);
}
