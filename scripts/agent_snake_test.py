#!/usr/bin/env python3
"""
Agent integration test: produce a Snake game via the DietCode Control Server.

Tests the new Bounded Autonomy / Permissionless RPC surface end-to-end:
  - rpc.ping / rpc.version  (Read)
  - session.info            (Read, background thread)
  - workspace.openFolder    (Destructive → auto-allowed: Permissionless)
  - verify.run              (Execute → auto-shown in terminal)
  - file.write              (Edit → create/overwrite file)
  - workspace.openFile      (Read)
  - file.stat               (Read, background thread)
  - analysis.workspaceSummary (Read, background thread)
"""

import socket, json, os, sys, pathlib, time

from dietcode_agent_client import SOCKET_PATH as SOCK, TOKEN_PATH as TOKEN_FILE, ensure_socket

# ─── Snake game ─────────────────────────────────────────────────────────────
SNAKE_HTML = """\
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Snake — DietCode Agent Test</title>
  <style>
    *{margin:0;padding:0;box-sizing:border-box}
    body{background:#0d0d1a;display:flex;flex-direction:column;align-items:center;
         justify-content:center;height:100vh;font-family:'Segoe UI',sans-serif;
         color:#e0e0ff;user-select:none}
    h1{font-size:2.5rem;letter-spacing:.15em;color:#7df9aa;margin-bottom:.4rem}
    #sub{color:#666;font-size:.8rem;margin-bottom:1rem}
    canvas{border:3px solid #7df9aa33;border-radius:8px;box-shadow:0 0 40px #7df9aa22}
    #hud{margin-top:1rem;font-size:1.1rem;color:#7df9aa;letter-spacing:.1em}
    #msg{margin-top:.6rem;font-size:.85rem;color:#ff6b6b;min-height:1.1em;text-align:center}
  </style>
</head>
<body>
  <h1>&#x1F40D; SNAKE</h1>
  <div id="sub">Created by DietCode Control Agent &mdash; Bounded Autonomy Mode</div>
  <canvas id="c" width="400" height="400"></canvas>
  <div id="hud">Score: <span id="sc">0</span> &nbsp;|&nbsp; Best: <span id="best">0</span></div>
  <div id="msg">Arrow keys / WASD &nbsp;&bull;&nbsp; Space to pause</div>
<script>
const G=20,C=20,cv=document.getElementById('c'),ctx=cv.getContext('2d');
const scEl=document.getElementById('sc'),bestEl=document.getElementById('best'),msgEl=document.getElementById('msg');
let sn,dir,nxt,food,sc,best=0,pause,dead,raf,last=0,spd=130;

const col={hd:'#7df9aa',bd:'#3ec97a',food:'#ff6b6b',eye:'#0d0d1a',bg:'#0d0d1a',grid:'#ffffff08'};

function rnd(n){return Math.floor(Math.random()*n)}
function newFood(){let p;do{p={x:rnd(G),y:rnd(G)}}while(sn.some(s=>s.x===p.x&&s.y===p.y));return p}

function init(){
  sn=[{x:10,y:10},{x:9,y:10},{x:8,y:10}];
  dir={x:1,y:0};nxt={x:1,y:0};food=newFood();
  sc=0;pause=false;dead=false;spd=130;
  scEl.textContent=0;msgEl.textContent='Arrow keys / WASD \u2022 Space to pause';
  if(raf)cancelAnimationFrame(raf);
  loop();
}

function loop(ts=0){
  raf=requestAnimationFrame(loop);
  if(pause||dead)return;
  if(ts-last<spd)return;
  last=ts;tick();draw();
}

function tick(){
  dir={...nxt};
  const h={x:sn[0].x+dir.x,y:sn[0].y+dir.y};
  if(h.x<0||h.x>=G||h.y<0||h.y>=G||sn.some(s=>s.x===h.x&&s.y===h.y)){gameOver();return}
  sn.unshift(h);
  if(h.x===food.x&&h.y===food.y){
    sc++;scEl.textContent=sc;
    if(sc>best){best=sc;bestEl.textContent=best}
    spd=Math.max(55,130-sc*3);food=newFood();
  } else sn.pop();
}

function gameOver(){
  dead=true;
  msgEl.textContent='Game Over \u2014 press Space or Enter to restart';
  draw();
}

function draw(){
  // background
  ctx.fillStyle=col.bg;ctx.fillRect(0,0,cv.width,cv.height);
  // grid
  ctx.strokeStyle=col.grid;ctx.lineWidth=.5;
  for(let i=0;i<=G;i++){
    ctx.beginPath();ctx.moveTo(i*C,0);ctx.lineTo(i*C,cv.height);ctx.stroke();
    ctx.beginPath();ctx.moveTo(0,i*C);ctx.lineTo(cv.width,i*C);ctx.stroke();
  }
  // food
  const p=.7+.3*Math.sin(Date.now()/180);
  ctx.shadowColor=col.food;ctx.shadowBlur=14*p;
  ctx.fillStyle=col.food;ctx.beginPath();
  ctx.arc(food.x*C+C/2,food.y*C+C/2,C/2*.85*p,0,Math.PI*2);ctx.fill();
  ctx.shadowBlur=0;
  // snake
  sn.forEach((seg,i)=>{
    const isH=i===0,x=seg.x*C+1,y=seg.y*C+1,w=C-2,h=C-2;
    if(isH){ctx.shadowColor=col.hd;ctx.shadowBlur=12}
    ctx.fillStyle=isH?col.hd:col.bd;
    ctx.beginPath();ctx.roundRect(x,y,w,h,4);ctx.fill();
    ctx.shadowBlur=0;
    if(isH){
      // eyes – always point in direction of travel
      const fwd=dir,perp={x:-fwd.y,y:fwd.x};
      const cx=seg.x*C+C/2,cy=seg.y*C+C/2;
      [[1,-1],[-1,-1]].forEach(([pOff,fOff])=>{
        const ex=cx+perp.x*pOff*5+fwd.x*fOff*4;
        const ey=cy+perp.y*pOff*5+fwd.y*fOff*4;
        ctx.fillStyle=col.eye;ctx.beginPath();
        ctx.arc(ex,ey,2,0,Math.PI*2);ctx.fill();
      });
    }
  });
  // game over overlay
  if(dead){
    ctx.fillStyle='#00000099';ctx.fillRect(0,0,cv.width,cv.height);
    ctx.fillStyle=col.food;ctx.font='bold 2.4rem monospace';ctx.textAlign='center';
    ctx.fillText('GAME OVER',cv.width/2,cv.height/2-14);
    ctx.font='1rem monospace';ctx.fillStyle='#aaa';
    ctx.fillText('Score: '+sc,cv.width/2,cv.height/2+20);
    ctx.textAlign='left';
  }
}

const DM={ArrowUp:{x:0,y:-1},ArrowDown:{x:0,y:1},ArrowLeft:{x:-1,y:0},ArrowRight:{x:1,y:0},
          w:{x:0,y:-1},s:{x:0,y:1},a:{x:-1,y:0},d:{x:1,y:0}};

document.addEventListener('keydown',e=>{
  if(e.key===' '||e.key==='Enter'){
    if(dead){init();return}
    pause=!pause;
    msgEl.textContent=pause?'Paused \u2014 Space to continue':'Arrow keys / WASD \u2022 Space to pause';
    return;
  }
  const nd=DM[e.key];
  if(nd&&!(nd.x===-dir.x&&nd.y===-dir.y))nxt=nd;
  if(Object.keys(DM).includes(e.key))e.preventDefault();
});

init();
</script>
</body>
</html>
"""

