#!/usr/bin/env node
// ============================================================================
// [운영] [PROD] 시험 자료 첨부 파일 정리 도구 (2026-11-23)
//   다니엘님 "첨부 파일도 정리해" → "정리 도구 만들어줘"
//
// 사용법 (터미널, 이 폴더에서):
//   node tools/prod-delete-test-files.mjs
//   1) 지울 파일 목록 붙여 넣기 — supabase/20261123_jh_prod_test_files.sql 의 ⑤ 결과 '지울_파일_목록' 칸 그대로
//   2) 운영 service_role 키 입력 — 화면에 보이지 않고, 어디에도 저장하지 않습니다
//   3) 보관함에 실제로 있는지 확인한 목록을 보여 줍니다
//   4) '삭제' 라고 입력해야만 지웁니다 (다른 것을 입력하면 아무것도 지우지 않고 끝)
//   5) 지운 뒤 다시 조회해 남은 파일이 없는지 확인합니다
//
// 안전장치: partner/ · staff/ 로 시작하는 files 칸 파일만, 한 번에 최대 50개, 경로에 .. 금지.
// ============================================================================
import readline from 'node:readline';

const SUPABASE_URL = process.env.KOB_FILES_TEST_URL || 'https://qlrpokxghtvbaxsnwhno.supabase.co';   // 운영 프로젝트 (공개 주소) · 시험 때만 가짜 주소
const BUCKET = 'files';
const MAX = 50;

// 입력 창은 하나만 열고 질문을 차례로 합니다 (붙여 넣은 글이 다음 질문으로 섞이지 않게)
const rl = readline.createInterface({ input: process.stdin, output: process.stdout, terminal: process.stdin.isTTY });
let muted = false;
rl._writeToOutput = function (s) { if (!muted) rl.output.write(s); };
const lines = [];
let waiting = null;
rl.on('line', l => { if (waiting) { const w = waiting; waiting = null; w(l); } else lines.push(l); });
function ask(q, { hidden = false } = {}) {
    process.stdout.write(q);
    muted = hidden;   // 키를 입력할 때는 글자를 화면에 보이지 않게
    return new Promise(resolve => {
        const done = (ans) => { if (hidden) { muted = false; process.stdout.write('\n'); } resolve(String(ans || '').trim()); };
        if (lines.length) done(lines.shift()); else waiting = done;
    });
}
function die(msg) { console.error('\n중지: ' + msg); process.exit(1); }

// 목록 검사 — 붙여 넣은 글이 정해진 모양인지
function parseList(text) {
    let list;
    try { list = JSON.parse(text); } catch (e) { die('목록 모양이 아닙니다. ⑤ 결과의 지울_파일_목록 칸을 그대로 붙여 넣어 주세요. 예: ["partner/c1018/…png", …]'); }
    if (!Array.isArray(list) || !list.length) die('지울 파일이 없습니다.');
    if (list.length > MAX) die(`한 번에 ${MAX}개까지만 지웁니다 (받은 수 ${list.length}).`);
    const bad = list.filter(p => typeof p !== 'string' || !/^(partner|staff)\//.test(p) || p.includes('..') || p.includes('\\'));
    if (bad.length) die('정해진 폴더(partner/ · staff/) 밖의 경로가 있습니다:\n  ' + bad.join('\n  '));
    return Array.from(new Set(list));
}

// 그 경로가 보관함에 있는지 — 폴더 목록에서 파일 이름을 찾습니다
async function exists(key, path) {
    const i = path.lastIndexOf('/');
    const prefix = path.slice(0, i), name = path.slice(i + 1);
    const res = await fetch(`${SUPABASE_URL}/storage/v1/object/list/${BUCKET}`, {
        method: 'POST',
        headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ prefix, search: name, limit: 100, offset: 0 })
    });
    if (res.status === 401 || res.status === 403) die('키가 맞지 않습니다 (운영 service_role 키인지 확인해 주세요).');
    if (!res.ok) die(`보관함 조회 실패 ${res.status}: ${(await res.text()).slice(0, 200)}`);
    const rows = await res.json();
    return Array.isArray(rows) && rows.some(r => r && r.name === name);
}

async function main() {
    console.log('[운영] [PROD] 시험 첨부 파일 정리 — 보관함 ' + BUCKET + ' (' + SUPABASE_URL + ')\n');
    const list = parseList(await ask('1) 지울 파일 목록을 붙여 넣고 Enter: '));
    console.log(`   ${list.length}개 받음`);
    const key = await ask('2) 운영 service_role 키 (화면에 보이지 않음): ', { hidden: true });
    if (!/^(eyJ|sb_secret_)/.test(key)) die('service_role 키 모양이 아닙니다.');

    console.log('\n3) 보관함 확인 중…');
    const found = [], missing = [];
    for (const p of list) (await exists(key, p) ? found : missing).push(p);
    found.forEach(p => console.log('   있음    ' + p));
    missing.forEach(p => console.log('   이미 없음 ' + p));
    if (!found.length) { console.log('\n지울 파일이 보관함에 없습니다. 이미 정리된 상태입니다.'); return; }

    const ok = await ask(`\n4) 위 ${found.length}개를 운영 보관함에서 지웁니다. 되돌릴 수 없습니다. 진행하려면 '삭제' 를 입력: `);
    if (ok !== '삭제') { console.log('아무것도 지우지 않고 끝냅니다.'); return; }

    const res = await fetch(`${SUPABASE_URL}/storage/v1/object/${BUCKET}`, {
        method: 'DELETE',
        headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ prefixes: found })
    });
    if (!res.ok) die(`삭제 실패 ${res.status}: ${(await res.text()).slice(0, 200)}`);
    const removed = await res.json().catch(() => []);
    console.log(`   삭제 요청 완료 (보관함 응답 ${Array.isArray(removed) ? removed.length : '?'}개)`);

    console.log('\n5) 다시 확인 중…');
    const left = [];
    for (const p of found) if (await exists(key, p)) left.push(p);
    if (left.length) { console.log('   아직 남은 파일:'); left.forEach(p => console.log('   ' + p)); process.exitCode = 1; }
    else console.log(`   ${found.length}개 모두 지워졌습니다.`);
}

main().catch(e => die(e && e.message ? e.message : String(e))).finally(() => rl.close());
