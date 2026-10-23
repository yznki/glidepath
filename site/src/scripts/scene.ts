// The night approach: one Three.js scene, one camera path, driven by the page driver (p = descent progress,
// t = seconds). No loop of its own: night.ts calls render() from the GSAP ticker.
import {
  AdditiveBlending,
  BufferAttribute,
  BufferGeometry,
  Float32BufferAttribute,
  LineBasicMaterial,
  LineSegments,
  PerspectiveCamera,
  Points,
  Scene as ThreeScene,
  ShaderMaterial,
  Vector3,
  WebGLRenderer,
} from 'three';

export type Pose = { x: number; y: number; z: number };

// Camera path: from the top of the approach (p = 0) to the threshold (p = 1). The runway runs along -z.
const Z0 = 120;
const Z1 = 22;
const Y0 = 26;
const Y1 = 1.7;
const FAR = 460; // runway length for depth shading
const HALF = 22; // runway half-width: wide enough to spread to the bottom-right corner on desktop

export const camPose = (p: number): Pose => ({ x: 0, y: Y0 + (Y1 - Y0) * p, z: Z0 + (Z1 - Z0) * p });
// The PR card flies ahead of the camera on the right and touches down at p = 1.
export const cardPose = (p: number): Pose => {
  const c = camPose(p);
  return { x: 2.6, y: 16 + (0.8 - 16) * p, z: c.z - (96 + (36 - 96) * p) };
};
// A fix is a point on the runway side, placed at the camera z where the fix passes.
export const fixPose = (at: number): Pose => ({ x: -9.5, y: 0.2, z: camPose(at).z });

const vertex = /* glsl */ `
attribute float aKind;   // 0 edge light, 1 approach bar, 2 amber signal, 3 threshold, 4 white PAPI
attribute float aSeq;    // approach: 0 at the threshold, 1 at the far end of the bar line
attribute float aDepth;  // 0 near the threshold, 1 at the far end (intro order)
attribute float aSize;
uniform float uTime;
uniform float uIntro;
uniform float uScale;
uniform float uPx;
uniform float uFar;
varying vec3 vCol;
varying float vA;
void main() {
  vec4 mv = modelViewMatrix * vec4(position, 1.0);
  float d = max(-mv.z, 0.1);
  float a = 1.0;
  // Approach rabbit: one pulse per 2.4 s runs from the far end toward the threshold.
  float head = 1.0 - fract(uTime / 2.4);
  float pulse = exp(-pow((aSeq - head) / 0.12, 2.0));
  if (aKind > 0.5 && aKind < 1.5) a = 0.28 + 0.72 * pulse;
  if (aKind > 2.5) a = 1.0;
  // Intro: lights switch on from the horizon toward you.
  // Near lights (depth 0: threshold, PAPI, the near edge) switch on last but still reach full strength (0.9 < 1).
  float thr = 0.9 * (1.0 - aDepth);
  a *= smoothstep(thr, thr + 0.06, uIntro);
  // Depth fade toward the far end of the runway.
  a *= clamp(1.0 - (d - 60.0) / uFar, 0.0, 1.0);
  vA = a;
  vCol = aKind > 1.5 && aKind < 2.5 ? vec3(0.82, 0.61, 0.27) : vec3(0.93, 0.94, 0.96);
  gl_PointSize = clamp(uScale * aSize * uPx / d, 1.2 * uPx, 22.0 * uPx);
  gl_Position = projectionMatrix * mv;
}`;

const fragment = /* glsl */ `
varying vec3 vCol;
varying float vA;
void main() {
  float r = length(gl_PointCoord - 0.5);
  float core = smoothstep(0.5, 0.12, r);
  float glow = exp(-r * r * 10.0);
  float a = (glow * 0.5 + core) * vA;
  if (a < 0.003) discard;
  gl_FragColor = vec4(vCol * a, a);
}`;

export type Scene = {
  canvas: HTMLCanvasElement;
  render(p: number, t: number, intro: number): void;
  project(x: number, y: number, z: number): { x: number; y: number; ahead: boolean; depth: number };
  resize(): void;
  dispose(): void;
};