# ─── RPC helpers ────────────────────────────────────────────────────────────
_rid = 0

def next_id():
    global _rid; _rid += 1; return str(_rid)

def token():
    return pathlib.Path(TOKEN_FILE).read_text().strip()

def rpc(s, method, params=None):
    rid = next_id()
    payload = json.dumps({"id": rid, "schemaVersion": "1.6.2", "token": token(),
                          "method": method, "params": params or {}}) + "\n"
    s.sendall(payload.encode())
    data = b""
    while b"\n" not in data:
        chunk = s.recv(131072)
        if not chunk: break
        data += chunk
    return json.loads(data.split(b"\n")[0])

def chk(label, r, fatal=False):
    if "error" in r:
        print(f"  ✗  {label}: {r['error'].get('message', r['error'])}")
        if fatal: sys.exit(1)
        return False
    print(f"  ✓  {label}")
    return True

# ─── Main ────────────────────────────────────────────────────────────────────
def main():
    bar = "━" * 52
    print(f"\n{bar}")
    print("  DietCode Control Agent — Snake Integration Test")
    print(f"{bar}\n")

    if not ensure_socket():
        print("  ✗  Failed to start DietCode headless process or socket did not initialize.")
        sys.exit(1)

    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.connect(SOCK)
        s.settimeout(15)

        # ── 1. Health check ────────────────────────────────────────────────
        print("  [1/6] Health check")
        r = rpc(s, "rpc.ping");  chk("rpc.ping", r, fatal=True)
        r = rpc(s, "rpc.version"); chk("rpc.version", r)
        ver = r.get("result", {}).get("appVersion", "?")
        print(f"        appVersion={ver}")

        # ── 2. Workspace context ───────────────────────────────────────────
        print("\n  [2/6] Workspace context (background thread — no main-thread wait)")
        r = rpc(s, "session.info"); chk("session.info", r, fatal=True)
        ws = r["result"]["workspace"]
        print(f"        workspace={ws or '(none)'}")

        if not ws:
            ide_dir = pathlib.Path(__file__).parent.parent.resolve()
            print(f"\n        No workspace open. Opening {ide_dir} (Destructive → Permissionless)")
            r = rpc(s, "workspace.openFolder", {"path": str(ide_dir)})
            chk("workspace.openFolder [Destructive→auto-allow]", r, fatal=True)
            time.sleep(0.5)
            r = rpc(s, "session.info"); ws = r["result"]["workspace"]
            print(f"        workspace={ws}")

        target_abs = os.path.join(ws, "snake.html")
        rel = "snake.html"

        # ── 3. Write snake.html via file.write ─────────────────────────────
        print("\n  [3/6] Writing snake.html via file.write [Edit permission]")
        r = rpc(s, "file.write", {"path": rel, "content": SNAKE_HTML})
        chk("file.write snake.html [Edit]", r, fatal=True)

        # ── 4. Stat the file ───────────────────────────────────────────────
        print("\n  [4/6] Verifying file via file.stat [Read, background thread]")
        r = rpc(s, "file.stat", {"path": rel})
        if chk("file.stat snake.html", r):
            info = r["result"]
            print(f"        size={info.get('sizeBytes')} bytes   lines={info.get('lineCount')}")

        # ── 5. Open in editor ──────────────────────────────────────────────
        print("\n  [5/6] Opening snake.html in editor [Read]")
        r = rpc(s, "workspace.openFile", {"path": rel})
        chk("workspace.openFile snake.html", r)

        # ── 6. Workspace summary ───────────────────────────────────────────
        print("\n  [6/6] Workspace analysis [background thread]")
        r = rpc(s, "analysis.workspaceSummary")
        chk("analysis.workspaceSummary", r)
        if "result" in r:
            res = r["result"]
            print(f"        files={res.get('totalFiles', '?')}  languages={list(res.get('languages', {}).keys())}")

        # ── Done ───────────────────────────────────────────────────────────
        print(f"\n{bar}")
        print(f"  ✓  snake.html created at:")
        print(f"     {target_abs}")
        print(f"\n  Open it in your browser to play Snake!")
        print(f"  (In DietCode: it's already open in the editor)")
        print(f"{bar}\n")

        # Open in browser too
        os.system(f"open '{target_abs}'")

if __name__ == "__main__":
    main()
