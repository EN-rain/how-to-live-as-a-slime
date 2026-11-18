shader_type spatial;
// Port of the Three.js "3D Anime Slime" vertex + fragment shaders.
// Colour maths is done in display (sRGB) space exactly like the HTML (which had no colour management),
// then converted to linear at the very end so Godot's output matches.
render_mode unshaded, depth_draw_always, fog_disabled, cull_back;

// ------------------------------------------------------------------------------------------------
// Inspector-editable look
// ------------------------------------------------------------------------------------------------
group_uniforms Shape;
uniform float uJiggleStrength : hint_range(0.0, 3.0, 0.01) = 1.0;

group_uniforms Refraction;
uniform float uDispersion : hint_range(0.0, 2.0, 0.01) = 0.85;
uniform float uRefractionStrength : hint_range(0.0, 1.0, 0.01) = 0.32;
uniform float uRippleNoiseScale = 1.65;
uniform float uBubbleNoiseScale = 3.5;

group_uniforms Surface;
uniform float uRimStrength : hint_range(0.0, 2.0, 0.01) = 1.15;
uniform float uOpacity : hint_range(0.0, 1.0, 0.01) = 0.48;
uniform float uNightMode : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform vec3 uTopGlow = vec3(0.08, 0.18, 0.28);
uniform float uBubbleBoost = 1.4;

group_uniforms Colors;
uniform vec3 uDayShallow : source_color = vec3(0.52, 0.82, 0.98);
uniform vec3 uDayDeep : source_color = vec3(0.28, 0.62, 0.90);
uniform vec3 uNightShallow : source_color = vec3(0.22, 0.64, 0.94);
uniform vec3 uNightDeep : source_color = vec3(0.08, 0.32, 0.64);
uniform vec3 uRimDay : source_color = vec3(0.80, 0.96, 1.0);
uniform vec3 uRimNight : source_color = vec3(0.62, 0.92, 1.0);
uniform vec3 uOutlineDay : source_color = vec3(0.16, 0.34, 0.52);
uniform vec3 uOutlineNight : source_color = vec3(0.04, 0.12, 0.24);
uniform vec3 uCausticA : source_color = vec3(0.18, 0.92, 0.62);
uniform vec3 uCausticB : source_color = vec3(0.42, 0.98, 0.35);
uniform vec3 uBubbleColor : source_color = vec3(0.85, 1.0, 0.95);
uniform vec3 uEyeColor : source_color = vec3(1.0, 1.0, 1.0);

group_uniforms Eyes;
uniform float uEyeSeparation = 0.32;
uniform vec2 uEyeSize = vec2(0.11, 0.17);
uniform float uEyeElevation = 0.12;

group_uniforms;

// ------------------------------------------------------------------------------------------------
// Driven by Slime.gd every frame (not meant to be edited by hand)
// ------------------------------------------------------------------------------------------------
uniform float uMelt = 0.28; // set from Slime.melt (the script needs the same value for collision radii)
uniform float uImpulseTime = 10.0;
uniform vec3 uImpulsePos = vec3(0.0, 0.5, 1.0);
uniform vec3 uImpulseVector = vec3(0.0);
uniform float uImpulse2Time = 10.0;
uniform vec3 uImpulse2Pos = vec3(0.0, 0.5, 1.0);
uniform vec3 uImpulse2Vector = vec3(0.0);
uniform vec3 uMoveDir = vec3(0.0, 0.0, 1.0);
uniform float uMoveAmt = 0.0;
uniform float uCrawl = 0.0;
uniform vec3 uLean = vec3(0.0);
uniform vec3 uEatPos[6];
uniform vec3 uEatParam[6];
uniform vec3 uBoxHalf[6];
uniform vec3 uPressDir = vec3(0.0, 0.0, 1.0);
uniform float uPressAmt = 0.0;
uniform vec3 uSplatDir = vec3(0.0, 0.0, 1.0);
uniform float uSplat = 0.0;
uniform float uSpread = 0.0;
uniform float uWall = 2.15;
uniform vec3 uSolidPos[8];
uniform vec3 uSolidParam[8];
uniform vec3 uSolidHalf[8];
uniform vec3 uSolidDir[8];
uniform float uRippleIntensity = 0.12;
uniform float uFacing = 0.45;
uniform float uBlink = 1.0;
// Squeezing through a gap between solids. uSqueeze is a 0..1 emphasis for the neck;
// the actual body factors come from the resolved posture below.
uniform float uSqueeze = 0.0;
uniform vec3 uSqueezeDir = vec3(1.0, 0.0, 0.0);
// Mesh-local gap centre (relative to the mesh origin) for the gap-centred neck deform
uniform vec3 uGapLocal = vec3(0.0);
// Resolved posture factors, authored by SlimeShapeModel. The hull bakes exactly these
// two horizontal factors (and the height factor), so applying them here keeps every
// vertex inside the collision envelope.
uniform float uSqueezeLat = 1.0;
uniform float uSqueezeLong = 1.0;
uniform float uSqueezeHeight = 1.0;
// World-space visual budget (tuning.skin) converted to mesh-local units; outward
// stylization is clamped to it.
uniform float uSkinLocal = 0.02;

// Resolved posture, authored by SlimeShapeModel every tick (absolute multipliers).
uniform float uLiquid = 0.0;
uniform float uLiquidHeight = 1.0;
uniform float uLiquidSpread = 1.0;
// Mesh-local radius of the rest sphere, so tuning.reference_radius drives the
// vertical profile instead of a second hardcoded copy of the same constant.
uniform float uRefRadius = 1.6;

// Engulf drape mode (holding Z on top of a larger object)
uniform vec3 uDrapePos = vec3(0.0);
uniform vec3 uDrapeHalf = vec3(0.01);
uniform float uDrapeShape = 0.0;
uniform float uDrapeYaw = 0.0;
uniform float uDrapeAmt = 0.0;

