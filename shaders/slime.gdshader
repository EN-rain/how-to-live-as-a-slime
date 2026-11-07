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
uniform vec3 uSolidPos[2];
uniform vec3 uSolidParam[2];
uniform vec3 uSolidHalf[2];
uniform vec3 uSolidDir[2];
uniform float uRippleIntensity = 0.12;
uniform float uFacing = 0.45;
uniform float uBlink = 1.0;
// Squeezing through a gap between solids: 0 = off, 1 = fully compressed across uSqueezeDir (a horizontal axis).
uniform float uSqueeze = 0.0;
uniform vec3 uSqueezeDir = vec3(1.0, 0.0, 0.0);

// Liquid puddle mode (hold Z key): flattens height, spreads outward, passes through small holes
uniform float uLiquid = 0.0;
uniform float uOverheadCompress = 1.0;

// Engulf drape mode (holding Z on top of a larger object)
uniform vec3 uDrapePos = vec3(0.0);
uniform vec3 uDrapeHalf = vec3(0.01);
uniform float uDrapeShape = 0.0;
uniform float uDrapeYaw = 0.0;
uniform float uDrapeAmt = 0.0;

// Budding fission (split animation for E and Q).
// uBudAmt 0→1: grows a secondary lobe out of the parent body.
// uBudDir: world-space direction the bud grows toward (normalized, local to this mesh).
// uBudScale: how large the bud lobe is relative to the parent body (0 → 1).
// Set uSplitAmt separately for the neck-snap oscillation impulse at detach moment.
uniform float uBudAmt = 0.0;
uniform vec3 uBudDir = vec3(0.0, 0.0, -1.0);
uniform float uBudScale = 0.0;
// Legacy: also keep uSplitAmt for the snap jiggle that fires on the clone side.
uniform float uSplitAmt = 0.0;
uniform vec3 uSplitDir = vec3(0.0, 0.0, -1.0);

uniform sampler2D tRefraction : hint_screen_texture, repeat_disable, filter_linear;

varying vec3 vWorldPosition;
varying vec3 vViewPosition;
varying vec3 vNormal;
varying vec3 vWorldNormal;
varying vec3 vLocalPos;
varying float vRippleMask;

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

// Same tap pattern as dentPush (a small disc of taps facing the obstacle) so the push is averaged, not aliased.
vec3 solidDent(vec3 p, vec3 c, float shape, vec3 h, float yaw, float blur, vec3 nOv) {
	float cy = cos(yaw);
	float sy = sin(yaw);
	vec3 dv = p - c;
	vec3 q = vec3(dv.x * cy - dv.z * sy, dv.y, dv.x * sy + dv.z * cy);
	vec3 nL = vec3(nOv.x * cy - nOv.z * sy, 0.0, nOv.x * sy + nOv.z * cy);
	vec3 u = vec3(-nL.z, 0.0, nL.x);
	vec3 v = vec3(0.0, 1.0, 0.0);
	float R = blur;
	vec3 acc = solidPushLocal(q, shape, h) * 0.28;
	acc += solidPushLocal(q + u * R, shape, h) * 0.12;
	acc += solidPushLocal(q - u * R, shape, h) * 0.12;
	acc += solidPushLocal(q + v * R, shape, h) * 0.12;
	acc += solidPushLocal(q - v * R, shape, h) * 0.12;
	acc += solidPushLocal(q + (u + v) * R * 0.7071, shape, h) * 0.06;
	acc += solidPushLocal(q + (u - v) * R * 0.7071, shape, h) * 0.06;
	acc += solidPushLocal(q + (-u + v) * R * 0.7071, shape, h) * 0.06;
	acc += solidPushLocal(q + (-u - v) * R * 0.7071, shape, h) * 0.06;
	return vec3(acc.x * cy + acc.z * sy, acc.y, -acc.x * sy + acc.z * cy);
}

