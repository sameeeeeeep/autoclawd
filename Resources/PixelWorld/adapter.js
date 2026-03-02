// AutoClawd → pixel-agents bridge
// Provides VS Code API mock, hides editor chrome, and routes pipeline events.

// ── 1. Inject CSS to hide editor chrome ──────────────────────────────────────
;(function injectCSS() {
  var s = document.createElement('style')
  s.textContent = [
    'html,body,#root { width:100%;height:100%;margin:0;overflow:hidden; }',
    // Hide bottom toolbar (+Agent / Layout / Settings) — inline style bottom:10px
    '[style*="bottom: 10px"],[style*="bottom:10px"] { display:none !important; }',
    // Hide zoom controls — container is position:absolute; top: 8px; left: 8px
    '[style*="top: 8px"][style*="left: 8px"] { display:none !important; }',
  ].join('\n')
  document.head.appendChild(s)

  // Poll until React mounts and hide chrome controls
  var _hideInterval = setInterval(function() {
    var found = false
    document.querySelectorAll('[style]').forEach(function(el) {
      var st = el.getAttribute('style') || ''
      if (st.indexOf('top: 8px') !== -1 && st.indexOf('left: 8px') !== -1) {
        el.style.setProperty('display', 'none', 'important')
        found = true
      }
      if (st.indexOf('bottom: 10px') !== -1 || st.indexOf('bottom:10px') !== -1) {
        el.style.setProperty('display', 'none', 'important')
      }
    })
    if (found) clearInterval(_hideInterval)
  }, 100)
})()

// ── 2. Helper: dispatch a message to the React app ───────────────────────────
function dispatch(data) {
  window.dispatchEvent(new MessageEvent('message', { data: data }))
}

// ── 3. VS Code API mock ───────────────────────────────────────────────────────
var _ready = false
window.acquireVsCodeApi = function() {
  return {
    postMessage: function(msg) {
      try {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.worldBridge) {
          window.webkit.messageHandlers.worldBridge.postMessage(JSON.stringify(msg))
        }
      } catch(e) {}
      if (msg && msg.type === 'webviewReady' && !_ready) {
        _ready = true
        setTimeout(_initPixelWorld, 80)
      }
    },
    getState: function() { return null },
    setState: function() {}
  }
}

// ── 4. Mission Control layout ─────────────────────────────────────────────────
function _buildLayout() {
  var COLS = 20, ROWS = 11
  var W=0, F1=1, F2=2, F3=3, F4=4
  var tiles = [], tileColors = []

  // Cool blue-grey for Mission Control (left room)
  var MC = {h:220, s:30, b:5,  c:0}
  // Dark teal for Claude Lab (right room)
  var CL = {h:190, s:35, b:-8, c:5}
  // Purple carpet accent in Claude Lab corner
  var CP = {h:280, s:40, b:-5, c:0}
  // Doorway transition
  var DW = {h:210, s:20, b:2,  c:0}

  for (var r=0; r<ROWS; r++) {
    for (var c=0; c<COLS; c++) {
      if (r===0||r===ROWS-1||c===0||c===COLS-1) {
        tiles.push(W); tileColors.push(null)
      } else if (c===10) {
        if (r>=4&&r<=6) { tiles.push(F4); tileColors.push(DW) }
        else             { tiles.push(W);  tileColors.push(null) }
      } else if (c<10) {
        tiles.push(F1); tileColors.push(MC)
      } else {
        if (c>=15&&c<=18&&r>=7&&r<=9) { tiles.push(F3); tileColors.push(CP) }
        else                           { tiles.push(F2); tileColors.push(CL) }
      }
    }
  }

  // Desk helper: given top-left (dc,dr), returns desk + 4 surrounding chairs
  // Pattern for 2×2 desk footprint at (dc,dr):
  //   top chair:    (dc,   dr-1)
  //   bottom chair: (dc+1, dr+2)
  //   left chair:   (dc-1, dr+1)
  //   right chair:  (dc+2, dr)
  function desk(uid, dc, dr) {
    return [
      {uid: uid,          type:'desk',  col:dc,   row:dr},
      {uid: uid+'-ct',    type:'chair', col:dc,   row:dr-1},
      {uid: uid+'-cb',    type:'chair', col:dc+1, row:dr+2},
      {uid: uid+'-cl',    type:'chair', col:dc-1, row:dr+1},
      {uid: uid+'-cr',    type:'chair', col:dc+2, row:dr},
    ]
  }

  var furniture = [].concat(
    // ── MISSION CONTROL (left room, cols 1-8) ──────────────────────────────
    desk('mc-d1', 3, 2),   // desk 1, top area  → chairs at (3,1)(4,4)(2,3)(5,2)
    desk('mc-d2', 3, 6),   // desk 2, bottom area → chairs at (3,5)(4,8)(2,7)(5,6)

    [
      {uid:'mc-wb',    type:'whiteboard', col:5, row:0},  // whiteboard on north wall
      {uid:'mc-shelf', type:'bookshelf',  col:7, row:3},  // bookshelf on right wall
      {uid:'mc-plant', type:'plant',      col:1, row:1},  // plant top-left
      {uid:'mc-lamp',  type:'lamp',       col:8, row:1},  // lamp by corridor
    ],

    // ── CLAUDE LAB (right room, cols 11-18) ────────────────────────────────
    desk('cl-d1', 13, 3),  // desk 3 → chairs at (13,2)(14,5)(12,4)(15,3)

    [
      {uid:'cl-wb',     type:'whiteboard', col:15, row:0}, // whiteboard on north wall
      {uid:'cl-plant',  type:'plant',      col:18, row:1}, // plant top-right
      {uid:'cl-cooler', type:'cooler',     col:17, row:7}, // cooler on carpet
      {uid:'cl-lamp1',  type:'lamp',       col:11, row:1}, // lamp by corridor
      {uid:'cl-lamp2',  type:'lamp',       col:11, row:8}, // lamp low-left
    ]
  )

  return {version:1, cols:COLS, rows:ROWS, tiles:tiles, tileColors:tileColors, furniture:furniture}
}