// Budding fission (split animation for E and Q): soft teardrop stretch toward the
// separating partner, driven by the neck-snap impulse on both sides. While
// uSplitNeckRadius is non-zero the partner's centre (mesh-local) and the shared neck
// radius sculpt the facing hemisphere onto the world-space seam between the halves.
uniform float uSplitAmt = 0.0;
uniform vec3 uSplitDir = vec3(0.0, 0.0, -1.0);
uniform vec3 uSplitPartnerLocal = vec3(0.0);
uniform float uSplitNeckRadius = 0.0;

// 1.0 on distant/small clones: skips the noise-driven bubble field and samples the
// screen texture once instead of four times. Never changes the silhouette.
uniform float uShaderLOD = 0.0;

// Water-slime interaction (driven by Slime.gd every tick when in/freshly out of water)
uniform float uWaterSubmersion = 0.0;
uniform float uWaterY = -9999.0;
uniform float uWetness = 0.0;
uniform vec3 uWaterVel = vec3(0.0);
uniform int uActiveEatCount = 6;
uniform int uActiveSolidCount = 8;

uniform sampler2D tRefraction : hint_screen_texture, repeat_disable, filter_linear;

varying vec3 vWorldPosition;
varying vec3 vViewPosition;
varying vec3 vNormal;
varying vec3 vWorldNormal;
varying vec3 vLocalPos;
varying float vRippleMask;
varying flat vec3 vCausticA;
varying flat vec3 vCausticB;
varying flat vec3 vShallowTint;
varying flat vec3 vDeepTint;
varying flat vec3 vRimColor;
varying flat vec3 vBubbleColor;
varying flat vec3 vEyeColor;
varying flat vec3 vOutlineColor;

vec3 lin2srgb(vec3 c) {
	c = max(c, vec3(0.0));
	vec3 hi = 1.055 * pow(c, vec3(1.0 / 2.4)) - vec3(0.055);
	vec3 lo = c * 12.92;
	return mix(hi, lo, step(c, vec3(0.0031308)));
}

// ------------------------------------------------------------------------------------------------
// Vertex: deformation
// ------------------------------------------------------------------------------------------------

// Regular n-gon in xz: x = distance along the nearest face normal (rho*cos), y = apothem. n<3 or n>=12 means round.
vec2 polyFold(vec2 xz, float n, float R) {
	float rho = length(xz);
	if (n < 2.5 || n >= 12.0) return vec2(rho, R);
	float sector = 6.28318531 / n;
	float ap = R * cos(3.14159265 / n);
	if (rho < 1e-5) return vec2(0.0, ap);
	float ang = atan(xz.x, xz.y);
	float a2 = mod(ang, sector) - 0.5 * sector;
	return vec2(rho * cos(a2), ap);
}

// shape = kind + sides*0.01  (kind: 0 box, 1 prism/cylinder, 2 pyramid/cone)
float sdShape(vec3 q, float shape, vec3 h) {
	float kind = floor(shape + 0.005);
	float n = floor((shape - kind) * 100.0 + 0.5);
	if (kind < 0.5) {
		vec3 a = abs(q) - h;
		return length(max(a, vec3(0.0))) + min(max(a.x, max(a.y, a.z)), 0.0);
	}
	vec2 f = polyFold(q.xz, n, h.x);
	if (kind < 1.5) {
		vec2 d2 = vec2(f.x - f.y, abs(q.y) - h.y);
		return min(max(d2.x, d2.y), 0.0) + length(max(d2, vec2(0.0)));
	}
	float r = f.y;
	float H2 = 2.0 * h.y;
	float dSide = (f.x * H2 + (q.y - h.y) * r) / sqrt(H2 * H2 + r * r);
	return max(dSide, -q.y - h.y);
}

// Push depth along -n that lifts a point to the offset surface: exact exit distance, iterated (stays correct for deep dents)
float pushAmt(vec3 q, vec3 nL, float shape, vec3 h, float e) {
	float s = 0.0;
	for (int k = 0; k < 4; k++) {
		s += max(e - sdShape(q - nL * s, shape, h), 0.0);
	}
	return s;
}

// The depth field is blurred over a small disc of taps in the plane facing the prop, so the dent wall at the
// prop's silhouette becomes a smooth ramp instead of a cliff the mesh can't resolve.
vec3 dentPush(vec3 p, vec3 c, float shape, vec3 h, float yaw, float blur, vec3 nOv) {
	float cy = cos(yaw);
	float sy = sin(yaw);
	vec3 dv = p - c;
	vec3 q = vec3(dv.x * cy - dv.z * sy, dv.y, dv.x * sy + dv.z * cy);
	float e = 0.08;
	if (sdShape(q, shape, h) > e + blur * 1.2) return vec3(0.0);
	vec3 n = dot(nOv, nOv) > 0.5 ? nOv : normalize(vec3(c.x, 0.0, c.z) + vec3(0.0001, 0.0, 0.0001));
	vec3 nL = vec3(n.x * cy - n.z * sy, 0.0, n.x * sy + n.z * cy);
	vec3 u = vec3(-nL.z, 0.0, nL.x);
	vec3 v = vec3(0.0, 1.0, 0.0);
	float R = blur;
	float acc = pushAmt(q, nL, shape, h, e) * 0.28;
	acc += pushAmt(q + u * R, nL, shape, h, e) * 0.12;
	acc += pushAmt(q - u * R, nL, shape, h, e) * 0.12;
	acc += pushAmt(q + v * R, nL, shape, h, e) * 0.12;
	acc += pushAmt(q - v * R, nL, shape, h, e) * 0.12;
	acc += pushAmt(q + (u + v) * R * 0.7071, nL, shape, h, e) * 0.06;
	acc += pushAmt(q + (u - v) * R * 0.7071, nL, shape, h, e) * 0.06;
	acc += pushAmt(q + (-u + v) * R * 0.7071, nL, shape, h, e) * 0.06;
	acc += pushAmt(q + (-u - v) * R * 0.7071, nL, shape, h, e) * 0.06;
	return -n * acc;
}

