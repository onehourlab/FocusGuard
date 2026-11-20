// iOS 版（FocusGuardKit）のテストと同じ例で、Web 版の審査・記録・集計を確かめる。
// 実行: cd web && npm test
import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as E from '../src/engine.js';

const at = (hour, minute = 0, day = 20) => new Date(2026, 10, day, hour, minute).getTime();
const make = (target = E.newTarget('Instagram'), settings = {}) => {
  const d = E.emptyData();
  d.targets.push(target);
  Object.assign(d.settings, settings);
  return d;
};
const req = (d, purpose, reason, minutes, time, extra) => E.newRequest(d.targets[0].id, purpose, reason, minutes, time, extra);
const why = (r) => r.checks.map((c) => `${c.criterion}:${c.status} ${c.message}`).join('\n');

test('具体的な連絡は承認', () => {
  const d = make();
  const r = E.review(req(d, '友達からのDMに返信する', '友達が返事を待っているから', 5, at(12)), d, at(12));
  assert.equal(r.verdict, 'approve', why(r));
  assert.equal(r.grantedMinutes, 5);
  assert.equal(r.category, 'communication');
  assert.equal(r.checks.length, 5);
});

test('あいまいな目的は拒否ではなく質問', () => {
  const d = make();
  const r = E.review(req(d, 'なんとなく', '暇だから', 10, at(12)), d, at(12));
  assert.equal(r.verdict, 'clarify');
  assert.ok(r.question);
});

test('娯楽という理由だけでは不承認にしない', () => {
  const d = make(E.newTarget('YouTube'));
  const r1 = E.review(req(d, 'YouTubeでゲーム実況の動画を見る', '休憩時間なので息抜きしたい', 20, at(15)), d, at(15));
  assert.equal(r1.verdict, 'clarify');
  const r2 = E.review(req(d, 'YouTubeでゲーム実況の動画を2本見たら終わり', '休憩時間なので息抜きしたい', 20, at(15)), d, at(15));
  assert.equal(r2.verdict, 'approve', why(r2));
  assert.equal(r2.category, 'entertainment');
});

test('再質問に答えると承認', () => {
  const d = make(E.newTarget('YouTube'));
  const q = req(d, 'YouTubeでゲーム実況の動画を見る', '休憩時間なので息抜きしたい', 20, at(15));
  const r1 = E.review(q, d, at(15));
  q.clarifications.push({ question: r1.question, answer: '新作の動画を1本見たら閉じます' });
  assert.equal(E.review(q, d, at(15)).verdict, 'approve');
});

test('再質問の上限後もあいまいなら不承認（理由つき）', () => {
  const d = make();
  const q = req(d, 'なんとなく', '暇だから', 10, at(12));
  q.clarifications = [{ question: 'q1', answer: 'なんとなく' }, { question: 'q2', answer: '暇' }];
  const r = E.review(q, d, at(12));
  assert.equal(r.verdict, 'deny');
  assert.ok(r.denialReasons.length > 0);
});

test('長すぎる時間は理由を質問', () => {
  const d = make();
  const r = E.review(req(d, '友達からのDMに返信する', '返事を待たせているので', 60, at(12)), d, at(12));
  assert.equal(r.verdict, 'clarify');
  assert.equal(r.checks.find((c) => c.criterion === 'duration').status, 'fail');
});

test('言い回しが違う同じ目的をまとめ、4回目に質問、答えれば承認', () => {
  const d = make();
  const past = [['友達からのDMに返信するため', '友達が返事を待っているから'], ['Instagramでメッセージを返すため', '相手から質問が来たので'], ['友達に返信するため', '既読をつけたままなので']];
  past.forEach(([p, w], i) => {
    const q = req(d, p, w, 5, at(9 + i));
    const r = E.review(q, d, at(9 + i));
    assert.equal(r.verdict, 'approve', p + '\n' + why(r));
    E.recordReview(d, q, r, at(9 + i));
  });
  assert.equal(new Set(d.records.map((r) => r.clusterId)).size, 1);
  const fourth = req(d, '友達に返信', '新しくメッセージが届いたので', 5, at(13));
  const r4 = E.review(fourth, d, at(13));
  assert.equal(r4.verdict, 'clarify');
  assert.equal(r4.question, '本日はすでに同じ目的で3回利用しています。今回はどのような新しい用事がありますか？');
  fourth.clarifications.push({ question: r4.question, answer: 'サークルの集合場所を部長に伝える必要がある' });
  assert.equal(E.review(fourth, d, at(13)).verdict, 'approve');
});

