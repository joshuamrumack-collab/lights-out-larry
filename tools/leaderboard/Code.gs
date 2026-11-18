/**
 * OneBeat class leaderboard — paste this into a Google Apps Script project
 * that is bound to a Google Sheet (Extensions → Apps Script in the sheet).
 * Then Deploy → New deployment → Web app:
 *   Execute as: Me    Who has access: Anyone
 * Copy the web app URL into the game (Settings → Class leaderboard URL,
 * or config/leaderboard.cfg before exporting the web build).
 *
 * Optional: set a class code so only your class can post.
 *   Project Settings → Script properties → CLASS_CODE = something
 */
const SHEET_NAME = 'Scores';
const HEADERS = ['time', 'week', 'name', 'song', 'title', 'difficulty', 'score', 'accuracy', 'max_combo', 'full_combo', 'assist'];

function sheet_() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  let sh = ss.getSheetByName(SHEET_NAME);
  if (!sh) {
    sh = ss.insertSheet(SHEET_NAME);
    sh.appendRow(HEADERS);
    sh.setFrozenRows(1);
  }
  return sh;
}

function codeOk_(code) {
  const want = PropertiesService.getScriptProperties().getProperty('CLASS_CODE') || '';
  return want === '' || String(code || '') === want;
}

function json_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}

function doPost(e) {
  let d;
  try { d = JSON.parse(e.postData.contents); } catch (err) { return json_({ ok: false, error: 'bad json' }); }
  if (!codeOk_(d.code)) return json_({ ok: false, error: 'wrong class code' });
  const name = String(d.name || '').replace(/[<>=+@]/g, '').trim().slice(0, 20);
  const score = Math.max(0, Math.min(99999999, Number(d.score) || 0));
  if (!name) return json_({ ok: false, error: 'no name' });
  const lock = LockService.getScriptLock();
  lock.waitLock(5000);
  try {
    sheet_().appendRow([new Date(), String(d.week || '').slice(0, 10), name, String(d.song || '').slice(0, 64),
      String(d.title || '').replace(/^[=+@-]/, "'").slice(0, 80), String(d.diff || '').slice(0, 10), score,
      Number(d.acc) || 0, Number(d.combo) || 0, d.fc ? 'FC' : '', d.assist ? 'assist' : '']);
  } finally {
    lock.releaseLock();
  }
  return json_({ ok: true });
}

function doGet(e) {
  const p = e.parameter || {};
  if (p.action !== 'top') return json_({ ok: true, app: 'OneBeat leaderboard' });
  if (!codeOk_(p.code)) return json_({ ok: false, rows: [], error: 'wrong class code' });
  const values = sheet_().getDataRange().getValues();
  const best = {};  // best score per name
  for (let i = 1; i < values.length; i++) {
    const r = values[i];
    if (r[3] !== p.song || r[5] !== p.diff) continue;
    if (p.week && p.week !== 'all' && r[1] !== p.week) continue;
    const name = r[2];
    if (!best[name] || r[6] > best[name].score) {
      best[name] = { name: name, score: r[6], acc: r[7], combo: r[8], fc: r[9] === 'FC', assist: r[10] === 'assist' };
    }
  }
  const rows = Object.values(best).sort((a, b) => b.score - a.score).slice(0, 10);
  return json_({ ok: true, rows: rows });
}
