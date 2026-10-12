// Drifting ember field behind the UI. Cheap: one Points draw call, capped pixel ratio, paused when hidden.
import * as THREE from 'three';

export function startBackground(canvas: HTMLCanvasElement) {
  if (matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  let renderer: THREE.WebGLRenderer;
  try {
    renderer = new THREE.WebGLRenderer({ canvas, alpha: true, antialias: false, powerPreference: 'low-power' });
  } catch {
    return; // no WebGL — the CSS gradient background is enough
  }
  renderer.setPixelRatio(Math.min(devicePixelRatio, 1.5));
  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(60, 1, 0.1, 100);
  camera.position.z = 30;

  const COUNT = innerWidth < 600 ? 260 : 600;
  const pos = new Float32Array(COUNT * 3);
  const speed = new Float32Array(COUNT);
  const colors = new Float32Array(COUNT * 3);
  const palette = [new THREE.Color('#e5484d'), new THREE.Color('#d9a84e'), new THREE.Color('#ff7a3d')];
  for (let i = 0; i < COUNT; i++) {
    pos[i * 3] = (Math.random() - 0.5) * 70;
    pos[i * 3 + 1] = (Math.random() - 0.5) * 50;
    pos[i * 3 + 2] = (Math.random() - 0.5) * 30;
    speed[i] = 0.6 + Math.random() * 1.6;
    const c = palette[i % 3];
    colors.set([c.r, c.g, c.b], i * 3);
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  geo.setAttribute('color', new THREE.BufferAttribute(colors, 3));

  // soft round sprite
  const sprite = document.createElement('canvas');
  sprite.width = sprite.height = 32;
  const g = sprite.getContext('2d')!;
  const grad = g.createRadialGradient(16, 16, 0, 16, 16, 16);
  grad.addColorStop(0, 'rgba(255,255,255,1)');
  grad.addColorStop(0.3, 'rgba(255,255,255,0.5)');
  grad.addColorStop(1, 'rgba(255,255,255,0)');
  g.fillStyle = grad;
  g.fillRect(0, 0, 32, 32);

  const mat = new THREE.PointsMaterial({
    size: 0.55, map: new THREE.CanvasTexture(sprite), vertexColors: true, transparent: true, opacity: 0.55,
    depthWrite: false, blending: THREE.AdditiveBlending,
  });
  const points = new THREE.Points(geo, mat);
  scene.add(points);

  const resize = () => {
    renderer.setSize(innerWidth, innerHeight, false);
    camera.aspect = innerWidth / innerHeight;
    camera.updateProjectionMatrix();
  };
  resize();
  addEventListener('resize', resize);

  let mx = 0, my = 0;
  addEventListener('pointermove', (e) => {
    mx = e.clientX / innerWidth - 0.5;
    my = e.clientY / innerHeight - 0.5;
  }, { passive: true });

  const clock = new THREE.Clock();
  let raf = 0;
  const tick = () => {
    const dt = Math.min(clock.getDelta(), 0.05);
    const t = clock.elapsedTime;
    for (let i = 0; i < COUNT; i++) {
      const y = i * 3 + 1;
      pos[y] += speed[i] * dt;
      pos[i * 3] += Math.sin(t * 0.6 + i) * 0.01;
      if (pos[y] > 26) pos[y] = -26;
    }
    geo.attributes.position.needsUpdate = true;
    camera.position.x += (mx * 4 - camera.position.x) * 0.03;
    camera.position.y += (-my * 3 - camera.position.y) * 0.03;
    camera.lookAt(0, 0, 0);
    renderer.render(scene, camera);
    raf = requestAnimationFrame(tick);
  };
  tick();
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) cancelAnimationFrame(raf);
    else { clock.getDelta(); tick(); }
  });
}
