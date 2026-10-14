import manifest from "../assets.json";

const SHEET_KEYS = new Set([
  "PLAYER_LOCOMOTION", "PLAYER_COMBAT", "PLAYER_FINISH", "WEAPON_EFFECTS",
  "BUFF_EFFECTS", "DEFENSE_EFFECTS", "UI_ICON_ATLAS", "REALM_FLOORS",
  "COIN_SHEET",
  ...Array.from({ length: 10 }, (_, i) => `REALM_ENEMIES_${String(i + 1).padStart(2, "0")}`),
  ...Array.from({ length: 10 }, (_, i) => `REALM_ELITES_${String(i + 1).padStart(2, "0")}`),
  ...Array.from({ length: 10 }, (_, i) => `REALM_REINFORCEMENTS_${String(i + 1).padStart(2, "0")}`),
  ...Array.from({ length: 10 }, (_, i) => `REALM_BOSS_${String(i + 1).padStart(2, "0")}`),
  ...Array.from({ length: 20 }, (_, i) => `SKIN_${String(i + 1).padStart(2, "0")}_SHEET`),
  ...Array.from({ length: 20 }, (_, i) => `SKIN_${String(i + 1).padStart(2, "0")}_COMBAT`),
  ...Array.from({ length: 20 }, (_, i) => `SKIN_${String(i + 1).padStart(2, "0")}_FINISH`),
]);

function loadImage(url) {
  return new Promise((resolve, reject) => {
    const image = new Image();
    image.decoding = "async";
    image.onerror = () => reject(new Error(`Gagal memuat aset ${url}`));
    image.onload = () => {
      // decode() unpacks the pixels off the main thread before the first draw,
      // so a freshly loaded sheet does not stall the frame it first appears in.
      // It is only an optimisation: never let it hold up loading for long.
      let settled = false;
      const finish = () => {
        if (settled) return;
        settled = true;
        resolve(image);
      };
      if (image.decode) image.decode().then(finish, finish);
      else finish();
      window.setTimeout(finish, 500);
    };
    image.src = url;
  });
}

function framesUrlFor(key) {
  const source = manifest[key];
  return source?.replace(/\.webp(?:\?.*)?$/, ".frames.json");
}

export class ArtLibrary {
  constructor(assetHandle) {
    this.assetHandle = assetHandle;
    this.entries = new Map();
    this.pending = new Map();
  }

  url(key) {
    return this.assetHandle?.get(key) || manifest[key];
  }

  async load(key) {
    if (this.entries.has(key)) return this.entries.get(key);
    if (this.pending.has(key)) return this.pending.get(key);
    const task = (async () => {
      const url = this.url(key);
      if (!url) throw new Error(`Aset ${key} tidak ditemukan`);
      const [image, data] = await Promise.all([
        loadImage(url),
        SHEET_KEYS.has(key) ? fetch(framesUrlFor(key)).then((response) => {
          if (!response.ok) throw new Error(`Frame data ${key} gagal dimuat`);
          return response.json();
        }) : Promise.resolve(null),
      ]);
      const entry = { image, data };
      this.entries.set(key, entry);
      this.pending.delete(key);
      return entry;
    })();
    this.pending.set(key, task);
    return task;
  }

  async loadInitial() {
    const core = [
      "PLAYER_LOCOMOTION", "PLAYER_COMBAT", "PLAYER_FINISH", "WEAPON_EFFECTS",
      "BUFF_EFFECTS", "DEFENSE_EFFECTS", "UI_ICON_ATLAS", "REALM_FLOORS",
      "COIN_SHEET", "SKIN_01_SHEET",
    ];
    await Promise.all([...core.map((key) => this.load(key)), this.loadRealm(0)]);
  }

  async loadRealm(index) {
    const id = String(index + 1).padStart(2, "0");
    return Promise.all([
      this.load(`REALM_BG_${id}`),
      this.load(`REALM_BG_EXT_${id}`),
      this.load(`REALM_ENEMIES_${id}`),
      this.load(`REALM_ELITES_${id}`),
      this.load(`REALM_REINFORCEMENTS_${id}`),
      this.load(`REALM_BOSS_${id}`),
    ]);
  }

  async loadSkin(index) {
    const id = String(index + 1).padStart(2, "0");
    return Promise.all([
      this.load(`SKIN_${id}_SHEET`),
      this.load(`SKIN_${id}_COMBAT`),
      this.load(`SKIN_${id}_FINISH`),
    ]);
  }

  // Menu preview only needs the idle sheet; combat/finish load when the run starts.
  async loadSkinPreview(index) {
    return this.load(`SKIN_${String(index + 1).padStart(2, "0")}_SHEET`);
  }

  // Each skin sheet is ~12 MB once decoded. Drop the ones not kept so browsing
  // all 20 Gun-Mages does not pile up hundreds of MB on a phone.
  retainSkins(indexes) {
    const keep = new Set(indexes.map((index) => String(index + 1).padStart(2, "0")));
    for (const key of [...this.entries.keys()]) {
      const match = /^SKIN_(\d\d)_/.exec(key);
      if (match && !keep.has(match[1])) this.entries.delete(key);
    }
  }

  get(key) {
    return this.entries.get(key);
  }
}

export function findAnimation(entry, name) {
  return entry?.data?.animations?.find((animation) => animation.name === name)?.frames || [];
}

