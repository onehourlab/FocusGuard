// Focus Guard の審査・類似判定・記録・集計（iOS 版 FocusGuardKit の JavaScript 移植）。
// 端末内（ブラウザ内）だけで動き、通信・外部AIは使わない。同じ入力には必ず同じ結果を返す。
// 日時はミリ秒（Date.now()）、日付は端末のローカル日付 "YYYY-MM-DD"。

// MARK: - 日付

export function dayKey(ms) {
  const d = new Date(ms);
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

export function addDays(key, n) {
  const [y, m, d] = key.split('-').map(Number);
  return dayKey(new Date(y, m - 1, d + n, 12).getTime());
}

export function dayStart(key) {
  const [y, m, d] = key.split('-').map(Number);
  return new Date(y, m - 1, d).getTime();
}

export const shortLabel = (key) => key.slice(5).replace(/^0/, '').replace('-0', '/').replace('-', '/');

const minuteOfDay = (ms) => { const d = new Date(ms); return d.getHours() * 60 + d.getMinutes(); };

const uuid = () => (globalThis.crypto?.randomUUID?.() ?? `id-${Date.now()}-${Math.random().toString(36).slice(2)}`);

// MARK: - 分類・ラベル

export const CATEGORIES = {
  communication: '連絡', information: '調べもの', study: '学習', work: '仕事', shopping: '買い物・予約',
  creation: '投稿・制作', navigation: '移動・地図', entertainment: '娯楽・息抜き', other: 'その他',
};
export const CRITERIA = {
  specificity: '目的の具体性', endCondition: '終了条件', duration: '時間の妥当性', history: '過去の利用との関係', rules: 'あなたのルール',
};
export const VERDICT_LABEL = { approve: '承認', clarify: '再質問', deny: '不承認' };
export const EMERGENCY_KINDS = { call: '電話・連絡', health: '健康・医療', safety: '安全・移動', other: 'その他の緊急' };
export const REFLECTIONS = { necessary: '本当に必要だった', partly: '一部は通常の申請でよかった', notNecessary: '緊急ではなかった' };

export function windowContains(w, ms) {
  const m = minuteOfDay(ms);
  if (w.start === w.end) return false;
  return w.start < w.end ? (m >= w.start && m < w.end) : (m >= w.start || m < w.end);
}
export const clock = (m) => `${Math.floor(m / 60)}:${String(m % 60).padStart(2, '0')}`;
export const windowLabel = (w) => `${clock(w.start)}〜${clock(w.end)}`;

// MARK: - 文章の正規化

export function normalize(text) {
  let t = String(text ?? '').normalize('NFKC').toLowerCase();
  t = t.replace(/[ァ-ヶ]/g, (c) => String.fromCharCode(c.charCodeAt(0) - 0x60)); // カタカナ→ひらがな
  return t.replace(/[\s\p{P}\p{S}]/gu, '');
}

const FILLERS_CMP = ['するため', 'したいため', 'したいので', 'ため', 'します', 'したい', 'するので', 'ので', 'から', 'です', 'ます'];

export function comparable(text, names = []) {
  let t = normalize(text);
  for (const n of names.map(normalize)) if (n.length >= 2) t = t.split(n).join('');
  t = t.replace(/[0-9]+分?/g, '');
  for (const f of FILLERS_CMP) t = t.split(f).join('');
  return t;
}

function bigrams(s) {
  const c = [...s];
  if (c.length < 2) return new Set(c.length ? [c.join('')] : []);
  const out = new Set();
  for (let i = 0; i < c.length - 1; i++) out.add(c[i] + c[i + 1]);
  return out;
}
function jaccard(a, b) {
  if (!a.size && !b.size) return 0;
  let inter = 0;
  for (const x of a) if (b.has(x)) inter++;
  return inter / (a.size + b.size - inter);
}

// MARK: - 概念（何をするか / 何について）

const C = (id, label, kind, words) => ({ id, label, kind, words, weight: kind === 'action' ? 2 : 1 });
export const CONCEPTS = [
  C('reply', '連絡・返信', 'action', ['返信', '返す', '返事', '返答', 'レス', 'リプ', '送信', '送る', '連絡', '既読', '電話', '通話']),
  C('watch', '視聴', 'action', ['視聴', '観る', '観た', '動画を見', '動画をみ', '配信を見', '再生', '見終', '聴く', '聞く']),
  C('browse', '閲覧', 'action', ['閲覧', '眺め', 'タイムライン', 'ストーリー', 'フィード', '投稿を見', '投稿をみ', '見て回']),
  C('search', '調べもの', 'action', ['調べ', '検索', '探す', '探し', '調査']),
  C('check', '確認', 'action', ['確認', 'チェック']),
  C('post', '投稿', 'action', ['投稿する', '投稿し', 'アップ', '載せ', '発信', 'ポスト']),
  C('buy', '購入・予約', 'action', ['買う', '買い', '購入', '注文', '予約', '支払', '申し込', '申込']),
  C('play', '遊び', 'action', ['ゲーム', '遊ぶ', '遊び', 'プレイ']),
  C('navigate', '移動', 'action', ['地図', '道を', '乗換', '乗り換え', '経路']),
  C('friend', '友人', 'topic', ['友達', '友人', '知り合い', 'クラスメイト', '先輩', '後輩', '同級生']),
  C('family', '家族', 'topic', ['家族', '母', '父', '親', '兄', '姉', '弟', '妹', '祖父', '祖母']),
  C('message', 'メッセージ', 'topic', ['dm', 'ダイレクトメッセージ', 'メッセージ', 'チャット', 'トーク', 'ライン']),
  C('video', '動画', 'topic', ['動画', 'ビデオ', '配信', '番組']),
  C('study', '学習', 'topic', ['勉強', '学習', '授業', '講義', '課題', '復習', '予習', '試験', 'テスト', '宿題', 'レポート']),
  C('work', '仕事', 'topic', ['仕事', '業務', '会議', '打ち合わせ', '取引先', '上司', 'バイト', '職場', 'シフト']),
  C('news', 'ニュース・情報', 'topic', ['ニュース', '天気', '情報', '運行']),
  C('relax', '息抜き', 'topic', ['息抜き', '休憩', 'リラックス', '気分転換', '推し', '趣味']),
  C('photo', '写真', 'topic', ['写真', '画像']),
  C('event', '予定', 'topic', ['イベント', '予定', '待ち合わせ', '集合']),
].map((c) => ({ ...c, nwords: c.words.map(normalize) }));

const TOPIC_GROUPS = [new Set(['message', 'video', 'photo']), new Set(['friend', 'family', 'study', 'work', 'news', 'relax', 'event'])];
const BOUNDED_ACTIONS = new Set(['reply', 'search', 'check', 'post', 'buy', 'navigate']);

export function concepts(text) {
  const n = normalize(text);
  return CONCEPTS.filter((c) => c.nwords.some((w) => n.includes(w)));
}
const ids = (cs) => new Set(cs.map((c) => c.id));
const hasAny = (set, list) => list.some((x) => set.has(x));

function typicalRange(cs) {
  const s = ids(cs);
  if (s.has('study') || s.has('work')) return [1, 120];
  if (s.has('watch')) return [3, 90];
  if (s.has('play') || s.has('relax')) return [5, 60];
  if (s.has('buy') || s.has('post')) return [2, 30];
  if (s.has('search') || s.has('browse')) return [1, 20];
  if (s.has('reply') || s.has('check') || s.has('navigate')) return [1, 15];
  return [1, 60];
}

export function categoryFor(cs) {
  const s = ids(cs);
  if (s.has('study')) return 'study';
  if (s.has('work')) return 'work';
  if (s.has('reply') || s.has('message')) return 'communication';
  if (s.has('buy')) return 'shopping';
  if (s.has('post')) return 'creation';
  if (s.has('navigate')) return 'navigation';
  if (s.has('search') || s.has('news') || s.has('check')) return 'information';
  if (hasAny(s, ['watch', 'browse', 'play', 'relax', 'video'])) return 'entertainment';
  return 'other';
}

// MARK: - 類似度

export const SAME_THRESHOLD = 0.6;

export function similarity(a, b, names = []) {
  const ca = concepts(a), cb = concepts(b);
  const ta = comparable(a, names), tb = comparable(b, names);
  const textScore = jaccard(bigrams(ta), bigrams(tb));
  if (ta && ta === tb) return 1;
  if (!ca.length || !cb.length) return textScore;
  const aa = ids(ca.filter((c) => c.kind === 'action'));
  const ab = ids(cb.filter((c) => c.kind === 'action'));
  const sharedActions = [...aa].filter((x) => ab.has(x));
  if (aa.size && ab.size && !sharedActions.length) return Math.min(textScore, 0.3);
  if (aa.size && sharedActions.length) {
    let score = 1;
    const ia = ids(ca), ib = ids(cb);
    for (const g of TOPIC_GROUPS) {
      const ga = [...ia].filter((x) => g.has(x)), gb = [...ib].filter((x) => g.has(x));
      if (ga.length && gb.length && !ga.some((x) => gb.includes(x))) score -= 0.45;
    }
    return Math.max(score * 0.85 + textScore * 0.15, textScore);
  }
  const ib = ids(cb);
  const shared = ca.filter((c) => ib.has(c.id)).reduce((s, c) => s + c.weight, 0);
  const smaller = Math.min(ca.reduce((s, c) => s + c.weight, 0), cb.reduce((s, c) => s + c.weight, 0));
  const conceptScore = smaller > 0 ? shared / smaller : 0;
  return Math.max(conceptScore * 0.85 + textScore * 0.15, textScore);
}

export function bestCluster(purpose, targetId, clusters, names = []) {
  let best = null, bestScore = 0;
  for (const c of clusters) {
    if (c.targetId !== targetId) continue;
    const score = Math.max(...[c.label, ...c.samples].map((s) => similarity(purpose, s, names)));
    if (score >= SAME_THRESHOLD && score > bestScore) { best = c; bestScore = score; }
  }
  return best;
}

export function clusterLabel(purpose) {
  const cs = concepts(purpose);
  const parts = [...cs.filter((c) => c.kind === 'topic').map((c) => c.label).sort(),
    ...cs.filter((c) => c.kind === 'action').map((c) => c.label).sort()];
  if (parts.length) return parts.join('・');
  const t = purpose.trim();
  return t.length > 16 ? t.slice(0, 16) + '…' : t;
}

// MARK: - 文章のヒューリスティクス

const VAGUE = ['なんとなく', '何となく', '暇', 'ひま', '特にない', 'とくにない', '別に', 'べつに', '適当', 'なんでも', '気分', '癖', 'くせ',
  'ついつい', 'なにか', '何か', 'いろいろ', '色々', 'ちょっと見', '見たいから', 'なんか'].map(normalize);
const FILLERS = ['するため', 'したいため', 'ため', 'する', 'したい', '使う', '使いたい', '見る', '見たい', 'ちょっと', '少し', 'アプリ', '開く',
  '分', 'です', 'ます', 'ので', 'から', 'を', 'に', 'で', 'の', 'が', 'は'].map(normalize);
const END_CUES = ['まで', '終わったら', '終わる', '終えたら', 'したら', '済んだら', '済ませ', '次第', '見終', '読み終', '返したら', '送ったら',
  '調べたら', 'わかったら', '分かったら', '確認したら', '決まったら', '閉じる', 'やめる', '1回', '一回', 'だけ返'].map(normalize);
const COUNT = /[0-9一二三四五六七八九十]+(本|件|通|話|回|ページ|章|人|個|問|枚|つ)/;

export const containsVague = (text) => { const n = normalize(text); return VAGUE.some((v) => n.includes(v)); };
export function substanceLength(text, names = []) {
  let t = normalize(text);
  for (const n of names.map(normalize)) if (n.length >= 2) t = t.split(n).join('');
  for (const w of [...VAGUE, ...FILLERS]) t = t.split(w).join('');
  return [...t.replace(/[0-9]+/g, '')].length;
}
export const hasEndCue = (text) => { const n = normalize(text); return END_CUES.some((c) => n.includes(c)) || COUNT.test(n); };

// MARK: - 審査

export const MAX_MINUTES_PER_REQUEST = 180;
const WORST = { pass: 0, warn: 1, fail: 2 };
const answersText = (req) => (req.clarifications ?? []).map((c) => c.answer).join('。');

/** 1回のセッションで1日の累計に数える分数（計測値があれば計測値、なければ許可時間） */
export const countedMinutes = (s) => (s.measuredMinutes != null ? Math.min(s.measuredMinutes, s.grantedMinutes) : s.grantedMinutes);

/**
 * 申請を審査する。data は保存データ全体、now は時刻（ミリ秒）。
 * 返り値: { verdict, checks[5], question, denialReasons, grantedMinutes, suggestedMinutes, category, source }
 */
export function review(request, data, now = Date.now()) {
  const target = data.targets.find((t) => t.id === request.targetId);
  if (!target) throw new Error('unknown target');
  const settings = data.settings;
  const names = [target.name];
  const ans = answersText(request);
  const purposeText = request.purpose + '。' + ans;
  const allText = request.purpose + '。' + request.reason + '。' + ans;
  const cs = concepts(purposeText);
  const category = categoryFor(cs);
  const hasAnswers = (request.clarifications ?? []).length > 0;
  const answersOK = hasAnswers && substanceLength(ans, names) >= 4 && !containsVague(ans);

  const specificity = checkSpecificity(request, cs, names, ans);
  const end = checkEndCondition(allText, cs, category);
  const duration = checkDuration(request, cs, answersOK);
  const history = checkHistory(request, data, target, names, now, hasAnswers, answersOK);
  const rules = checkRules(request, data, target, category, hasAnswers, names, now);

  const ruleStatus = rules.reduce((w, r) => (WORST[r.status] > WORST[w] ? r.status : w), 'pass');
  const ruleCheck = {
    criterion: 'rules', status: ruleStatus,
    message: rules.length ? rules.map((r) => r.message).join(' ') : ruleSummary(settings, target),
    question: rules.find((r) => r.status === 'fail' && !r.isHard)?.question ?? null,
  };
  const checks = [specificity, end, duration, history, ruleCheck];
  const base = { checks, category, source: 'rules', question: null, denialReasons: [], grantedMinutes: 0, suggestedMinutes: null };

  const hard = rules.filter((r) => r.isHard && r.status === 'fail');
  if (hard.length) {
    const sugg = hard.map((r) => r.suggestedMinutes).filter((m) => m > 0);
    return { ...base, verdict: 'deny', denialReasons: hard.map((r) => r.message), suggestedMinutes: sugg.length ? Math.min(...sugg) : null };
  }
  const failing = [ruleCheck, history, specificity, end, duration].filter((c) => c.status === 'fail');
  if (failing.length) {
    const n = (request.clarifications ?? []).length;
    if (n < settings.maxClarifications) {
      return { ...base, verdict: 'clarify', question: failing.map((c) => c.question).find(Boolean) ?? 'もう少し具体的に教えてください。' };
    }
    const reasons = failing.map((c) => `${CRITERIA[c.criterion]}：${c.message}`);
    reasons.push(`追加の説明を${n}回受けても確認できなかったため、通常の解除は行いません。緊急の場合は緊急解除を使えます。`);
    return { ...base, verdict: 'deny', denialReasons: reasons };
  }
  return { ...base, verdict: 'approve', grantedMinutes: request.minutes };
}

function checkSpecificity(req, cs, names, ans) {
  const text = req.purpose + '。' + ans;
  const substance = substanceLength(text, names);
  const topics = cs.filter((c) => c.kind === 'topic');
  const vagueOnly = containsVague(req.purpose) && !topics.length && substance < 6;
  const reasonWeak = substanceLength(req.reason + '。' + ans, names) < 2 || (containsVague(req.reason) && !(req.clarifications ?? []).length);
  let status;
  if (vagueOnly || substance < 3) status = 'fail';
  else if (!cs.length && substance < 6) status = 'fail';
  else if (!topics.length && substance < 5) status = 'warn';
  else status = 'pass';
  if (status !== 'fail' && reasonWeak) {
    return { criterion: 'specificity', status: 'fail', message: '「なぜ今使う必要があるのか」が読み取れません。',
      question: 'なぜ今使う必要があるのか教えてください（例：相手が返事を待っている、今日が締め切り）。' };
  }
  if (status === 'pass') return { criterion: 'specificity', status, message: '何をするのかが具体的です。', question: null };
  if (status === 'warn') return { criterion: 'specificity', status, message: '目的は読み取れますが、対象（誰に・何を）がもう少しあると明確です。', question: null };
  return { criterion: 'specificity', status, message: '何をするのかがはっきりしません。',
    question: `「${req.purpose}」で具体的に何をしますか？　誰に・何を・どうするのかを教えてください。` };
}

function checkEndCondition(allText, cs, category) {
  const s = ids(cs);
  const bounded = [...s].some((x) => BOUNDED_ACTIONS.has(x));
  const cue = hasEndCue(allText);
  const openEnded = category === 'entertainment' || hasAny(s, ['watch', 'browse', 'play']);
  const status = cue || bounded ? 'pass' : (openEnded ? 'fail' : 'warn');
  if (status === 'pass') return { criterion: 'endCondition', status, message: cue ? '終わりにするタイミングが書かれています。' : '用事が済めば終わる内容です。', question: null };
  if (status === 'warn') return { criterion: 'endCondition', status, message: '終わりのタイミングがやや曖昧です。時間が来たら制限に戻ります。', question: null };
  return { criterion: 'endCondition', status, message: 'どこで終わりにするのかが書かれていません。',
    question: '何をしたら終わりにしますか？（例：「2本見たら終わり」「返信を送ったら閉じる」）' };
}

function checkDuration(req, cs, answersOK) {
  const upper = typicalRange(cs)[1];
  const label = clusterLabel(req.purpose);
  if (req.minutes <= upper) return { criterion: 'duration', status: 'pass', message: `${req.minutes}分は目的に対して妥当な範囲です（目安 ${upper}分以内）。`, question: null };
  if (req.minutes <= upper * 2 || answersOK) return { criterion: 'duration', status: 'warn', message: `${req.minutes}分は目安（${upper}分）より長めです。`, question: null };
  return { criterion: 'duration', status: 'fail', message: `${req.minutes}分は目安（${upper}分）の2倍を超えています。`,
    question: `「${label}」に${req.minutes}分は長めに見えます。その時間が必要な理由か、短くできるかを教えてください。` };
}

function checkHistory(req, data, target, names, now, hasAnswers, answersOK) {
  const today = dayKey(now);
  const others = data.records.filter((r) => r.request.targetId === req.targetId && r.request.id !== req.id);
  const lookback = addDays(today, -14);
  const mine = comparable(req.purpose + req.reason, names);
  const duplicate = !!mine && others.some((r) => r.day >= lookback && r.status !== 'abandoned'
    && comparable(r.request.purpose + r.request.reason, names) === mine);
  const cluster = bestCluster(req.purpose, req.targetId, data.clusters, names);
  const sameToday = cluster ? others.filter((r) => r.day === today && r.status === 'approved' && r.clusterId === cluster.id) : [];
  const sids = new Set(sameToday.map((r) => r.sessionId).filter(Boolean));
  const sameSessions = data.sessions.filter((s) => sids.has(s.id));
  const minutesToday = sameSessions.reduce((a, s) => a + countedMinutes(s), 0);
  const recentUsedUp = sameSessions.find((s) => s.endReason === 'usageLimitReached' && now - (s.endedAt ?? s.wallClockEnd) < 10 * 60000);
  const extensionCount = req.extendsSessionId ? others.filter((r) => r.request.extendsSessionId === req.extendsSessionId && r.status === 'approved').length : 0;

  let issue = null;
  if (duplicate) issue = ['以前の申請とまったく同じ文章です。', '以前の申請とまったく同じ文章です。今回の用事が前回とどう違うのかを具体的に教えてください。'];
  else if (extensionCount >= 2) issue = [`この利用はすでに${extensionCount}回延長しています。`, `この利用はすでに${extensionCount}回延長しています。あと何が残っていて、それはいつ終わりますか？`];
  else if (sameToday.length >= data.settings.repeatQuestionThreshold) issue = [`本日すでに同じ目的で${sameToday.length}回（計${minutesToday}分）利用しています。`, `本日はすでに同じ目的で${sameToday.length}回利用しています。今回はどのような新しい用事がありますか？`];
  else if (recentUsedUp) {
    const mins = Math.max(1, Math.floor((now - (recentUsedUp.endedAt ?? recentUsedUp.wallClockEnd)) / 60000));
    issue = [`${mins}分前に同じ目的の許可時間を使い切ったばかりです。`, `${mins}分前にも同じ目的で利用し、時間を使い切りました。前回で済まなかったことは何ですか？`];
  }
  if (issue) {
    if (hasAnswers && answersOK) return { criterion: 'history', status: 'warn', message: issue[0] + '新しい用事の説明がありました。', question: null };
    if (hasAnswers) return { criterion: 'history', status: 'fail', message: issue[0] + '追加の説明から新しい用事が読み取れませんでした。', question: '前回までと違う、今回だけの用事を具体的に書いてください。' };
    return { criterion: 'history', status: 'fail', message: issue[0], question: issue[1] };
  }
  if (sameToday.length) return { criterion: 'history', status: 'pass', message: `本日この目的で${sameToday.length + 1}回目です（これまで計${minutesToday}分）。`, question: null };
  return { criterion: 'history', status: 'pass', message: '過去の利用と矛盾する点はありません。', question: null };
}

function checkRules(req, data, target, category, hasAnswers, names, now) {
  const out = [];
  const F = (message, extra = {}) => out.push({ status: 'fail', message, question: null, isHard: true, suggestedMinutes: null, ...extra });
  if (req.minutes < 1) F('時間は1分以上で申請してください。', { suggestedMinutes: 1 });
  if (req.minutes > MAX_MINUTES_PER_REQUEST) F(`1回の申請は最大${MAX_MINUTES_PER_REQUEST}分です。`, { suggestedMinutes: MAX_MINUTES_PER_REQUEST });
  if (target.maxMinutesPerSession != null && req.minutes > target.maxMinutesPerSession) {
    F(`「${target.name}」は1回${target.maxMinutesPerSession}分までのルールです。`, { suggestedMinutes: target.maxMinutesPerSession });
  }
  for (const w of target.restrictedWindows ?? []) {
    if (!windowContains(w, now) || w.allowed.includes(category)) continue;
    const allowed = Object.keys(CATEGORIES).filter((c) => w.allowed.includes(c)).map((c) => CATEGORIES[c]).join('・') || 'なし';
    const msg = `${windowLabel(w)}は「${allowed}」の目的だけに使うルールです（今回は「${CATEGORIES[category]}」と判定）。`;
    F(msg, { isHard: hasAnswers, question: hasAnswers ? null : `${msg}今回の用事がそのどれかに当たる場合は、どれに当たるのか説明してください。` });
  }
  if (data.settings.limitMode === 'reviewWithDailyCaps') {
    const today = dayKey(now);
    const todaySessions = data.sessions.filter((s) => !s.isEmergency && s.targetId === target.id && dayKey(s.startedAt) === today);
    if (target.dailyCapMinutes != null) {
      const cap = target.dailyCapMinutes;
      const remaining = cap - todaySessions.reduce((a, s) => a + countedMinutes(s), 0);
      if (remaining <= 0) F(`本日の「${target.name}」の上限${cap}分に達しています。`);
      else if (req.minutes > remaining) F(`本日の「${target.name}」は残り${remaining}分です（上限${cap}分）。`, { suggestedMinutes: remaining });
    }
    const byId = new Map(data.records.map((r) => [r.request.id, r.request]));
    for (const cap of target.purposeCaps ?? []) {
      if (similarity(req.purpose, cap.label, names) < SAME_THRESHOLD) continue;
      const used = todaySessions.filter((s) => {
        const r = byId.get(s.requestId);
        return r && similarity(r.purpose, cap.label, names) >= SAME_THRESHOLD;
      }).reduce((a, s) => a + countedMinutes(s), 0);
      const remaining = cap.maxMinutesPerDay - used;
      if (remaining <= 0) F(`「${cap.label}」の本日の上限${cap.maxMinutesPerDay}分に達しています。`);
      else if (req.minutes > remaining) F(`「${cap.label}」は本日残り${remaining}分です。`, { suggestedMinutes: remaining });
    }
  }
  return out;
}

function ruleSummary(settings, target) {
  const parts = [];
  if (settings.limitMode === 'reviewWithDailyCaps' && target.dailyCapMinutes != null) parts.push(`1日の上限${target.dailyCapMinutes}分の範囲内`);
  if (target.maxMinutesPerSession != null) parts.push(`1回${target.maxMinutesPerSession}分以内`);
  if ((target.restrictedWindows ?? []).length) parts.push('時間帯ルールに適合');
  return parts.length ? parts.join('・') + 'です。' : '設定したルールに反する点はありません。';
}

// MARK: - 保存データと記録

export function emptyData() {
  return {
    schemaVersion: 1,
    settings: { limitMode: 'reviewOnly', dailyGoalMinutes: null, baselineDailyMinutes: null, repeatQuestionThreshold: 3,
      maxClarifications: 2, emergencyDefaultMinutes: 15, hasCompletedOnboarding: false },
    targets: [], records: [], sessions: [], emergencies: [], clusters: [], shieldEvents: [],
  };
}

export function newTarget(name, extra = {}) {
  return { id: uuid(), name, appKey: '', dailyCapMinutes: null, purposeCaps: [], maxMinutesPerSession: null,
    restrictedWindows: [], personalRules: [], ...extra };
}

export function newRequest(targetId, purpose, reason, minutes, createdAt = Date.now(), extra = {}) {
  return { id: uuid(), targetId, purpose, reason, minutes, createdAt, clarifications: [], extendsSessionId: null, ...extra };
}

/** Web 版は使用時間を測れないため、解除期間は許可した時間そのもの（経過時間）で終わる */
export function startSession(data, { targetId, requestId = null, minutes, emergency = false, now = Date.now() }) {
  const s = { id: uuid(), targetId, requestId, isEmergency: emergency, startedAt: now, grantedMinutes: minutes,
    wallClockEnd: now + minutes * 60000, endedAt: null, endReason: null, measuredMinutes: null };
  data.sessions.push(s);
  return s;
}

export function endSession(data, id, reason, now = Date.now()) {
  const s = data.sessions.find((x) => x.id === id);
  if (!s || s.endedAt != null) return;
  s.endedAt = Math.min(now, s.wallClockEnd);
  s.endReason = reason;
  // 経過時間で数える（早めに終えた場合はその分だけ）
  s.measuredMinutes = Math.max(0, Math.round((s.endedAt - s.startedAt) / 60000));
}

export function closeExpired(data, now = Date.now()) {
  const closed = [];
  for (const s of data.sessions) {
    if (s.endedAt == null && now >= s.wallClockEnd) {
      s.endedAt = s.wallClockEnd; s.endReason = 'usageLimitReached'; s.measuredMinutes = s.grantedMinutes;
      closed.push(s);
    }
  }
  return closed;
}

export const isActive = (s, now = Date.now()) => s.endedAt == null && now < s.wallClockEnd;
export const activeSessions = (data, now = Date.now()) => data.sessions.filter((s) => isActive(s, now));

function assignCluster(data, request) {
  const names = [data.targets.find((t) => t.id === request.targetId)?.name ?? ''];
  const c = bestCluster(request.purpose, request.targetId, data.clusters, names);
  if (c) {
    if (!c.samples.includes(request.purpose)) { c.samples.push(request.purpose); if (c.samples.length > 12) c.samples.shift(); }
    return c.id;
  }
  const nc = { id: uuid(), targetId: request.targetId, label: clusterLabel(request.purpose), samples: [request.purpose] };
  data.clusters.push(nc);
  return nc.id;
}

export function recordReview(data, request, result, now = Date.now()) {
  let rec = data.records.find((r) => r.request.id === request.id);
  if (!rec) { rec = { request, day: dayKey(request.createdAt), status: 'clarifying', rounds: [], lastResult: null, clusterId: null, category: null, abandonedAt: null, sessionId: null }; data.records.push(rec); }
  rec.request = request;
  rec.rounds.push(result.verdict);
  rec.lastResult = result;
  rec.category = result.category;
  rec.abandonedAt = null;
  if (result.verdict === 'approve') {
    rec.status = 'approved';
    rec.clusterId = assignCluster(data, request);
    if (request.extendsSessionId) endSession(data, request.extendsSessionId, 'extended', now);
    rec.sessionId = startSession(data, { targetId: request.targetId, requestId: request.id, minutes: result.grantedMinutes, now }).id;
  } else {
    rec.status = result.verdict === 'clarify' ? 'clarifying' : 'denied';
  }
  return rec;
}

export function recordAbandon(data, request, stage) {
  let rec = data.records.find((r) => r.request.id === request.id);
  if (rec && (rec.status === 'approved' || rec.status === 'denied')) return;
  if (!rec) { rec = { request, day: dayKey(request.createdAt), status: 'abandoned', rounds: [], lastResult: null, clusterId: null, category: null, abandonedAt: stage, sessionId: null }; data.records.push(rec); }
  rec.request = request;
  rec.status = 'abandoned';
  rec.abandonedAt = stage;
}

export function recordEmergency(data, { kind, targetId = null, minutes, now = Date.now() }) {
  const session = startSession(data, { targetId, minutes, emergency: true, now });
  const rec = { id: uuid(), date: now, day: dayKey(now), kind, targetId, minutes, sessionId: session.id, reflection: null };
  data.emergencies.push(rec);
  return { record: rec, session };
}

/** ショートカットからの「アプリを開いた」記録（申請へ進んだ／閉じた） */
export function recordShieldEvent(data, kind, targetId, now = Date.now()) {
  data.shieldEvents.push({ date: now, day: dayKey(now), kind, targetId });
}

export function prune(data, now = Date.now()) {
  const cutoff = addDays(dayKey(now), -400);
  data.records = data.records.filter((r) => r.day >= cutoff);
  data.emergencies = data.emergencies.filter((e) => e.day >= cutoff);
  data.shieldEvents = data.shieldEvents.filter((e) => e.day >= cutoff);
  data.sessions = data.sessions.filter((s) => s.endedAt == null || dayKey(s.startedAt) >= cutoff);
}

// MARK: - 集計（データが無いものは null。推測で埋めない）

export function summary(data, day) {
  const recs = data.records.filter((r) => r.day === day);
  const sessions = data.sessions.filter((s) => dayKey(s.startedAt) === day);
  const normal = sessions.filter((s) => !s.isEmergency);
  const measured = normal.filter((s) => s.measuredMinutes != null);
  const ems = data.emergencies.filter((e) => e.day === day);
  const groups = new Map();
  for (const r of recs) if (r.status === 'approved' && r.clusterId) (groups.get(r.clusterId) ?? groups.set(r.clusterId, []).get(r.clusterId)).push(r);
  const repeated = [];
  for (const [cid, g] of groups) {
    if (g.length < 2) continue;
    const sids = new Set(g.map((r) => r.sessionId));
    repeated.push({ clusterId: cid, targetId: g[0].request.targetId, label: data.clusters.find((c) => c.id === cid)?.label ?? g[0].request.purpose,
      count: g.length, minutes: normal.filter((s) => sids.has(s.id)).reduce((a, s) => a + countedMinutes(s), 0) });
  }
  repeated.sort((a, b) => b.count - a.count || b.minutes - a.minutes);
  const rounds = recs.flatMap((r) => r.rounds);
  const out = {
    day,
    requestCount: recs.filter((r) => r.rounds.length).length,
    approvedRounds: rounds.filter((v) => v === 'approve').length,
    clarifyRounds: rounds.filter((v) => v === 'clarify').length,
    deniedRounds: rounds.filter((v) => v === 'deny').length,
    abandonedCount: recs.filter((r) => r.status === 'abandoned').length,
    shieldClosedCount: data.shieldEvents.filter((e) => e.day === day && e.kind === 'closed').length,
    shieldOpenCount: data.shieldEvents.filter((e) => e.day === day && e.kind === 'opened').length,
    emergencyCount: ems.length,
    emergencyMinutes: ems.reduce((a, e) => a + e.minutes, 0),
    grantedMinutes: normal.reduce((a, s) => a + s.grantedMinutes, 0),
    measuredMinutes: measured.length ? measured.reduce((a, s) => a + s.measuredMinutes, 0) : null,
    countedMinutes: normal.reduce((a, s) => a + countedMinutes(s), 0),
    repeated,
  };
  out.hasData = out.requestCount > 0 || out.emergencyCount > 0 || out.shieldOpenCount > 0 || out.grantedMinutes > 0 || out.abandonedCount > 0;
  return out;
}

export const week = (data, endDay, count = 7) => Array.from({ length: count }, (_, i) => summary(data, addDays(endDay, i - count + 1)));

export function baseline(data, beforeDay, lookback = 7) {
  if (data.settings.baselineDailyMinutes != null) return { minutes: data.settings.baselineDailyMinutes, source: '設定した基準値' };
  const past = Array.from({ length: lookback }, (_, i) => summary(data, addDays(beforeDay, -(i + 1)))).filter((s) => s.hasData);
  if (!past.length) return null;
  return { minutes: Math.floor(past.reduce((a, s) => a + s.countedMinutes, 0) / past.length), source: `過去${past.length}日の平均` };
}

export function goalStatus(s, settings) {
  if (settings.dailyGoalMinutes == null) return null;
  return { achieved: s.countedMinutes <= settings.dailyGoalMinutes, used: s.countedMinutes, goal: settings.dailyGoalMinutes };
}

export function emergenciesNeedingReflection(data, today) {
  const from = addDays(today, -7);
  return data.emergencies.filter((e) => e.day < today && e.day >= from && !e.reflection).sort((a, b) => b.date - a.date);
}

export function frequentEmergencyNotice(data, today) {
  const from = addDays(today, -6);
  const n = data.emergencies.filter((e) => e.day >= from && e.day <= today).length;
  return n >= 3 ? `この7日間で緊急解除を${n}回使いました。使った場面を振り返り、必要なアプリは制限の対象から外すことも検討してください。` : null;
}
