import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { RADIUS, VISION, DAY_LENGTH, isLand, distance } from './world.mjs';

export class WorldView {
  constructor(container, handlers) {
    this.container = container;
    this.handlers = handlers;
    this.scene = new THREE.Scene();
    this.camera = new THREE.OrthographicCamera(-35, 35, 35, -35, 0.1, 200);
    this.renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    this.renderer.shadowMap.enabled = true;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.container.prepend(this.renderer.domElement);
    this.controls = new OrbitControls(this.camera, this.renderer.domElement);
    this.controls.enableDamping = true;
    this.controls.dampingFactor = 0.08;
    this.controls.minPolarAngle = 0.25;
    this.controls.maxPolarAngle = Math.PI / 2.3;
    this.controls.minZoom = 0.7;
    this.controls.maxZoom = 3;
    this.controls.enablePan = true;
    this.entities = new Map();
    this.residents = new Map();
    this.labels = new Map();
    this.raycaster = new THREE.Raycaster();
    this.pointer = new THREE.Vector2();
    this.ground = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);
    this.hit = new THREE.Vector3();
    this.tool = 'observe';
    this.vision = false;
    this.showNames = true;
    this.focus();
    this.buildScene();
    this.observer = new ResizeObserver(() => this.resize());
    this.observer.observe(container);
    this.renderer.domElement.addEventListener('pointerdown', e => {
      this.down = { x: e.clientX, y: e.clientY, time: performance.now(), button: e.button };
    });
    this.renderer.domElement.addEventListener('pointermove', e => this.hover(e));
    this.renderer.domElement.addEventListener('pointerleave', () => { this.preview.visible = false; });
    this.renderer.domElement.addEventListener('pointerup', e => {
      if (!this.down || this.down.button !== 0 || Math.hypot(e.clientX - this.down.x, e.clientY - this.down.y) > 5 || performance.now() - this.down.time > 600) return;
      this.cast(e);
      if (this.tool !== 'observe') {
        if (this.raycaster.ray.intersectPlane(this.ground, this.hit)) handlers.place(this.hit.x, this.hit.z);
        return;
      }
      const hits = this.raycaster.intersectObjects([...this.residents.values(), ...this.entities.values()], true);
      for (const result of hits) {
        let object = result.object;
        while (object && !object.userData.entityId && !object.userData.agentId) object = object.parent;
        if (object?.userData.agentId) { handlers.select(object.userData.agentId); return; }
        if (object?.userData.entityId) { handlers.inspect(object.userData.entityId); return; }
      }
    });
    this.renderer.domElement.addEventListener('webglcontextlost', e => {
      e.preventDefault();
      handlers.error(new Error('3D 图形上下文丢失。请先存档，再刷新页面。'));
    });
  }

  color(name, other, mix = 0) {
    const css = getComputedStyle(document.documentElement);
    const value = new THREE.Color(css.getPropertyValue(`--cp-${name}`).trim());
    return other ? value.lerp(new THREE.Color(css.getPropertyValue(`--cp-${other}`).trim()), mix) : value;
  }

  material(name, other, mix = 0, options = {}) {
    return new THREE.MeshStandardMaterial({ color: this.color(name, other, mix), roughness: 0.88, ...options });
  }

  mesh(geometry, material, parent, x = 0, y = 0, z = 0) {
    const mesh = new THREE.Mesh(geometry, material);
    mesh.position.set(x, y, z);
    mesh.castShadow = true;
    mesh.receiveShadow = true;
    parent.add(mesh);
    return mesh;
  }

  buildScene() {
    const darkTheme = document.documentElement.dataset.theme === 'dark';
    const lightColor = this.color(darkTheme ? 'text' : 'surface');
    this.renderer.setClearColor(this.color('bg'));
    const ambient = new THREE.HemisphereLight(lightColor, this.color('border-strong'), 2.7);
    this.scene.add(ambient);
    this.sun = new THREE.DirectionalLight(lightColor, 3.2);
    this.sun.position.set(-18, 36, 20);
    this.sun.castShadow = true;
    this.sun.shadow.mapSize.set(2048, 2048);
    Object.assign(this.sun.shadow.camera, { left: -32, right: 32, top: 32, bottom: -32, near: 1, far: 90 });
    this.sun.shadow.normalBias = 0.08;
    this.sun.shadow.bias = -0.0002;
    this.scene.add(this.sun);
    this.terrain = new THREE.Group();
    this.scene.add(this.terrain);
    const grass = this.material('success', 'bg', 0.68);
    this.mesh(new THREE.CylinderGeometry(RADIUS, RADIUS - 1.2, 2.8, 72), this.material('warning', 'text-muted', 0.75), this.terrain, 0, -1.55);
    this.mesh(new THREE.CylinderGeometry(RADIUS + 0.15, RADIUS, 0.5, 72), this.material('border', 'warning', 0.18), this.terrain, 0, -0.4);
    this.mesh(new THREE.CylinderGeometry(RADIUS, RADIUS, 0.22, 72), grass, this.terrain, 0, -0.11);
    const shore = this.mesh(new THREE.CircleGeometry(1, 64), this.material('bg', 'warning', 0.16), this.terrain, -7, 0.02, -2);
    shore.rotation.x = -Math.PI / 2;
    shore.scale.set(5.25, 4, 1);
    this.water = this.mesh(new THREE.CircleGeometry(1, 64), this.material('link', 'bg', 0.55, { roughness: 0.22, metalness: 0.12 }), this.terrain, -7, 0.045, -2);
    this.water.rotation.x = -Math.PI / 2;
    this.water.scale.set(4.8, 3.5, 1);
    for (let i = 0; i < 3; i++) {
      const ring = this.mesh(new THREE.RingGeometry(0.7 + i * 0.52, 0.735 + i * 0.52, 48),
        this.material('surface', null, 0, { transparent: true, opacity: 0.25 }), this.terrain, -7, 0.06, -2);
      ring.rotation.x = -Math.PI / 2;
      ring.scale.x = 1.35;
    }
    const patches = new THREE.InstancedMesh(new THREE.ConeGeometry(0.11, 0.5, 3), this.material('success', 'text-muted', 0.55), 280);
    const dummy = new THREE.Object3D();
    let count = 0;
    for (let i = 0; count < 280 && i < 1500; i++) {
      const angle = i * 2.39996;
      const hash = Math.sin(i * 127.1 + 311.7) * 43758.5453;
      const radius = Math.sqrt(hash - Math.floor(hash)) * 22.4;
      const x = Math.cos(angle) * radius, z = Math.sin(angle) * radius;
      if (!isLand(x, z) || Math.hypot(x - 2, z - 3) < 5) continue;
      dummy.position.set(x, 0.15, z);
      dummy.rotation.set(0, angle, 0.1);
      dummy.scale.setScalar(0.6 + (i % 7) / 10);
      dummy.updateMatrix();
      patches.setMatrixAt(count++, dummy.matrix);
    }
    patches.count = count;
    this.terrain.add(patches);
    for (let i = 0; i < 16; i++) {
      const angle = i * 1.7, r = 1 + (i % 5) * 0.7;
      const pebble = this.mesh(new THREE.DodecahedronGeometry(0.19, 0), this.material('border-strong', 'bg', 0.25), this.terrain, Math.cos(angle) * r, 0.12, Math.sin(angle) * r + 3);
      pebble.scale.y = 0.45;
    }
    this.clouds = new THREE.Group();
    this.scene.add(this.clouds);
    for (let i = 0; i < 4; i++) {
      const group = new THREE.Group();
      for (let j = 0; j < 3; j++) {
        const cloud = this.mesh(new THREE.IcosahedronGeometry(1.8, 1), this.material(darkTheme ? 'text' : 'surface', null, 0, { transparent: true, opacity: 0.55, depthWrite: false }), group, (j - 1) * 2, j === 1 ? 0.3 : 0);
        cloud.castShadow = false;
        cloud.scale.set(1.2, 0.45, 0.65);
      }
      group.position.set(Math.cos(i * 1.6) * 26, 7 + i * 0.5, Math.sin(i * 1.6) * 25);
      this.clouds.add(group);
    }
    this.selection = this.mesh(new THREE.RingGeometry(0.7, 0.81, 40), this.material('accent'), this.scene, 0, 0.09);
    this.selection.rotation.x = -Math.PI / 2;
    this.selection.castShadow = false;
    this.visionRing = this.mesh(new THREE.RingGeometry(VISION - 0.06, VISION, 80), this.material('accent', null, 0, { transparent: true, opacity: 0.5 }), this.scene, 0, 0.1);
    this.visionRing.rotation.x = -Math.PI / 2;
    this.visionRing.castShadow = false;
    this.preview = this.mesh(new THREE.RingGeometry(0.55, 0.65, 32), this.material('accent'), this.scene, 0, 0.14);
    this.preview.rotation.x = -Math.PI / 2;
    this.preview.visible = false;
    this.preview.castShadow = false;
    const rainPositions = new Float32Array(240 * 3);
    for (let i = 0; i < 240; i++) {
      rainPositions[i * 3] = Math.sin(i * 27.51) * 22;
      rainPositions[i * 3 + 1] = (i % 16) / 16 * 15;
      rainPositions[i * 3 + 2] = Math.cos(i * 9.71) * 22;
    }
    this.rain = new THREE.Points(new THREE.BufferGeometry().setAttribute('position', new THREE.BufferAttribute(rainPositions, 3)),
      new THREE.PointsMaterial({ color: this.color('link', 'bg', 0.2), size: 0.12, transparent: true, opacity: 0.65 }));
    this.scene.add(this.rain);
  }

  makeEntity(e) {
    const g = new THREE.Group();
    g.position.set(e.x, 0, e.z);
    g.userData.entityId = e.id;
    const wood = this.material('warning', 'text-muted', 0.76);
    const leaves = this.material('success', 'text-muted', 0.43);
    const stone = this.material('border-strong', 'bg', 0.22);
    if (e.type === 'tree') {
      this.mesh(new THREE.CylinderGeometry(0.15, 0.25, 1.6, 6), wood, g, 0, 0.8);
      for (let i = 0; i < 3; i++) this.mesh(new THREE.ConeGeometry(1.18 - i * 0.26, 1.6, 7), leaves, g, 0, 1.7 + i * 0.75);
    } else if (e.type === 'food') {
      for (let i = 0; i < 3; i++) this.mesh(new THREE.IcosahedronGeometry(0.55, 0), leaves, g, Math.sin(i * 2.1) * 0.4, 0.4, Math.cos(i * 2.1) * 0.4);
      for (let i = 0; i < 6; i++) this.mesh(new THREE.SphereGeometry(0.12, 6, 5), this.material('accent'), g, Math.sin(i * 2.4) * 0.55, 0.65 + (i % 2) * 0.14, Math.cos(i * 2.4) * 0.4);
    } else if (e.type === 'stone') {
      for (let i = 0; i < 3; i++) {
        const mesh = this.mesh(new THREE.DodecahedronGeometry(0.62 - i * 0.08, 0), stone, g, Math.sin(i * 3) * 0.5, 0.35, Math.cos(i * 3) * 0.4);
        mesh.rotation.set(0.2, i, 0.5);
      }
    } else if (e.type === 'shelter') {
      this.mesh(new THREE.BoxGeometry(1.95, 1.6, 1.7), this.material('bg', 'warning', 0.12), g, 0, 0.8);
      const roof = this.mesh(new THREE.ConeGeometry(1.8, 1.3, 4), this.material('accent', 'text-muted', 0.65), g, 0, 2.05);
      roof.rotation.y = Math.PI / 4;
      this.mesh(new THREE.BoxGeometry(0.5, 1.05, 0.06), wood, g, 0, 0.53, 0.88);
      this.mesh(new THREE.BoxGeometry(0.38, 0.38, 0.07), this.material('warning', 'bg', 0.35), g, 0.62, 1.05, 0.88);
      this.mesh(new THREE.BoxGeometry(0.25, 0.65, 0.3), stone, g, 0.5, 2.2, -0.25);
    } else if (e.type === 'water') {
      this.mesh(new THREE.CylinderGeometry(0.68, 0.8, 0.4, 10), stone, g, 0, 0.2);
      const top = this.mesh(new THREE.CircleGeometry(0.55, 32), this.material('link', 'bg', 0.35, { metalness: 0.15, roughness: 0.2 }), g, 0, 0.42);
      top.rotation.x = -Math.PI / 2;
      this.mesh(new THREE.CylinderGeometry(0.075, 0.12, 0.4, 8), this.material('link', 'surface', 0.3), g, 0, 0.62);
    } else if (e.type === 'fire') {
      for (let i = 0; i < 8; i++) this.mesh(new THREE.DodecahedronGeometry(0.19), stone, g, Math.cos(i / 8 * Math.PI * 2) * 0.55, 0.15, Math.sin(i / 8 * Math.PI * 2) * 0.55);
      this.mesh(new THREE.ConeGeometry(0.3, 0.8, 5), this.material('warning', null, 0, { emissive: this.color('warning'), emissiveIntensity: 0.6 }), g, 0, 0.5);
      this.mesh(new THREE.ConeGeometry(0.18, 0.45, 5), this.material('accent', 'warning', 0.6), g, 0.14, 0.35, 0.04);
    } else {
      this.mesh(new THREE.CylinderGeometry(0.85, 1, 0.2, 8), stone, g, 0, 0.1);
      const gem = this.mesh(new THREE.OctahedronGeometry(0.62), this.material('accent', null, 0, { metalness: 0.2, emissive: this.color('accent'), emissiveIntensity: 0.22 }), g, 0, 1.12);
      g.userData.gem = gem;
      const orbit = this.mesh(new THREE.TorusGeometry(1, 0.035, 6, 48), this.material('accent', 'bg', 0.25), g, 0, 1);
      orbit.rotation.x = Math.PI / 2.8;
    }
    this.scene.add(g);
    this.entities.set(e.id, g);
    return g;
  }

  makeResident(a) {
    const g = new THREE.Group();
    g.userData.agentId = a.id;
    const shirt = this.material(['accent', 'link', 'warning', 'success', 'text-muted', 'border-strong'][a.color], 'bg', 0.15);
    const skin = this.material('bg', 'warning', 0.18);
    const dark = this.material('text-muted');
    this.mesh(new THREE.CapsuleGeometry(0.25, 0.32, 3, 7), shirt, g, 0, 0.77);
    this.mesh(new THREE.SphereGeometry(0.27, 12, 10), skin, g, 0, 1.29);
    this.mesh(new THREE.SphereGeometry(0.28, 10, 6, 0, Math.PI * 2, 0, Math.PI / 2), dark, g, 0, 1.32);
    for (const x of [-0.1, 0.1]) this.mesh(new THREE.SphereGeometry(0.025, 6, 5), dark, g, x, 1.31, 0.24);
    const legs = [-1, 1].map(side => this.mesh(new THREE.CapsuleGeometry(0.085, 0.3, 2, 6), dark, g, side * 0.13, 0.26));
    const arms = [-1, 1].map(side => this.mesh(new THREE.CapsuleGeometry(0.075, 0.26, 2, 6), skin, g, side * 0.32, 0.73));
    this.mesh(new THREE.BoxGeometry(0.32, 0.35, 0.14), this.material('warning', 'text-muted', 0.65), g, 0, 0.85, -0.27);
    if (a.color === 2 || a.color === 5) {
      this.mesh(new THREE.CylinderGeometry(0.42, 0.42, 0.05, 12), this.material('warning', 'bg', 0.5), g, 0, 1.53);
      this.mesh(new THREE.CylinderGeometry(0.22, 0.28, 0.18, 10), this.material('warning', 'bg', 0.5), g, 0, 1.62);
    }
    g.userData.legs = legs;
    g.userData.arms = arms;
    this.scene.add(g);
    this.residents.set(a.id, g);
    const label = document.createElement('div');
    label.className = 'agent-label';
    const speech = document.createElement('span');
    speech.className = 'speech';
    const name = document.createElement('span');
    name.className = 'name';
    name.textContent = a.name;
    label.append(speech, name);
    this.container.querySelector('#labels').append(label);
    this.labels.set(a.id, label);
    return g;
  }

  cast(e) {
    const r = this.renderer.domElement.getBoundingClientRect();
    this.pointer.set((e.clientX - r.left) / r.width * 2 - 1, -(e.clientY - r.top) / r.height * 2 + 1);
    this.raycaster.setFromCamera(this.pointer, this.camera);
  }

  hover(e) {
    this.cast(e);
    this.preview.visible = this.tool !== 'observe' && Boolean(this.raycaster.ray.intersectPlane(this.ground, this.hit));
    if (this.preview.visible) {
      this.preview.position.set(this.hit.x, 0.12, this.hit.z);
      this.preview.material.color.copy(this.color(isLand(this.hit.x, this.hit.z) ? 'accent' : 'danger'));
    }
  }

  focus() {
    this.camera.position.set(32, 37, 43);
    this.camera.zoom = 1;
    this.camera.updateProjectionMatrix();
    this.controls.target.set(0, 0, 0);
    this.controls.update();
  }

  resize() {
    const w = this.container.clientWidth, h = this.container.clientHeight;
    if (!w || !h) return;
    const aspect = w / h;
    const height = Math.max(59, 57 / aspect);
    this.camera.left = -height * aspect / 2;
    this.camera.right = height * aspect / 2;
    this.camera.top = height / 2;
    this.camera.bottom = -height / 2;
    this.camera.updateProjectionMatrix();
    this.renderer.setSize(w, h);
  }

  screenPoint(p) {
    const v = new THREE.Vector3(p.x, p.y || 0, p.z).project(this.camera);
    const r = this.container.getBoundingClientRect();
    return { x: r.left + (v.x + 1) / 2 * r.width, y: r.top + (1 - v.y) / 2 * r.height, depth: v.z };
  }

  reset() {
    for (const child of [...this.scene.children]) {
      child.traverse(object => {
        object.geometry?.dispose();
        if (object.material) for (const m of Array.isArray(object.material) ? object.material : [object.material]) m.dispose();
        object.shadow?.dispose();
      });
      this.scene.remove(child);
    }
    this.entities.clear();
    this.residents.clear();
    for (const label of this.labels.values()) label.remove();
    this.labels.clear();
    this.buildScene();
  }

  render(w, selected) {
    this.controls.update();
    const a = w.agents.find(a => a.id === selected);
    const visible = e => !this.vision || !a || distance(a, e) <= VISION;
    for (const e of w.entities) {
      const g = this.entities.get(e.id) || this.makeEntity(e);
      g.visible = visible(e);
      if (['food', 'tree', 'stone', 'water'].includes(e.type)) g.scale.setScalar(e.amount < 1 ? 0.55 : 1);
      if (g.userData.gem) {
        g.userData.gem.position.y = 1.15 + Math.sin(w.t * 1.5) * 0.13;
        g.userData.gem.rotation.y = w.t * 0.4;
      }
    }
    const rect = this.container.getBoundingClientRect();
    const labelBoxes = [];
    for (const resident of [...w.agents].sort((x, y) => Number(y.id === selected) - Number(x.id === selected))) {
      const g = this.residents.get(resident.id) || this.makeResident(resident);
      g.position.set(resident.x, 0, resident.z);
      g.visible = visible(resident) && resident.alive;
      const walking = resident.path.length > 0;
      if (walking) g.rotation.y = Math.atan2(resident.path[0].x - resident.x, resident.path[0].z - resident.z);
      g.userData.legs.forEach((leg, i) => { leg.rotation.x = walking ? Math.sin(w.t * 9 + i * Math.PI) * 0.48 : 0; });
      g.userData.arms.forEach((arm, i) => { arm.rotation.x = walking ? -Math.sin(w.t * 9 + i * Math.PI) * 0.32 : 0; });
      if (resident.action?.type === 'rest' && !walking) g.scale.y = 0.68;
      else g.scale.y = 1;
      const label = this.labels.get(resident.id);
      const p = this.screenPoint({ x: resident.x, y: 2.1, z: resident.z });
      label.hidden = !g.visible || !this.showNames || p.depth > 1 || p.depth < -1;
      if (!label.hidden) {
        const box = { x: p.x, y: p.y };
        if (labelBoxes.some(b => Math.abs(b.x - box.x) < 36 && Math.abs(b.y - box.y) < 25)) label.hidden = true;
        else labelBoxes.push(box);
      }
      label.style.left = `${p.x - rect.left}px`;
      label.style.top = `${p.y - rect.top}px`;
      label.classList.toggle('selected', resident.id === selected);
      label.firstChild.textContent = resident.speechUntil > w.t ? resident.speech : '';
    }
    this.selection.visible = Boolean(a?.alive);
    this.visionRing.visible = this.vision && Boolean(a?.alive);
    if (a) {
      this.selection.position.set(a.x, 0.1, a.z);
      this.visionRing.position.set(a.x, 0.1, a.z);
    }
    this.rain.visible = w.weather === 'rain';
    if (this.rain.visible) {
      const positions = this.rain.geometry.attributes.position;
      for (let i = 0; i < positions.count; i++) positions.setY(i, ((i % 16) / 16 * 15 - w.t * 7) % 15 + 15);
      positions.needsUpdate = true;
    }
    const daylight = Math.max(0, Math.sin(((w.t / DAY_LENGTH * 24 + 7) % 24 - 6) / 24 * Math.PI * 2));
    this.sun.intensity = (1.2 + daylight * 2) * (w.weather === 'rain' ? 0.65 : 1);
    this.clouds.rotation.y = w.t * 0.002;
    this.clouds.visible = w.weather !== 'drought';
    this.terrain.children[2].material.color.copy(this.color(w.weather === 'drought' ? 'warning' : 'success', 'bg', 0.68));
    this.renderer.render(this.scene, this.camera);
  }
}