vec3 deformSlime(vec3 pos, vec3 norm, float t) {
	vec3 p = pos;

	float height01 = clamp((p.y / 1.6 + 1.0) * 0.5, 0.0, 1.0);
	float bellyCurve = sin(height01 * 3.14159265);
	float lowerBulge = pow(1.0 - height01, 1.35) * smoothstep(0.0, 0.22, height01);
	float bellySpread = 1.0 + (lowerBulge * 0.34 + bellyCurve * 0.08) * (0.8 + uMelt * 1.1);
	p.xz *= bellySpread;

	p.y *= (0.86 - uMelt * 0.22);

	float groundFloor = -1.6 * (0.86 - uMelt * 0.22);

	float baseH = p.y - groundFloor;
	if (baseH < 0.9) {
		float tB = clamp(baseH / 0.9, 0.0, 1.0);
		p.y = groundFloor + 0.9 * (2.0 * tB * tB - tB * tB * tB);
	}

	if (uSqueeze > 0.001) {
		// Squeezing through a gap: bottleneck constriction along flow passage (neck pinched, front/rear bulges)
		float sq = clamp(uSqueeze, 0.0, 0.94);
		vec2 sqd = normalize(uSqueezeDir.xz + vec2(0.0001));
		vec2 fwdFlow = vec2(-sqd.y, sqd.x);
		float sqa = dot(p.xz, sqd);
		float flowDist = dot(p.xz, fwdFlow);
		// Local neck constriction: maximum compression at neck (flowDist ~ 0), relaxing towards front and rear
		float neckProfile = exp(-flowDist * flowDist * 1.6);
		float localSq = sq * mix(0.4, 1.0, neckProfile);
		float widthScale = max(0.08, 1.0 - localSq);
		// Front and rear bulge out to conserve fluid volume
		float bulge = sq * (1.0 - neckProfile) * 0.45;
		float lengthScale = 1.0 + sq * 0.75 + bulge;
		float heightScale = 1.0 + localSq * 0.35 * (1.0 - uLiquid);
		p.xz = sqd * (sqa * widthScale) + fwdFlow * (flowDist * lengthScale);
		p.y = groundFloor + (p.y - groundFloor) * heightScale;
	}

	if (uLiquid > 0.001) {
		// Volume-preserving liquid puddle flattening:
		// At 22% height, conservation of volume requires spread = 1 / sqrt(0.22) ≈ 2.13x.
		float targetH = 0.22 * uOverheadCompress;
		float liqH = mix(1.0, targetH, uLiquid);
		float liqR = mix(1.0, 1.0 / sqrt(max(0.04, targetH)), uLiquid);
		if (uSqueeze > 0.001) {
			vec2 sqd = normalize(uSqueezeDir.xz + vec2(0.0001));
			vec2 fwdFlow = vec2(-sqd.y, sqd.x);
			float sqa = dot(p.xz, sqd);
			float flowDist = dot(p.xz, fwdFlow);
			// Area-preserving squeeze in liquid: compressing sqd axis expands fwdFlow proportionally
			p.xz = sqd * (sqa * mix(1.0, 0.45, uLiquid)) + fwdFlow * (flowDist * mix(1.0, liqR * 1.25, uLiquid));
		} else {
			p.xz *= liqR;
		}
		p.y = groundFloor + (p.y - groundFloor) * liqH;

		// Directional flow surge: the leading edge surges forward in movement direction
		vec2 mdir = normalize(uMoveDir.xz + vec2(0.0001));
		float flowAlong = dot(p.xz, mdir);
		p.xz += mdir * (uMoveAmt * 0.30 * uLiquid * smoothstep(-1.2, 1.8, flowAlong));

		// Viscous amoebic perimeter ripples (surface tension lobes)
		float ang = atan(p.z, p.x);
		float edgeWobble = (sin(ang * 4.0 + t * 4.0) * 0.06 + sin(ang * 6.0 - t * 3.0) * 0.03) * uLiquid;
		float distCenter = length(p.xz);
		p.xz *= 1.0 + edgeWobble * smoothstep(0.4, 2.0, distCenter);

		// Capillary surface ripples propagating across the liquid sheet
		float capRipple = sin(distCenter * 4.0 - t * 7.0 + flowAlong * 2.0) * 0.030 * uLiquid;
		p.y += capRipple * smoothstep(0.0, 0.35, p.y - groundFloor);
	}

	// ---- Sticky Droplet Budding (E and Q split) ----
	// Softly draws out a sticky droplet peak toward the separating partner.
	// Preserves smooth convex jelly curvature with NO flat cut face, NO pinch dents, and NO distorted peanut mesh.
	if (uSplitAmt > 0.001) {
		vec2 sdir = normalize(uSplitDir.xz + vec2(0.0001));
		float sproj = dot(p.xz, sdir);

		// Soft teardrop stretch toward the separating partner
		float stretch = smoothstep(-0.3, 1.2, sproj) * uSplitAmt * 0.35;

		p.xz += sdir * stretch;
	}

	float breathe = sin(t * 2.0) * 0.022 * uJiggleStrength;
	p.y *= (1.0 + breathe);
	p.xz *= (1.0 - breathe * 0.45);

	float gentleSway = sin(p.y * 2.2 - t * 2.4) * 0.012 * uJiggleStrength;
	p.xz += norm.xz * gentleSway * smoothstep(0.05, 0.5, height01);

	float distToPoke = distance(pos, uImpulsePos);
	float pokeInfluence = exp(-distToPoke * 1.15);
	float springOsc = sin(uImpulseTime * 14.0) * exp(-uImpulseTime * 3.0);
	vec3 impulseOffset = uImpulseVector * pokeInfluence * springOsc * uJiggleStrength;

	float distToPoke2 = distance(pos, uImpulse2Pos);
	float pokeInfluence2 = exp(-distToPoke2 * 1.15);
	float springOsc2 = sin(uImpulse2Time * 14.0) * exp(-uImpulse2Time * 3.0);
	vec3 impulseOffset2 = uImpulse2Vector * pokeInfluence2 * springOsc2 * uJiggleStrength;

	float globalBounce = sin(uImpulseTime * 11.0) * exp(-uImpulseTime * 2.6) * length(uImpulseVector) * 0.32 * uJiggleStrength;
	p.y += globalBounce * (height01 - 0.15);
	p.xz -= globalBounce * 0.38 * p.xz * (1.0 - height01 * 0.5);

	p += (impulseOffset + impulseOffset2) * smoothstep(0.02, 0.25, height01);

	for (int i = 0; i < 6; i++) {
		if (uEatParam[i].y > 0.001) {
			p += dentPush(p, uEatPos[i], uEatParam[i].x, uBoxHalf[i], uEatParam[i].z, 0.26, vec3(0.0)) * uEatParam[i].y;
		}
	}
	// In liquid puddle mode the slime is a flat disk — press/splat/solid-dent deformations
	// were designed for the upright blob and look wrong on the expanded puddle. Fade them out.
	float solidBlend = 1.0 - uLiquid;

	float effPress = uPressAmt * solidBlend;
	if (effPress > 0.001) {
		vec2 pd2 = normalize(uPressDir.xz + vec2(0.0001));
		float al = dot(p.xz, pd2);
		vec2 pp = p.xz - pd2 * al;
		float anchor = 1.9;
		al = anchor + (al - anchor) * (1.0 - 0.12 * effPress);
		p.xz = pd2 * al + pp * (1.0 + 0.07 * effPress);
		p.y = groundFloor + (p.y - groundFloor) * (1.0 + 0.05 * effPress);
	}
	float effSplat = uSplat * solidBlend;
	float effSpread = uSpread * solidBlend;
	if (effSplat > 0.001 || effSpread > 0.001) {
		// Splat model: the body compresses toward the wall (anchored at the contact plane), the top carries on forward
		// while the floor-gripping base lags, and the mass spreads sideways/up with a slower lag (viscous).
		vec2 sd = normalize(uSplatDir.xz + vec2(0.0001));
		float sa = dot(p.xz, sd);
		vec2 sperp = p.xz - sd * sa;
		float wallS = uWall;
		sa = wallS + (sa - wallS) * (1.0 - 0.34 * effSplat);
		sa += effSplat * 0.16 * (height01 - 0.15);
		p.xz = sd * sa + sperp * (1.0 + 0.34 * effSpread);
		p.y = groundFloor + (p.y - groundFloor) * (1.0 + 0.10 * effSpread);
	}
	p.y = max(p.y, groundFloor);

	float wave = 0.5 + 0.5 * sin(uCrawl);
	float sy = 1.0 + uMoveAmt * (0.10 * wave - 0.04);
	p.xz *= 1.0 / sqrt(sy);
	p.y = groundFloor + (p.y - groundFloor) * sy;
	vec2 d = normalize(uMoveDir.xz + vec2(0.0001));
	p.xz -= uLean.xz * (height01 - 0.2) * 0.38;
	float tw = sin(uCrawl - dot(pos.xz, d) * 2.8);
	float twMask = smoothstep(0.1, 0.6, height01);
	p.y += uMoveAmt * 0.07 * tw * twMask;
	p.xz += norm.xz * uMoveAmt * 0.03 * tw * twMask;

	// Wrap the body around whatever it is squashed against — faded out in liquid mode or heavy squeeze.
	float dentBlend = solidBlend * (1.0 - clamp(uSqueeze, 0.0, 1.0) * 0.65);
	for (int i = 0; i < 2; i++) {
		float solidAmt = uSolidParam[i].y * dentBlend;
		if (solidAmt > 0.001) {
			float ring = length(solidDent(p, uSolidPos[i], uSolidParam[i].x, uSolidHalf[i], uSolidParam[i].z, 0.55, uSolidDir[i]));
			p += norm * ring * 0.3 * solidAmt;
			p += solidDent(p, uSolidPos[i], uSolidParam[i].x, uSolidHalf[i], uSolidParam[i].z, 0.15, uSolidDir[i]) * solidAmt;
		}
	}

	if (uDrapeAmt > 0.001) {
		float cy = cos(uDrapeYaw);
		float sy = sin(uDrapeYaw);
		vec3 dv = p - uDrapePos;
		vec3 q = vec3(dv.x * cy - dv.z * sy, dv.y, dv.x * sy + dv.z * cy);
		vec2 topReach = max(uDrapeHalf.xz * 1.18, vec2(0.2));
		p.xz = mix(p.xz, normalize(p.xz + vec2(0.0001)) * length(topReach), uDrapeAmt * 0.65);
		if (dv.y < 0.0) {
			p.y = mix(p.y, uDrapePos.y - abs(dv.y) * 1.25, uDrapeAmt * 0.45);
		}
	}

	return p;
}