// ── 5. Init ───────────────────────────────────────────────────────────────────
function _initPixelWorld() {
  // Agents MUST be dispatched before layoutLoaded — the app buffers them
  // and adds them when the layout fires (builds seats first).
  dispatch({
    type: 'existingAgents',
    agents: [1, 2, 3, 4, 5, 6],
    agentMeta: {
      1: { palette: 0, seatId: 's1' },  // Writer    → left-back
      2: { palette: 1, seatId: 's2' },  // Analyst   → center-back
      3: { palette: 4, seatId: 's3' },  // TaskBot   → right-back
      4: { palette: 5, seatId: 's4' },  // Clawd     → left-front
      5: { palette: 2, seatId: 's5' },  // WA-Bot    → center-front
      6: { palette: 3, seatId: 's6' },  // Archivist → right-front
    },
    folderNames: {
      1:'Writer', 2:'Analyst', 3:'TaskBot',
      4:"Claw'd", 5:'WA-Bot',  6:'Archivist',
    }
  })

  // Layout fires second — processes buffered agents into available seats
  dispatch({ type: 'layoutLoaded', layout: _buildLayout() })
}

// ── 6. Pipeline event API — called by Swift ───────────────────────────────────
var _seq = 0
window.receiveEvent = function(type, data) {
  var id = ++_seq
  var tid = type + '_' + id

  if (type === 'transcript') {
    dispatch({ type:'agentToolsClear', id:1 })
    dispatch({ type:'agentToolStart',  id:1, toolId:tid, status:'Capturing transcript...' })
    dispatch({ type:'agentStatus',     id:1, status:'active' })

  } else if (type === 'cleaning') {
    dispatch({ type:'agentToolsClear', id:2 })
    dispatch({ type:'agentToolStart',  id:2, toolId:tid, status:'Cleaning transcript...' })
    dispatch({ type:'agentStatus',     id:2, status:'active' })
    setTimeout(function() { dispatch({ type:'agentToolsClear', id:1 }) }, 800)

  } else if (type === 'analysis') {
    dispatch({ type:'agentToolsClear', id:3 })
    dispatch({ type:'agentToolStart',  id:3, toolId:tid, status:'Analyzing pipeline...' })
    dispatch({ type:'agentStatus',     id:3, status:'active' })
    setTimeout(function() { dispatch({ type:'agentToolsClear', id:2 }) }, 600)

  } else if (type === 'task_created') {
    var title = (data && data.title) ? data.title : 'New Task'
    var mode  = (data && data.mode)  ? data.mode  : 'ask'
    dispatch({ type:'agentToolsClear', id:4 })
    dispatch({ type:'agentToolStart',  id:4, toolId:tid, status:title })
    dispatch({ type:'agentStatus',     id:4, status:'active' })
    setTimeout(function() { dispatch({ type:'agentToolsClear', id:3 }) }, 400)
    if (mode !== 'auto') {
      setTimeout(function() { dispatch({ type:'agentStatus', id:4, status:'waiting' }) }, 1200)
    }

  } else if (type === 'task_executing') {
    dispatch({ type:'agentToolStart', id:4, toolId:tid, status:'Running Claude Code...' })
    dispatch({ type:'agentStatus',    id:4, status:'active' })

  } else if (type === 'task_done') {
    dispatch({ type:'agentStatus', id:4, status:'waiting' })
    setTimeout(function() { dispatch({ type:'agentToolsClear', id:4 }) }, 2000)

  } else if (type === 'whatsapp') {
    dispatch({ type:'agentToolsClear', id:5 })
    dispatch({ type:'agentToolStart',  id:5, toolId:tid, status:'WhatsApp message...' })
    dispatch({ type:'agentStatus',     id:5, status:'active' })
    setTimeout(function() {
      dispatch({ type:'agentStatus', id:5, status:'waiting' })
      setTimeout(function() { dispatch({ type:'agentToolsClear', id:5 }) }, 1500)
    }, 3000)

  } else if (type === 'reset') {
    for (var i=1; i<=6; i++) dispatch({ type:'agentToolsClear', id:i })
  }
}

// ── 7. Focus helper ───────────────────────────────────────────────────────────
window.focusOn = function(name) {
  var map = {writer:1, analyst:2, taskbot:3, clawd:4, wabot:5, archivist:6}
  var i = map[name && name.toLowerCase()]
  if (i) dispatch({ type:'agentSelected', id:i })
}
