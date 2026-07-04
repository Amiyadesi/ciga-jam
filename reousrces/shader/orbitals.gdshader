// Gravitational Waves — Kerr Geodesic Edition (Godot canvas_item port)
// Spacetime fabric rendered by ray-marching spatial geodesics around two
// spinning (Kerr) black holes, with explicit Lense-Thirring frame-dragging.
//
// Apply to a fullscreen ColorRect (or any CanvasItem). FRAGCOORD origin is
// top-left in Godot; if the orbit appears mirrored vs. the original, flip Y
// in the `uv` line below.

shader_type canvas_item;

#define PI  3.14159265359
#define TAU 6.28318530718


uniform float zoom       : hint_range(0.1, 50) = 1.0; 
uniform vec2  pan        = vec2(0.0);
uniform float time_scale : hint_range(0.0, 5.0) = 1.0;


float hash(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(
		mix(hash(i),              hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * 2.0;
		a *= 0.5;
	}
	return v;
}

const float CYCLE = 28.0;
const float MERGE = 0.82;
const float C_GW  = 0.45;

const float Q     = 0.62;
const float ETA   = Q / ((1.0 + Q) * (1.0 + Q));
const float SPEED = 2.5;

const float M_SCALE = 0.025;
// Kerr's
const float SPIN1   = 0.75;
const float SPIN2   = 0.60;
const float SPIN_F  = 0.67;

float cyclePhase() { return mod(TIME * time_scale, CYCLE) / CYCLE; }

float tauPN(float p) { return max(MERGE - p, 0.0) / MERGE; }

float orbitR(float p) {
	float t = tauPN(p);
	float r = 0.26 * pow(t + 0.0025, 0.25);
	return r * (1.0 - smoothstep(MERGE - 0.015, MERGE, p));
}

float orbitAngle(float p) {
	float t = tauPN(p);
	float phase   = 8.0 * SPEED * (1.0 - pow(t, 0.625));
	float precess = 0.6 * ETA * phase;
	return TAU * phase + precess;
}

float gwFreq(float p) {
	float t = tauPN(p);
	float f = 0.5 * SPEED / pow(t + 0.0008, 0.375);
	f = min(f, 12.0 * SPEED);
	return mix(f, f * 1.15, smoothstep(MERGE, MERGE + 0.04, p));
}

float gwAmp(float p) {
	float t = 1.0 - tauPN(p);
	float inspiral = mix(0.012, 0.18, pow(t, 2.0));
	float postT = max(p - MERGE, 0.0) / (1.0 - MERGE);
	return p < MERGE ? inspiral : 0.18 * exp(-postT * 5.5);
}

float delayedPhase(float r) {
	float rSrc  = orbitR(cyclePhase()) + 0.01;
	float rProp = max(r - rSrc, 0.0);
	return mod(TIME * time_scale - rProp / C_GW, CYCLE) / CYCLE;
}

vec2 bodyPos(float p, int which) {
	float a = orbitAngle(p);
	float r = orbitR(p);
	float r1 = r * Q / (1.0 + Q);
	float r2 = r       / (1.0 + Q);
	return which == 0
		? vec2(cos(a),      sin(a))      * r1
		: vec2(cos(a + PI), sin(a + PI)) * r2;
}

float gwScalar(vec2 p, float ph) {
	float r = length(p);
	if (r < 0.01) return 0.0;

	float phDel = delayedPhase(r);
	float theta = atan(p.y, p.x);
	float amp   = gwAmp(phDel);

	float env = amp / (0.1 + sqrt(r) * 0.5);
	float psi = 2.0 * orbitAngle(phDel);

	float hP = env * cos(2.0 * theta - psi);
	float hX = env * sin(2.0 * theta - psi) * 0.5;
	return hP + hX;
}

float frameDragOmega(float r, float M, float a) {
	float r2 = r * r;
	float r4 = r2 * r2;
	float denom = r4 + a * a * r2 + 2.0 * M * a * a * r;
	return 2.0 * M * a * r / max(denom, 1e-8);
}

float kerrHorizon(float M, float a) {
	return M + sqrt(max(M * M - a * a, 0.0));
}

vec2 kerrGeodesicWarp(vec2 p, vec2 c, float M, float a) {
	vec2  d0 = p - c;
	float r0 = length(d0);
	if (r0 < 1e-4) return vec2(0.0);

	float rH = kerrHorizon(M, a) * 1.05;

	if (r0 < rH) return -d0 * 3.0;

	float falloff = exp(-r0 * 2.6);
	if (falloff < 1e-3) return vec2(0.0);

	const float K_R = 0.55;
	const float K_W = 0.22;
	const int   N   = 7;

	vec2 pos = d0;
	vec2 acc = vec2(0.0);

	for (int i = 0; i < N; i++) {
		float r = length(pos);
		if (r < rH) { acc += -normalize(pos) * (rH - r); break; }

		float ds = clamp(r * 0.22, 0.005, 0.08);

		vec2  rhat   = pos / r;
		vec2  phihat = vec2(-rhat.y, rhat.x);
		float delta  = max(r * r - 2.0 * M * r + a * a, 1e-4);
		float om1    = frameDragOmega(r, M, a);
		vec2  k1     = (-rhat * (K_R * M / delta) + phihat * (K_W * om1 * r)) * ds;

		vec2  mid    = pos + 0.5 * k1;
		float rm     = length(mid);
		if (rm < rH) { acc += k1; break; }
		vec2  rhat2   = mid / rm;
		vec2  phihat2 = vec2(-rhat2.y, rhat2.x);
		float deltam  = max(rm * rm - 2.0 * M * rm + a * a, 1e-4);
		float om2     = frameDragOmega(rm, M, a);
		vec2  k2      = (-rhat2 * (K_R * M / deltam) + phihat2 * (K_W * om2 * rm)) * ds;

		acc += k2;
		pos += k2;
	}

	return acc * falloff;
}

float gridLines(vec2 p, float spacing) {
	vec2 g = abs(mod(p + spacing * 0.5, vec2(spacing)) - spacing * 0.5);
	return 1.0 - smoothstep(0.0, spacing * 0.04, min(g.x, g.y));
}

vec2 wellWarp(vec2 p, vec2 c, float mass) {
	float M = mass * M_SCALE;
	float spin = mix(SPIN2, SPIN1, clamp(mass, 0.0, 1.0));
	float a = spin * M;
	return kerrGeodesicWarp(p, c, M, a);
}

float fabricGrid(vec2 p, float ph) {
	float h = gwScalar(p, ph);
	vec2 disp = vec2(h, -h) * 0.25;

	vec2 b1 = bodyPos(ph, 0);
	vec2 b2 = bodyPos(ph, 1);
	float M1 = 1.0 * M_SCALE;
	float M2 = Q   * M_SCALE;
	disp += kerrGeodesicWarp(p, b1, M1, SPIN1 * M1);
	disp += kerrGeodesicWarp(p, b2, M2, SPIN2 * M2);

	float post = smoothstep(MERGE, MERGE + 0.05, ph);
	float Mf = (1.0 + Q) * 0.95 * M_SCALE;
	vec2 remnant = kerrGeodesicWarp(p, vec2(0.0), Mf, SPIN_F * Mf);
	disp = mix(disp, remnant, post);

	vec2 dp = p + disp;
	return gridLines(dp, 0.08) * 0.85 + gridLines(dp, 0.02) * 0.15;
}

vec3 starfield(vec2 uv) {
	vec3 col = vec3(0.0);
	for (int L = 0; L < 3; L++) {
		float sc = 50.0 + float(L) * 110.0;
		vec2 id = floor(uv * sc);
		vec2 f  = fract(uv * sc);
		float r = hash(id + float(L) * 33.7);
		if (r > 0.96) {
			vec2 o = vec2(hash(id * 1.3 + 0.7), hash(id * 2.1 + 1.3));
			float d = length(f - o);
			float bri = pow(max(1.0 - d * 7.0, 0.0), 14.0 + float(L) * 8.0);
			bri *= 0.75 + 0.25 * sin(TIME * 1.3 + r * 80.0);
			float temp = hash(id + 5.0);
			vec3 tc = mix(vec3(0.65, 0.8, 1.0), vec3(1.0, 0.9, 0.7), temp);
			col += tc * bri * (0.3 + r);
		}
	}
	return col;
}

vec3 drawBody(vec2 uv, vec2 pos, float mass) {
	float d = length(uv - pos);
	float m = sqrt(mass);
	vec3 col = vec3(1.0, 0.98, 0.95) * exp(-d * d / (0.000025 * m * m)) * 5.0 * m;
	col += vec3(0.4, 0.6, 1.0) * exp(-d * d / (0.0004 * m * m)) * 2.0 * m;
	col += vec3(0.15, 0.25, 0.6) * exp(-d / (0.035 * m)) * 0.4 * m;
	return col;
}

vec3 mergerFlash(vec2 uv, float ph) {
	if (ph < MERGE - 0.02) return vec3(0.0);
	float d = length(uv);

	float flash = exp(-pow(ph - MERGE, 2.0) * 4000.0);
	vec3 col = vec3(1.0, 0.97, 0.92) * exp(-d * d * 50.0) * flash * 12.0;
	col    += vec3(0.5, 0.7, 1.0) * exp(-d * d * 12.0) * flash * 5.0;

	float ringT = max(ph - MERGE, 0.0) * 15.0;
	float ringR = ringT * 0.07;
	float ring  = exp(-pow(d - ringR, 2.0) / max(0.0003 + ringT * 0.0001, 0.0001));
	ring *= exp(-ringT * 0.4);
	col += vec3(0.3, 0.55, 1.0) * ring * 4.0 * step(MERGE, ph);

	return col;
}

vec3 aces(vec3 x) {
	return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);
}

