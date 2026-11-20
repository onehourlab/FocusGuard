// Focus Guard Web 版の画面。データはこのブラウザの中だけに保存する（通信なし）。
import * as E from './engine.js';
import * as S from './store.js';

const root = document.getElementById('app');
let data = S.load();
const mutate = (fn) => { const r = S.update(fn); data = S.load(); return r; };

// MARK: - 小さな道具

const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const mins = (m) => (m >= 60 ? `${Math.floor(m / 60)}時間${m % 60 ? `${m % 60}分` : ''}` : `${m}分`);
const timeText = (ms) => new Date(ms).toLocaleTimeString('ja-JP', { hour: '2-digit', minute: '2-digit' });
const today = () => E.dayKey(Date.now());
const target = (id) => data.targets.find((t) => t.id === id);
const BASE = location.href.split('#')[0];
export const SHORTCUT_NAME = 'FocusGuard許可';

export const APP_PRESETS = [
  { name: 'Instagram', key: 'instagram', scheme: 'instagram://' },
  { name: 'YouTube', key: 'youtube', scheme: 'youtube://' },
  { name: 'X', key: 'x', scheme: 'twitter://' },
  { name: 'TikTok', key: 'tiktok', scheme: 'snssdk1233://' },
  { name: 'LINE', key: 'line', scheme: 'line://' },
  { name: 'Threads', key: 'threads', scheme: 'barcelona://' },
  { name: 'Facebook', key: 'facebook', scheme: 'fb://' },
  { name: 'Netflix', key: 'netflix', scheme: 'nflx://' },
];

/** ショートカット「FocusGuard許可」を呼び、1回だけ通れる許可を残してアプリへ戻る */
const passLink = (t) => (t?.appKey
  ? `shortcuts://run-shortcut?name=${encodeURIComponent(SHORTCUT_NAME)}&input=text&text=${encodeURIComponent(`${t.appKey}|${t.scheme || ''}`)}`
  : null);
const gateURL = (t) => `${BASE}#/gate?app=${encodeURIComponent(t.appKey)}`;

// クリック処理：描画のたびに登録し直す
let actions = [];
const act = (fn) => { actions.push(fn); return `data-act="${actions.length - 1}"`; };

function route() {
  const [path, q] = location.hash.slice(1).split('?');
  return { path: path || '/', params: new URLSearchParams(q || '') };
}

function go(hash) {
  if (location.hash === hash) render(); else location.hash = hash;
}

// MARK: - 申請フロー（ページを離れたら「取りやめ」として記録）

let flow = null;

function startFlow({ targetId = null, extendsSessionId = null, purpose = '', fromGate = false }) {
  flow = {
    request: E.newRequest(targetId, purpose, '', 5, Date.now(), { extendsSessionId }),
    seedPurpose: purpose, step: targetId ? 'purpose' : 'target', result: null, answer: '', fromGate,
  };
}

function leaveFlow() {
  if (!flow) return;
  const { request, result, seedPurpose } = flow;
  const started = (request.purpose.trim() && request.purpose.trim() !== seedPurpose.trim()) || request.reason.trim();
  if (request.targetId && result?.verdict === 'clarify') mutate((d) => E.recordAbandon(d, request, 'duringClarification'));
  else if (request.targetId && !result && started) mutate((d) => E.recordAbandon(d, request, 'beforeSubmit'));
  flow = null;
}

// MARK: - 共通の部品

const card = (title, body, cls = '') => `<section class="card ${cls}">${title ? `<h3>${title}</h3>` : ''}${body}</section>`;
const stat = (label, value, note = '') => `<div class="stat"><span>${label}</span><strong>${value}</strong>${note ? `<small>${note}</small>` : ''}</div>`;
const statusBadge = { approved: ['承認', 'ok'], denied: ['不承認', 'ng'], clarifying: ['再質問中', 'warn'], abandoned: ['取りやめ', 'muted'] };
const checkIcon = { pass: '✓', warn: '!', fail: '×' };

function tabs(path) {
  const t = (hash, label, p) => `<a href="${hash}" class="${path === p ? 'on' : ''}">${label}</a>`;
  return `<nav class="tabs">${t('#/', '今日', '/')}${t('#/report', 'レポート', '/report')}${t('#/history', '履歴', '/history')}${t('#/settings', '設定', '/settings')}</nav>`;
}

function page(title, body, { back = null, tabsFor = null } = {}) {
  return `<header class="bar">${back ? `<a class="back" href="${back}">‹ 戻る</a>` : '<span></span>'}<h1>${title}</h1><span></span></header>
  <main>${body}</main>${tabsFor ? tabs(tabsFor) : ''}`;
}

// MARK: - 今日

