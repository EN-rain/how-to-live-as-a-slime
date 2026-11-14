shader_type sky;

global uniform float u_time_of_day;
global uniform float u_weather_wetness;
global uniform float u_wind_strength;

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float up = clamp(dir.y, -1.0, 1.0);
	float horizon = pow(1.0 - clamp(abs(up), 0.0, 1.0), 3.2);

	// Orbital sun vector across the sky dome (0.25 = 06:00 sunrise, 0.50 = noon, 0.75 = sunset)
	float sun_angle = (u_time_of_day - 0.25) * 6.2831853;
	vec3 sun_dir = normalize(vec3(cos(sun_angle), sin(sun_angle), 0.34));
	vec3 moon_dir = -sun_dir;

	float sun_elev = sun_dir.y;
	float day_w = smoothstep(-0.08, 0.20, sun_elev);
	float twilight = smoothstep(-0.22, -0.02, sun_elev) * (1.0 - smoothstep(0.04, 0.26, sun_elev));
	float overcast = clamp(u_weather_wetness, 0.0, 1.0);

	// Zenith & Horizon Palette Keyframes (linear color space)
	vec3 night_top = vec3(0.008, 0.015, 0.045);
	vec3 night_hor = vec3(0.018, 0.032, 0.075);
	vec3 dawn_top  = vec3(0.20, 0.32, 0.62);
	vec3 dawn_hor  = vec3(0.95, 0.56, 0.36);
	vec3 day_top   = vec3(0.32, 0.60, 0.88);
	vec3 day_hor   = vec3(0.72, 0.84, 0.93);

	vec3 sky_top = mix(night_top, day_top, day_w);
	sky_top = mix(sky_top, dawn_top, twilight * 0.78);
	vec3 sky_hor = mix(night_hor, day_hor, day_w);
	sky_hor = mix(sky_hor, dawn_hor, twilight * 0.90);

	// Directional sunset/sunrise glow band around solar azimuth
	float sun_align = max(dot(normalize(vec3(dir.x, 0.0, dir.z)), normalize(vec3(sun_dir.x, 0.0, sun_dir.z) + vec3(1e-4))), 0.0);
	sky_hor += vec3(0.45, 0.22, 0.08) * (twilight * pow(sun_align, 3.0) * (1.0 - overcast * 0.75));

	// Darken & desaturate gracefully under overcast storm rain
	vec3 storm_top = mix(vec3(0.04, 0.055, 0.09), vec3(0.30, 0.35, 0.42), day_w);
	vec3 storm_hor = mix(vec3(0.06, 0.08, 0.12), vec3(0.44, 0.49, 0.56), day_w);
	sky_top = mix(sky_top, storm_top, overcast * 0.82);
	sky_hor = mix(sky_hor, storm_hor, overcast * 0.85);

	vec3 col = mix(sky_top, sky_hor, horizon);
	if (up < 0.0) {
		vec3 ground_col = mix(vec3(0.03, 0.04, 0.07), vec3(0.22, 0.26, 0.30), day_w);
		col = mix(sky_hor, ground_col, smoothstep(0.0, -0.25, up));
	}

	// Lightweight single-layer drifting clouds
	if (up > 0.01) {
		vec2 cloud_uv = dir.xz / (up + 0.18) * 1.45 + vec2(TIME * (0.012 + u_wind_strength * 0.035), TIME * 0.006);
		float cl_n = 0.65 * noise2(cloud_uv) + 0.35 * noise2(cloud_uv * 2.3 + vec2(4.1, -2.7));
		float cl_mask = smoothstep(mix(0.62, 0.30, overcast), mix(0.86, 0.68, overcast), cl_n) * smoothstep(0.01, 0.16, up);
		vec3 cl_day = mix(vec3(0.98, 0.99, 1.0), vec3(0.46, 0.50, 0.58), overcast * 0.85);
		cl_day = mix(cl_day, vec3(1.0, 0.74, 0.52), twilight * 0.65);
		vec3 cl_night = vec3(0.11, 0.15, 0.25);
		vec3 cl_col = mix(cl_night, cl_day, day_w);
		col = mix(col, cl_col, cl_mask * mix(0.55, 0.82, overcast));

		// Crisp pinpoint night starfield masked by daylight & storm clouds
		float star_vis = (1.0 - day_w) * (1.0 - overcast * 0.90) * smoothstep(0.06, 0.32, up);
		if (star_vis > 0.01) {
			vec2 s_uv = dir.xz / (up + 0.35) * 125.0;
			vec2 s_cell = floor(s_uv);
			vec2 s_f = fract(s_uv) - vec2(0.5);
			float s_rnd = hash21(s_cell);
			if (s_rnd > 0.962) {
				vec2 jitter = vec2(hash21(s_cell + 13.7), hash21(s_cell + 47.3)) * 0.55 - 0.275;
				float d = length(s_f - jitter);
				float dot_star = smoothstep(0.11, 0.015, d);
				float twinkle = 0.68 + 0.32 * sin(TIME * (1.8 + s_rnd * 4.0) + s_rnd * 40.0);
				col += vec3(0.84, 0.91, 1.0) * (dot_star * star_vis * twinkle * ((s_rnd - 0.962) / 0.038) * 1.15);
			}
		}
	}

	// Sun & Moon Discs (attenuated by rain clouds and horizon fade)
	float clear_sky = 1.0 - overcast * 0.88;
	float sun_dot = clamp(dot(dir, sun_dir), 0.0, 1.0);
	if (sun_dir.y > -0.05) {
		float disc = smoothstep(0.9988, 0.99945, sun_dot);
		float halo = pow(sun_dot, 36.0) * 0.45 + pow(sun_dot, 8.0) * 0.12;
		vec3 sun_col = mix(vec3(1.0, 0.58, 0.24), vec3(1.0, 0.96, 0.86), smoothstep(0.0, 0.30, sun_dir.y));
		col += sun_col * ((disc * 2.2 + halo) * clear_sky * smoothstep(-0.05, 0.06, sun_dir.y));
	}

	float moon_dot = clamp(dot(dir, moon_dir), 0.0, 1.0);
	if (moon_dir.y > -0.04) {
		float m_disc = smoothstep(0.99915, 0.99955, moon_dot);
		float m_halo = pow(moon_dot, 52.0) * 0.22;
		col += vec3(0.76, 0.86, 1.0) * ((m_disc * 1.15 + m_halo) * clear_sky * smoothstep(-0.04, 0.08, moon_dir.y));
	}

	COLOR = col;
}