// ------------------------------------------------------------------------------------------------
// Solid-contact dent (replaces dentPush for obstacles the slime is squashed against)
//
// dentPush shoves every point along ONE fixed direction (the contact normal) until it clears the obstacle. That is fine
// for a flat face, but against a corner it pinches the skin into a kinked notch (points on the two flanks get dragged
// diagonally, the tip gets thrown back along the axis). This version instead pushes each point along the obstacle's own
// outward normal at that point, by the distance it is inside the offset outline, so the skin follows the real outline
// and the push fades out continuously (no cliff). Corners of boxes are rounded a little so the jelly wraps round them.
// ------------------------------------------------------------------------------------------------
const float SOLID_OFFSET = 0.08;  // skin gap between jelly and obstacle
const float SOLID_ROUND = 0.25;   // corner rounding radius (flat faces are unaffected)

// Footprint (xz) signed distance to the obstacle and its outward normal there: returns vec3(sd, nx, nz).
vec3 footSd(vec3 q, float shape, vec3 h, float rr) {
	float kind = floor(shape + 0.005);
	float n = floor((shape - kind) * 100.0 + 0.5);
	if (kind < 0.5) {
		vec2 hs = max(h.xz - vec2(rr), vec2(0.01));
		vec2 a = abs(q.xz) - hs;
		vec2 d = q.xz - clamp(q.xz, -hs, hs);
		float od = length(d);
		float sd = od + min(max(a.x, a.y), 0.0) - rr;
		vec2 nn;
		if (a.x > 0.0 && a.y > 0.0) {
			nn = d / max(od, 1e-5);
		} else if (a.x > a.y) {
			nn = vec2(q.x >= 0.0 ? 1.0 : -1.0, 0.0);
		} else {
			nn = vec2(0.0, q.z >= 0.0 ? 1.0 : -1.0);
		}
		return vec3(sd, nn);
	}
	// prism (kind 1) keeps its radius; pyramid/cone (kind 2) narrows with height, like the collision reach does
	float R = h.x;
	if (kind > 1.5) R *= clamp(1.0 - (q.y + h.y) / (2.0 * h.y), 0.06, 1.0);
	float rho = length(q.xz);
	if (n < 2.5 || n >= 12.0) {
		return vec3(rho - R, q.xz / max(rho, 1e-5));
	}
	float sector = 6.28318531 / n;
	float faceAng = (floor(atan(q.x, q.z) / sector) + 0.5) * sector;
	vec2 nf = vec2(sin(faceAng), cos(faceAng));
	return vec3(dot(q.xz, nf) - R * cos(3.14159265 / n), nf);
}

// Horizontal push at one local-space point: along the outward normal, by how far the point is inside the offset outline.
// Fades out over the obstacle's top edge so the jelly above a low obstacle is left alone.
vec3 solidPushLocal(vec3 q, float shape, vec3 h) {
	vec3 f = footSd(q, shape, h, SOLID_ROUND);
	float win = 1.0 - smoothstep(0.0, 0.2, q.y - h.y);
	float mag = max(SOLID_OFFSET - f.x, 0.0) * win;
	return vec3(f.y * mag, 0.0, f.z * mag);
}

// C1-smooth maximum with 0: zero value and zero slope for a <= -k,
// exact linear identity (value = a, slope = 1) for a >= +k. Eliminates normal cracks.
float smax0(float a, float k) {
	float t = clamp(a + k, 0.0, 2.0 * k);
	return (a > k) ? a : (t * t) / (4.0 * k);
}

struct SolidPre {
	float cy;
	float sy;
	float dirX;
	float dirZ;
	float ratioX;
	float ratioZ;
	float isRoof;
};

struct DeformPre {
	float scaleYBase;
	float groundFloor;
	float syCrawl;
	float invSqrtSy;
	float splatYScale;
	vec2 sdir;
	vec2 sperp;
	float pdist;
	vec2 pdir;
	vec2 moveDirXZ;
	float drapeCy;
	float drapeSy;
	float waterHSpd;
	float maxBellyR;
};

// Precomputes invariant per-solid rotation and proportional compression factors once per vertex.
SolidPre buildSolidPre(vec3 c, vec3 h, float yaw, float groundFloorLocal, float maxBellyR) {
	SolidPre sp;
	sp.cy = cos(yaw);
	sp.sy = sin(yaw);
	vec3 H = h + vec3(0.05);
	sp.isRoof = (c.y - h.y > groundFloorLocal + 0.35) ? 1.0 : 0.0;
	vec2 cRot = vec2(c.x * sp.cy - c.z * sp.sy, c.x * sp.sy + c.z * sp.cy);
	float clearX = max(abs(cRot.x) - H.x, 0.12);
	float clearZ = max(abs(cRot.y) - H.z, 0.12);
	sp.dirX = cRot.x >= 0.0 ? 1.0 : -1.0;
	sp.dirZ = cRot.y >= 0.0 ? 1.0 : -1.0;
	sp.ratioX = smax0(1.0 - clearX / maxBellyR, 0.04);
	sp.ratioZ = smax0(1.0 - clearZ / maxBellyR, 0.04);
	return sp;
}

