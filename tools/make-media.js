// Generates the addon's textures as uncompressed 32-bit TGA (WoW loads these
// directly). All shapes are white with a black outline so SetVertexColor can
// tint them to any colour while the outline stays dark and readable.
//
//   node tools/make-media.js
const fs = require('fs');
const path = require('path');

const OUT = path.join(__dirname, '..', 'Media');
fs.mkdirSync(OUT, { recursive: true });

function writeTGA(file, w, h, pixel) {
  const buf = Buffer.alloc(18 + w * h * 4);
  buf[2] = 2;                 // uncompressed true-colour
  buf.writeUInt16LE(w, 12);
  buf.writeUInt16LE(h, 14);
  buf[16] = 32;               // bits per pixel
  buf[17] = 0x28;             // 8 alpha bits, top-left origin
  let o = 18;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const [r, g, b, a] = pixel(x, y);
      buf[o++] = Math.round(b * 255);
      buf[o++] = Math.round(g * 255);
      buf[o++] = Math.round(r * 255);
      buf[o++] = Math.round(a * 255);
    }
  }
  fs.writeFileSync(path.join(OUT, file), buf);
  console.log('wrote', file, w + 'x' + h);
}

function inPoly(px, py, poly) {
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, yi] = poly[i], [xj, yj] = poly[j];
    if ((yi > py) !== (yj > py) && px < ((xj - xi) * (py - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

// Rasterise polygons (in 64-unit space) at 4x, dilate for the outline, then
// box-filter down so edges are anti-aliased.
function outlinedShape(file, polys, outlinePx) {
  const S = 64, SS = 4, H = S * SS;
  const fill = new Uint8Array(H * H);
  for (let y = 0; y < H; y++)
    for (let x = 0; x < H; x++) {
      const ux = (x + 0.5) / SS, uy = (y + 0.5) / SS;
      if (polys.some(p => inPoly(ux, uy, p))) fill[y * H + x] = 1;
    }
  const r = outlinePx * SS, r2 = r * r;
  const line = new Uint8Array(H * H);
  for (let y = 0; y < H; y++)
    for (let x = 0; x < H; x++) {
      if (!fill[y * H + x]) continue;
      for (let dy = -r; dy <= r; dy++)
        for (let dx = -r; dx <= r; dx++) {
          if (dx * dx + dy * dy > r2) continue;
          const nx = x + dx, ny = y + dy;
          if (nx >= 0 && ny >= 0 && nx < H && ny < H) line[ny * H + nx] = 1;
        }
    }
  writeTGA(file, S, S, (x, y) => {
    let f = 0, o = 0;
    for (let sy = 0; sy < SS; sy++)
      for (let sx = 0; sx < SS; sx++) {
        const i = (y * SS + sy) * H + (x * SS + sx);
        f += fill[i]; o += line[i];
      }
    f /= SS * SS; o /= SS * SS;
    if (o === 0) return [0, 0, 0, 0];
    const v = f / o;          // white where filled, black in the outline band
    return [v, v, v, o];
  });
}

// Down-pointing arrow: shaft + head.
outlinedShape('arrow.tga', [
  [[25, 4], [39, 4], [39, 30], [25, 30]],
  [[7, 27], [57, 27], [32, 59]],
], 3);

// Two stacked chevrons.
outlinedShape('chevron.tga', [
  [[7, 6], [20, 6], [32, 19], [44, 6], [57, 6], [32, 33]],
  [[7, 29], [20, 29], [32, 42], [44, 29], [57, 29], [32, 56]],
], 2.5);

// Diamond (a gem floating overhead).
outlinedShape('diamond.tga', [
  [[32, 4], [56, 30], [32, 60], [8, 30]],
], 3);

// Soft round glow.
writeTGA('glow.tga', 64, 64, (x, y) => {
  const d = Math.hypot(x + 0.5 - 32, y + 0.5 - 32) / 32;
  const a = Math.max(0, 1 - d);
  return [1, 1, 1, a * a];
});

// Light pillar: bright core, soft edges, fading out towards the top.
writeTGA('beam.tga', 32, 128, (x, y) => {
  const dx = (x + 0.5 - 16) / 16;
  const across = Math.exp(-dx * dx * 6) * 0.75 + Math.exp(-dx * dx * 40) * 0.25;
  const t = (y + 0.5) / 128;               // 0 top, 1 bottom
  const up = Math.pow(t, 1.4) * Math.min(1, (1 - t) * 12 + 0.6);
  return [1, 1, 1, Math.min(1, across * up)];
});