export function createScene(host: HTMLElement, mobile: boolean): Scene | null {
  // Probe first: creating a renderer without WebGL logs an error from three.
  const probe = document.createElement('canvas');
  if (!probe.getContext('webgl2') && !probe.getContext('webgl')) return null;
  let renderer: WebGLRenderer;
  try {
    renderer = new WebGLRenderer({ antialias: false, alpha: true, powerPreference: 'high-performance' });
  } catch {
    return null;
  }
  const px = Math.min(window.devicePixelRatio || 1, mobile ? 1.5 : 2);
  renderer.setPixelRatio(px);
  renderer.setClearColor(0x030304, 1);
  host.appendChild(renderer.domElement);

  const camera = new PerspectiveCamera(50, 1, 0.5, 900);
  // Shift the view so the vanishing point sits at about 62% across and 30% down (desktop), or above the copy (phone).
  const shift = () => {
    const w = window.innerWidth;
    const h = window.innerHeight;
    camera.setViewOffset(w, h, mobile ? 0 : -w * 0.12, mobile ? h * 0.25 : h * 0.2, w, h);
  };

  // Edge lights, two rows converging on the vanishing point.
  const step = mobile ? 11 : 3.2;
  const pos: number[] = [];
  const kind: number[] = [];
  const seq: number[] = [];
  const depth: number[] = [];
  const size: number[] = [];
  const addPoint = (x: number, y: number, z: number, k: number, s: number, dpt: number, q = 0) => {
    pos.push(x, y, z);
    kind.push(k);
    seq.push(q);
    depth.push(dpt);
    size.push(s);
  };
  const edgeStart = 90; // from near the camera, so the runway fills the bottom-right corner
  const edgeEnd = -FAR;
  const nearEnd = -48; // denser edge lights from here to the camera, around the threshold
  const dptOf = (z: number) => Math.min(1, Math.max(0, -z / -edgeEnd));
  for (let z = edgeStart; z >= nearEnd; z -= mobile ? 4 : 1.6) {
    addPoint(-HALF, 0.25, z, 0, 2.0, dptOf(z));
    addPoint(HALF, 0.25, z, 0, 2.0, dptOf(z));
  }
  for (let z = nearEnd - step; z >= edgeEnd; z -= step) {
    addPoint(-HALF, 0.25, z, 0, 1.8, dptOf(z));
    addPoint(HALF, 0.25, z, 0, 1.8, dptOf(z));
  }
  // Approach lights: bars across the centreline, from the threshold toward the camera.
  const bars = mobile ? 6 : 12;
  const barStep = 9;
  for (let b = 0; b < bars; b++) {
    const z = 8 + b * barStep;
    const q = b / Math.max(1, bars - 1);
    for (let i = -2; i <= 2; i++) addPoint(i * 1.6, 0.05, z, 1, 0.8, z / 130, q);
  }
  // Threshold bar and the amber signal light beside it.
  for (let i = -4; i <= 4; i++) addPoint(i * 2, 0.05, 0, 3, 1.1, 0);
  addPoint(-10.5, 0.7, -2, 2, 2.0, 0);
  // PAPI: four lights in a row beside the runway, near the threshold. Two white, two amber: on slope.
  for (let i = 0; i < 4; i++) addPoint(-(HALF + 4) + i * 2.4, 0.6, -6, i < 2 ? 4 : 2, 2.4, 0);

  const geo = new BufferGeometry();
  geo.setAttribute('position', new Float32BufferAttribute(pos, 3));
  geo.setAttribute('aKind', new Float32BufferAttribute(kind, 1));
  geo.setAttribute('aSeq', new Float32BufferAttribute(seq, 1));
  geo.setAttribute('aDepth', new Float32BufferAttribute(depth, 1));
  geo.setAttribute('aSize', new Float32BufferAttribute(size, 1));
  const mat = new ShaderMaterial({
    vertexShader: vertex,
    fragmentShader: fragment,
    uniforms: {
      uTime: { value: 0 },
      uIntro: { value: 0 },
      uScale: { value: mobile ? 760 : 1000 },
      uPx: { value: px },
      uFar: { value: FAR },
    },
    transparent: true,
    depthWrite: false,
    blending: AdditiveBlending,
  });
  const lights = new Points(geo, mat);

  // Runway edges, faint, so the surface reads at night.
  const lineGeo = new BufferGeometry();
  lineGeo.setAttribute(
    'position',
    new BufferAttribute(new Float32Array([-HALF, 0, edgeStart, -HALF, 0, edgeEnd, HALF, 0, edgeStart, HALF, 0, edgeEnd]), 3),
  );
  const lines = new LineSegments(lineGeo, new LineBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.12 }));

  const sc = new ThreeScene();
  sc.add(lights, lines);
  // Compile the shaders now, not on the first frame, so the intro starts on time.
  camera.position.set(0, 26, 120);
  camera.lookAt(0, 6, -120);
  renderer.compile(sc, camera);

  const resize = () => {
    const w = window.innerWidth;
    const h = window.innerHeight;
    renderer.setSize(w, h, false);
    renderer.domElement.style.width = '100%';
    renderer.domElement.style.height = '100%';
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
    shift();
  };
  resize();

  const v = new Vector3();
  return {
    canvas: renderer.domElement,
    render(p, t, intro) {
      const c = camPose(p);
      camera.position.set(c.x, c.y, c.z);
      // Look ahead down the runway; the pitch eases as the aircraft descends.
      camera.lookAt(0, c.y * 0.25, c.z - 240);
      mat.uniforms.uTime.value = t;
      mat.uniforms.uIntro.value = intro;
      renderer.render(sc, camera);
    },
    project(x, y, z) {
      v.set(x, y, z);
      const local = v.clone().applyMatrix4(camera.matrixWorldInverse);
      const ahead = local.z < -0.5;
      v.project(camera);
      return {
        x: ((v.x + 1) / 2) * window.innerWidth,
        y: ((1 - v.y) / 2) * window.innerHeight,
        ahead,
        depth: -local.z,
      };
    },
    resize,
    dispose() {
      geo.dispose();
      mat.dispose();
      lineGeo.dispose();
      renderer.dispose();
      renderer.domElement.remove();
    },
  };
}
