// SVG -> 透過 PNG ラスタライザ（開発ビルド専用）。
// Build-StarterSet.ps1 が Fluent UI Emoji の Flat / High Contrast (SVG) を
// PNG 化するために使う。エンドユーザーは実行不要。
//
// 使い方: node rasterize.js <manifest.json>
//   manifest.json = [{ "in": "<svg>", "out": "<png>", "width": 256 }, ...]
//
// 依存: @resvg/resvg-js（プリビルド バイナリ。追加のシステム依存なし）。
// require は NODE_PATH 経由でも解決できるよう Build-StarterSet.ps1 が設定する。

'use strict';
const fs = require('fs');
const { Resvg } = require('@resvg/resvg-js');

const manifestPath = process.argv[2];
if (!manifestPath) {
  console.error('usage: node rasterize.js <manifest.json>');
  process.exit(2);
}

let manifest;
try {
  manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
} catch (e) {
  console.error('manifest 読み込み失敗: ' + e.message);
  process.exit(2);
}
if (!Array.isArray(manifest)) { manifest = [manifest]; }

let ok = 0;
let fail = 0;
for (const m of manifest) {
  try {
    const svg = fs.readFileSync(m.in);
    const r = new Resvg(svg, {
      fitTo: { mode: 'width', value: m.width || 256 },
      background: 'rgba(0,0,0,0)'
    });
    fs.writeFileSync(m.out, r.render().asPng());
    ok++;
  } catch (e) {
    console.error('FAIL ' + m.in + ' :: ' + e.message);
    fail++;
  }
}
console.log('rasterized ok=' + ok + ' fail=' + fail);
process.exit(fail > 0 ? 1 : 0);