test('日付が変わると回数はリセット、記録は残る', () => {
  const d = make();
  ['返事を待たせているので', '質問が来たので', '予定を聞かれたので'].forEach((w, i) => {
    const q = req(d, '友達からのDMに返信する', w, 5, at(9 + i));
    E.recordReview(d, q, E.review(q, d, at(9 + i)), at(9 + i));
  });
  const t = req(d, '友達からのDMに返信する', '朝に連絡が来ていたので', 5, at(9, 0, 21));
  assert.equal(E.review(t, d, at(9, 0, 21)).verdict, 'approve');
  assert.equal(d.records.length, 3);
});

test('コピーした文章は質問', () => {
  const d = make();
  const a = req(d, '友達からのDMに返信する', '友達が返事を待っているから', 5, at(9));
  E.recordReview(d, a, E.review(a, d, at(9)), at(9));
  const r = E.review(req(d, '友達からのDMに返信する', '友達が返事を待っているから', 5, at(20)), d, at(20));
  assert.equal(r.verdict, 'clarify');
  assert.match(r.question, /同じ文章/);
});

test('1日の上限：残り時間を提案して不承認', () => {
  const d = make(E.newTarget('YouTube', { dailyCapMinutes: 30 }), { limitMode: 'reviewWithDailyCaps' });
  const a = req(d, '授業の動画を1本見る', '明日の小テストの範囲だから', 25, at(10));
  const r1 = E.review(a, d, at(10));
  assert.equal(r1.verdict, 'approve', why(r1));
  E.recordReview(d, a, r1, at(10));
  const r2 = E.review(req(d, '別の授業の動画を1本見る', '復習が残っているので', 10, at(11)), d, at(11));
  assert.equal(r2.verdict, 'deny');
  assert.equal(r2.suggestedMinutes, 5);
});

test('審査だけのモードでは1日の上限を使わない', () => {
  const d = make(E.newTarget('YouTube', { dailyCapMinutes: 1 }));
  assert.equal(E.review(req(d, '授業の動画を1本見る', '明日の小テストの範囲だから', 25, at(10)), d, at(10)).verdict, 'approve');
});

test('目的ごとの上限', () => {
  const d = make(E.newTarget('Instagram', { dailyCapMinutes: 30, purposeCaps: [{ id: 'c', label: 'DM返信', maxMinutesPerDay: 10 }] }), { limitMode: 'reviewWithDailyCaps' });
  const a = req(d, '友達からのDMに返信する', '返事を待たせているので', 8, at(10));
  E.recordReview(d, a, E.review(a, d, at(10)), at(10));
  const r = E.review(req(d, '先輩にメッセージを返す', '集合時間を聞かれたので', 5, at(11)), d, at(11));
  assert.equal(r.verdict, 'deny');
  assert.equal(r.suggestedMinutes, 2);
});

test('1回の上限', () => {
  const d = make(E.newTarget('X', { maxMinutesPerSession: 10 }));
  const r = E.review(req(d, '電車の運行情報を調べる', '帰りの電車が止まっているので', 15, at(18)), d, at(18));
  assert.equal(r.verdict, 'deny');
  assert.equal(r.suggestedMinutes, 10);
});