function homePage() {
  const now = Date.now();
  const s = E.summary(data, today());
  const y = E.summary(data, E.addDays(today(), -1));
  const active = E.activeSessions(data, now);
  const pending = E.emergenciesNeedingReflection(data, today());
  const notice = E.frequentEmergencyNotice(data, today());
  const goal = E.goalStatus(s, data.settings);
  const needsSetup = data.targets.some((t) => !t.appKey) || !data.settings.shortcutReady;

  let html = '';
  if (pending.length) {
    const e = pending[0];
    html += card('緊急解除のふりかえり', `<p>${E.shortLabel(e.day)} ${timeText(e.date)} に「${E.EMERGENCY_KINDS[e.kind]}」で緊急解除を使いました。振り返ると、どうでしたか？</p>
      ${notice ? `<p class="note">${notice}</p>` : ''}
      <div class="stack">${Object.entries(E.REFLECTIONS).map(([k, v]) => `<button class="btn" ${act(() => { mutate((d) => { d.emergencies.find((x) => x.id === e.id).reflection = k; }); render(); })}>${v}</button>`).join('')}</div>
      ${pending.length > 1 ? `<p class="note">ほかに${pending.length - 1}件あります</p>` : ''}`);
  }
  html += `<div class="stack">
    <button class="btn primary big" ${act(() => { startFlow({ targetId: data.targets.length === 1 ? data.targets[0].id : null }); go('#/request'); })} ${data.targets.length ? '' : 'disabled'}>利用を申請する</button>
    <a class="btn danger big" href="#/emergency">緊急解除</a></div>`;
  if (needsSetup) {
    html += card('自動でここに来るようにする', `<p>Instagram などを開いたとき自動でこの画面に来るよう、iPhone の「ショートカット」アプリを設定します。</p><a class="btn" href="#/setup">設定手順を見る</a>`, 'hint');
  }
  if (active.length) {
    html += card('解除中', active.map((x) => {
      const t = target(x.targetId);
      const left = Math.max(0, Math.ceil((x.wallClockEnd - now) / 60000));
      const rec = data.records.find((r) => r.sessionId === x.id);
      return `<div class="session"><div><strong>${esc(t?.name ?? 'すべての対象')}</strong>${x.isEmergency ? ' <span class="badge ng">緊急</span>' : ''}
        <p class="note">${timeText(x.wallClockEnd)}まで（残り約${left}分）</p></div>
        <div class="row">${t && passLink(t) ? `<a class="btn" href="${passLink(t)}">${esc(t.name)}を開く</a>` : ''}
        <button class="btn" ${act(() => { mutate((d) => E.endSession(d, x.id, 'endedByUser')); render(); })}>今すぐ終える</button>
        ${!x.isEmergency && t ? `<button class="btn" ${act(() => { startFlow({ targetId: t.id, extendsSessionId: x.id, purpose: rec?.request.purpose ?? '' }); go('#/request'); })}>延長を申請</button>` : ''}</div></div>`;
    }).join('') + '<p class="note">時間を過ぎると、次にアプリを開いたときから再び申請が必要になります。</p>');
  }
  html += card('今日の記録', `<div class="grid">
    ${stat('許可して使った時間', mins(s.countedMinutes), y.hasData ? diffText(s.countedMinutes - y.countedMinutes) : '昨日の記録なし')}
    ${stat('申請', `${s.requestCount}回`)}
    ${stat('承認 / 再質問 / 不承認', `${s.approvedRounds} / ${s.clarifyRounds} / ${s.deniedRounds}`)}
    ${stat('申請の取りやめ', `${s.abandonedCount}回`)}
    ${stat('開こうとした回数', `${s.shieldOpenCount}回`, s.shieldClosedCount ? `うち${s.shieldClosedCount}回は開かずに閉じた` : '')}
    ${stat('緊急解除', `${s.emergencyCount}回`, s.emergencyCount ? `計${mins(s.emergencyMinutes)}` : '')}
  </div><p class="note">「取りやめ」「開かずに閉じた」は、使うのを思いとどまった可能性を示す目安です。理由までは分からないため、必ずしも衝動を抑えられたとは限りません。Web版は他のアプリ内での実際の使用時間を測れないため、許可した時間（早めに終えた場合はそこまで）で数えています。</p>`);
  if (s.repeated.length) {
    html += card('同じ目的での繰り返し', s.repeated.map((r) => `<div class="line"><span>${esc(r.label)}<small>${esc(target(r.targetId)?.name ?? '')}</small></span><strong>${r.count}回・${mins(r.minutes)}</strong></div>`).join(''));
  }
  if (goal) {
    const pct = Math.min(100, Math.round((goal.used / Math.max(goal.goal, 1)) * 100));
    html += card('1日の目標', `<div class="meter ${goal.achieved ? '' : 'over'}"><i style="width:${pct}%"></i></div>
      <p>${goal.achieved ? `目標 ${mins(goal.goal)} のうち ${mins(goal.used)}。達成ペースです。` : `目標 ${mins(goal.goal)} を ${mins(goal.used - goal.goal)} 超えています。`}</p>`);
  }
  return page('今日', html, { tabsFor: '/' });
}

const diffText = (d) => (d === 0 ? '昨日と同じ' : d > 0 ? `昨日より${mins(d)}多い` : `昨日より${mins(-d)}少ない`);

// MARK: - アプリを開いたとき（ショートカットから来る）

function gatePage(params) {
  const key = params.get('app') ?? '';
  const t = data.targets.find((x) => x.appKey === key);
  if (!t) {
    return page('Focus Guard', card('このアプリはまだ登録されていません', `<p>「${esc(key)}」を制限の対象として登録してください。</p><a class="btn primary" href="#/target?new=1&app=${encodeURIComponent(key)}">登録する</a>`));
  }
  // ショートカットから来るたびに1回だけ「開こうとした」を記録（記録済みの印 seen=1 を URL に付ける）
  if (!params.get('seen')) {
    mutate((d) => E.recordShieldEvent(d, 'opened', t.id));
    history.replaceState(null, '', `#/gate?app=${encodeURIComponent(key)}&seen=1`);
  }
  const now = Date.now();
  const active = E.activeSessions(data, now).find((x) => x.targetId === t.id || x.targetId == null);
  if (active) {
    return page(esc(t.name), card('許可中です', `<p><strong>${timeText(active.wallClockEnd)}まで</strong>（残り約${Math.max(0, Math.ceil((active.wallClockEnd - now) / 60000))}分）使えます。</p>
      <a class="btn primary big" href="${passLink(t)}">${esc(t.name)}に戻る</a>
      <button class="btn" ${act(() => { mutate((d) => E.endSession(d, active.id, 'endedByUser')); render(); })}>もう終える</button>`));
  }
  const rules = (t.personalRules ?? []).length ? `<div class="rules"><strong>自分で決めたルール</strong>${t.personalRules.map((r) => `<p>・${esc(r)}</p>`).join('')}</div>` : '';
  return page(esc(t.name), `<section class="gate">
      <div class="hourglass" aria-hidden="true"></div>
      <h2>${esc(t.name)}を開く前に</h2>
      <ol><li>何のために使う？</li><li>何分必要？</li><li>なぜ今？</li></ol>
      ${rules}
      <button class="btn primary big" ${act(() => { mutate((d) => E.recordShieldEvent(d, 'requested', t.id)); startFlow({ targetId: t.id, fromGate: true }); go('#/request'); })}>利用を申請する</button>
      <button class="btn big" ${act(() => { mutate((d) => E.recordShieldEvent(d, 'closed', t.id)); go('#/closed'); })}>今はやめておく</button>
      <a class="link danger" href="#/emergency?target=${t.id}">緊急解除（審査なし・すぐに使えます）</a>
    </section>`);
}

function closedPage() {
  return page('Focus Guard', card('', `<h2>閉じました</h2><p>ホーム画面に戻ってください。開こうとしたこと・やめたことは記録しました。</p><a class="btn" href="#/">今日の記録を見る</a>`));
}

// MARK: - 申請

