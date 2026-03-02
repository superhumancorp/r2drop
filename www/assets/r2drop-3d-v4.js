import * as THREE from 'three';
import { SVGLoader } from 'three/addons/loaders/SVGLoader.js';

const container = document.getElementById('r2drop-3d-container');
if (container) {
  const w = container.clientWidth || 800;
  const h = container.clientHeight || 800;

  const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  renderer.setSize(w, h);
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  container.appendChild(renderer.domElement);

  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(40, w / h, 0.1, 1000);
  camera.position.set(0, 0, 5);

  // Bright studio lighting
  scene.add(new THREE.AmbientLight(0xffffff, 1.0));
  [
    [0xffffff, 3.0, [0, 0, 6]],
    [0xddc8ff, 2.0, [4, 4, 3]],
    [0xc4b5fd, 1.5, [-4, 2, 2]],
    [0xe0d4ff, 1.0, [0, -3, 2]],
    [0xffffff, 1.0, [-2, 0, 4]],
  ].forEach(([color, intensity, pos]) => {
    const d = new THREE.DirectionalLight(color, intensity);
    d.position.set(...pos); scene.add(d);
  });

  // Bright glossy material — light purple, very visible on dark bg
  const mat = new THREE.MeshStandardMaterial({
    color: 0xc4b5fd,
    emissive: 0x7c3aed,
    emissiveIntensity: 0.35,
    metalness: 0.1,
    roughness: 0.2,
    side: THREE.DoubleSide,
  });

  // Parse SVG
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
      geo.computeVertexNormals();
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
  pivot.scale.set(sc, sc, sc);
  pivot.rotation.x = Math.PI; // flip Y (SVG coords) via rotation, not negative scale

  scene.add(pivot);

  // Mouse tracking
  let mx = 0, my = 0;
  window.addEventListener('mousemove', e => {
    mx = (e.clientX / window.innerWidth - 0.5) * 2;
    my = (e.clientY / window.innerHeight - 0.5) * 2;
  });

  // Animate
  const baseRotX = Math.PI;
  const clock = new THREE.Clock();
  (function animate() {
    requestAnimationFrame(animate);
    const t = clock.getElapsedTime();
    pivot.position.y = Math.sin(t * 0.8) * 0.1;
    pivot.rotation.y = t * 0.12 + mx * 0.25;
    pivot.rotation.x = baseRotX + Math.sin(t * 0.5) * 0.04 + my * 0.1;
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