test('時間帯ルール：まず質問、説明後も当てはまらなければ不承認', () => {
  const d = make(E.newTarget('YouTube', { restrictedWindows: [{ id: 'w', start: 22 * 60, end: 7 * 60, allowed: ['study', 'communication'] }] }));
  const q = req(d, '好きな配信者の動画を1本見たら終わり', '新作が出たので', 15, at(23));
  const r1 = E.review(q, d, at(23));
  assert.equal(r1.verdict, 'clarify');
  q.clarifications.push({ question: r1.question, answer: '寝る前の楽しみにしたい' });
  assert.equal(E.review(q, d, at(23)).verdict, 'deny');
  assert.equal(E.review(req(d, '好きな配信者の動画を1本見たら終わり', '新作が出たので', 15, at(17)), d, at(17)).verdict, 'approve');
});

test('類似判定', () => {
  const pairs = [['友達からのDMに返信するため5分', 'Instagramでメッセージを返すため5分'], ['友達からのDMに返信するため5分', '友達に返信するため5分'], ['Instagramでメッセージを返すため5分', '友達に返信するため5分']];
  for (const [a, b] of pairs) assert.ok(E.similarity(a, b, ['Instagram']) >= E.SAME_THRESHOLD, `${a} / ${b}`);
  assert.ok(E.similarity('友達のDMに返信する', '授業の動画を見る') < E.SAME_THRESHOLD);
  assert.ok(E.similarity('ストーリーを眺める', 'コンサートのチケットを予約する') < E.SAME_THRESHOLD);
  assert.ok(E.similarity('友達にDM返信', '家族にDM返信') < E.SAME_THRESHOLD);
  assert.equal(E.normalize('ＤＭ　メッセージ！'), E.normalize('dmめっせーじ'));
});

test('緊急解除は何回でも使え、翌日に振り返りを促す', () => {
  const d = make(E.newTarget('LINE'));
  for (let i = 0; i < 5; i++) assert.ok(E.recordEmergency(d, { kind: 'call', minutes: 15, now: at(8 + i) }).session.isEmergency);
  assert.equal(d.emergencies.length, 5);
  const today = E.dayKey(at(12));
  assert.equal(E.emergenciesNeedingReflection(d, today).length, 0);
  assert.equal(E.emergenciesNeedingReflection(d, E.addDays(today, 1)).length, 5);
  assert.ok(E.frequentEmergencyNotice(d, E.addDays(today, 1)));
  const s = E.summary(d, today);
  assert.equal(s.emergencyCount, 5);
  assert.equal(s.grantedMinutes, 0);
});

test('データが無いときは数字を作らない', () => {
  const d = E.emptyData();
  const today = E.dayKey(at(12));
  assert.equal(E.baseline(d, today), null);
  const s = E.summary(d, today);
  assert.equal(s.hasData, false);
  assert.equal(s.measuredMinutes, null);
  assert.equal(E.goalStatus(s, d.settings), null);
});

test('取りやめの記録と、承認後は取りやめにならないこと', () => {
  const d = make(E.newTarget('TikTok'));
  E.recordAbandon(d, req(d, 'おすすめを見る', '', 10, at(22)), 'beforeSubmit');
  const b = req(d, '友達に返信', '待たせている', 5, at(22));
  E.recordReview(d, b, { verdict: 'approve', grantedMinutes: 5, category: 'communication', checks: [] }, at(22));
  E.recordAbandon(d, b, 'duringClarification');
  const s = E.summary(d, E.dayKey(at(22)));
  assert.equal(s.abandonedCount, 1);
  assert.equal(s.requestCount, 1);
});

test('解除は許可時間で終わり、早く終えた分は短く数える', () => {
  const d = make(E.newTarget('X'));
  const s = E.startSession(d, { targetId: d.targets[0].id, minutes: 10, now: at(9) });
  assert.equal(E.closeExpired(d, at(9, 5)).length, 0);
  E.endSession(d, s.id, 'endedByUser', at(9, 4));
  assert.equal(s.measuredMinutes, 4);
  const t = E.startSession(d, { targetId: d.targets[0].id, minutes: 5, now: at(10) });
  assert.equal(E.closeExpired(d, at(10, 6)).length, 1);
  assert.equal(t.measuredMinutes, 5);
});
