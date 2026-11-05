// 屏幕像素探针: 从真机截图实测元素边界, 不再靠估坐标。
// 用法:
//   node png_probe.js size <png>
//   node png_probe.js qcol <png> <x> [shift] [minRun]   竖切: 找上下分界
//   node png_probe.js qrow <png> <y> [shift] [minRun]   横切: 找左右分界
// shift 是每通道右移位数 (越大越粗, 默认 3 = 每通道 5 bit), minRun 忽略短游程。
const fs = require('fs');
const zlib = require('zlib');

function decode(pngPath) {
  const b = fs.readFileSync(pngPath);
  if (b.readUInt32BE(0) !== 0x89504e47) throw new Error('not a PNG');
  let off = 8;
  let ihdr = null;
  const idat = [];
  while (off < b.length) {
    const len = b.readUInt32BE(off);
    const type = b.toString('ascii', off + 4, off + 8);
    const data = b.subarray(off + 8, off + 8 + len);
    if (type === 'IHDR') {
      ihdr = {
        w: data.readUInt32BE(0), h: data.readUInt32BE(4),
        depth: data[8], color: data[9], interlace: data[12],
      };
    } else if (type === 'IDAT') idat.push(data);
    off += 12 + len;
  }
  if (ihdr.depth !== 8 || ihdr.interlace !== 0) throw new Error('only 8-bit non-interlaced: ' + JSON.stringify(ihdr));
  const ch = ihdr.color === 6 ? 4 : ihdr.color === 2 ? 3 : ihdr.color === 0 ? 1 : (() => { throw new Error('colortype ' + ihdr.color); })();
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const stride = ihdr.w * ch;
  const px = Buffer.alloc(ihdr.h * stride);
  const paeth = (a, c, bb) => {
    const p = a + bb - c, pa = Math.abs(p - a), pb = Math.abs(p - c), pc = Math.abs(p - bb);
    return pa <= pb && pa <= pc ? a : pb <= pc ? c : bb;
  };
  for (let y = 0; y < ihdr.h; y++) {
    const ft = raw[y * (stride + 1)];
    const line = raw.subarray(y * (stride + 1) + 1, y * (stride + 1) + 1 + stride);
    const cur = y * stride, prev = cur - stride;
    for (let x = 0; x < stride; x++) {
      let v = line[x];
      if (ft === 1) v += x >= ch ? px[cur + x - ch] : 0;
      else if (ft === 2) v += y > 0 ? px[prev + x] : 0;
      else if (ft === 3) v += ((x >= ch ? px[cur + x - ch] : 0) + (y > 0 ? px[prev + x] : 0)) >> 1;
      else if (ft === 4) v += y > 0 && x >= ch ? paeth(px[cur + x - ch], prev >= 0 ? px[prev + x - ch] : 0, px[prev + x]) : (y > 0 ? px[prev + x] : 0);
      px[cur + x] = v & 0xff;
    }
  }
  return { w: ihdr.w, h: ihdr.h, ch, px };
}

// 量化后再取游程: 抗锯齿噪声压掉, 纯色 UI 区会浮出来
const qhex = (img, i, sh) => {
  const o = [];
  for (let k = 0; k < 3; k++) o.push((img.px[i + k] >> sh).toString(16));
  return '#' + o.join('');
};
function qruns(img, axis, fixed, sh, minRun) {
  // axis 'y' = 沿 y 方向扫描 (给定 x 的竖切), axis 'x' = 沿 x 方向 (给定 y 的横切)
  const n = axis === 'y' ? img.h : img.w;
  const seq = [];
  for (let t = 0; t < n; t++) {
    const c = qhex(img, (axis === 'y' ? (t * img.w + fixed) : (fixed * img.w + t)) * img.ch, sh);
    const last = seq[seq.length - 1];
    if (last && last.c === c) last.n++;
    else seq.push({ c, n: 1, t0: t });
  }
  return seq.filter(s => s.n >= minRun).map(s => `${s.c} ${s.t0}..${s.t0 + s.n - 1}`).join(' | ');
}

const [, , mode, png, ...args] = process.argv;
const img = decode(png);
const sh = +(args[1] || 3);
const minRun = +(args[2] || 6);
if (mode === 'size') console.log(img.w + 'x' + img.h + ' ch=' + img.ch);
else if (mode === 'qcol') console.log(`qcol x=${args[0]}: ` + qruns(img, 'y', +args[0], sh, minRun));
else if (mode === 'qrow') console.log(`qrow y=${args[0]}: ` + qruns(img, 'x', +args[0], sh, minRun));
else console.log('modes: size | qcol <png> <x> [shift] [minRun] | qrow <png> <y> [shift] [minRun]');