// Conforms the slime surface around an obstacle using proportional half-space scaling.
// Each obstacle scales only the half of the slime facing it (0 at center -> W at rim),
// so left and right obstacles never cross or fold the center dome, and release is instant.
vec3 solidDent(vec3 p, vec3 c, vec3 h, SolidPre sp, float maxBellyR) {
	vec3 dv = p - c;
	vec3 q = vec3(dv.x * sp.cy - dv.z * sp.sy, dv.y, dv.x * sp.sy + dv.z * sp.cy);
	vec3 H = h + vec3(0.05);
	if (q.y > H.y + 0.18 || q.y < -H.y - 0.18) return vec3(0.0);

	// Overhead roof / tunnel ceiling check
	if (sp.isRoof > 0.5) {
		float wxRoof = 1.0 - smoothstep(h.x - 0.02, h.x + 0.22, abs(q.x));
		float wzRoof = 1.0 - smoothstep(h.z - 0.02, h.z + 0.22, abs(q.z));
		float penY = smax0(q.y - (-H.y), 0.08);
		return vec3(0.0, -penY * wxRoof * wzRoof, 0.0);
	}

	float winY = 1.0 - smoothstep(H.y - 0.02, H.y + 0.16, q.y);
	if (winY <= 0.001) return vec3(0.0);

	// Vertex position relative to slime center (0,0) in obstacle-rotated XZ coordinates
	vec2 pRot = vec2(p.x * sp.cy - p.z * sp.sy, p.x * sp.sy + p.z * sp.cy);
	float rVert = length(p.xz);
	float rho = clamp(rVert / maxBellyR, 0.0, 1.0);

	// Only vertices on the obstacle's side of the slime center (proj > 0) are compressed toward clearX/clearZ
	float projX = sp.dirX * pRot.x;
	float projZ = sp.dirZ * pRot.y;
	float halfMaskX = smoothstep(0.0, 0.14, projX);
	float halfMaskZ = smoothstep(0.0, 0.14, projZ);

	float wz = 1.0 - smoothstep(h.z - 0.02, h.z + 0.26, abs(q.z));
	float wx = 1.0 - smoothstep(h.x - 0.02, h.x + 0.26, abs(q.x));

	// Push inward (towards slime center) proportionally to pRot so rings stay evenly ordered and never fold
	vec2 pushX = vec2(-pRot.x * sp.ratioX * halfMaskX * wz, 0.0);
	vec2 pushZ = vec2(0.0, -pRot.y * sp.ratioZ * halfMaskZ * wx);

	vec2 cRot = vec2(c.x * sp.cy - c.z * sp.sy, c.x * sp.sy + c.z * sp.cy);
	float ox = abs(cRot.x) - h.x;
	float oz = abs(cRot.y) - h.z;
	float inX = h.x - abs(q.x);
	float inZ = h.z - abs(q.z);
	float cornerFaceW = smoothstep(-0.20, 0.20, inZ - inX);
	float sideOnlyX = smoothstep(-0.10, 0.10, ox);
	float sideOnlyZ = smoothstep(-0.10, 0.10, oz);
	float faceW = mix(sideOnlyX, cornerFaceW, sideOnlyX * sideOnlyZ);

	vec2 pushXZ = mix(pushZ, pushX, faceW) * winY;

	float compressAmt = length(pushXZ);
	float domeLift = smax0(compressAmt - 0.02, 0.08) * 0.12 * (1.0 - rho * 0.55) * smoothstep(-0.8, 0.4, p.y);
	vec2 worldPushXZ = vec2(pushXZ.x * sp.cy + pushXZ.y * sp.sy, -pushXZ.x * sp.sy + pushXZ.y * sp.cy);
	return vec3(worldPushXZ.x, domeLift, worldPushXZ.y);
}