function requestPage() {
  if (!flow) startFlow({});
  const f = flow;
  const r = f.request;
  const t = target(r.targetId);
  const isExt = !!r.extendsSessionId;
  const head = (n, title) => `<p class="step">${esc(t?.name ?? '')}・${n} / 3</p><h2>${title}</h2>`;
  let body = '';

  if (f.step === 'target') {
    body = `<h2>どのアプリを使いますか？</h2>${data.targets.map((x) => `<button class="btn list" ${act(() => { r.targetId = x.id; f.step = 'purpose'; render(); })}>${esc(x.name)}</button>`).join('')}`;
  } else if (f.step === 'purpose') {
    body = `${head(1, isExt ? '延長して何をしますか？' : '何のために使いますか？')}
      <p class="note">誰に・何を・どうするのか、何をしたら終わりにするのかを書いてください。</p>
      <textarea id="purpose" rows="3" placeholder="${isExt ? '例：授業動画の残り1本を最後まで見る' : '例：友達からのDMに返信したら閉じる'}">${esc(r.purpose)}</textarea>
      <p class="note">書き方の例：友達からのDMに返信したら閉じる／授業動画を1本見る／明日の天気と電車の運行情報を調べる</p>
      ${(t?.personalRules ?? []).length ? `<div class="rules"><strong>自分で決めたルール</strong>${t.personalRules.map((x) => `<p>・${esc(x)}</p>`).join('')}</div>` : ''}
      <button class="btn primary big" id="next1" ${act(() => { r.purpose = document.getElementById('purpose').value; if (r.purpose.trim()) { f.step = 'minutes'; render(); } })}>次へ</button>`;
  } else if (f.step === 'minutes') {
    const remaining = remainingNote(t);
    body = `${head(2, '何分必要ですか？')}
      <p class="note">時間を過ぎると、次に開いたときから再び申請が必要になります。延長するには理由を書いて審査を受けます。</p>
      <div class="minutes"><button class="btn round" ${act(() => { r.minutes = Math.max(1, r.minutes - 1); render(); })}>−</button>
        <strong>${mins(r.minutes)}</strong>
        <button class="btn round" ${act(() => { r.minutes = Math.min(E.MAX_MINUTES_PER_REQUEST, r.minutes + 1); render(); })}>＋</button></div>
      <div class="chips">${[3, 5, 10, 15, 30, 60].map((m) => `<button class="chip ${r.minutes === m ? 'on' : ''}" ${act(() => { r.minutes = m; render(); })}>${m}分</button>`).join('')}</div>
      ${remaining ? `<p class="note">${remaining}</p>` : ''}
      <button class="btn primary big" ${act(() => { f.step = 'reason'; render(); })}>次へ</button>`;
  } else if (f.step === 'reason') {
    body = `${head(3, isExt ? 'なぜ延長が必要ですか？' : 'なぜ今使う必要がありますか？')}
      <p class="note">${isExt ? '最初の時間で終わらなかった理由を書いてください。' : 'あとでは駄目な理由があれば書いてください。'}</p>
      <textarea id="reason" rows="3" placeholder="${isExt ? '例：動画が思ったより長く、残り5分だった' : '例：集合時間の返事を待たせているため'}">${esc(r.reason)}</textarea>
      <div class="summary"><small>申請内容</small><p>${esc(t?.name)}を${mins(r.minutes)}：${esc(r.purpose)}</p></div>
      <button class="btn primary big" ${act(() => { r.reason = document.getElementById('reason').value; if (r.reason.trim()) submit(); })}>審査を受ける</button>`;
  } else if (f.step === 'result') {
    body = resultView(f, t);
  }
  return page(isExt ? '延長の申請' : '利用の申請', body, { back: '#/' });
}

function remainingNote(t) {
  if (!t || data.settings.limitMode !== 'reviewWithDailyCaps' || t.dailyCapMinutes == null) return '';
  const used = data.sessions.filter((s) => !s.isEmergency && s.targetId === t.id && E.dayKey(s.startedAt) === today()).reduce((a, s) => a + E.countedMinutes(s), 0);
  return `本日の「${esc(t.name)}」は残り${Math.max(0, t.dailyCapMinutes - used)}分です（上限${t.dailyCapMinutes}分）。`;
}

function submit() {
  const f = flow;
  f.request.purpose = f.request.purpose.trim();
  f.request.reason = f.request.reason.trim();
  const now = Date.now();
  const result = E.review(f.request, data, now);
  mutate((d) => E.recordReview(d, structuredClone(f.request), result, now));
  f.result = result;
  f.step = 'result';
  render();
  window.scrollTo(0, 0);
}

function resultView(f, t) {
  const r = f.result;
  const color = { approve: 'ok', clarify: 'warn', deny: 'ng' }[r.verdict];
  const headline = { approve: `${esc(t.name)}を${mins(r.grantedMinutes)}使えます。`, clarify: 'もう少し教えてください。', deny: '今回は通常の解除を行いません。' }[r.verdict];
  let html = `<div class="verdict ${color}"><span>${{ approve: '✓', clarify: '?', deny: '×' }[r.verdict]}</span><div><h2>${E.VERDICT_LABEL[r.verdict]}</h2><p>${headline}</p></div></div>`;
  if (r.question) html += card('追加で教えてください', `<p class="q">${esc(r.question)}</p>`);
  if (r.denialReasons.length) html += card('通常の解除をしない理由', r.denialReasons.map((x) => `<p>・${esc(x)}</p>`).join(''));

  if (r.verdict === 'approve') {
    const link = passLink(t);
    html += link
      ? `<a class="btn primary big" href="${link}">${esc(t.name)}を開く</a><p class="note">ショートカット「${SHORTCUT_NAME}」が動き、1回だけ通れるようにしてから${esc(t.name)}を開きます。</p>`
      : `<a class="btn primary big" href="#/">閉じる</a><p class="note">設定でアプリの種類を選ぶと、ここから直接開けます。</p>`;
  } else if (r.verdict === 'clarify') {
    html += `<textarea id="answer" rows="3" placeholder="ここに回答を書く">${esc(f.answer)}</textarea>
      <button class="btn primary big" ${act(() => {
        const a = document.getElementById('answer').value.trim();
        if (!a) return;
        f.request.clarifications.push({ question: r.question ?? '', answer: a });
        f.answer = '';
        submit();
      })}>回答して再審査</button>`;
  } else {
    html += '<div class="stack">';
    if (r.suggestedMinutes > 0) html += `<button class="btn primary" ${act(() => restart(r.suggestedMinutes))}>${mins(r.suggestedMinutes)}で申請し直す</button>`;
    html += `<button class="btn" ${act(() => restart(f.request.minutes))}>内容を書き直す</button>
      <a class="link danger" href="#/emergency${t ? `?target=${t.id}` : ''}">緊急解除へ</a></div>`;
  }
  html += card('判定の内訳', r.checks.map((c) => `<div class="check ${c.status}"><i>${checkIcon[c.status]}</i><div><strong>${E.CRITERIA[c.criterion]}</strong><p>${esc(c.message)}</p></div></div>`).join('')
    + `<p class="note">判定：ルール判定（このブラウザ内・通信なし）／分類：${E.CATEGORIES[r.category]}</p>`);
  return html;
}

