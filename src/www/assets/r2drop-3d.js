import * as THREE from 'three';
import { SVGLoader } from 'three/addons/loaders/SVGLoader.js';

const container = document.getElementById('r2drop-3d-container');
if (container) {
  const w = container.clientWidth || 800;
  const h = container.clientHeight || 800;

  const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  renderer.setSize(w, h);
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.2;
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  container.appendChild(renderer.domElement);

  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(40, w / h, 0.1, 1000);
  camera.position.set(0, 0, 5);

  // Studio lighting — matches Spline default
  scene.add(new THREE.AmbientLight(0x9999cc, 0.4));
  const kl = new THREE.DirectionalLight(0xffffff, 2.0);
  kl.position.set(3, 4, 5); scene.add(kl);
  const fl = new THREE.DirectionalLight(0x8b5cf6, 0.7);
  fl.position.set(-4, 2, 3); scene.add(fl);
  const rl = new THREE.DirectionalLight(0xc084fc, 0.9);
  rl.position.set(0, -3, -4); scene.add(rl);
  const bl = new THREE.DirectionalLight(0xa78bfa, 0.4);
  bl.position.set(-2, -1, -2); scene.add(bl);

  // Material — Spline-style glossy with clearcoat (vecto3d approach)
  const mat = new THREE.MeshPhysicalMaterial({
    color: 0x7c3aed,
    metalness: 0.4,
    roughness: 0.2,
    clearcoat: 1.0,
    clearcoatRoughness: 0.1,
    reflectivity: 0.8,
    envMapIntensity: 1.2,
    side: THREE.DoubleSide,
  });

  // Environment map for reflections
  const pmrem = new THREE.PMREMGenerator(renderer);
  pmrem.compileEquirectangularShader();
  const envScene = new THREE.Scene();
  envScene.background = new THREE.Color(0x15112b);
  const el1 = new THREE.DirectionalLight(0x818cf8, 3);
  el1.position.set(2, 2, 2); envScene.add(el1);
  const el2 = new THREE.DirectionalLight(0xc084fc, 2);
  el2.position.set(-2, -1, 1); envScene.add(el2);
  const el3 = new THREE.DirectionalLight(0xffffff, 1);
  el3.position.set(0, 3, -2); envScene.add(el3);
  const envMap = pmrem.fromScene(envScene, 0.04).texture;
  mat.envMap = envMap;
  scene.environment = envMap;

  // Parse SVG and extrude
  const svgStr = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 595.28 841.89"><path d="M376.05,561.02l-226.9.69c-115.03-20.03-91.21-181.59,24.78-171.08.47-6.62-.65-13.98,0-20.49,5.5-54.76,55.53-91.29,109.43-76.96,42.34,11.26,67.58,54.74,61.54,97.42,33.28-1.48,64.23,7.4,84.75,34.69,38.61,51.35,8.13,124.03-53.59,135.73Z"/></svg>`;

  const loader = new SVGLoader();
  const svgData = loader.parse(svgStr);
  const meshGroup = new THREE.Group();

  svgData.paths.forEach(path => {
    SVGLoader.createShapes(path).forEach(shape => {
      const geo = new THREE.ExtrudeGeometry(shape, {
        depth: 20,
        bevelEnabled: true,
        bevelThickness: 3,
        bevelSize: 2,
        bevelSegments: 8,
        curveSegments: 32,
      });
      meshGroup.add(new THREE.Mesh(geo, mat));
    });
  });

  // Center
  const box = new THREE.Box3().setFromObject(meshGroup);
  const ctr = new THREE.Vector3();
  box.getCenter(ctr);
  meshGroup.position.set(-ctr.x, -ctr.y, -ctr.z);

  const pivot = new THREE.Group();
  pivot.add(meshGroup);
  const sz = new THREE.Vector3();
  box.getSize(sz);
  const sc = 3.2 / Math.max(sz.x, sz.y);
  pivot.scale.set(sc, -sc, sc);
  scene.add(pivot);

  // Mouse tracking
  let mx = 0, my = 0;
  window.addEventListener('mousemove', e => {
    mx = (e.clientX / window.innerWidth - 0.5) * 2;
    my = (e.clientY / window.innerHeight - 0.5) * 2;
  });

  // Animate
  const clock = new THREE.Clock();
  (function animate() {
    requestAnimationFrame(animate);
    const t = clock.getElapsedTime();
    pivot.position.y = Math.sin(t * 0.8) * 0.1;
    pivot.rotation.y = t * 0.12 + mx * 0.25;
    pivot.rotation.x = Math.sin(t * 0.5) * 0.04 + my * 0.1;
    renderer.render(scene, camera);
  })();

  // Resize
  window.addEventListener('resize', () => {
    const nw = container.clientWidth, nh = container.clientHeight;
    renderer.setSize(nw, nh);
    camera.aspect = nw / nh;
    camera.updateProjectionMatrix();
  });
}
