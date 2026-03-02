// ─── AutoClawd Mission Control ───────────────────────────────────────────────
// Perspective room renderer — sprites placed over background.png
// Background: 960×648 pixel art Mission Control room
// ─────────────────────────────────────────────────────────────────────────────
;(function () {
'use strict';

// ── Scene dimensions (match background.png) ───────────────────────────────────
var BG_W = 960;
var BG_H = 648;

// ── Floor zone (where characters live) ───────────────────────────────────────
// Floor tiles start at approximately y=385 in the 648px image
var FLOOR_Y   = 385;   // y where floor begins
var FLOOR_BOT = 640;   // y at bottom of floor

// ── Perspective helpers ────────────────────────────────────────────────────────
// Objects further back (smaller y) appear smaller
function perspScale(y) {
  var t = (y - FLOOR_Y) / (FLOOR_BOT - FLOOR_Y); // 0 = far back, 1 = front
  return 0.58 + t * 0.42; // scale range: 0.58 → 1.0 (back row bigger than before)
}

// ── Canvas setup ─────────────────────────────────────────────────────────────
var bg      = document.getElementById('bg');
var canvas  = document.getElementById('overlay');
var ctx     = canvas.getContext('2d');
ctx.imageSmoothingEnabled = false;

function resize() {
  var rw = window.innerWidth;
  var rh = window.innerHeight;
  var s  = Math.min(rw / BG_W, rh / BG_H);
  var dw = Math.round(BG_W * s);
  var dh = Math.round(BG_H * s);
  var ox = Math.round((rw - dw) / 2);
  var oy = Math.round((rh - dh) / 2);

  // Position background image
  bg.style.width  = dw + 'px';
  bg.style.height = dh + 'px';
  bg.style.left   = ox + 'px';
  bg.style.top    = oy + 'px';

  // Overlay canvas matches exactly
  canvas.width  = BG_W;
  canvas.height = BG_H;
  canvas.style.width  = dw + 'px';
  canvas.style.height = dh + 'px';
  canvas.style.left   = ox + 'px';
  canvas.style.top    = oy + 'px';
  ctx.imageSmoothingEnabled = false;
}
resize();
window.addEventListener('resize', resize);

// ── Desk positions + pipeline function labels ─────────────────────────────────
// 6 desks: back row left→right, then front row left→right
// Pipeline agents visit them in index order (0→5)
var DESKS = [
  { x: 195, y: 479, label: 'Comms',       idx: 0 },
  { x: 480, y: 469, label: 'Analysis',    idx: 1 },
  { x: 765, y: 479, label: 'Projects',    idx: 2 },
  { x: 220, y: 579, label: 'Approval',    idx: 3 },
  { x: 480, y: 589, label: 'Claude Code', idx: 4 },
  { x: 740, y: 579, label: 'Archive',     idx: 5 },
];

// How far in front of the desk's y-centre an agent stands (px).
// Increase to push agents further toward the viewer from the desk.
var DESK_STAND_OFFSET = 50;

// ── Agent color palettes ──────────────────────────────────────────────────────
var PAL = [
  { s:'#4a7ec0', h:'#22180a', k:'#f4c090', p:'#3a6aaa' },  // 0 blue
  { s:'#c8b030', h:'#140800', k:'#f4c090', p:'#a89020' },  // 1 yellow
  { s:'#2e8858', h:'#0e0500', k:'#bf8050', p:'#206848' },  // 2 green
  { s:'#8040b8', h:'#14143a', k:'#f4c090', p:'#6030a0' },  // 3 purple
  { s:'#c05020', h:'#240e00', k:'#e09060', p:'#a03c10' },  // 4 orange
  { s:'#b83030', h:'#260c0c', k:'#f4c090', p:'#982020' },  // 5 red
];

// ── Character sprite templates: 16 cols × 24 rows ────────────────────────────
// '' = transparent | 'H'=hair | 'K'=skin | 'S'=shirt | 'P'=pants | 'O'=shoe
var CHAR_TEMPLATES = (function () {
  var _ = '', H = 'H', K = 'K', S = 'S', P = 'P';

  // Seated idle (back-facing, at desk)
  var sit = [
    [_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_],  // 0
    [_,_,_,_,_,H,H,H,H,H,H,_,_,_,_,_],  // 1  hair
    [_,_,_,_,H,H,H,H,H,H,H,H,_,_,_,_],  // 2  hair
    [_,_,_,_,H,H,H,H,H,H,H,H,_,_,_,_],  // 3  hair
    [_,_,_,_,H,H,H,H,H,H,H,H,_,_,_,_],  // 4  hair
    [_,_,_,_,_,K,K,K,K,K,K,_,_,_,_,_],  // 5  neck
    [_,_,_,S,S,S,S,S,S,S,S,S,S,_,_,_],  // 6  collar
    [_,_,S,S,S,S,S,S,S,S,S,S,S,S,_,_],  // 7  shoulder caps
    [_,_,_,S,S,S,S,S,S,S,S,S,S,_,_,_],  // 8  upper back
    [_,_,_,S,S,S,S,S,S,S,S,S,S,_,_,_],  // 9  back
    [_,_,_,S,S,S,S,S,S,S,S,S,S,_,_,_],  // 10 back
    [_,_,_,_,S,S,S,S,S,S,S,S,_,_,_,_],  // 11 waist
    [_,_,_,_,P,P,P,P,P,P,P,P,_,_,_,_],  // 12 hips
    [_,_,P,P,P,P,_,_,_,_,P,P,P,P,_,_],  // 13 thighs (seated, wide)
    [_,_,P,P,P,P,_,_,_,_,P,P,P,P,_,_],  // 14 thighs
    [_,_,_,P,P,_,_,_,_,_,_,P,P,_,_,_],  // 15 knees
    [_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_],  // 16
    [_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_],  // 17
    [_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_],  // 18
    [_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_],  // 19
    [_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_],  // 20
    [_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_],  // 21
    [_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_],  // 22
    [_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_],  // 23
  ];

  // Typing pose: arms raised/wide (back-facing, at desk)
  var type = [
    [_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_],  // 0
    [_,_,_,_,_,H,H,H,H,H,H,_,_,_,_,_],  // 1
    [_,_,_,_,H,H,H,H,H,H,H,H,_,_,_,_],  // 2
    [_,_,_,_,H,H,H,H,H,H,H,H,_,_,_,_],  // 3
    [_,_,_,_,H,H,H,H,H,H,H,H,_,_,_,_],  // 4
    [_,_,_,_,_,K,K,K,K,K,K,_,_,_,_,_],  // 5  neck
    [_,S,S,S,S,S,S,S,S,S,S,S,S,S,S,_],  // 6  arms raised wide
    [_,_,S,S,S,S,S,S,S,S,S,S,S,S,_,_],  // 7
    [_,_,_,S,S,S,S,S,S,S,S,S,S,_,_,_],  // 8  back
    [_,_,_,S,S,S,S,S,S,S,S,S,S,_,_,_],  // 9
    [_,_,_,S,S,S,S,S,S,S,S,S,S,_,_,_],  // 10
    [_,_,_,_,S,S,S,S,S,S,S,S,_,_,_,_],  // 11
    [_,_,_,_,P,P,P,P,P,P,P,P,_,_,_,_],  // 12
    [_,_,P,P,P,P,_,_,_,_,P,P,P,P,_,_],  // 13
    [_,_,P,P,P,P,_,_,_,_,P,P,P,P,_,_],  // 14
    [_,_,_,P,P,_,_,_,_,_,_,P,P,_,_,_],  // 15
    [_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_],  // 16
    [_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_],  // 17
    [_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_],  // 18
    [_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_],  // 19
    [_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_],  // 20
    [_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_],  // 21
    [_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_],  // 22
    [_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_],  // 23
  ];

  return { sit: sit, type: type };
})();

// ── Sprite cache: pre-render templates to offscreen canvases ─────────────────
var _spriteCache = {};
function getSprite(tmplName, palIdx) {
  var key = tmplName + '_' + palIdx;
  if (_spriteCache[key]) return _spriteCache[key];
  var tmpl     = CHAR_TEMPLATES[tmplName];
  var pal      = PAL[palIdx % PAL.length];
  var colorMap = { H: pal.h, K: pal.k, S: pal.s, P: pal.p };
  var ZOOM = 4;
  var rows = tmpl.length, cols = tmpl[0].length;
  var cv   = document.createElement('canvas');
  cv.width  = cols * ZOOM;
  cv.height = rows * ZOOM;
  var cx    = cv.getContext('2d');
  cx.imageSmoothingEnabled = false;
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      var ch = tmpl[r][c];
      if (!ch) continue;
      cx.fillStyle = colorMap[ch];
      cx.fillRect(c * ZOOM, r * ZOOM, ZOOM, ZOOM);
    }
  }
  _spriteCache[key] = cv;
  return cv;
}