float smin_neck(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

vec3 deformSlime(vec3 pos, vec3 norm, float t, float breathe, float imp1Osc, float imp1Bounce, float imp2Osc, float crawlWave, DeformPre pre, SolidPre spList[8], int solidCount) {
	vec3 p = pos;

	float height01 = clamp((p.y / uRefRadius + 1.0) * 0.5, 0.0, 1.0);
	float bellyCurve = sin(height01 * 3.14159265);
	float lowerBulge = pow(1.0 - height01, 1.35) * smoothstep(0.0, 0.22, height01);
	float bellySpread = 1.0 + (lowerBulge * 0.34 + bellyCurve * 0.08) * (0.8 + uMelt * 1.1);
	p.xz *= bellySpread;

	p.y *= pre.scaleYBase;

	float groundFloor = pre.groundFloor;

	float baseH = p.y - groundFloor;
	if (baseH < 0.9) {
		float tB = clamp(baseH / 0.9, 0.0, 1.0);
		p.y = groundFloor + 0.9 * (2.0 * tB * tB - tB * tB * tB);
	}

	// ---- Sticky Droplet Budding (E and Q split) ----
	// Organic fluid separation: teardrop bridge stretches toward the partner,
	// tapering smoothly inward without flaring, while the facing cap forms a rounded dome.
	if (uSplitAmt > 0.001 || uSplitNeckRadius > 0.001) {
		float sproj = dot(p.xz, pre.sdir);
		float sperpd = dot(p.xz, pre.sperp);

		// Forward stretch towards the separating partner (pulls out a gooey neck)
		float forwardWeight = smoothstep(-0.25, 1.4, sproj);
		float stretch = forwardWeight * uSplitAmt * 0.65;
		p.xz += pre.sdir * stretch;

		// Monotonic teardrop taper: smoothly constricts inward towards the neck tip (never flaring back out)
		float taperMask = smoothstep(-0.15, 1.4, sproj);
		float pinch = taperMask * uSplitAmt * 0.45;
		p.xz -= pre.sperp * (sperpd * pinch);

		// Vertical thinning of the connecting neck
		float vertThin = smoothstep(0.0, 1.3, sproj) * uSplitAmt * 0.30;
		p.y = mix(p.y, groundFloor + (p.y - groundFloor) * (1.0 - vertThin), forwardWeight);

		// Rear bulge to conserve visual volume while being pulled forward
		float backWeight = 1.0 - smoothstep(-1.1, 0.1, sproj);
		p.xz -= pre.sdir * (backWeight * uSplitAmt * 0.18);

		// World-coupled neck: rounded dome cap meeting the partner at the seam plane
		if (uSplitNeckRadius > 0.001 && pre.pdist > 0.0) {
			float proj = dot(p.xz, pre.pdir);
			float radial = length(p.xz - pre.pdir * proj);
			float faceW = smoothstep(0.30 * uRefRadius, 0.95 * uRefRadius, proj)
				* smoothstep(0.0, 0.45 * uRefRadius, pre.pdist);
			float seam = pre.pdist * 0.5;
			float seamRadius = smin_neck(radial, uSplitNeckRadius, 0.08);
			float normR = clamp(seamRadius / max(uSplitNeckRadius, 0.001), 0.0, 1.0);
			float capDome = sqrt(max(0.0, 1.0 - normR * normR)) * 0.18 * uSplitNeckRadius;
			vec2 radialDir = radial > 1e-4 ? (p.xz - pre.pdir * proj) / radial : vec2(1.0, 0.0);
			vec2 target = pre.pdir * (seam - capDome) + radialDir * seamRadius;
			p.xz = mix(p.xz, target, faceW * 0.85);
			p.y = mix(p.y, groundFloor + (p.y - groundFloor) * 0.62, faceW * 0.55);
		}
	}

	p.y *= (1.0 + breathe);
	p.xz *= (1.0 - breathe * 0.45);

	float gentleSway = sin(p.y * 2.2 - t * 2.4) * 0.012 * uJiggleStrength;
	p.xz += norm.xz * gentleSway * smoothstep(0.05, 0.5, height01);

	if (abs(uSplat) > 0.001 || abs(uSpread) > 0.001) {
		float hRel = max(p.y - groundFloor, 0.0);
		float xzScale = clamp(1.0 + (uSplat * 0.24 + uSpread * 0.16) * (1.0 - 0.35 * height01), 0.78, 1.45);
		p.y = groundFloor + hRel * pre.splatYScale;
		p.xz *= xzScale;
	}

	vec3 impulseOffset = vec3(0.0);
	if (uImpulseTime < 3.5) {
		float distToPoke = distance(pos, uImpulsePos);
		float pokeInfluence = exp(-distToPoke * 1.15);
		impulseOffset = uImpulseVector * pokeInfluence * imp1Osc * uJiggleStrength;

		float globalBounce = clamp(imp1Bounce, -uSkinLocal, uSkinLocal) * (1.0 - uLiquid);
		p.y += globalBounce * (height01 - 0.15);
		float bounceRadial = globalBounce * 0.38 * (1.0 - height01 * 0.5);
		float radialCap = uSkinLocal / max(length(p.xz), 0.1);
		p.xz *= 1.0 - clamp(bounceRadial, -radialCap, radialCap);
	}

	vec3 impulseOffset2 = vec3(0.0);
	if (uImpulse2Time < 3.5) {
		float distToPoke2 = distance(pos, uImpulse2Pos);
		float pokeInfluence2 = exp(-distToPoke2 * 1.15);
		impulseOffset2 = uImpulse2Vector * pokeInfluence2 * imp2Osc * uJiggleStrength;
	}

	p += (impulseOffset + impulseOffset2) * smoothstep(0.02, 0.25, height01);

	int eatCount = min(uActiveEatCount, 6);
	for (int i = 0; i < eatCount; i++) {
		if (uEatParam[i].y > 0.001) {
			p += dentPush(p, uEatPos[i], uEatParam[i].x, uBoxHalf[i], uEatParam[i].z, 0.26, vec3(0.0)) * uEatParam[i].y;
		}
	}
	// In liquid puddle mode the slime is a flat disk — press/splat/solid-dent deformations
	// were designed for the upright blob and look wrong on the expanded puddle. Fade them out.
	float solidBlend = 1.0 - uLiquid;

	float effPress = uPressAmt * solidBlend;
	if (effPress > 0.001) {
		p.y = groundFloor + (p.y - groundFloor) * (1.0 + 0.03 * effPress);
	}
	float effSpread = uSpread * solidBlend;
	if (effSpread > 0.001) {
		p.y = groundFloor + (p.y - groundFloor) * (1.0 + 0.04 * effSpread);
	}
	p.y = max(p.y, groundFloor);

	p.xz *= pre.invSqrtSy;
	p.y = groundFloor + (p.y - groundFloor) * pre.syCrawl;
	// Lean is a shear that moves the apex sideways, which leaves the hull immediately;
	// fade it out in liquid and bound it to the skin.
	vec2 leanOff = uLean.xz * (height01 - 0.2) * 0.38 * (1.0 - uLiquid);
	float leanLen = length(leanOff);
	if (leanLen > uSkinLocal) leanOff *= uSkinLocal / leanLen;
	p.xz -= leanOff;
	float tw = sin(uCrawl - dot(pos.xz, pre.moveDirXZ) * 2.8);
	float twMask = smoothstep(0.1, 0.6, height01);
	p.y += uMoveAmt * 0.07 * tw * twMask;
	p.xz += norm.xz * uMoveAmt * 0.03 * tw * twMask;

	if (uDrapeAmt > 0.001) {
		vec3 dv = p - uDrapePos;
		vec3 q = vec3(dv.x * pre.drapeCy - dv.z * pre.drapeSy, dv.y, dv.x * pre.drapeSy + dv.z * pre.drapeCy);
		vec2 topReach = max(uDrapeHalf.xz * 1.18, vec2(0.2));
		p.xz = mix(p.xz, normalize(p.xz + vec2(0.0001)) * length(topReach), uDrapeAmt * 0.65);
		if (dv.y < 0.0) {
			p.y = mix(p.y, uDrapePos.y - abs(dv.y) * 1.25, uDrapeAmt * 0.45);
		}
	}

	// Final authoritative obstacle conforming across up to 8 nearby objects.
	for (int i = 0; i < solidCount; i++) {
		float solidAmt = uSolidParam[i].y;
		if (solidAmt > 0.001) {
			vec3 dent = solidDent(p, uSolidPos[i], uSolidHalf[i], spList[i], pre.maxBellyR);
			p += dent * solidAmt;
		}
	}
	// Gentle hydrostatic waterline ripple & buoyant belly tuck (strictly bounded within uSkinLocal)
	if (uWaterSubmersion > 0.01) {
		float h01 = clamp((p.y / uRefRadius + 1.0) * 0.5, 0.0, 1.0);
		float swim_rip = sin(pos.x * 3.4 + t * 4.8) * cos(pos.z * 3.4 - t * 4.1);
		float tuck = smoothstep(0.32, 0.0, h01) * 0.045 * uWaterSubmersion;
		p.y += min(tuck, uSkinLocal * 0.55);
		float d_lip = (h01 - 0.36) / 0.16;
		float lip_band = exp(-(d_lip * d_lip));
		float radial_wobble = min(lip_band * (0.022 + 0.014 * swim_rip * clamp(pre.waterHSpd * 0.25, 0.2, 1.0)) * uWaterSubmersion, uSkinLocal * 0.45);
		p.xz += normalize(p.xz + vec2(0.0001)) * radial_wobble;
	}
	p.y = max(p.y, groundFloor);

	return p;
}

void vertex() {
	vec3 position = VERTEX;
	vec3 nrm = NORMAL;
	vLocalPos = position;

	// Hoist constant/uniform-only math out of the 3x finite-difference deformSlime calls and fragment()
	float breathe = sin(TIME * 2.0) * 0.022 * uJiggleStrength;
	float imp1Osc = 0.0;
	float imp1Bounce = 0.0;
	float imp1Decay = 0.0;
	if (uImpulseTime < 3.5) {
		imp1Osc = sin(uImpulseTime * 14.0) * exp(-uImpulseTime * 3.0);
		imp1Bounce = sin(uImpulseTime * 11.0) * exp(-uImpulseTime * 2.6) * length(uImpulseVector) * 0.32 * uJiggleStrength;
		imp1Decay = exp(-uImpulseTime * 2.5);
	}
	float imp2Osc = 0.0;
	float imp2Decay = 0.0;
	if (uImpulse2Time < 3.5) {
		imp2Osc = sin(uImpulse2Time * 14.0) * exp(-uImpulse2Time * 3.0);
		imp2Decay = exp(-uImpulse2Time * 2.5);
	}
	float crawlWave = 0.5 + 0.5 * sin(uCrawl);

	DeformPre pre;
	pre.scaleYBase = 0.86 - uMelt * 0.22;
	pre.groundFloor = -uRefRadius * pre.scaleYBase;
	pre.syCrawl = 1.0 + uMoveAmt * (0.10 * crawlWave - 0.04);
	pre.invSqrtSy = inversesqrt(pre.syCrawl);
	pre.splatYScale = clamp(1.0 - uSplat * 0.42, 0.52, 1.42);
	pre.sdir = normalize(uSplitDir.xz + vec2(0.0001));
	pre.sperp = vec2(-pre.sdir.y, pre.sdir.x);
	float pdistSq = (uSplitNeckRadius > 0.001) ? dot(uSplitPartnerLocal.xz, uSplitPartnerLocal.xz) : 0.0;
	pre.pdist = pdistSq > 1e-5 ? sqrt(pdistSq) : 0.0;
	pre.pdir = pre.pdist > 0.0 ? (uSplitPartnerLocal.xz / pre.pdist) : vec2(1.0, 0.0);
	pre.moveDirXZ = normalize(uMoveDir.xz + vec2(0.0001));
	pre.drapeCy = (uDrapeAmt > 0.001) ? cos(uDrapeYaw) : 1.0;
	pre.drapeSy = (uDrapeAmt > 0.001) ? sin(uDrapeYaw) : 0.0;
	pre.waterHSpd = (uWaterSubmersion > 0.01) ? length(uWaterVel.xz) : 0.0;
	pre.maxBellyR = uRefRadius * 1.24;

	int solidCount = min(uActiveSolidCount, 8);
	SolidPre spList[8];
	for (int i = 0; i < solidCount; i++) {
		if (uSolidParam[i].y > 0.001) {
			spList[i] = buildSolidPre(uSolidPos[i], uSolidHalf[i], uSolidParam[i].z, pre.groundFloor, pre.maxBellyR);
		}
	}

	vec3 tangent = normalize(cross(nrm, vec3(0.0, 1.0, 0.1)));
	vec3 bitangent = normalize(cross(nrm, tangent));
	float eps = 0.025;

	vec3 p0 = deformSlime(position, nrm, TIME, breathe, imp1Osc, imp1Bounce, imp2Osc, crawlWave, pre, spList, solidCount);
	vec3 p1 = deformSlime(position + tangent * eps, normalize(position + tangent * eps), TIME, breathe, imp1Osc, imp1Bounce, imp2Osc, crawlWave, pre, spList, solidCount);
	vec3 p2 = deformSlime(position + bitangent * eps, normalize(position + bitangent * eps), TIME, breathe, imp1Osc, imp1Bounce, imp2Osc, crawlWave, pre, spList, solidCount);

	vec3 deformedNormal = normalize(cross(p1 - p0, p2 - p0) + nrm * 1e-4);

	vec4 worldPos = MODEL_MATRIX * vec4(p0, 1.0);
	vWorldPosition = worldPos.xyz;

	vec4 mvPosition = VIEW_MATRIX * worldPos;
	vViewPosition = -mvPosition.xyz;

	vNormal = normalize(mat3(MODELVIEW_MATRIX) * deformedNormal);
	vWorldNormal = normalize(mat3(MODEL_MATRIX) * deformedNormal);

	float distToPoke = distance(position, uImpulsePos);
	float distToPoke2 = distance(position, uImpulse2Pos);
	vRippleMask = exp(-distToPoke * 1.5) * imp1Decay + exp(-distToPoke2 * 1.5) * imp2Decay;

	vCausticA = lin2srgb(uCausticA);
	vCausticB = lin2srgb(uCausticB);
	vShallowTint = mix(lin2srgb(uDayShallow), lin2srgb(uNightShallow), uNightMode);
	vDeepTint = mix(lin2srgb(uDayDeep), lin2srgb(uNightDeep), uNightMode);
	vRimColor = mix(lin2srgb(uRimDay), lin2srgb(uRimNight), uNightMode);
	vBubbleColor = lin2srgb(uBubbleColor) * uBubbleBoost;
	vEyeColor = lin2srgb(uEyeColor);
	vOutlineColor = mix(lin2srgb(uOutlineDay), lin2srgb(uOutlineNight), uNightMode);

	VERTEX = p0;
	NORMAL = deformedNormal;
}

// ------------------------------------------------------------------------------------------------
// Fragment
// ------------------------------------------------------------------------------------------------

vec3 srgb2lin(vec3 c) {
	vec3 hi = pow((c + vec3(0.055)) / 1.055, vec3(2.4));
	vec3 lo = c / 12.92;
	return mix(hi, lo, step(c, vec3(0.04045)));
}

vec4 permute(vec4 x) { return mod(((x * 34.0) + 1.0) * x, 289.0); }
vec4 taylorInvSqrt(vec4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

float snoise(vec3 v) {
	const vec2 C = vec2(1.0 / 6.0, 1.0 / 3.0);
	const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);
	vec3 i = floor(v + dot(v, C.yyy));
	vec3 x0 = v - i + dot(i, C.xxx);
	vec3 g = step(x0.yzx, x0.xyz);
	vec3 l = 1.0 - g;
	vec3 i1 = min(g.xyz, l.zxy);
	vec3 i2 = max(g.xyz, l.zxy);
	vec3 x1 = x0 - i1 + 1.0 * C.xxx;
	vec3 x2 = x0 - i2 + 2.0 * C.xxx;
	vec3 x3 = x0 - 1.0 + 3.0 * C.xxx;
	i = mod(i, 289.0);
	vec4 p = permute(permute(permute(
			i.z + vec4(0.0, i1.z, i2.z, 1.0))
			+ i.y + vec4(0.0, i1.y, i2.y, 1.0))
			+ i.x + vec4(0.0, i1.x, i2.x, 1.0));
	float n_ = 1.0 / 7.0;
	vec3 ns = n_ * D.wyz - D.xzx;
	vec4 j = p - 49.0 * floor(p * ns.z * ns.z);
	vec4 x_ = floor(j * ns.z);
	vec4 y_ = floor(j - 7.0 * x_);
	vec4 x = x_ * ns.x + ns.yyyy;
	vec4 y = y_ * ns.x + ns.yyyy;
	vec4 h = 1.0 - abs(x) - abs(y);
	vec4 b0 = vec4(x.xy, y.xy);
	vec4 b1 = vec4(x.zw, y.zw);
	vec4 s0 = floor(b0) * 2.0 + 1.0;
	vec4 s1 = floor(b1) * 2.0 + 1.0;
	vec4 sh = -step(h, vec4(0.0));
	vec4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
	vec4 a1 = b1.xzyw + s1.xzyw * sh.zzww;
	vec3 p0 = vec3(a0.xy, h.x);
	vec3 p1 = vec3(a0.zw, h.y);
	vec3 p2 = vec3(a1.xy, h.z);
	vec3 p3 = vec3(a1.zw, h.w);
	vec4 nrm = taylorInvSqrt(vec4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
	p0 *= nrm.x;
	p1 *= nrm.y;
	p2 *= nrm.z;
	p3 *= nrm.w;
	vec4 m = max(0.6 - vec4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
	m = m * m;
	return 42.0 * dot(m * m, vec4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

// Screen texture is linear in Godot; the HTML worked on display values, so convert on the way in.
vec3 sampleScreen(vec2 uvGl) {
	return lin2srgb(texture(tRefraction, vec2(uvGl.x, 1.0 - uvGl.y)).rgb);
}

void fragment() {
	float t = TIME;
	// GL-style screen UV (origin bottom-left) so every offset below keeps the HTML's sign convention.
	vec2 screenUV = vec2(SCREEN_UV.x, 1.0 - SCREEN_UV.y);
	vec3 viewDir = normalize(vViewPosition);
	vec3 normal = normalize(vNormal);
	vec3 worldNormal = normalize(vWorldNormal);

	vec3 noiseCoord = vWorldPosition * uRippleNoiseScale + vec3(0.0, -t * 0.45, t * 0.25);
	float n1 = snoise(noiseCoord);
	float n2 = (uShaderLOD > 0.5) ? n1 : snoise(noiseCoord * 1.8 - vec3(t * 0.35));

	float ndotv = max(0.0, dot(normal, viewDir));
	float edgeFactor = pow(1.0 - ndotv, 1.5);

	vec2 rippleOffset = vec2(n1 * 0.7 + n2 * 0.3, n2 * 0.7 - n1 * 0.3)
		* 0.012 * uRippleIntensity * (0.35 + 0.65 * edgeFactor + vRippleMask * 1.2);

	vec2 lensOffset = normal.xy * (0.065 * uRefractionStrength);
	vec2 totalDistortion = lensOffset + rippleOffset;

	float disp = 0.009 * uDispersion;
	vec2 dir = normalize(totalDistortion + vec2(0.0001));

	vec2 uvR = clamp(screenUV - totalDistortion * (1.0 - 0.18 * uDispersion) + dir * disp * 0.4, vec2(0.002), vec2(0.998));
	vec2 uvG = clamp(screenUV - totalDistortion * 1.0, vec2(0.002), vec2(0.998));
	vec2 uvB = clamp(screenUV - totalDistortion * (1.0 + 0.22 * uDispersion) - dir * disp * 0.55, vec2(0.002), vec2(0.998));

	vec3 sG = sampleScreen(uvG);
	vec3 sR = (uShaderLOD > 0.5) ? sG : sampleScreen(uvR);
	vec3 sB = (uShaderLOD > 0.5) ? sG : sampleScreen(uvB);

	vec3 refractedColor = vec3(sR.r, sG.g, sB.b);

	float edgeDelta = clamp(length(sG - sB) * 1.5, 0.0, 0.45);
	vec3 greenCyanCaustic = mix(vCausticA, vCausticB, n1 * 0.5 + 0.5);
	float basalMask = smoothstep(0.05, -0.72, vLocalPos.y) * smoothstep(0.1, 0.85, 1.0 - ndotv);
	refractedColor += greenCyanCaustic * edgeDelta * 0.45 * uDispersion;
	refractedColor = mix(refractedColor, greenCyanCaustic * 0.92, basalMask * 0.28 * clamp(uDispersion, 0.0, 1.4));

	float fresnel = pow(1.0 - ndotv, 2.6);

	float thickness = pow(ndotv, 0.65);
	vec3 jellyTint = mix(vShallowTint, vDeepTint, thickness);

	float effectiveOpacity = clamp(uOpacity * (0.72 + 0.48 * thickness), 0.05, 0.95);
	vec3 color = mix(refractedColor, jellyTint, effectiveOpacity);

	float topGradient = smoothstep(-0.8, 1.0, worldNormal.y);
	color += uTopGlow * topGradient * (1.0 - uNightMode * 0.4);

	float innerRim = smoothstep(0.38, 0.82, fresnel) * uRimStrength;
	color = mix(color, vRimColor, clamp(innerRim * 0.78, 0.0, 0.92));

	vec3 localP = vLocalPos * uBubbleNoiseScale + vec3(0.0, t * 0.6, 0.0);
	float bubbleField = 0.0;
	if (uShaderLOD < 0.5) {
		float bubbleNoise1 = snoise(localP);
		float bubbleNoise2 = 0.5 + 0.5 * (sin(localP.x * 7.3 + localP.y * 5.1 + n1 * 4.2) * cos(localP.z * 7.9 - t * 2.4));
		bubbleField = smoothstep(0.55, 0.72, bubbleNoise1) * smoothstep(0.4, 0.6, bubbleNoise2);
	}
	float depthFactor = smoothstep(-0.8, 0.6, vLocalPos.y);
	color = mix(color, vBubbleColor, bubbleField * depthFactor * 0.55 * clamp(uRippleIntensity * 2.0, 0.2, 1.5));

	vec3 lp = normalize(vLocalPos);
	float eyeYaw = atan(lp.x, lp.z) - uFacing;
	eyeYaw = atan(sin(eyeYaw), cos(eyeYaw));
	float eyeElev = asin(clamp(lp.y, -1.0, 1.0));
	float targetElev = mix(uEyeElevation, 0.48, uLiquid);
	vec2 eyeSz = mix(uEyeSize, vec2(uEyeSize.x * 1.3, uEyeSize.y * 0.9), uLiquid);
	vec2 eq = vec2((abs(eyeYaw) - uEyeSeparation) / eyeSz.x, (eyeElev - targetElev) / (eyeSz.y * uBlink));
	float eyeMask = 1.0 - smoothstep(0.82, 1.0, length(eq));
	color = mix(color, vEyeColor, eyeMask * 0.97);

	// Water-slime surface interaction: refractive submerged caustics, thin glinting meniscus lip & glossy wet sheen
	if (uWaterSubmersion > 0.005 && uWaterY > -9000.0) {
		float h_spd = length(uWaterVel.xz);
		float waveY = uWaterY + sin(vWorldPosition.x * 2.4 + t * 2.8) * cos(vWorldPosition.z * 2.4 - t * 2.2) * (0.030 + clamp(h_spd * 0.008, 0.0, 0.035));
		float distFromWater = vWorldPosition.y - waveY;
		float underMask = 1.0 - smoothstep(-0.04, 0.03, distFromWater);

		// Soft volumetric underwater refraction glow (reuses n1 for zero extra simplex calls)
		float submergedDepth = clamp(-distFromWater, 0.0, 1.2);
		float bokehGlow = pow(clamp(0.5 + 0.5 * (sin(vWorldPosition.x * 2.3 + n1 * 2.5 + t * 0.8) * cos(vWorldPosition.z * 2.1 - t * 0.7)), 1e-4, 1.0), 3.0);
		color = mix(
			color,
			mix(vec3(0.06, 0.38, 0.62), vec3(0.38, 0.86, 0.96), bokehGlow * 0.55),
			underMask * clamp(0.16 + submergedDepth * 0.16 + bokehGlow * 0.12, 0.0, 0.38) * clamp(uWaterSubmersion * 1.4, 0.25, 1.0)
		);

		// Razor-crisp noise-eroded waterline meniscus sheen
		float menBreak = smoothstep(-0.15, 0.45, sin(vWorldPosition.x * 7.5 + vWorldPosition.z * 6.8 - t * 3.6) * 0.5 + n1 * 0.7);
		float men_d = distFromWater / 0.026;
		float menBand = exp(-(men_d * men_d)) * clamp(uWaterSubmersion * 3.5, 0.0, 1.0) * menBreak;
		color = mix(color, vec3(0.84, 0.97, 1.0), clamp(menBand * 0.62, 0.0, 0.72));
	}
	if (uWetness > 0.01) {
		float wetRim = pow(max(1.0 - ndotv, 1e-4), 1.9) * 0.58 + pow(max(worldNormal.y, 1e-4), 2.8) * 0.34;
		float wetSpec = smoothstep(0.72, 0.97, n1 * 0.24 + 0.76 * max(0.0, dot(reflect(-viewDir, normal), normalize(vec3(0.42, 0.86, 0.34)))));
		float dropSparkle = 0.5 + 0.5 * sin(vLocalPos.x * 16.0 + n2 * 4.5) * cos(vLocalPos.z * 17.0 - vLocalPos.y * 12.0 + t * 1.1);
		float droplets = smoothstep(0.84, 0.97, dropSparkle) * smoothstep(-0.1, 0.7, worldNormal.y);
		color += vec3(0.36, 0.80, 0.98) * (wetRim * 0.22 + wetSpec * 0.42 + droplets * 0.28) * uWetness;
	}

	float celOutline = smoothstep(0.84, 0.95, 1.0 - ndotv);
	color = mix(color, vOutlineColor, celOutline * 0.55 * clamp(uRimStrength, 0.0, 1.5));

	ALBEDO = srgb2lin(clamp(color, vec3(0.0), vec3(1.0)));
}