function restart(minutes) {
  const old = flow;
  startFlow({ targetId: old.request.targetId, extendsSessionId: old.request.extendsSessionId, purpose: old.request.purpose, fromGate: old.fromGate });
  flow.seedPurpose = '';
  flow.request.reason = old.request.reason;
  flow.request.minutes = minutes;
  render();
}

// MARK: - 緊急解除

let emergencyDone = null;

function emergencyPage(params) {
  const scope = params.get('target');
  const t = scope ? target(scope) : null;
  if (emergencyDone) {
    const e = emergencyDone;
    const tt = target(e.targetId);
    return page('緊急解除', card('', `<h2 class="ng-text">解除しました</h2><p>「${E.EMERGENCY_KINDS[e.kind]}」として${mins(e.minutes)}解除しています（${timeText(e.date + e.minutes * 60000)}まで）。</p>
      ${tt && passLink(tt) ? `<a class="btn primary big" href="${passLink(tt)}">${esc(tt.name)}を開く</a>` : ''}
      <a class="btn" href="#/" ${act(() => { emergencyDone = null; })}>閉じる</a>`), { back: '#/' });
  }
  let minutes = data.settings.emergencyDefaultMinutes;
  const n = data.emergencies.filter((e) => e.day === today()).length;
  return page('緊急解除', `<h2>審査なしで、すぐに解除します。</h2>
    <p class="note">通信やAIは使いません。使ったことは記録され、あとで振り返りをお願いすることがあります。回数による制限はありません。</p>
    <label class="field">解除する時間<select id="em-min">${[5, 15, 30, 60].map((m) => `<option value="${m}" ${m === minutes ? 'selected' : ''}>${m}分</option>`).join('')}</select></label>
    <label class="field">対象<select id="em-target"><option value="">すべての対象</option>${data.targets.map((x) => `<option value="${x.id}" ${t?.id === x.id ? 'selected' : ''}>${esc(x.name)}</option>`).join('')}</select></label>
    <p><strong>何のための緊急ですか？（押すとすぐに解除されます）</strong></p>
    <div class="kinds">${Object.entries(E.EMERGENCY_KINDS).map(([k, v]) => `<button class="kind" ${act(() => {
      minutes = Number(document.getElementById('em-min').value);
      const tid = document.getElementById('em-target').value || null;
      const { record } = mutate((d) => E.recordEmergency(d, { kind: k, targetId: tid, minutes }));
      emergencyDone = { ...record, targetId: tid ?? t?.id ?? null };
      render();
    })}>${v}</button>`).join('')}</div>
    ${card('毎回の緊急解除が必要なアプリは', '<p>電話・連絡・健康・安全のために使うアプリは、ショートカットの自動化に入れなければ、いつでもそのまま開けます。iPhone の「電話」と緊急SOSはもともと影響を受けません。</p>', 'hint')}
    ${n ? `<p class="note">今日の緊急解除：${n}回</p>` : ''}`, { back: '#/' });
}

// MARK: - レポート

function reportPage() {
  const days = E.week(data, today());
  const withData = days.filter((d) => d.hasData);
  const base = E.baseline(data, E.addDays(today(), -6), 28);
  const max = Math.max(1, ...days.map((d) => d.countedMinutes));
  const bars = days.map((d, i) => {
    const h = d.hasData ? Math.max(2, Math.round((d.countedMinutes / max) * 120)) : 0;
    const x = 10 + i * 46;
    return `<g>${d.hasData ? `<rect x="${x}" y="${140 - h}" width="30" height="${h}" rx="4"></rect><text x="${x + 15}" y="${134 - h}" class="v">${d.countedMinutes}</text>` : `<text x="${x + 15}" y="134" class="v muted">—</text>`}
      <text x="${x + 15}" y="158" class="d">${E.shortLabel(d.day)}</text></g>`;
  }).join('');
  let html = card('許可して使った時間（1週間）', withData.length
    ? `<svg viewBox="0 0 332 166" class="chart" role="img" aria-label="1週間の利用時間">${bars}</svg><p class="note">単位は分。「—」は記録がない日です（0分とは区別しています）。</p>`
    : '<p class="note">この1週間の記録はまだありません。</p>');
  if (base && withData.length) {
    const avg = Math.floor(withData.reduce((a, d) => a + d.countedMinutes, 0) / withData.length);
    const diff = base.minutes - avg;
    html += card('削減量', `<p class="big-num">${diff >= 0 ? `1日あたり ${mins(diff)} 減` : `1日あたり ${mins(-diff)} 増`}</p><p class="note">基準：${base.source} ${mins(base.minutes)}/日 ・ 今週：記録のある${withData.length}日の平均 ${mins(avg)}/日</p>`);
  } else {
    html += card('削減量', '<p class="note">比べられる基準がまだありません。設定で基準値を入れるか、記録が貯まると表示されます。</p>');
  }
  const sum = (k) => days.reduce((a, d) => a + d[k], 0);
  html += card('1週間の合計', `<div class="grid">${stat('申請', `${sum('requestCount')}回`)}${stat('取りやめ', `${sum('abandonedCount')}回`)}
    ${stat('開こうとした', `${sum('shieldOpenCount')}回`)}${stat('開かずに閉じた', `${sum('shieldClosedCount')}回`)}
    ${stat('承認 / 再質問 / 不承認', `${sum('approvedRounds')} / ${sum('clarifyRounds')} / ${sum('deniedRounds')}`)}${stat('緊急解除', `${sum('emergencyCount')}回`)}</div>`);
  const merged = new Map();
  for (const r of days.flatMap((d) => d.repeated)) {
    const m = merged.get(r.clusterId) ?? { ...r, count: 0, minutes: 0 };
    m.count += r.count; m.minutes += r.minutes; merged.set(r.clusterId, m);
  }
  if (merged.size) {
    html += card('同じ目的での繰り返し（1日2回以上の日）', [...merged.values()].sort((a, b) => b.count - a.count).slice(0, 5)
      .map((r) => `<div class="line"><span>${esc(r.label)}</span><strong>${r.count}回・${mins(r.minutes)}</strong></div>`).join(''));
  }
  return page('1週間のレポート', html, { tabsFor: '/report' });
}