// ── Walker sprite sheets (StandingA character) ────────────────────────────────
// Each file: 640×1120 RGBA, transparent BG
// Content center x ≈ 317 (= 0.495 of width), content bottom y ≈ 1090 (= 0.973 of height)
var WALKER_BASE_H  = 135;       // rendered height at perspScale=1.0
var WALKER_CX_FRAC = 317 / 640; // content center-x fraction
var WALKER_BY_FRAC = 1090 / 1120; // content bottom-y fraction

var WALKER = {};
var walkerLoaded = 0;
(function () {
  var files = {
    back1:      'StandingA-Back-Walk-1.png',
    back2:      'StandingA-Back-Walk-2.png',
    front1:     'StandingA-Front-Walk-1.png',
    front2:     'StandingA-Front-Walk-2.png',
    left1:      'StandingA-Left-Walk-1.png',
    left2:      'StandingA-Left-Walk-2.png',
    right1:     'StandingA-Right-Walk-1.png',
    right2:     'StandingA-Right-Walk-2.png',
    backStand:  'StandingA-back-standing.png',
    frontStand: 'StandingA-front-standing.png',
  };
  Object.keys(files).forEach(function (k) {
    var img = new Image();
    img.onload  = function () { WALKER[k] = img; walkerLoaded++; };
    img.onerror = function () { walkerLoaded++; }; // count failures so drawWalker unblocks
    img.src = './sprites/' + files[k];
  });
})();

// ── Agent state ───────────────────────────────────────────────────────────────
var pending     = {};
var agents      = {};
var layoutReady = false;
var SEATS       = {};   // legacy seat map — kept so flush() doesn't throw

function flush() {
  var seatKeys = Object.keys(SEATS);
  var seatIdx  = 0;
  Object.keys(pending).sort().forEach(function(id) {
    var p    = pending[id];
    var skey = p.seatId || seatKeys[seatIdx++ % seatKeys.length];
    var seat = SEATS[skey] || SEATS[seatKeys[0]];
    agents[id] = {
      id:         id,
      palette:    p.palette | 0,
      name:       p.name || ('Agent ' + id),
      x:          seat.x,
      y:          seat.y,
      tx:         seat.x,
      ty:         seat.y,
      seatId:     skey,
      vx:         0,
      vy:         0,
      dir:        'back',
      moveState:  'seated',             // 'seated' | 'walkingOut' | 'returning' | 'walkingBack'
      breakTimer: Math.round(600 + Math.random() * 900), // ticks before taking a break
      idleTimer:  0,
      status:     'idle',
      tools:      [],
      spark:      [],
    };
  });
  pending = {};
}

// ── Message bus ───────────────────────────────────────────────────────────────
window.addEventListener('message', function(ev) {
  var m = ev.data;
  if (!m || !m.type) return;
  switch (m.type) {
    case 'existingAgents':
      (m.agents || []).forEach(function(id) {
        var meta = (m.agentMeta || {})[id] || {};
        pending[id] = {
          palette: meta.palette || 0,
          seatId:  meta.seatId  || null,
          name:    (m.folderNames || {})[id] || ('Agent ' + id),
        };
      });
      if (layoutReady) flush();
      break;
    case 'layoutLoaded':
      layoutReady = true;
      flush();
      break;
    case 'agentStatus':
      if (agents[m.id]) agents[m.id].status = m.status;
      // Agent 4 (Claude Code) goes idle/waiting → advance to Archive
      if (m.id == 4 && m.status === 'waiting') {
        advancePipeline('atClaude', 'toArchive', 5);
      }
      break;
    case 'agentToolStart':
      if (agents[m.id]) {
        agents[m.id].tools.push(m.status || '');
        if (agents[m.id].tools.length > 3) agents[m.id].tools.shift();
      }
      // Pipeline event routing:
      // id=1 transcript → dequeue front agent, send to Comms
      if (m.id == 1) assignNextAgent();
      // id=2 cleaning starts → advance from Comms to Analysis
      if (m.id == 2) advancePipeline('atComms', 'toAnalysis', 1);
      // id=3 analysis starts → advance from Analysis to Projects
      if (m.id == 3) advancePipeline('atAnalysis', 'toProjects', 2);
      // id=4 task created/executing → advance from Projects to Approval desk
      if (m.id == 4) advancePipeline('atProjects', 'toApproval', 3);
      break;
    case 'agentToolsClear':
      if (agents[m.id]) {
        agents[m.id].tools  = [];
        agents[m.id].status = 'idle';
      }
      break;
  }
});

// Trigger adapter init
var _vsc = window.acquireVsCodeApi && window.acquireVsCodeApi();
if (_vsc) _vsc.postMessage({ type: 'webviewReady' });

// ── Drawing helpers ────────────────────────────────────────────────────────────
function f(x,y,w,h,c) { ctx.fillStyle = c; ctx.fillRect(x,y,w,h); }

function lighten(hex, amt) {
  var r = Math.min(255, parseInt(hex.slice(1,3),16) + amt);
  var g = Math.min(255, parseInt(hex.slice(3,5),16) + amt);
  var b = Math.min(255, parseInt(hex.slice(5,7),16) + amt);
  return '#' + [r,g,b].map(function(v){ return v.toString(16).padStart(2,'0'); }).join('');
}

function rrect(x,y,w,h,r) {
  ctx.beginPath();
  ctx.moveTo(x+r,y); ctx.lineTo(x+w-r,y);
  ctx.quadraticCurveTo(x+w,y,x+w,y+r); ctx.lineTo(x+w,y+h-r);
  ctx.quadraticCurveTo(x+w,y+h,x+w-r,y+h); ctx.lineTo(x+r,y+h);
  ctx.quadraticCurveTo(x,y+h,x,y+h-r); ctx.lineTo(x,y+r);
  ctx.quadraticCurveTo(x,y,x+r,y); ctx.closePath();
}