void fragment() {
	vec2 rect_px = 1.0 / fwidth(UV);
	float aspect = rect_px.x / rect_px.y;
	vec2 uv = (UV - 0.5) * vec2(aspect, 1.0) / zoom + pan;

	float ph = cyclePhase();

	vec2 b1 = bodyPos(ph, 0);
	vec2 b2 = bodyPos(ph, 1);

	vec3 col = vec3(0.004, 0.007, 0.018);

	vec2 sUV = uv;
	float preMerge = 1.0 - smoothstep(MERGE - 0.01, MERGE + 0.03, ph);
	vec2 dB1 = uv - b1;
	vec2 dB2 = uv - b2;
	float rB1 = length(dB1);
	float rB2 = length(dB2);
	if (rB1 > 0.01) sUV += normalize(dB1) * 0.0002 / (rB1 * rB1 + 0.001) * preMerge;
	if (rB2 > 0.01) sUV += normalize(dB2) * 0.0002 / (rB2 * rB2 + 0.001) * preMerge * Q;

	col += starfield(sUV * 2.0) * 0.4;

	col += vec3(0.01, 0.003, 0.02) * fbm(sUV * 3.5 + 2.0) * fbm(sUV * 5.0 - 3.0) * 1.5;
	col += vec3(0.003, 0.01, 0.03) * fbm(sUV * 2.5 + 7.0) * 0.5;

	float h  = gwScalar(uv, ph);
	float hm = abs(h);
	float r  = length(uv);
	float fade = smoothstep(0.95, 0.2, r);

	if (r > 0.02) {
		float phDel = delayedPhase(r);
		float theta = atan(uv.y, uv.x);
		float psi   = 2.0 * orbitAngle(phDel);
		float wph   = 2.0 * theta - psi;
		float crest = pow(max(cos(wph), 0.0), 24.0);
		float quad  = 0.3 + 0.7 * abs(cos(2.0 * theta));
		float env   = gwAmp(phDel) / (0.1 + sqrt(r) * 0.5);
		col += vec3(0.05, 0.12, 0.3) * crest * quad * smoothstep(0.0, 0.015, env) * fade * 0.8;
	}

	float g = fabricGrid(uv, ph);

	vec3 gc = mix(
		vec3(0.02, 0.05, 0.12),
		vec3(0.08, 0.22, 0.5),
		smoothstep(0.003, 0.06, hm)
	);
	gc += vec3(0.1, 0.05, 0.0) * smoothstep(0.07, 0.2, hm);
	col += gc * g * fade * (0.22 + 0.68 * smoothstep(0.001, 0.025, hm));

	col += vec3(0.012, 0.03, 0.08) * smoothstep(0.008, 0.05, hm) * fade * 0.5;

	float eps = 0.003;
	vec2 grad = vec2(
		abs(gwScalar(uv + vec2(eps, 0.0), ph)) - hm,
		abs(gwScalar(uv + vec2(0.0, eps), ph)) - hm
	) / eps;
	float lit = dot(normalize(vec3(-grad * 4.0, 1.0)), normalize(vec3(0.3, 0.5, 1.0)));
	col *= 0.8 + 0.3 * lit;

	col += vec3(0.1, 0.22, 0.5) * pow(max(lit, 0.0), 48.0) * smoothstep(0.02, 0.08, hm) * 0.4 * fade;

	float bodyFade = 1.0 - smoothstep(MERGE - 0.01, MERGE + 0.02, ph);
	col += drawBody(uv, b1, 1.0) * bodyFade;
	col += drawBody(uv, b2, Q)   * bodyFade;

	col += drawBody(uv, vec2(0.0), (1.0 + Q) * 0.95)
	     * smoothstep(MERGE + 0.01, MERGE + 0.06, ph) * 1.8;

	col += mergerFlash(uv, ph);

	col = aces(col * 1.2);
	col = pow(col, vec3(1.0 / 2.2));

	float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(col, vec3(luma) * vec3(0.82, 0.9, 1.12), 0.15);

	col *= 1.0 - dot(uv * 0.85, uv * 0.85);

	COLOR = vec4(col, 1.0);
}