// MARK: - 履歴

function historyPage() {
  const recs = [...data.records].sort((a, b) => b.request.createdAt - a.request.createdAt);
  const byDay = new Map();
  for (const r of recs) (byDay.get(r.day) ?? byDay.set(r.day, []).get(r.day)).push(r);
  let html = '';
  if (!recs.length && !data.emergencies.length) html = card('', '<p class="note">まだ記録がありません。利用申請をすると、ここに目的と結果が残ります。</p>');
  for (const [day, items] of byDay) {
    html += `<h4 class="section">${E.shortLabel(day)}（${items.length}件）</h4>` + items.map((r) => {
      const [label, cls] = statusBadge[r.status];
      const s = data.sessions.find((x) => x.id === r.sessionId);
      const cluster = data.clusters.find((c) => c.id === r.clusterId);
      return `<details class="card rec"><summary><span class="badge ${cls}">${label}</span> <small>${esc(target(r.request.targetId)?.name ?? '削除した対象')}・${timeText(r.request.createdAt)}</small>
        <p>${esc(r.request.purpose || '（目的の入力前）')}</p><small>申告 ${mins(r.request.minutes)}${r.rounds.length > 1 ? `・審査${r.rounds.length}回` : ''}</small></summary>
        <dl><dt>今使う理由</dt><dd>${esc(r.request.reason || '—')}</dd>
        ${cluster ? `<dt>目的のまとまり</dt><dd>${esc(cluster.label)}</dd>` : ''}
        ${r.category ? `<dt>分類</dt><dd>${E.CATEGORIES[r.category]}</dd>` : ''}
        <dt>審査の経過</dt><dd>${r.rounds.map((v) => E.VERDICT_LABEL[v]).join(' → ') || '—'}</dd>
        ${r.abandonedAt ? `<dt>取りやめた段階</dt><dd>${r.abandonedAt === 'beforeSubmit' ? '送信前' : '再質問の途中'}</dd>` : ''}
        ${s ? `<dt>使った時間</dt><dd>${s.measuredMinutes != null ? mins(s.measuredMinutes) : '使用中'}（許可 ${mins(s.grantedMinutes)}）</dd>` : ''}
        ${r.request.clarifications.map((c) => `<dt>Q. ${esc(c.question)}</dt><dd>A. ${esc(c.answer)}</dd>`).join('')}
        ${(r.lastResult?.checks ?? []).map((c) => `<dt>${checkIcon[c.status]} ${E.CRITERIA[c.criterion]}</dt><dd>${esc(c.message)}</dd>`).join('')}</dl></details>`;
    }).join('');
  }
  if (data.emergencies.length) {
    html += '<h4 class="section">緊急解除</h4>' + card('', [...data.emergencies].sort((a, b) => b.date - a.date).slice(0, 50).map((e) => `<div class="line"><span>${E.EMERGENCY_KINDS[e.kind]}・${mins(e.minutes)}<small>${new Date(e.date).toLocaleString('ja-JP')}</small></span><small>${e.reflection ? E.REFLECTIONS[e.reflection] : '未振り返り'}</small></div>`).join(''));
  }
  return page('履歴', html, { tabsFor: '/history' });
}

// MARK: - 設定

function settingsPage() {
  const st = data.settings;
  const set = (fn) => { mutate((d) => fn(d.settings)); render(); };
  const opt = (label, key, def) => `<label class="field toggle"><span>${label}</span><input type="checkbox" ${st[key] != null ? 'checked' : ''} ${act(() => set((x) => { x[key] = x[key] != null ? null : def; }))}></label>
    ${st[key] != null ? `<label class="field">${label}（分/日）<input type="number" min="5" max="600" step="5" value="${st[key]}" data-setting="${key}"></label>` : ''}`;
  const html = card('制限するアプリ', data.targets.map((t) => `<a class="btn list" href="#/target?id=${t.id}">${esc(t.name)}<small>${targetSummary(t)}</small></a>`).join('')
      + '<a class="btn" href="#/target?new=1">＋ 制限するアプリを追加</a>')
    + card('ショートカット', `<p class="note">アプリを開いたとき自動でここに来る仕組みです。</p><a class="btn" href="#/setup">設定手順を見る</a>`)
    + card('審査', `<label class="field">管理の方法<select data-setting="limitMode"><option value="reviewOnly" ${st.limitMode === 'reviewOnly' ? 'selected' : ''}>毎回の審査だけ</option><option value="reviewWithDailyCaps" ${st.limitMode === 'reviewWithDailyCaps' ? 'selected' : ''}>審査＋1日の上限</option></select></label>
      <p class="note">${st.limitMode === 'reviewOnly' ? '毎回の申請で審査します。1日の累計上限は使いません（1回ごとの申告時間は常に守られます）。' : '審査に加えて、アプリごと・目的ごとに設定した1日の上限を超える申請は承認しません。'}</p>
      <label class="field">同じ目的で何回使ったあとに質問するか<input type="number" min="1" max="10" value="${st.repeatQuestionThreshold}" data-setting="repeatQuestionThreshold"></label>
      <label class="field">再質問の最大回数<input type="number" min="1" max="4" value="${st.maxClarifications}" data-setting="maxClarifications"></label>
      <p class="note">Web版はAIを使わず、決まったルールで審査します（iOS版は端末内のAIも使います）。文章は外部に送信しません。</p>`)
    + card('目標', `${opt('1日の目標', 'dailyGoalMinutes', 60)}${opt('削減量の基準値', 'baselineDailyMinutes', 120)}<p class="note">基準値を入れない場合は、過去の実際の記録の平均と比べます。記録が無いうちは削減量を表示しません。</p>`)
    + card('緊急解除', `<label class="field">標準の時間<select data-setting="emergencyDefaultMinutes">${[5, 15, 30, 60].map((m) => `<option value="${m}" ${m === st.emergencyDefaultMinutes ? 'selected' : ''}>${m}分</option>`).join('')}</select></label>`)
    + card('データ', `<p class="note">データはこのブラウザの中だけに保存されます。Safari の「サイトデータを削除」をすると消えるため、ときどきバックアップしてください。</p>
      <div class="stack"><button class="btn" ${act(exportData)}>バックアップを保存</button>
      <label class="btn">バックアップから戻す<input type="file" accept="application/json" id="import" hidden></label>
      <button class="btn danger-outline" ${act(() => { if (confirm('申請と緊急解除の履歴を削除しますか？元に戻せません。')) { mutate((d) => { d.records = []; d.emergencies = []; d.clusters = []; d.shieldEvents = []; d.sessions = d.sessions.filter((s) => E.isActive(s)); }); render(); } })}>履歴を削除</button></div>`);
  return page('設定', html, { tabsFor: '/settings' });
}