// ── Draw one workstation console desk ─────────────────────────────────────────
// Full mission-control console: desk surface + monitor backs + control panel
function drawDesk(d) {
  var sc   = perspScale(d.y);
  var dw   = Math.round(138 * sc);   // wide console
  var dx   = Math.round(d.x - dw / 2);

  // Vertical positions
  var surfY = Math.round(d.y - 33 * sc);   // desk top surface
  var surfH = Math.max(2, Math.round(8 * sc));
  var panH  = Math.max(5, Math.round(27 * sc));  // front panel face height
  var legH  = Math.round(21 * sc);               // legs to floor

  // ── Desk top surface ──────────────────────────────────────────────────────
  f(dx, surfY, dw, surfH, '#1e2e42');
  f(dx, surfY, dw, 1, '#3e5a78');                // top highlight
  f(dx, surfY + surfH - 1, dw, 1, '#0e1828');    // bottom shadow

  // ── Front panel (faces viewer) ────────────────────────────────────────────
  f(dx, surfY + surfH, dw, panH, '#141e2c');
  // Panel top inset line
  f(dx + Math.round(sc), surfY + surfH, dw - Math.round(sc*2),
    Math.max(1, Math.round(sc)), '#0a1220');

  // Embedded widescreen in panel
  var sw = Math.round(54 * sc), sh = Math.max(3, Math.round(11 * sc));
  var sx = Math.round(d.x - sw / 2);
  var sy = surfY + surfH + Math.round(panH * 0.08);
  f(sx, sy, sw, sh, '#0b1828');
  f(sx + Math.max(1,Math.round(sc)), sy + Math.max(1,Math.round(sc)),
    sw - Math.round(2*sc), sh - Math.round(2*sc), '#0e3258');
  // Scanline
  f(sx + Math.max(1,Math.round(sc)), sy + Math.max(1,Math.round(sc)),
    Math.round(sw*0.4), Math.max(1,Math.round(sc)), '#1a5080');

  // Status LEDs row
  var ledY = surfY + surfH + Math.round(panH * 0.76);
  var lr   = Math.max(1, Math.round(3 * sc));
  f(Math.round(d.x - 21*sc), ledY, lr, lr, '#1ecc44');
  f(Math.round(d.x -  8*sc), ledY, lr, lr, '#2244ee');
  f(Math.round(d.x +  6*sc), ledY, lr, lr, '#ee3318');
  f(Math.round(d.x + 18*sc), ledY, lr, lr, '#eeaa00');

  // ── Desk legs (two, left and right) ───────────────────────────────────────
  var legW = Math.max(2, Math.round(6 * sc));
  var legY = surfY + surfH + panH;
  f(dx + Math.round(dw * 0.07), legY, legW, legH, '#0e1828');
  f(dx + dw - Math.round(dw * 0.07) - legW, legY, legW, legH, '#0e1828');

  // ── Monitor backs (sitting on desk top surface, we see the rear) ──────────
  var mw  = Math.round(42 * sc), mh = Math.round(30 * sc);
  // Left monitor
  var mlx = dx + Math.round(dw * 0.18);
  var mly = surfY - mh;
  f(mlx, mly, mw, mh, '#111820');
  f(mlx, mly, mw, Math.max(1,Math.round(sc)), '#1e2e40');     // top edge
  f(mlx, mly, Math.max(1,Math.round(sc)), mh, '#1a2838');     // left edge
  // Vent slits on monitor back
  for (var vi = 0; vi < 3; vi++) {
    f(mlx + Math.round(mw*0.25), mly + Math.round(mh*(0.55 + vi*0.12)),
      Math.round(mw*0.50), Math.max(1,Math.round(sc)), '#0a1018');
  }
  // Monitor stand
  f(mlx + Math.round(mw*0.38), surfY - Math.round(3*sc),
    Math.round(mw*0.24), Math.round(3*sc), '#0e1620');

  // Right monitor
  var mrx = dx + dw - Math.round(dw * 0.18) - mw;
  var mry = surfY - mh;
  f(mrx, mry, mw, mh, '#111820');
  f(mrx, mry, mw, Math.max(1,Math.round(sc)), '#1e2e40');
  f(mrx + mw - Math.max(1,Math.round(sc)), mry, Math.max(1,Math.round(sc)), mh, '#1a2838');
  for (var vj = 0; vj < 3; vj++) {
    f(mrx + Math.round(mw*0.25), mry + Math.round(mh*(0.55 + vj*0.12)),
      Math.round(mw*0.50), Math.max(1,Math.round(sc)), '#0a1018');
  }
  f(mrx + Math.round(mw*0.38), surfY - Math.round(3*sc),
    Math.round(mw*0.24), Math.round(3*sc), '#0e1620');

  // ── Keyboard on desk top ──────────────────────────────────────────────────
  var kw = Math.round(45 * sc), kh = Math.max(1, Math.round(5 * sc));
  f(Math.round(d.x - kw/2), surfY + surfH - kh - Math.max(1,Math.round(sc)),
    kw, kh, '#192636');
  f(Math.round(d.x - kw/2), surfY + surfH - kh - Math.max(1,Math.round(sc)),
    kw, Math.max(1,Math.round(sc)), '#243448');  // key top highlight

  // ── Desk function label (above monitors) ──────────────────────────────────
  if (d.label) {
    var labelY = mly - Math.round(4 * sc);
    ctx.save();
    ctx.font         = 'bold ' + Math.round(Math.max(8, 12 * sc)) + 'px "Courier New",monospace';
    ctx.textAlign    = 'center';
    ctx.textBaseline = 'bottom';
    // Subtle glow backing
    ctx.fillStyle = 'rgba(0,20,50,0.55)';
    var lw = ctx.measureText(d.label).width;
    ctx.fillRect(Math.round(d.x - lw/2 - 3), labelY - Math.round(9*sc), lw + 6, Math.round(9*sc));
    ctx.fillStyle = 'rgba(100,190,255,0.90)';
    ctx.fillText(d.label, d.x, labelY);
    ctx.restore();
  }
}

