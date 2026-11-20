// 端末内（このブラウザ）だけに保存する。サーバーには送らない。
import { emptyData } from './engine.js';

const KEY = 'focusguard.v1';

export function load() {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return emptyData();
    const d = JSON.parse(raw);
    const base = emptyData();
    return { ...base, ...d, settings: { ...base.settings, ...(d.settings ?? {}) } };
  } catch {
    return emptyData();
  }
}

export function save(data) {
  try {
    localStorage.setItem(KEY, JSON.stringify(data));
    return true;
  } catch {
    return false;
  }
}

/** 読み込み → 変更 → 保存（別タブで変わっていても最新から始める） */
export function update(fn) {
  const d = load();
  const out = fn(d);
  save(d);
  return out;
}

export function exportJSON() {
  return JSON.stringify(load(), null, 2);
}

export function importJSON(text) {
  const d = JSON.parse(text);
  if (!d || !Array.isArray(d.targets) || !Array.isArray(d.records)) throw new Error('Focus Guard のバックアップではありません');
  save(d);
}