function targetSummary(t) {
  const p = [t.appKey ? 'ショートカット連携あり' : 'アプリ未選択'];
  if (t.dailyCapMinutes != null) p.push(`1日${t.dailyCapMinutes}分`);
  if (t.maxMinutesPerSession != null) p.push(`1回${t.maxMinutesPerSession}分まで`);
  if (t.purposeCaps.length) p.push(`目的別上限${t.purposeCaps.length}`);
  if (t.restrictedWindows.length) p.push(`時間帯ルール${t.restrictedWindows.length}`);
  return p.join('・');
}

function exportData() {
  const blob = new Blob([S.exportJSON()], { type: 'application/json' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = `focusguard-backup-${today()}.json`;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
}

// MARK: - 対象の編集

let draft = null;

function targetPage(params) {
  const id = params.get('id');
  if (!draft || (id && draft.id !== id) || (!id && !draft.isNew)) {
    const existing = id ? target(id) : null;
    const preset = APP_PRESETS.find((p) => p.key === params.get('app'));
    draft = existing ? structuredClone(existing) : { ...E.newTarget(preset?.name ?? ''), appKey: preset?.key ?? params.get('app') ?? '', scheme: preset?.scheme ?? '', isNew: true };
  }
  const t = draft;
  const presetKey = APP_PRESETS.some((p) => p.key === t.appKey) ? t.appKey : (t.appKey ? 'custom' : '');
  const catBoxes = (w) => Object.entries(E.CATEGORIES).map(([k, v]) => `<label class="chip ${w.allowed.includes(k) ? 'on' : ''}"><input type="checkbox" hidden ${w.allowed.includes(k) ? 'checked' : ''} ${act(() => { w.allowed = w.allowed.includes(k) ? w.allowed.filter((x) => x !== k) : [...w.allowed, k]; render(); })}>${v}</label>`).join('');
  const toMin = (v) => { const [h, m] = v.split(':').map(Number); return h * 60 + m; };
  const hhmm = (m) => `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;

  const html = card('対象', `<label class="field">アプリ<select id="preset">${['<option value="">選ぶ</option>', ...APP_PRESETS.map((p) => `<option value="${p.key}" ${presetKey === p.key ? 'selected' : ''}>${p.name}</option>`), `<option value="custom" ${presetKey === 'custom' ? 'selected' : ''}>その他（自分で入力）</option>`].join('')}</select></label>
      <label class="field">名前<input id="t-name" value="${esc(t.name)}" placeholder="例：Instagram"></label>
      ${presetKey === 'custom' ? `<label class="field">識別名（半角英数字）<input id="t-key" value="${esc(t.appKey)}" placeholder="例：mygame"></label>
      <label class="field">アプリを開くURL（分かれば）<input id="t-scheme" value="${esc(t.scheme ?? '')}" placeholder="例：mygame://"></label>` : ''}`)
    + card('1日の上限（任意）', `<label class="field toggle"><span>1日の上限を使う</span><input type="checkbox" ${t.dailyCapMinutes != null ? 'checked' : ''} ${act(() => { t.dailyCapMinutes = t.dailyCapMinutes != null ? null : 30; render(); })}></label>
      ${t.dailyCapMinutes != null ? `<label class="field">1日の上限（分）<input type="number" min="5" max="600" step="5" value="${t.dailyCapMinutes}" data-draft="dailyCapMinutes"></label>` : ''}
      ${data.settings.limitMode === 'reviewOnly' ? '<p class="note">現在は「毎回の審査だけ」のため、1日の上限は使われません（設定で切り替え）。</p>' : ''}
      ${t.purposeCaps.map((c, i) => `<div class="row"><input value="${esc(c.label)}" placeholder="目的（例：DM返信）" data-cap-label="${i}"><input type="number" min="1" max="600" value="${c.maxMinutesPerDay}" data-cap-min="${i}" class="short"><span>分</span><button class="btn small" ${act(() => { t.purposeCaps.splice(i, 1); render(); })}>削除</button></div>`).join('')}
      <button class="btn small" ${act(() => { t.purposeCaps.push({ id: crypto.randomUUID(), label: '', maxMinutesPerDay: 10 }); render(); })}>＋ 目的ごとの上限</button>
      <p class="note">目的ごとの上限は、言い回しが違っても意味が近い申請をまとめて数えます。</p>`)
    + card('1回あたり（任意）', `<label class="field toggle"><span>1回の上限を使う</span><input type="checkbox" ${t.maxMinutesPerSession != null ? 'checked' : ''} ${act(() => { t.maxMinutesPerSession = t.maxMinutesPerSession != null ? null : 15; render(); })}></label>
      ${t.maxMinutesPerSession != null ? `<label class="field">1回の上限（分）<input type="number" min="1" max="180" value="${t.maxMinutesPerSession}" data-draft="maxMinutesPerSession"></label>` : ''}`)
    + card('時間帯ルール', t.restrictedWindows.map((w, i) => `<div class="window"><div class="row"><input type="time" value="${hhmm(w.start)}" data-win-start="${i}">〜<input type="time" value="${hhmm(w.end)}" data-win-end="${i}"><button class="btn small" ${act(() => { t.restrictedWindows.splice(i, 1); render(); })}>削除</button></div><p class="note">この時間帯に許可する目的</p><div class="chips">${catBoxes(w)}</div></div>`).join('')
      + `<button class="btn small" ${act(() => { t.restrictedWindows.push({ id: crypto.randomUUID(), start: 22 * 60, end: 7 * 60, allowed: ['communication', 'study'] }); render(); })}>＋ 時間帯ルール</button>
      <p class="note">指定した時間帯は、選んだ目的の申請だけを承認します。最初は確認の質問をし、説明を受けても当てはまらない場合に不承認にします。</p>`)
    + card('自分で決めたルール（文章）', t.personalRules.map((r, i) => `<div class="row"><span class="grow">${esc(r)}</span><button class="btn small" ${act(() => { t.personalRules.splice(i, 1); render(); })}>削除</button></div>`).join('')
      + `<div class="row"><input id="new-rule" placeholder="例：試験前の週は授業動画だけ" class="grow"><button class="btn small" ${act(() => { const v = document.getElementById('new-rule').value.trim(); if (v && !t.personalRules.includes(v)) t.personalRules.push(v); render(); })}>追加</button></div>
      <p class="note">Web版では、申請のたびに画面に表示して自分で確かめます（自動判定はしません）。</p>`)
    + `<div class="stack"><button class="btn primary big" ${act(saveDraft)}>保存</button>
      ${t.isNew ? '' : `<button class="btn danger-outline" ${act(() => { if (confirm(`「${t.name}」を削除しますか？`)) { mutate((d) => { d.targets = d.targets.filter((x) => x.id !== t.id); }); draft = null; go('#/settings'); } })}>この対象を削除</button>`}</div>`;
  return page(t.isNew ? '制限するアプリを追加' : esc(t.name), html, { back: '#/settings' });
}

function syncDraftInputs() {
  if (!draft) return;
  const v = (id) => document.getElementById(id)?.value;
  if (v('t-name') != null) draft.name = v('t-name');
  if (v('t-key') != null) draft.appKey = v('t-key').trim().toLowerCase().replace(/[^a-z0-9_-]/g, '');
  if (v('t-scheme') != null) draft.scheme = v('t-scheme').trim();
  document.querySelectorAll('[data-cap-label]').forEach((el) => { draft.purposeCaps[+el.dataset.capLabel].label = el.value; });
  document.querySelectorAll('[data-cap-min]').forEach((el) => { draft.purposeCaps[+el.dataset.capMin].maxMinutesPerDay = Math.max(1, +el.value || 1); });
  const toMin = (s) => { const [h, m] = s.split(':').map(Number); return (h || 0) * 60 + (m || 0); };
  document.querySelectorAll('[data-win-start]').forEach((el) => { draft.restrictedWindows[+el.dataset.winStart].start = toMin(el.value); });
  document.querySelectorAll('[data-win-end]').forEach((el) => { draft.restrictedWindows[+el.dataset.winEnd].end = toMin(el.value); });
  document.querySelectorAll('[data-draft]').forEach((el) => { draft[el.dataset.draft] = Math.max(1, +el.value || 1); });
}

function saveDraft() {
  syncDraftInputs();
  const t = draft;
  t.name = t.name.trim();
  if (!t.name) { alert('名前を入力してください'); return; }
  if (!t.appKey) { alert('アプリを選んでください'); return; }
  if (data.targets.some((x) => x.appKey === t.appKey && x.id !== t.id)) { alert('同じアプリがすでに登録されています'); return; }
  t.purposeCaps = t.purposeCaps.filter((c) => c.label.trim());
  const { isNew, ...clean } = t;
  mutate((d) => {
    const i = d.targets.findIndex((x) => x.id === clean.id);
    if (i >= 0) d.targets[i] = clean; else d.targets.push(clean);
  });
  draft = null;
  go(data.settings.hasCompletedOnboarding ? '#/settings' : '#/');
}

// MARK: - ショートカットの設定手順

function setupPage() {
  const list = data.targets.filter((t) => t.appKey);
  const html = card('しくみ', `<p>Web版は他のアプリを止めることはできません。代わりに iPhone の「ショートカット」アプリで、<strong>制限したいアプリを開いたら自動でこの画面を開く</strong>ようにします。承認されると、ショートカットが「1回だけ通れる許可」を残してアプリを開きます。</p>
      <p class="note">必要なのは「ショートカット」アプリ（iPhone に標準で入っています）だけです。料金はかかりません。</p>`)
    + card('手順1：許可用のショートカットを作る（1回だけ）', `<ol class="steps">
      <li>「ショートカット」アプリを開き、右上の「＋」で新規作成。名前を <code>${SHORTCUT_NAME}</code> にする（この名前のとおりに）。</li>
      <li>「ショートカットの入力」を受け取る設定にする：画面下の「i」→「共有シートに表示」はオフのままでよい。最初のアクションに「<strong>テキストを分割</strong>」を追加し、入力を「ショートカットの入力」、区切りを「カスタム」で <code>|</code> にする。</li>
      <li>「<strong>リストから項目を取得</strong>」を追加し「最初の項目」にする（＝アプリの識別名）。</li>
      <li>「<strong>テキスト</strong>」を追加して <code>ok</code> と入力。</li>
      <li>「<strong>ファイルを保存</strong>」を追加：保存するもの＝上のテキスト、「保存先を尋ねる」をオフ、保存先＝ <code>Shortcuts/FocusGuard/</code>（識別名）<code>.txt</code>、「上書き」をオン。</li>
      <li>「<strong>リストから項目を取得</strong>」で、手順2の「分割されたテキスト」の「最後の項目」を取り出す（＝アプリを開くURL）。</li>
      <li>「<strong>URLを開く</strong>」を追加し、上の項目を開く。</li></ol>`)
    + card('手順2：アプリごとの自動化を作る', `<ol class="steps">
      <li>「ショートカット」アプリ下の「オートメーション」→「＋」→「<strong>App</strong>」を選び、制限したいアプリを1つ選ぶ。「開いている」にチェック、「<strong>すぐに実行</strong>」を選ぶ。</li>
      <li>「<strong>ファイルを取得</strong>」を追加：<code>Shortcuts/FocusGuard/</code>（識別名）<code>.txt</code>、「見つからない場合はエラー」をオフ。</li>
      <li>「<strong>if</strong>」を追加：条件「ファイル」が「<strong>任意の値がある</strong>」。</li>
      <li>if の中（値があるとき）に「<strong>ファイルを削除</strong>」（削除の前に確認：オフ）＝1回だけ通す。</li>
      <li>「その他の場合」の中に「<strong>URLを開く</strong>」で、下の各アプリ用のURLを入れる。</li></ol>
      ${list.length ? list.map((t) => `<div class="url"><strong>${esc(t.name)}</strong>（識別名 <code>${esc(t.appKey)}</code>）<input readonly value="${esc(gateURL(t))}" onclick="this.select()"><button class="btn small" ${act(() => copy(gateURL(t)))}>コピー</button></div>`).join('')
        : '<p class="note">先に「設定 → 制限するアプリ」でアプリを登録すると、ここに各アプリ用のURLが表示されます。</p>'}`)
    + card('手順3：確かめる', `<ol class="steps"><li>制限したアプリを開くと、この画面（「〜を開く前に」）に切り替わることを確認。</li>
      <li>申請して承認されたら「〜を開く」を押す。ショートカットが動いてアプリが開けばOK。</li></ol>
      <button class="btn primary" ${act(() => { mutate((d) => { d.settings.shortcutReady = true; }); go('#/'); })}>設定が終わった</button>`)
    + card('知っておいてほしいこと', `<ul class="steps"><li>許可時間が過ぎても、アプリを使っている途中で自動的には閉じません。<strong>次に開いたとき</strong>から再び申請が必要になります（時間ぴったりで止めるのはiOSアプリ版の機能です）。</li>
      <li>この画面は <strong>Safari</strong> で開いてください（ホーム画面に追加したアプリとSafariでは記録が別になります）。</li>
      <li>電波が無くても、一度開いたことがあれば表示できます。緊急解除も通信なしで使えます。</li>
      <li>自動化をやめたいときは、「ショートカット」→「オートメーション」で削除すればすぐに元に戻ります。</li></ul>`);
  return page('ショートカットの設定', html, { back: '#/settings' });
}

function copy(text) {
  navigator.clipboard?.writeText(text).then(() => toast('コピーしました'), () => toast('コピーできませんでした。長押しで選択してください'));
}

function toast(msg) {
  const el = document.createElement('div');
  el.className = 'toast';
  el.textContent = msg;
  document.body.appendChild(el);
  setTimeout(() => el.remove(), 1800);
}

// MARK: - はじめに

function onboardingPage() {
  const html = `<section class="hero"><div class="hourglass" aria-hidden="true"></div><h2>開く前に、ひと呼吸。</h2>
    <p>Focus Guard は、使う時間を減らすことよりも「目的を持って使う」ことを助けるアプリです。</p>
    <ol class="three"><li>何のために使うのか</li><li>何分必要なのか</li><li>なぜ今使う必要があるのか</li></ol>
    <p class="note">制限したいアプリを使う前に、この3つを文章で申請します。内容をルールで確かめ、申告した時間だけ使えるようにします。あえて少し手間がかかるようにしています。</p>
    <p class="ng-text">緊急のときは、審査なし・待ち時間なし・通信なしで、すぐに解除できます。</p></section>`
    + card('まず、制限するアプリを登録', (data.targets.length ? data.targets.map((t) => `<p>・${esc(t.name)}</p>`).join('') : '')
      + '<a class="btn" href="#/target?new=1">＋ 制限するアプリを追加</a>')
    + `<button class="btn primary big" ${data.targets.length ? '' : 'disabled'} ${act(() => { mutate((d) => { d.settings.hasCompletedOnboarding = true; }); go('#/setup'); })}>はじめる（次にショートカットを設定）</button>`;
  return page('Focus Guard', html);
}

// MARK: - 描画

let lastPath = null;

function render() {
  data = S.load();
  mutate((d) => { E.closeExpired(d); E.prune(d); });
  const { path, params } = route();
  if (lastPath === '/request' && path !== '/request') leaveFlow();
  if (lastPath === '/target' && path !== '/target') draft = null;
  if (path !== '/emergency') emergencyDone = null;
  lastPath = path;
  actions = [];

  const free = ['/gate', '/target', '/emergency', '/setup', '/closed'];
  let html;
  if (!data.settings.hasCompletedOnboarding && !free.includes(path)) html = onboardingPage();
  else if (path === '/gate') html = gatePage(params);
  else if (path === '/closed') html = closedPage();
  else if (path === '/request') html = requestPage();
  else if (path === '/emergency') html = emergencyPage(params);
  else if (path === '/report') html = reportPage();
  else if (path === '/history') html = historyPage();
  else if (path === '/settings') html = settingsPage();
  else if (path === '/target') html = targetPage(params);
  else if (path === '/setup') html = setupPage();
  else html = homePage();
  root.innerHTML = html;
}

// クリック・入力をまとめて受け取る
root.addEventListener('click', (e) => {
  const el = e.target.closest('[data-act]');
  if (!el) return;
  if (el.tagName !== 'INPUT' && el.tagName !== 'A') e.preventDefault();
  if (route().path === '/target' && el.dataset.act) syncDraftInputs();
  actions[+el.dataset.act]?.();
});

root.addEventListener('change', (e) => {
  const el = e.target;
  if (el.dataset.setting) {
    const k = el.dataset.setting;
    const v = el.type === 'number' || k === 'emergencyDefaultMinutes' ? Math.max(1, Number(el.value) || 1) : el.value;
    mutate((d) => { d.settings[k] = v; });
    render();
  } else if (el.id === 'preset' && draft) {
    syncDraftInputs();
    const p = APP_PRESETS.find((x) => x.key === el.value);
    if (p) { draft.appKey = p.key; draft.scheme = p.scheme; if (!draft.name.trim()) draft.name = p.name; }
    else if (el.value === 'custom') { draft.appKey = draft.appKey && !APP_PRESETS.some((x) => x.key === draft.appKey) ? draft.appKey : 'custom'; draft.scheme = ''; }
    else draft.appKey = '';
    render();
  } else if (el.id === 'import' && el.files?.[0]) {
    el.files[0].text().then((txt) => {
      try { S.importJSON(txt); toast('戻しました'); render(); } catch (err) { alert(err.message); }
    });
  }
});

// 入力中の文字を申請データへ（再描画しても消えないように）
root.addEventListener('input', (e) => {
  if (!flow) return;
  if (e.target.id === 'purpose') flow.request.purpose = e.target.value;
  if (e.target.id === 'reason') flow.request.reason = e.target.value;
  if (e.target.id === 'answer') flow.answer = e.target.value;
});

window.addEventListener('hashchange', render);
window.addEventListener('storage', render);
document.addEventListener('visibilitychange', () => { if (!document.hidden) render(); });
setInterval(() => { const p = route().path; if (p === '/' || p === '/gate') render(); }, 20000);

render();

if ('serviceWorker' in navigator && location.protocol !== 'file:') {
  navigator.serviceWorker.register('./sw.js').catch(() => {});
}