// ── Draw one agent using pixel-array sprites ──────────────────────────────────
function drawAgent(a) {
  var sc      = perspScale(a.y);
  var active  = a.status === 'active';
  var waiting = a.status === 'waiting';

  // Alternate sit/type frame when active (typing animation)
  var tmplName = (active && Math.floor(tick / 8) % 2 === 0) ? 'type' : 'sit';
  var sprite   = getSprite(tmplName, a.palette);

  // Destination size: maintain sprite aspect ratio, perspective scaled
  var destH = Math.round(90 * sc);
  var destW = Math.round(destH * sprite.width / sprite.height);
  var dx    = Math.round(a.x - destW / 2);
  var dy    = Math.round(a.y - destH);

  ctx.save();
  ctx.imageSmoothingEnabled = false;

  // Ground shadow
  ctx.fillStyle = 'rgba(0,0,0,0.28)';
  ctx.beginPath();
  ctx.ellipse(a.x, a.y + 2, destW * 0.42, destW * 0.14, 0, 0, Math.PI * 2);
  ctx.fill();

  // Stamp sprite
  ctx.drawImage(sprite, 0, 0, sprite.width, sprite.height, dx, dy, destW, destH);

  // ── Status LED ──
  var ledX = dx + destW + Math.round(2 * sc);
  var ledY = dy + Math.round(destH * 0.08);
  var lr   = Math.max(2, Math.round(3 * sc));
  if (active) {
    ctx.fillStyle = '#22ff66';
    ctx.beginPath(); ctx.arc(ledX, ledY, lr, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = 'rgba(34,255,100,0.25)';
    ctx.beginPath(); ctx.arc(ledX, ledY, lr * 2.8, 0, Math.PI * 2); ctx.fill();
    if (tick % 10 === 0) {
      a.spark.push({
        x: a.x, y: dy + Math.round(destH * 0.25),
        vx: (Math.random() - 0.5) * sc * 1.5, vy: (-1.6 - Math.random()) * sc, life: 20
      });
    }
  } else if (waiting) {
    ctx.fillStyle = '#ffaa22';
    ctx.beginPath(); ctx.arc(ledX, ledY, lr, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = 'rgba(255,170,34,0.22)';
    ctx.beginPath(); ctx.arc(ledX, ledY, lr * 2, 0, Math.PI * 2); ctx.fill();
  } else {
    ctx.fillStyle = '#1a3399';
    ctx.beginPath(); ctx.arc(ledX, ledY, Math.max(1, lr - 1), 0, Math.PI * 2); ctx.fill();
  }

  // ── Sparks ──
  for (var s = a.spark.length - 1; s >= 0; s--) {
    var sp = a.spark[s];
    var alpha = sp.life / 20;
    ctx.fillStyle = 'rgba(80,255,160,' + alpha.toFixed(2) + ')';
    ctx.fillRect(sp.x | 0, sp.y | 0, Math.max(1, Math.round(sc * 2)), Math.max(1, Math.round(sc * 2)));
    sp.x += sp.vx; sp.y += sp.vy; sp.vy += 0.06; sp.life--;
    if (sp.life <= 0) a.spark.splice(s, 1);
  }

  // ── Tool bubble ──
  if (a.tools.length > 0) {
    drawBubble(a.tools[a.tools.length - 1], a.x, dy - Math.round(sc * 4), active, sc);
  }

  // ── Name label ──
  var nameY = dy - (a.tools.length > 0 ? Math.round(sc * 24) : Math.round(sc * 6));
  ctx.font          = Math.round(Math.max(8, 10 * sc)) + 'px "Courier New",monospace';
  ctx.textAlign     = 'center';
  ctx.textBaseline  = 'bottom';
  ctx.fillStyle     = 'rgba(180,215,255,0.80)';
  ctx.fillText(a.name, a.x, nameY);

  ctx.restore();
}

// ── [REMOVED: old fillRect drawHair — no longer needed] ──────────────────────
function _deadHair(hx, hy, hw, hh, sc, col, style) {
  // Base: full head coverage
  f(hx, hy, hw, hh, col);
  var hi = lighten(col, 30);
  var dk = col; // keep dark for shading

  if (style === 0) {
    // Short, neat — flat top, slight width taper at bottom
    f(hx + Math.round(hw*0.10), hy, Math.round(hw*0.80), Math.max(1,Math.round(sc*2)), hi);
    // Undercut: slight fade at nape (skin shows at bottom corners)
    f(hx, hy + Math.round(hh*0.82), Math.round(hw*0.18), Math.round(hh*0.18), '#00000000');
    f(hx + Math.round(hw*0.82), hy + Math.round(hh*0.82), Math.round(hw*0.18), Math.round(hh*0.18), '#00000000');
  } else if (style === 1) {
    // Medium — slightly tousled top bump
    f(hx + Math.round(hw*0.20), hy - Math.max(1,Math.round(sc*2)),
      Math.round(hw*0.60), Math.max(1,Math.round(sc*2)), col);   // bump up center
    f(hx + Math.round(hw*0.25), hy, Math.round(hw*0.50), Math.max(1,Math.round(sc*2)), hi);
    // Slight side tufts
    f(hx - Math.max(1,Math.round(sc)), hy + Math.round(hh*0.10),
      Math.max(1,Math.round(sc*2)), Math.round(hh*0.30), col);
    f(hx + hw - Math.max(1,Math.round(sc)), hy + Math.round(hh*0.10),
      Math.max(1,Math.round(sc*2)), Math.round(hh*0.30), col);
    f(hx + Math.round(hw*0.12), hy, Math.round(hw*0.76), Math.max(1,Math.round(sc)), hi);
  } else if (style === 2) {
    // Curly / voluminous — wider and puffier
    f(hx - Math.max(1,Math.round(sc*2)), hy + Math.round(hh*0.05),
      Math.round(sc*3), Math.round(hh*0.55), col);
    f(hx + hw - Math.round(sc), hy + Math.round(hh*0.05),
      Math.round(sc*3), Math.round(hh*0.55), col);
    // Top puff
    f(hx + Math.round(hw*0.15), hy - Math.max(1,Math.round(sc*2)),
      Math.round(hw*0.70), Math.round(sc*3), col);
    f(hx + Math.round(hw*0.20), hy, Math.round(hw*0.60), Math.max(1,Math.round(sc*2)), hi);
    // Curly texture dots
    f(hx + Math.round(hw*0.15), hy + Math.round(hh*0.25), Math.max(1,Math.round(sc)), Math.max(1,Math.round(sc)), hi);
    f(hx + Math.round(hw*0.55), hy + Math.round(hh*0.20), Math.max(1,Math.round(sc)), Math.max(1,Math.round(sc)), hi);
    f(hx + Math.round(hw*0.35), hy + Math.round(hh*0.35), Math.max(1,Math.round(sc)), Math.max(1,Math.round(sc)), hi);
  } else {
    // Long / swept — hair hangs below head base
    f(hx + Math.round(hw*0.08), hy, Math.round(hw*0.84), Math.max(1,Math.round(sc*2)), hi);
    // Side curtains hanging past head base
    f(hx, hy + Math.round(hh*0.60), Math.round(hw*0.20), Math.round(hh*0.50), col);
    f(hx + Math.round(hw*0.80), hy + Math.round(hh*0.60), Math.round(hw*0.20), Math.round(hh*0.50), col);
    // Center part line
    f(hx + Math.round(hw*0.47), hy + Math.round(hh*0.05),
      Math.max(1,Math.round(sc)), Math.round(hh*0.40), dk);
  }
}

// ── [old fillRect drawAgent removed — replaced above with pixel-array version] ─
function _deadAgent(a) {
  var sc  = perspScale(a.y);
  // Chibi grid: designed at 56×90 logical units, scaled by sc
  var U   = sc;            // 1 logical unit = sc canvas pixels
  var CW  = Math.round(56 * U);
  var CH  = Math.round(90 * U);
  var pal = PAL[a.palette % PAL.length];

  var active  = a.status === 'active';
  var waiting = a.status === 'waiting';

  var bob = active ? (Math.floor(tick / 5) % 2 === 0 ? 0 : -Math.round(U)) : 0;
  var ox  = Math.round(a.x - CW / 2);
  var oy  = Math.round(a.y - CH) + bob;

  ctx.save();

  // Ground shadow
  ctx.fillStyle = 'rgba(0,0,0,0.30)';
  ctx.beginPath();
  ctx.ellipse(a.x, a.y + 2, CW * 0.42, CW * 0.14, 0, 0, Math.PI * 2);
  ctx.fill();

  // ── SHOES ── (y: 82–90%)
  var shoeY = oy + Math.round(CH * 0.82);
  var shoeH = Math.round(CH * 0.10);
  var shoeW = Math.round(CW * 0.25);
  f(ox + Math.round(CW * 0.10), shoeY, shoeW, shoeH, '#12141c');
  f(ox + Math.round(CW * 0.65), shoeY, shoeW, shoeH, '#12141c');
  // toe shine
  f(ox + Math.round(CW * 0.10), shoeY, Math.round(shoeW*0.5), Math.max(1,Math.round(U)), '#252838');
  f(ox + Math.round(CW * 0.65), shoeY, Math.round(shoeW*0.5), Math.max(1,Math.round(U)), '#252838');

  // ── LEGS ── (y: 60–84%)
  var legW  = Math.max(2, Math.round(CW * 0.18));
  var legH  = Math.round(CH * 0.26);
  var legY  = oy + Math.round(CH * 0.60);
  var trouser = '#1e2040';
  var trouserH= lighten(trouser, 14);
  // left leg
  f(ox + Math.round(CW * 0.13), legY, legW, legH, trouser);
  f(ox + Math.round(CW * 0.13), legY, legW, Math.max(1,Math.round(U)), trouserH);
  // right leg
  f(ox + Math.round(CW * 0.69), legY, legW, legH, trouser);
  f(ox + Math.round(CW * 0.69), legY, legW, Math.max(1,Math.round(U)), trouserH);
  // knee detail (mid-leg brighter strip)
  var kneeY = legY + Math.round(legH * 0.50);
  f(ox + Math.round(CW * 0.13), kneeY, legW, Math.max(1,Math.round(U)), lighten(trouser, 20));
  f(ox + Math.round(CW * 0.69), kneeY, legW, Math.max(1,Math.round(U)), lighten(trouser, 20));

  // ── BODY ── (y: 28–64%)
  var bodyY = oy + Math.round(CH * 0.28);
  var bodyW = Math.round(CW * 0.78);
  var bodyH = Math.round(CH * 0.36);
  var bodyX = ox + Math.round((CW - bodyW) / 2);
  f(bodyX, bodyY, bodyW, bodyH, pal.s);
  // Shoulder top edge bright
  f(bodyX, bodyY, bodyW, Math.max(1, Math.round(U * 2)), lighten(pal.s, 40));
  // Shoulder side caps (slightly protruding)
  f(bodyX - Math.round(U*2), bodyY, Math.round(U*3), Math.round(bodyH * 0.40), pal.s);
  f(bodyX + bodyW - Math.round(U), bodyY, Math.round(U*3), Math.round(bodyH * 0.40), pal.s);
  // Center back seam
  f(ox + Math.round(CW * 0.48), bodyY + Math.round(bodyH * 0.08),
    Math.max(1,Math.round(U)), Math.round(bodyH * 0.78), pal.p);
  // Lower body shade
  f(bodyX, bodyY + Math.round(bodyH * 0.75), bodyW, Math.round(bodyH * 0.25), pal.p);

  // Arms (back view, wide fit; raised when active for typing)
  var armW   = Math.max(2, Math.round(CW * 0.14));
  var armH   = Math.round(bodyH * 0.80);
  var armRaise = active ? Math.round(U * 6) : 0;
  // left arm
  f(ox, bodyY + armRaise, armW, armH - armRaise, pal.s);
  f(ox, bodyY + armRaise, armW, Math.max(1,Math.round(U)), lighten(pal.s, 25));
  // right arm
  f(ox + CW - armW, bodyY + armRaise, armW, armH - armRaise, pal.s);
  f(ox + CW - armW, bodyY + armRaise, armW, Math.max(1,Math.round(U)), lighten(pal.s, 25));
  // hands / cuffs
  var handW = Math.round(CW * 0.12), handH = Math.max(2, Math.round(U * 5));
  f(ox - Math.round(U), bodyY + armH - armRaise, handW, handH, pal.k);
  f(ox + CW - handW + Math.round(U), bodyY + armH - armRaise, handW, handH, pal.k);

  // ── NECK ── (y: 22–30%)
  var neckW = Math.round(CW * 0.22);
  var neckH = Math.round(CH * 0.10);
  f(ox + Math.round((CW - neckW) / 2), oy + Math.round(CH * 0.22), neckW, neckH, pal.k);
  // collar back
  f(ox + Math.round(CW * 0.32), bodyY - Math.round(U*2),
    Math.round(CW * 0.36), Math.round(U*3), lighten(pal.s, 20));

  // ── HEAD ── (y: 0–30%, chibi = BIG head)
  var headW = Math.round(CW * 0.72);
  var headH = Math.round(CH * 0.28);
  var hx    = ox + Math.round((CW - headW) / 2);
  var hy    = oy;

  // Skin base (back of head peek at nape)
  f(hx + Math.round(headW*0.20), hy + Math.round(headH*0.78),
    Math.round(headW*0.60), Math.max(2, Math.round(U*3)), pal.k);
  // Ears
  f(hx - Math.max(1,Math.round(U)), hy + Math.round(headH*0.35),
    Math.max(2,Math.round(U*2)), Math.round(headH*0.28), pal.k);
  f(hx + headW, hy + Math.round(headH*0.35),
    Math.max(2,Math.round(U*2)), Math.round(headH*0.28), pal.k);
  // Inner ear shadow
  f(hx - Math.max(1,Math.round(U)) + Math.max(1,Math.round(U)), hy + Math.round(headH*0.40),
    Math.max(1,Math.round(U)), Math.round(headH*0.15), lighten(pal.k, -20));

  // Hair (personality style per palette)
  drawHair(hx, hy, headW, headH, U, pal.h, HAIR_STYLE[a.palette % 4]);

  // ── STATUS LED ──
  var ledX = hx + headW + Math.round(U*2);
  var ledY = hy + Math.round(headH * 0.12);
  var lr   = Math.max(2, Math.round(U * 3));
  if (active) {
    ctx.fillStyle = '#22ff66';
    ctx.beginPath(); ctx.arc(ledX, ledY, lr, 0, Math.PI*2); ctx.fill();
    ctx.fillStyle = 'rgba(34,255,100,0.25)';
    ctx.beginPath(); ctx.arc(ledX, ledY, lr * 2.8, 0, Math.PI*2); ctx.fill();
    if (tick % 10 === 0) {
      a.spark.push({ x: a.x, y: a.y - Math.round(CH * 0.50),
        vx: (Math.random()-0.5)*U*1.5, vy: (-1.6-Math.random())*U, life: 20 });
    }
  } else if (waiting) {
    ctx.fillStyle = '#ffaa22';
    ctx.beginPath(); ctx.arc(ledX, ledY, lr, 0, Math.PI*2); ctx.fill();
    ctx.fillStyle = 'rgba(255,170,34,0.22)';
    ctx.beginPath(); ctx.arc(ledX, ledY, lr * 2, 0, Math.PI*2); ctx.fill();
  } else {
    ctx.fillStyle = '#1a3399';
    ctx.beginPath(); ctx.arc(ledX, ledY, Math.max(1, lr-1), 0, Math.PI*2); ctx.fill();
  }

  // ── SPARKS ──
  for (var s = a.spark.length - 1; s >= 0; s--) {
    var sp = a.spark[s];
    var alpha = sp.life / 20;
    ctx.fillStyle = 'rgba(80,255,160,' + alpha.toFixed(2) + ')';
    ctx.fillRect(sp.x|0, sp.y|0, Math.max(1,Math.round(U*2)), Math.max(1,Math.round(U*2)));
    sp.x += sp.vx; sp.y += sp.vy; sp.vy += 0.06; sp.life--;
    if (sp.life <= 0) a.spark.splice(s, 1);
  }

  // ── TOOL BUBBLE ──
  if (a.tools.length > 0) {
    drawBubble(a.tools[a.tools.length - 1], a.x, oy - Math.round(U*4), active, sc);
  }

  // ── NAME LABEL ──
  var nameY = oy - (a.tools.length > 0 ? Math.round(U*24) : Math.round(U*7));
  ctx.font = Math.round(Math.max(8, 10*sc)) + 'px "Courier New",monospace';
  ctx.textAlign    = 'center';
  ctx.textBaseline = 'bottom';
  ctx.fillStyle    = 'rgba(180,215,255,0.80)';
  ctx.fillText(a.name, a.x, nameY);

  ctx.restore();
}

// ── [old PNG spritesheet drawAgentSprite removed — superseded] ────────────────
function _deadAgentSprite(a) {
  var sc    = perspScale(a.y);
  var destH = Math.round(SPRITE_BASE_H * sc);
  var destW = Math.round(SPRITE_CW * (destH / SPRITE_CH));

  // Cycle through 8 seated frames slowly (one frame every 20 ticks ≈ 3fps)
  var frameIdx = Math.floor(tick / 20) % SPRITE_COLS;
  var srcX = frameIdx * SPRITE_CW;
  var srcY = SPRITE_ROW  * SPRITE_CH;

  // Content alternates left/right within each cell — pick correct center
  var rawCX  = (frameIdx % 2 === 0) ? SPRITE_CX_EVEN : SPRITE_CX_ODD;
  var contentCX = Math.round(rawCX * (destH / SPRITE_CH));
  var dx = Math.round(a.x - contentCX);
  var dy = Math.round(a.y - destH);

  ctx.save();
  ctx.imageSmoothingEnabled = false;
  ctx.drawImage(spriteImg, srcX, srcY, SPRITE_CW, SPRITE_CH, dx, dy, destW, destH);

  // ── Status LED (top-right corner of sprite) ──
  var ledX = dx + destW - Math.round(4 * sc);
  var ledY = dy + Math.round(destH * 0.12);
  var lr   = Math.max(2, Math.round(3 * sc));
  if (a.status === 'active') {
    ctx.fillStyle = '#22ff66';
    ctx.beginPath(); ctx.arc(ledX, ledY, lr, 0, Math.PI*2); ctx.fill();
    ctx.fillStyle = 'rgba(34,255,100,0.28)';
    ctx.beginPath(); ctx.arc(ledX, ledY, lr * 2.8, 0, Math.PI*2); ctx.fill();
    if (tick % 10 === 0) {
      a.spark.push({ x: a.x, y: dy + Math.round(destH * 0.25),
        vx: (Math.random()-0.5)*sc*1.5, vy: (-1.5-Math.random())*sc, life: 20 });
    }
  } else if (a.status === 'waiting') {
    ctx.fillStyle = '#ffaa22';
    ctx.beginPath(); ctx.arc(ledX, ledY, lr, 0, Math.PI*2); ctx.fill();
    ctx.fillStyle = 'rgba(255,170,34,0.22)';
    ctx.beginPath(); ctx.arc(ledX, ledY, lr * 2, 0, Math.PI*2); ctx.fill();
  } else {
    ctx.fillStyle = '#1a3399';
    ctx.beginPath(); ctx.arc(ledX, ledY, Math.max(1,lr-1), 0, Math.PI*2); ctx.fill();
  }

  // ── Sparks ──
  for (var s = a.spark.length - 1; s >= 0; s--) {
    var sp = a.spark[s];
    var alpha = sp.life / 20;
    ctx.fillStyle = 'rgba(80,255,160,' + alpha.toFixed(2) + ')';
    ctx.fillRect(sp.x|0, sp.y|0, Math.max(1,Math.round(sc*2)), Math.max(1,Math.round(sc*2)));
    sp.x += sp.vx; sp.y += sp.vy; sp.vy += 0.06; sp.life--;
    if (sp.life <= 0) a.spark.splice(s, 1);
  }

  // ── Tool bubble ──
  if (a.tools.length > 0) {
    drawBubble(a.tools[a.tools.length-1], a.x, dy - Math.round(sc*4), a.status === 'active', sc);
  }

  // ── Name label ──
  var nameY = dy - (a.tools.length > 0 ? Math.round(sc*24) : Math.round(sc*6));
  ctx.font = Math.round(Math.max(8, 10*sc)) + 'px "Courier New",monospace';
  ctx.textAlign    = 'center';
  ctx.textBaseline = 'bottom';
  ctx.fillStyle    = 'rgba(180,215,255,0.85)';
  ctx.fillText(a.name, a.x, nameY);

  ctx.restore();
}

// ── Queue & Pipeline Agent System ─────────────────────────────────────────────
// Queue: left-to-right in front of TV wall. [0]=front (leftmost, served first).
// Pipeline: one agent per transcript, walks desks in order, waits for real events.
// Failure: stall timeout → agent walks back to right end of queue.

var QUEUE_BASE_X  = 90;   // x of slot 0 (front of queue, near TV left edge)
var QUEUE_Y       = 405;  // y of queue (floor just below TV)
var QUEUE_SPACING = 36;   // px between slots

var agentQueue    = [];   // waiting agents, index 0 = front (leftmost)
var pipelineAgents = [];  // in-flight agents walking the desk circuit
var _agentSeq     = 0;

function queueSlotX(idx) { return QUEUE_BASE_X + idx * QUEUE_SPACING; }

function _makeAgent(id) {
  return {
    id: id, label: '.' + id,
    x: 0, y: QUEUE_Y, tx: 0, ty: QUEUE_Y,
    vx: 0, vy: 0, dir: 'back',
    state: 'inQueue', stallTimer: 0,
    status: 'idle', spark: [], tools: [],
  };
}

// Add a fresh agent to the back of the queue
function spawnQueueAgent() {
  _agentSeq++;
  var a    = _makeAgent(_agentSeq);
  var slot = agentQueue.length;
  a.tx = queueSlotX(slot);
  a.x  = queueSlotX(slot) + 80; // enter from the right
  agentQueue.push(a);
}

// Take the front agent, assign it to a transcript, spawn a replacement
function assignNextAgent() {
  _dbgAssign++;
  if (agentQueue.length === 0) spawnQueueAgent();
  var a = agentQueue.shift();           // front (leftmost)
  agentQueue.forEach(function (qa, i) { // shift remaining left
    qa.tx = queueSlotX(i); qa.ty = QUEUE_Y;
  });
  a.state = 'toComms';
  a.tx    = DESKS[0].x;
  a.ty    = DESKS[0].y + DESK_STAND_OFFSET;
  pipelineAgents.push(a);
  spawnQueueAgent();                    // always keep queue populated
}

// State ordering — used by advancePipeline to find agents that haven't arrived yet.
var _STATE_ORDER = [
  'inQueue',
  'toComms',      'atComms',
  'toAnalysis',   'atAnalysis',
  'toProjects',   'atProjects',
  'toApproval',   'atApproval',   // Approval desk (was Claude Code)
  'toClaude',     'atClaude',     // Claude Code desk (was QA)
  'toArchive',    'atArchive',
  'leaving',
];

// Advance whichever pipeline agent is AT or WALKING TOWARD fromState.
// If the agent is exactly at fromState it advances immediately.
// If it is still en route (e.g. 'toComms' when fromState='atComms'), the
// advance is stored as a pending intent (_nextState/_nextDesk) and applied
// automatically the moment the agent arrives — so no event is ever dropped.
function advancePipeline(fromState, toState, deskIdx) {
  _dbgAdvance++;
  var fromIdx = _STATE_ORDER.indexOf(fromState);
  var best = null, bestIdx = -1;

  for (var i = 0; i < pipelineAgents.length; i++) {
    var pa = pipelineAgents[i];
    var paIdx = _STATE_ORDER.indexOf(pa.state);
    // Agent must be at or before fromState (hasn't passed it yet),
    // and must be the furthest-along eligible agent (closest to fromState).
    if (paIdx >= 1 && paIdx <= fromIdx && paIdx > bestIdx) {
      best = pa; bestIdx = paIdx;
    }
  }

  if (best) {
    if (_STATE_ORDER.indexOf(best.state) === fromIdx) {
      // Exactly at fromState — advance immediately
      best.state      = toState;
      best.stallTimer = 0;
      best.status     = 'idle';
      best.tx = DESKS[deskIdx].x;
      best.ty = DESKS[deskIdx].y + DESK_STAND_OFFSET;
    } else {
      // Still walking toward fromState — queue for when it arrives
      best._nextState = toState;
      best._nextDesk  = deskIdx;
    }
  }
}

// Apply a queued pending advance immediately (called on desk arrival).
function _applyPending(pa) {
  if (pa._nextState) {
    pa.state = pa._nextState; pa.stallTimer = 0; pa.status = 'idle';
    pa.tx = DESKS[pa._nextDesk].x; pa.ty = DESKS[pa._nextDesk].y + DESK_STAND_OFFSET;
    pa._nextState = null; pa._nextDesk = null;
  }
}

// Eject a failed agent from the pipeline back to the right end of the queue
function returnToQueue(pa) {
  var idx = pipelineAgents.indexOf(pa);
  if (idx !== -1) pipelineAgents.splice(idx, 1);
  pa.status = 'idle'; pa.stallTimer = 0; pa.state = 'inQueue';
  agentQueue.push(pa); // queue updater will set correct tx/ty next frame
}

// ── Movement helpers ──────────────────────────────────────────────────────────
var WALK_SPEED = 1.8; // base px/tick at perspScale=1.0

function walkDir(vx, vy) {
  if (Math.abs(vy) > Math.abs(vx) * 0.5) {
    return 'front';  // always show front face — back sprites not used while walking
  }
  return vx < 0 ? 'left' : 'right';
}

function randomWaypoint() {
  return WAYPOINTS[Math.floor(Math.random() * WAYPOINTS.length)];
}

// Move entity toward (tx,ty). Returns true when arrived.
function moveToward(e, speed) {
  var dx = e.tx - e.x, dy = e.ty - e.y;
  var dist = Math.sqrt(dx * dx + dy * dy);
  if (dist < 2) {
    e.x = e.tx; e.y = e.ty; e.vx = 0; e.vy = 0;
    return true;
  }
  var spd = speed * perspScale(e.y);
  e.vx = (dx / dist) * spd;
  e.vy = (dy / dist) * spd;
  e.x += e.vx; e.y += e.vy;
  e.dir = walkDir(e.vx, e.vy);
  return false;
}

function updateAgents() {
  Object.values(agents).forEach(function (a) {
    if (a.moveState === 'seated') {
      a.vx = 0; a.vy = 0;
      if (a.status !== 'active') {   // don't pull active agents away
        a.breakTimer--;
        if (a.breakTimer <= 0) {
          var wp = randomWaypoint();
          a.tx = wp.x; a.ty = wp.y;
          a.moveState = 'walkingOut';
        }
      }
    } else if (a.moveState === 'walkingOut') {
      if (moveToward(a, WALK_SPEED)) {
        a.moveState  = 'returning';
        a.idleTimer  = 60 + Math.round(Math.random() * 120);
      }
    } else if (a.moveState === 'returning') {
      a.vx = 0; a.vy = 0;
      a.idleTimer--;
      if (a.idleTimer <= 0) {
        var seat = SEATS[a.seatId];
        a.tx = seat.x; a.ty = seat.y;
        a.moveState = 'walkingBack';
      }
    } else if (a.moveState === 'walkingBack') {
      if (moveToward(a, WALK_SPEED)) {
        a.moveState  = 'seated';
        a.breakTimer = 600 + Math.round(Math.random() * 900);
      }
    }
  });
}

// Ticks waiting at a desk before giving up and re-queuing (~10s at 60fps)
var STALL_TIMEOUT  = 600;
// Ticks to celebrate at Archive before walking off (~1.5s at 60fps)
var ARCHIVE_DWELL  = 90;

function updatePipelineAgents() {
  // ── Queue agents: slide each one toward its slot position ──────────────────
  agentQueue.forEach(function (qa, i) {
    qa.tx = queueSlotX(i);
    qa.ty = QUEUE_Y;
    var arrived = moveToward(qa, WALK_SPEED);
    if (arrived) qa.dir = 'back'; // face the TV when waiting
  });

  // ── Pipeline agents: event-driven state machine ───────────────────────────
  for (var i = pipelineAgents.length - 1; i >= 0; i--) {
    var pa = pipelineAgents[i];

    // ── Walking states → arrive → flip to 'at...' waiting state ─────────────
    if (pa.state === 'toComms') {
      if (moveToward(pa, WALK_SPEED)) {
        pa.state = 'atComms'; pa.stallTimer = 0; pa.status = 'active';
        _applyPending(pa);   // fire queued advance if pipeline event arrived early
      }
    } else if (pa.state === 'toAnalysis') {
      if (moveToward(pa, WALK_SPEED)) {
        pa.state = 'atAnalysis'; pa.stallTimer = 0; pa.status = 'active';
        _applyPending(pa);
      }
    } else if (pa.state === 'toProjects') {
      if (moveToward(pa, WALK_SPEED)) {
        pa.state = 'atProjects'; pa.stallTimer = 0; pa.status = 'active';
        _applyPending(pa);
      }
    } else if (pa.state === 'toApproval') {
      if (moveToward(pa, WALK_SPEED)) {
        pa.state = 'atApproval'; pa.stallTimer = 0; pa.status = 'active';
        _applyPending(pa);
      }
    } else if (pa.state === 'toClaude') {
      if (moveToward(pa, WALK_SPEED)) {
        pa.state = 'atClaude'; pa.stallTimer = 0; pa.status = 'active';
      }
    } else if (pa.state === 'toArchive') {
      if (moveToward(pa, WALK_SPEED)) {
        pa.state = 'atArchive'; pa.stallTimer = 0; pa.status = 'active';
      }

    // ── Waiting states: stand still; only move when advancePipeline() fires ──
    } else if (pa.state === 'atComms' || pa.state === 'atAnalysis' ||
               pa.state === 'atProjects' || pa.state === 'atApproval' ||
               pa.state === 'atClaude') {
      pa.vx = 0; pa.vy = 0;
      // If a pending advance was queued (pipeline fired while still en route),
      // dwell briefly at this desk then auto-apply it (~0.7 s at 60 fps).
      if (pa._nextState) {
        pa.stallTimer++;
        if (pa.stallTimer >= 40) {
          pa.state = pa._nextState; pa.stallTimer = 0; pa.status = 'idle';
          pa.tx = DESKS[pa._nextDesk].x; pa.ty = DESKS[pa._nextDesk].y + DESK_STAND_OFFSET;
          pa._nextState = null; pa._nextDesk = null;
        }
      }
      // No stall timeout — agents wait indefinitely for real pipeline events

    // ── Archive: brief celebration dwell → then leave ─────────────────────────
    } else if (pa.state === 'atArchive') {
      pa.vx = 0; pa.vy = 0;
      pa.stallTimer++;
      if (pa.stallTimer >= ARCHIVE_DWELL) {
        pa.state  = 'leaving';
        pa.status = 'idle';
        pa.tx     = pa.x;
        pa.ty     = FLOOR_BOT + 80; // walk off bottom edge
      }

    // ── Leaving: walk off screen then remove ──────────────────────────────────
    } else if (pa.state === 'leaving') {
      moveToward(pa, WALK_SPEED);
      if (pa.y >= FLOOR_BOT + 40) {
        pipelineAgents.splice(i, 1);
      }
    }
  }
}

// ── Draw a walking character using StandingA sprites ─────────────────────────
function drawWalker(a) {
  var sc    = perspScale(a.y);
  var dir   = a.dir || 'front';
  var moving = Math.abs(a.vx) > 0.05 || Math.abs(a.vy) > 0.05;
  var wf    = Math.floor(tick / 10) % 2 === 0 ? '1' : '2';
  var key   = moving ? (dir + wf)
            : (dir === 'back' ? 'backStand' : 'frontStand');
  var img   = WALKER[key] || WALKER['frontStand'];

  if (!img) return;

  var destH = Math.round(WALKER_BASE_H * sc);
  var destW = Math.round(640 * (destH / 1120));
  var dx    = Math.round(a.x - destW * WALKER_CX_FRAC);
  var dy    = Math.round(a.y - destH * WALKER_BY_FRAC);

  ctx.save();
  ctx.imageSmoothingEnabled = false;

  // Ground shadow
  ctx.fillStyle = 'rgba(0,0,0,0.22)';
  ctx.beginPath();
  ctx.ellipse(a.x, a.y + 1, destW * 0.38, destW * 0.12, 0, 0, Math.PI * 2);
  ctx.fill();

  ctx.drawImage(img, 0, 0, 640, 1120, dx, dy, destW, destH);

  // Name label (queue agents use .label, others may have .name)
  var nameY = dy - Math.round(sc * 5);
  ctx.font          = Math.round(Math.max(8, 10 * sc)) + 'px "Courier New",monospace';
  ctx.textAlign     = 'center';
  ctx.textBaseline  = 'bottom';
  ctx.fillStyle     = 'rgba(180,215,255,0.85)';
  ctx.fillText(a.label || a.name || '', a.x, nameY);

  ctx.restore();
}

function drawBubble(text, cx, ty, active, sc) {
  var maxLen = 18;
  if (text.length > maxLen) text = text.slice(0, maxLen) + '…';
  var fs = Math.round(Math.max(8, 10 * sc));
  ctx.font = fs + 'px "Courier New",monospace';
  var tw = ctx.measureText(text).width;
  var bw = Math.max(tw + 12, 40 * sc), bh = Math.max(14, 16 * sc);
  var bx = cx - bw/2, by = ty - bh - 4;

  ctx.fillStyle = 'rgba(6,10,26,0.93)';
  rrect(bx, by, bw, bh, 3 * sc); ctx.fill();
  ctx.strokeStyle = active ? 'rgba(34,255,100,0.8)' : 'rgba(55,80,170,0.65)';
  ctx.lineWidth   = Math.max(0.5, sc);
  rrect(bx, by, bw, bh, 3 * sc); ctx.stroke();

  ctx.fillStyle    = active ? '#44ffaa' : '#88aaff';
  ctx.textAlign    = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(text, cx, by + bh / 2);
  ctx.textAlign = 'left';

  // tail
  ctx.fillStyle = 'rgba(6,10,26,0.93)';
  ctx.beginPath();
  ctx.moveTo(cx - 3*sc, by+bh);
  ctx.lineTo(cx + 3*sc, by+bh);
  ctx.lineTo(cx, by + bh + 5*sc);
  ctx.closePath(); ctx.fill();
}

// ── Diagnostic counters (shown as HUD) ────────────────────────────────────────
var _dbgAssign   = 0;   // times assignNextAgent called
var _dbgAdvance  = 0;   // times advancePipeline called
var _dbgReady    = false; // did window.notifyReady() fire?
window.notifyReady = function() { _dbgReady = true; };

// ── Big Screen Slideshow ──────────────────────────────────────────────────────
// Covers the three dark panels on the back wall (canvas coords in 960×648 space)
var SCREEN = { x: 280, y: 48, w: 404, h: 244 }; // centre panel (exact coords)

var _bsImgs    = [];
var _bsLoaded  = 0;
;(function () {
  var files = [
    './bigscreen/big1.png',
    './bigscreen/big2.png',
    './bigscreen/big3.png',
  ];
  files.forEach(function (f, i) {
    var img = new Image();
    img.onload  = function () { _bsImgs[i] = img; _bsLoaded++; };
    img.onerror = function () { _bsLoaded++; }; // don't stall on missing file
    img.src = f;
  });
})();

var _bsCur   = 0;   // index of image currently on screen
var _bsAlpha = 0;   // crossfade progress 0→1
var _bsTick  = 0;   // ticks spent on this slide
var BS_HOLD  = 240; // ticks to hold each image (~4s at 60fps)
var BS_FADE  = 80;  // ticks to crossfade (~1.3s)

function drawBigScreen() {
  if (_bsLoaded === 0 || _bsImgs.length === 0) return;
  var n = _bsImgs.length;

  ctx.save();
  ctx.imageSmoothingEnabled = true;
  ctx.imageSmoothingQuality = 'high';

  // Clip to screen area so nothing bleeds outside the panels
  ctx.beginPath();
  ctx.rect(SCREEN.x, SCREEN.y, SCREEN.w, SCREEN.h);
  ctx.clip();

  // Current image
  var cur = _bsImgs[_bsCur % n];
  if (cur && cur.complete) ctx.drawImage(cur, SCREEN.x, SCREEN.y, SCREEN.w, SCREEN.h);

  // Fade in next image on top
  if (_bsAlpha > 0) {
    var nxt = _bsImgs[(_bsCur + 1) % n];
    if (nxt && nxt.complete) {
      ctx.globalAlpha = _bsAlpha;
      ctx.drawImage(nxt, SCREEN.x, SCREEN.y, SCREEN.w, SCREEN.h);
      ctx.globalAlpha = 1;
    }
  }

  // Subtle scanline overlay so it feels like a screen, not a photo
  ctx.fillStyle = 'rgba(0,0,0,0.08)';
  for (var sy = SCREEN.y; sy < SCREEN.y + SCREEN.h; sy += 3) {
    ctx.fillRect(SCREEN.x, sy, SCREEN.w, 1);
  }

  ctx.restore();

  // Advance slide timer
  _bsTick++;
  if (_bsTick >= BS_HOLD) {
    _bsAlpha = (_bsTick - BS_HOLD) / BS_FADE;
    if (_bsAlpha >= 1) {
      _bsCur   = (_bsCur + 1) % n;
      _bsAlpha = 0;
      _bsTick  = 0;
    }
  }
}

// ── Side Screen — Pipeline Status Panel ──────────────────────────────────────
// Left panel of the back wall: top-left (104,48) → bottom-right (264,292)
var SIDE_SCREEN = { x: 104, y: 48, w: 160, h: 244 };

var PIPELINE_STAGES = [
  { label: 'Queue',       states: ['inQueue'] },
  { label: 'Comms',       states: ['toComms',    'atComms'] },
  { label: 'Analysis',    states: ['toAnalysis', 'atAnalysis'] },
  { label: 'Projects',    states: ['toProjects', 'atProjects'] },
  { label: 'Approval',    states: ['toApproval', 'atApproval'] },
  { label: 'Claude Code', states: ['toClaude',   'atClaude'] },
  { label: 'Archive',     states: ['toArchive',  'atArchive', 'leaving'] },
];

var _ssPanelAgent = 0;  // index into agentQueue ++ pipelineAgents
function _ssAll() { return agentQueue.concat(pipelineAgents); }

function drawSideScreen() {
  var ss  = SIDE_SCREEN;
  var all = _ssAll();
  ctx.save();

  // Background
  ctx.fillStyle = '#04080f';
  ctx.fillRect(ss.x, ss.y, ss.w, ss.h);

  // Scanlines
  ctx.fillStyle = 'rgba(0,20,60,0.18)';
  for (var sl = 0; sl < ss.h; sl += 3) {
    ctx.fillRect(ss.x, ss.y + sl, ss.w, 1);
  }

  // Screen border
  ctx.strokeStyle = '#0a2040';
  ctx.lineWidth = 1;
  ctx.strokeRect(ss.x + 0.5, ss.y + 0.5, ss.w - 1, ss.h - 1);

  // ── Header ───────────────────────────────────────────────────────────────────
  ctx.fillStyle = 'rgba(100,180,255,0.10)';
  ctx.fillRect(ss.x, ss.y, ss.w, 22);
  ctx.font = 'bold 8px "Courier New",monospace';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillStyle = 'rgba(100,190,255,0.85)';
  ctx.fillText('PIPELINE STATUS', ss.x + ss.w / 2, ss.y + 11);
  ctx.fillStyle = '#0a2040';
  ctx.fillRect(ss.x, ss.y + 22, ss.w, 1);

  // ── Agent selector ───────────────────────────────────────────────────────────
  var selY = ss.y + 34;

  if (all.length === 0) {
    ctx.fillStyle = '#1a3a5a';
    ctx.font = '8px "Courier New",monospace';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText('NO AGENTS', ss.x + ss.w / 2, selY);
    ctx.restore();
    return;
  }

  if (_ssPanelAgent >= all.length) _ssPanelAgent = 0;
  var agent   = all[_ssPanelAgent];
  var hasMany = all.length > 1;

  // ◄ ► arrows
  ctx.font = '11px "Courier New",monospace';
  ctx.textBaseline = 'middle';
  ctx.fillStyle = hasMany ? 'rgba(68,170,255,0.90)' : 'rgba(40,70,110,0.35)';
  ctx.textAlign = 'left';
  ctx.fillText('\u25c4', ss.x + 7, selY);
  ctx.textAlign = 'right';
  ctx.fillText('\u25ba', ss.x + ss.w - 7, selY);

  // Agent name
  var agentName = agent.label || agent.name || ('Agent ' + (_ssPanelAgent + 1));
  ctx.fillStyle = '#a0d0ff';
  ctx.font = 'bold 8px "Courier New",monospace';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(agentName, ss.x + ss.w / 2, selY);

  // n / total
  if (hasMany) {
    ctx.fillStyle = 'rgba(60,100,160,0.8)';
    ctx.font = '7px "Courier New",monospace';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText((_ssPanelAgent + 1) + ' / ' + all.length, ss.x + ss.w / 2, selY + 11);
  }

  // ── Pipeline stages ───────────────────────────────────────────────────────────
  var stagesTop = ss.y + (hasMany ? 53 : 47);
  var stagesBot = ss.y + ss.h - 6;
  var stageH    = Math.floor((stagesBot - stagesTop) / PIPELINE_STAGES.length);
  var dotX      = ss.x + 18;

  // Find active stage
  var curStage = -1;
  for (var si = 0; si < PIPELINE_STAGES.length; si++) {
    if (PIPELINE_STAGES[si].states.indexOf(agent.state) >= 0) {
      curStage = si; break;
    }
  }

  for (var i = 0; i < PIPELINE_STAGES.length; i++) {
    var stage    = PIPELINE_STAGES[i];
    var isActive = (i === curStage);
    var isPast   = (curStage > 0 && i < curStage);
    var stageY   = stagesTop + i * stageH + Math.floor(stageH / 2);

    // Connector line to next dot
    if (i < PIPELINE_STAGES.length - 1) {
      var nextDotY = stagesTop + (i + 1) * stageH + Math.floor(stageH / 2);
      ctx.strokeStyle = isPast ? '#1a6040' : '#0a1828';
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(dotX, stageY + 5);
      ctx.lineTo(dotX, nextDotY - 5);
      ctx.stroke();
    }

    // Pulsing glow halo on active dot
    if (isActive) {
      var pulse = 0.5 + 0.5 * Math.sin(tick * 0.08);
      ctx.fillStyle = 'rgba(68,255,160,' + (0.12 + 0.10 * pulse) + ')';
      ctx.beginPath();
      ctx.arc(dotX, stageY, 9, 0, Math.PI * 2);
      ctx.fill();
    }

    // Dot
    ctx.fillStyle = isActive ? '#44ffaa' : isPast ? '#1a8050' : '#0c1a28';
    ctx.beginPath();
    ctx.arc(dotX, stageY, isActive ? 5 : 3, 0, Math.PI * 2);
    ctx.fill();
    if (isActive || isPast) {
      ctx.strokeStyle = isActive ? '#44ffaa' : '#155535';
      ctx.lineWidth = 0.5;
      ctx.stroke();
    }

    // Stage label
    ctx.font = isActive ? 'bold 8px "Courier New",monospace'
                        : '8px "Courier New",monospace';
    ctx.fillStyle    = isActive ? '#44ffaa' : isPast ? '#28805a' : '#1a3a5a';
    ctx.textAlign    = 'left';
    ctx.textBaseline = 'middle';
    ctx.fillText(stage.label, dotX + 13, stageY);

    // Walking arrow → on right edge when en route to this stage
    var atState = stage.states[stage.states.length - 1];
    if (isActive && agent.state !== atState && agent.state !== 'inQueue') {
      ctx.fillStyle = 'rgba(68,255,160,0.55)';
      ctx.font = '8px "Courier New",monospace';
      ctx.textAlign = 'right';
      ctx.fillText('\u2192', ss.x + ss.w - 7, stageY);
    }
  }

  ctx.restore();
}

// mousedown handler for ◄ ► arrows on the side screen.
// Left half of the selector row = prev agent, right half = next agent.
canvas.addEventListener('mousedown', function (e) {
  var rect = canvas.getBoundingClientRect();
  var cx   = (e.clientX - rect.left) * (BG_W / rect.width);
  var cy   = (e.clientY - rect.top)  * (BG_H / rect.height);
  var ss   = SIDE_SCREEN;
  var selY = ss.y + 34;
  var n    = _ssAll().length;
  if (n < 2) return;
  // Entire side-screen width, generous ±16px vertical band around selY
  if (cx < ss.x || cx > ss.x + ss.w) return;
  if (cy < selY - 16 || cy > selY + 16) return;
  var mid = ss.x + ss.w / 2;
  if (cx < mid)
    _ssPanelAgent = (_ssPanelAgent - 1 + n) % n;
  else
    _ssPanelAgent = (_ssPanelAgent + 1) % n;
  e.preventDefault();
});

// Pointer cursor when hovering over the agent selector row
canvas.addEventListener('mousemove', function (e) {
  var rect = canvas.getBoundingClientRect();
  var cx   = (e.clientX - rect.left) * (BG_W / rect.width);
  var cy   = (e.clientY - rect.top)  * (BG_H / rect.height);
  var ss   = SIDE_SCREEN;
  var selY = ss.y + 34;
  var inZone = cx >= ss.x && cx <= ss.x + ss.w &&
               cy >= selY - 16 && cy <= selY + 16 &&
               _ssAll().length > 1;
  canvas.style.cursor = inZone ? 'pointer' : 'default';
});

// ── Main render loop ──────────────────────────────────────────────────────────
var tick = 0;

function frame() {
  tick++;
  ctx.clearRect(0, 0, BG_W, BG_H);

  // Back-wall screens — agents walk in front of them
  drawBigScreen();
  drawSideScreen();

  // Update pipeline agents
  updatePipelineAgents();

  // ── HUD: debug status line ─────────────────────────────────────────────────
  ctx.save();
  ctx.font = '11px "Courier New",monospace';
  ctx.textAlign = 'left';
  ctx.textBaseline = 'top';
  ctx.fillStyle = _dbgReady ? 'rgba(50,255,100,0.85)' : 'rgba(255,100,50,0.85)';
  ctx.fillText(
    'ready:' + (_dbgReady ? 'Y' : 'N') +
    ' q:' + agentQueue.length +
    ' p:' + pipelineAgents.length +
    ' assign:' + _dbgAssign +
    ' advance:' + _dbgAdvance,
    8, 8
  );
  ctx.restore();

  // Build draw list — desks always visible; all agents (queue + pipeline) sorted by y
  var drawList = [];

  DESKS.forEach(function (d) {
    drawList.push({ kind: 'desk', y: d.y, obj: d });
  });

  // Queue agents waiting near the TV wall
  agentQueue.forEach(function (qa) {
    drawList.push({ kind: 'walker', y: qa.y, obj: qa });
  });

  // Pipeline agents walking the desk circuit
  pipelineAgents.forEach(function (pa) {
    drawList.push({ kind: 'walker', y: pa.y, obj: pa });
  });

  // Back-to-front sort for perspective layering
  drawList.sort(function (a, b) { return a.y - b.y; });

  drawList.forEach(function (item) {
    if      (item.kind === 'desk')   drawDesk(item.obj);
    else if (item.kind === 'walker') drawWalker(item.obj);
  });

  requestAnimationFrame(frame);
}

requestAnimationFrame(frame);

// Reset all pipeline agents back to the queue
function resetPipeline() {
  while (pipelineAgents.length > 0) {
    returnToQueue(pipelineAgents[0]);
  }
}

// Expose for console testing and Swift bridge
window.spawnQueueAgent    = spawnQueueAgent;
window.assignNextAgent    = assignNextAgent;
window.advancePipeline    = advancePipeline;
window.returnToQueue      = returnToQueue;
window.resetPipeline      = resetPipeline;

// Diagnostic dump — called by Swift after assignNextAgent to verify state
window._dbgDump = function() {
  return 'q:' + agentQueue.length +
         ' p:' + pipelineAgents.length +
         ' assign:' + _dbgAssign +
         ' advance:' + _dbgAdvance +
         ' sprites:' + walkerLoaded +
         ' pStates:' + pipelineAgents.map(function(a){return a.state}).join(',') +
         ' qPos:' + agentQueue.map(function(a){return Math.round(a.x)+','+Math.round(a.y)}).join('|') +
         ' pPos:' + pipelineAgents.map(function(a){return Math.round(a.x)+','+Math.round(a.y)}).join('|');
};

// Pre-populate the queue with 3 waiting agents so the scene isn't empty
setTimeout(function () {
  spawnQueueAgent();
  spawnQueueAgent();
  spawnQueueAgent();
}, 500);

})();