void vertex() {
	vec3 position = VERTEX;
	vec3 nrm = NORMAL;
	vLocalPos = position;

	vec3 tangent = normalize(cross(nrm, vec3(0.0, 1.0, 0.1)));
	vec3 bitangent = normalize(cross(nrm, tangent));
	float eps = 0.025;

	vec3 p0 = deformSlime(position, nrm, TIME);
	vec3 p1 = deformSlime(position + tangent * eps, normalize(position + tangent * eps), TIME);
	vec3 p2 = deformSlime(position + bitangent * eps, normalize(position + bitangent * eps), TIME);

	vec3 deformedNormal = normalize(cross(p1 - p0, p2 - p0));

	vec4 worldPos = MODEL_MATRIX * vec4(p0, 1.0);
	vWorldPosition = worldPos.xyz;

	vec4 mvPosition = VIEW_MATRIX * worldPos;
	vViewPosition = -mvPosition.xyz;

	vNormal = normalize(mat3(MODELVIEW_MATRIX) * deformedNormal);
	vWorldNormal = normalize(mat3(MODEL_MATRIX) * deformedNormal);

	float distToPoke = distance(position, uImpulsePos);
	float distToPoke2 = distance(position, uImpulse2Pos);
	vRippleMask = exp(-distToPoke * 1.5) * exp(-uImpulseTime * 2.5) + exp(-distToPoke2 * 1.5) * exp(-uImpulse2Time * 2.5);

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

vec3 lin2srgb(vec3 c) {
	c = max(c, vec3(0.0));
	vec3 hi = 1.055 * pow(c, vec3(1.0 / 2.4)) - vec3(0.055);
	vec3 lo = c * 12.92;
	return mix(hi, lo, step(c, vec3(0.0031308)));
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
	float n2 = snoise(noiseCoord * 1.8 - vec3(t * 0.35));

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
	vec2 uvGY = clamp(screenUV - totalDistortion * (1.0 + 0.10 * uDispersion) - dir * disp * 0.25, vec2(0.002), vec2(0.998));
	vec2 uvB = clamp(screenUV - totalDistortion * (1.0 + 0.22 * uDispersion) - dir * disp * 0.55, vec2(0.002), vec2(0.998));

	vec3 sR = sampleScreen(uvR);
	vec3 sG = sampleScreen(uvG);
	vec3 sGY = sampleScreen(uvGY);
	vec3 sB = sampleScreen(uvB);

	vec3 refractedColor = vec3(sR.r, mix(sG.g, sGY.g, 0.5), sB.b);

	float edgeDelta = clamp(length(sG - sB) * 1.5, 0.0, 0.45);
	vec3 greenCyanCaustic = mix(lin2srgb(uCausticA), lin2srgb(uCausticB), n1 * 0.5 + 0.5);
	float basalMask = smoothstep(0.05, -0.72, vLocalPos.y) * smoothstep(0.1, 0.85, 1.0 - ndotv);
	refractedColor += greenCyanCaustic * edgeDelta * 0.45 * uDispersion;
	refractedColor = mix(refractedColor, greenCyanCaustic * 0.92, basalMask * 0.28 * clamp(uDispersion, 0.0, 1.4));

	float fresnel = pow(1.0 - ndotv, 2.6);

	vec3 shallowTint = mix(lin2srgb(uDayShallow), lin2srgb(uNightShallow), uNightMode);
	vec3 deepTint = mix(lin2srgb(uDayDeep), lin2srgb(uNightDeep), uNightMode);

	float thickness = pow(ndotv, 0.65);
	vec3 jellyTint = mix(shallowTint, deepTint, thickness);

	float effectiveOpacity = clamp(uOpacity * (0.72 + 0.48 * thickness), 0.05, 0.95);
	vec3 color = mix(refractedColor, jellyTint, effectiveOpacity);

	float topGradient = smoothstep(-0.8, 1.0, worldNormal.y);
	color += uTopGlow * topGradient * (1.0 - uNightMode * 0.4);

	float innerRim = smoothstep(0.38, 0.82, fresnel) * uRimStrength;
	vec3 rimColor = mix(lin2srgb(uRimDay), lin2srgb(uRimNight), uNightMode);
	color = mix(color, rimColor, clamp(innerRim * 0.78, 0.0, 0.92));

	vec3 localP = vLocalPos * uBubbleNoiseScale + vec3(0.0, t * 0.6, 0.0);
	float bubbleNoise1 = snoise(localP);
	float bubbleNoise2 = snoise(localP * 2.2 - vec3(0.0, t * 1.1, 0.0));
	float bubbleField = smoothstep(0.55, 0.72, bubbleNoise1) * smoothstep(0.4, 0.6, bubbleNoise2);
	float depthFactor = smoothstep(-0.8, 0.6, vLocalPos.y);
	vec3 bubbleColor = lin2srgb(uBubbleColor) * uBubbleBoost;
	color = mix(color, bubbleColor, bubbleField * depthFactor * 0.55 * clamp(uRippleIntensity * 2.0, 0.2, 1.5));

	vec3 lp = normalize(vLocalPos);
	float eyeYaw = atan(lp.x, lp.z) - uFacing;
	eyeYaw = atan(sin(eyeYaw), cos(eyeYaw));
	float eyeElev = asin(clamp(lp.y, -1.0, 1.0));
	float targetElev = mix(uEyeElevation, 0.48, uLiquid);
	vec2 eyeSz = mix(uEyeSize, vec2(uEyeSize.x * 1.3, uEyeSize.y * 0.9), uLiquid);
	vec2 eq = vec2((abs(eyeYaw) - uEyeSeparation) / eyeSz.x, (eyeElev - targetElev) / (eyeSz.y * uBlink));
	float eyeMask = 1.0 - smoothstep(0.82, 1.0, length(eq));
	color = mix(color, lin2srgb(uEyeColor), eyeMask * 0.97);

	float celOutline = smoothstep(0.84, 0.95, 1.0 - ndotv);
	vec3 outlineColor = mix(lin2srgb(uOutlineDay), lin2srgb(uOutlineNight), uNightMode);
	color = mix(color, outlineColor, celOutline * 0.55 * clamp(uRimStrength, 0.0, 1.5));

	ALBEDO = srgb2lin(clamp(color, vec3(0.0), vec3(1.0)));
}