export function findFrame(entry, name) {
  return entry?.data?.frames?.find((frame) => frame.name === name);
}

export function drawFrameInCell(ctx, entry, frame, x, y, width, height, alpha = 1) {
  if (!entry?.image || !frame) return;
  const crop = frame.content || frame.source;
  const scale = Math.min(width / crop.w, height / crop.h);
  const drawWidth = crop.w * scale;
  const drawHeight = crop.h * scale;
  ctx.save();
  ctx.globalAlpha *= alpha;
  ctx.drawImage(entry.image, crop.x, crop.y, crop.w, crop.h,
    x + (width - drawWidth) / 2, y + (height - drawHeight) / 2, drawWidth, drawHeight);
  ctx.restore();
}

export function drawAtlas(ctx, art, key, name, x, y, width, height, alpha = 1) {
  const entry = art.get(key);
  drawFrameInCell(ctx, entry, findFrame(entry, name), x, y, width, height, alpha);
}

export function drawAnimatedCell(ctx, art, key, animation, time, x, y, width, height, alpha = 1) {
  const entry = art.get(key);
  const frames = findAnimation(entry, animation);
  if (!frames.length) return;
  const frame = frames[Math.floor(time * 10) % frames.length];
  drawFrameInCell(ctx, entry, frame, x, y, width, height, alpha);
}

export function drawAnchored(ctx, art, key, animation, time, anchorX, anchorY, targetHeight, flip = false, alpha = 1) {
  const entry = art.get(key);
  const frames = findAnimation(entry, animation);
  if (!entry || !frames.length) return;
  const frame = frames[Math.floor(Math.max(0, time) * 10) % frames.length];
  const crop = frame.content || frame.source;
  const maxHeight = Math.max(...frames.map((item) => (item.content || item.source).h));
  const scale = targetHeight / maxHeight;
  const drawX = -(frame.anchor.x - crop.x) * scale;
  const drawY = -(frame.anchor.y - crop.y) * scale;
  ctx.save();
  ctx.globalAlpha *= alpha;
  ctx.translate(anchorX, anchorY);
  if (flip) ctx.scale(-1, 1);
  ctx.drawImage(entry.image, crop.x, crop.y, crop.w, crop.h,
    drawX, drawY, crop.w * scale, crop.h * scale);
  ctx.restore();
}

// Fits a whole animation into a box with ONE scale and a shared foot anchor,
// so frames with different crop sizes don't jump, shrink or slide around.
export function drawAnimatedFit(ctx, art, key, animation, time, x, y, width, height, alpha = 1) {
  const entry = art.get(key);
  const frames = findAnimation(entry, animation);
  if (!entry?.image || !frames.length) return;
  const anchorOf = (frame) => {
    const crop = frame.content || frame.source;
    return frame.anchor || { x: crop.x + crop.w / 2, y: crop.y + crop.h };
  };
  let minX = Infinity;
  let maxX = -Infinity;
  let minY = Infinity;
  let maxY = -Infinity;
  for (const frame of frames) {
    const crop = frame.content || frame.source;
    const anchor = anchorOf(frame);
    minX = Math.min(minX, crop.x - anchor.x);
    maxX = Math.max(maxX, crop.x + crop.w - anchor.x);
    minY = Math.min(minY, crop.y - anchor.y);
    maxY = Math.max(maxY, crop.y + crop.h - anchor.y);
  }
  const scale = Math.min(width / (maxX - minX), height / (maxY - minY));
  // Center the union horizontally and stand it on the bottom edge of the box.
  const originX = x + (width - (maxX - minX) * scale) / 2 - minX * scale;
  const originY = y + height - maxY * scale;
  const frame = frames[Math.floor(Math.max(0, time) * 10) % frames.length];
  const crop = frame.content || frame.source;
  const anchor = anchorOf(frame);
  ctx.save();
  ctx.globalAlpha *= alpha;
  ctx.drawImage(entry.image, crop.x, crop.y, crop.w, crop.h,
    originX + (crop.x - anchor.x) * scale, originY + (crop.y - anchor.y) * scale, crop.w * scale, crop.h * scale);
  ctx.restore();
}

export function drawFloor(ctx, art, frameName, floorY, width, targetHeight) {
  const entry = art.get("REALM_FLOORS");
  const frame = findFrame(entry, frameName);
  if (!entry || !frame) return;
  const crop = frame.content || frame.source;
  const scale = targetHeight / crop.h;
  const tileWidth = crop.w * scale;
  const drawY = floorY - (frame.surfaceY - crop.y) * scale;
  for (let x = -tileWidth * 0.25; x < width + tileWidth; x += tileWidth * 0.92) {
    ctx.drawImage(entry.image, crop.x, crop.y, crop.w, crop.h,
      x, drawY, tileWidth, crop.h * scale);
  }
}

export function drawBackdrop(ctx, entry, width, height) {
  if (!entry?.image) return;
  const image = entry.image;
  const scale = Math.max(width / image.naturalWidth, height / image.naturalHeight);
  const drawWidth = image.naturalWidth * scale;
  const drawHeight = image.naturalHeight * scale;
  ctx.drawImage(image, (width - drawWidth) / 2, (height - drawHeight) / 2, drawWidth, drawHeight);
}
