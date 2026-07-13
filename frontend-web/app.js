/* ============================================================
   LiftIQ — app shell: routing, theming, screens
   ============================================================ */

(() => {
  const $  = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

  const host    = $("#screen-host");
  const overlay = $("#detail-overlay");
  const fileInput = $("#file-input");

  // ---------- Preferences ----------
  const prefs = {
    get theme()      { return localStorage.getItem("liftiq.theme") || "system"; },
    set theme(v)     { localStorage.setItem("liftiq.theme", v); applyTheme(); },
    get viewMode()   { return localStorage.getItem("liftiq.viewMode") || "simple"; },
    set viewMode(v)  { localStorage.setItem("liftiq.viewMode", v); },
    get athlete()    { return localStorage.getItem("liftiq.athlete") || "Athlete"; },
  };

  function applyTheme() {
    const sysDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
    const mode = prefs.theme === "system" ? (sysDark ? "dark" : "light") : prefs.theme;
    document.documentElement.setAttribute("data-theme", mode);
  }
  window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", applyTheme);
  applyTheme();

  // ---------- Helpers ----------
  const EX_ICON = { squat: "🏋️", deadlift: "🪝" };
  const cap = s => s.charAt(0).toUpperCase() + s.slice(1);

  function fmtDate(d) {
    const today = new Date(); today.setHours(0,0,0,0);
    const day = new Date(d); day.setHours(0,0,0,0);
    const diff = Math.round((today - day) / 86400e3);
    if (diff === 0) return "Today";
    if (diff === 1) return "Yesterday";
    return d.toLocaleDateString(undefined, { month: "short", day: "numeric" });
  }
  function fmtTime(d) {
    return d.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });
  }
  function scoreClass(s) {
    if (s == null) return "score-warn";
    return s >= 85 ? "score-good" : s >= 65 ? "score-warn" : "score-bad";
  }

  function toast(msg, ms = 2400) {
    const t = $("#toast");
    t.textContent = msg;
    t.classList.remove("hidden");
    clearTimeout(t._h);
    t._h = setTimeout(() => t.classList.add("hidden"), ms);
  }

  function sessionRow(s) {
    return `
      <div class="session-row glass" data-session="${s.id}">
        <div class="session-badge">${EX_ICON[s.exercise] || "🏋️"}</div>
        <div class="session-info">
          <div class="session-name">${cap(s.exercise)} · ${s.repCount} reps${s.isMock ? "" : " · imported"}</div>
          <div class="session-meta">${fmtDate(s.date)} at ${fmtTime(s.date)}${s.flaggedReps ? ` · ${s.flaggedReps} flagged` : " · clean"}</div>
        </div>
        <div class="score-pill ${scoreClass(s.score)}">${s.score ?? "–"}</div>
        <svg class="chevron" width="16" height="16" viewBox="0 0 24 24"><path d="m9 6 6 6-6 6" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>
      </div>`;
  }

  // ============================================================
  // SCREENS
  // ============================================================

  function renderHome() {
    const latest = LiftData.latest();
    const wk = LiftData.weekStats();
    const hour = new Date().getHours();
    const greet = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening";

    host.innerHTML = `
      <div class="screen stagger">
        <div>
          <div class="screen-sub">${greet},</div>
          <div class="screen-title">${prefs.athlete}</div>
        </div>

        ${latest ? `
        <div class="card glass hero-card" data-session="${latest.id}">
          <div class="hero-row">
            <div class="hero-meta">
              <div class="hero-kicker">Latest session</div>
              <div class="hero-title">${cap(latest.exercise)} · ${latest.repCount} reps</div>
              <div class="hero-sub">${fmtDate(latest.date)} · ${latest.flaggedReps ? latest.flaggedReps + " rep(s) flagged" : "All reps clean"}</div>
            </div>
            <div id="hero-ring"></div>
          </div>
        </div>` : ""}

        <div class="tile-grid">
          <div class="tile glass"><div class="tile-val">${wk.sessions}</div><div class="tile-name">Sessions this week</div></div>
          <div class="tile glass"><div class="tile-val">${wk.reps}</div><div class="tile-name">Total reps</div></div>
          <div class="tile glass"><div class="tile-val">${wk.avgScore ?? "–"}</div><div class="tile-name">Avg score</div></div>
        </div>

        <div class="card glass">
          <div class="card-label">Recent sessions</div>
          ${LiftData.all().slice(0, 4).map(sessionRow).join("")}
        </div>

        <button class="btn btn-primary" id="home-analyze" style="margin-top:16px">
          <svg width="18" height="18" viewBox="0 0 24 24"><path d="M12 5v14M5 12h14" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"/></svg>
          Analyze a new lift
        </button>
      </div>`;

    if (latest) Charts.scoreRing($("#hero-ring"), latest.score, 92);
    $("#home-analyze").onclick = () => switchTab("analyze");
    bindSessionRows();
  }

  function renderHistory() {
    let filter = "all";
    function list() {
      let items = LiftData.all();
      if (filter === "flagged") items = items.filter(s => s.flaggedReps > 0);
      else if (filter !== "all") items = items.filter(s => s.exercise === filter);
      return items.length
        ? items.map(sessionRow).join("")
        : `<div class="empty"><div class="empty-icon">📂</div>
             <div class="empty-title">No sessions here</div>
             <div class="empty-sub">Run VidCalc.py on a video and import the session JSON from the Analyze tab.</div></div>`;
    }
    host.innerHTML = `
      <div class="screen">
        <div class="screen-title">History</div>
        <div class="screen-sub">${LiftData.all().length} analysed sessions</div>
        <div class="chip-row">
          <button class="chip active" data-f="all">All</button>
          <button class="chip" data-f="squat">Squat</button>
          <button class="chip" data-f="deadlift">Deadlift</button>
          <button class="chip" data-f="flagged">⚑ Flagged</button>
        </div>
        <div id="history-list" style="margin-top:8px">${list()}</div>
      </div>`;

    $$(".chip").forEach(c => c.onclick = () => {
      $$(".chip").forEach(x => x.classList.remove("active"));
      c.classList.add("active");
      filter = c.dataset.f;
      $("#history-list").innerHTML = list();
      bindSessionRows();
    });
    bindSessionRows();
  }

  function renderAnalyze() {
    host.innerHTML = `
      <div class="screen stagger">
        <div class="screen-title">Analyze</div>
        <div class="screen-sub">Import results from the analysis pipeline</div>

        <div class="drop-zone" id="drop-zone">
          <div class="drop-icon">📥</div>
          <div class="drop-title">Import session JSON</div>
          <div class="drop-sub">Drop a <b>session_*.json</b> file here<br>or tap to browse</div>
        </div>

        <div class="card glass">
          <div class="card-label">How it works</div>
          <div class="step"><div class="step-num">1</div><div class="step-text">Record your set from a <b>side-on view</b> with the whole body in frame, standing still for the first ~2 seconds (calibration).</div></div>
          <div class="step"><div class="step-num">2</div><div class="step-text">Run <code>VidCalc.py</code> on the video. It exports <code>session_&lt;name&gt;.json</code> next to the annotated output.</div></div>
          <div class="step"><div class="step-num">3</div><div class="step-text">Import the JSON here to see your form score, flags, and full joint-angle breakdown.</div></div>
        </div>

        <div class="card glass">
          <div class="card-label">Coming to the iOS app</div>
          <div class="step"><div class="step-num">📱</div><div class="step-text"><b>Record in-app</b> — capture and analyse directly on-device.</div></div>
          <div class="step"><div class="step-num">⚡</div><div class="step-text"><b>Live mode</b> — real-time flags while you lift.</div></div>
        </div>
      </div>`;

    const dz = $("#drop-zone");
    dz.onclick = () => fileInput.click();
    dz.ondragover = e => { e.preventDefault(); dz.classList.add("dragover"); };
    dz.ondragleave = () => dz.classList.remove("dragover");
    dz.ondrop = e => {
      e.preventDefault(); dz.classList.remove("dragover");
      const f = e.dataTransfer.files[0];
      if (f) readSessionFile(f);
    };
  }

  function renderTrends() {
    const t = LiftData.trendSeries();
    host.innerHTML = `
      <div class="screen stagger">
        <div class="screen-title">Trends</div>
        <div class="screen-sub">Across ${t.labels.length} sessions</div>

        <div class="card glass">
          <div class="card-label">Form score over time</div>
          <div class="chart-box" id="trend-score"></div>
        </div>

        <div class="card glass">
          <div class="card-label">Average squat depth (knee angle at bottom — lower is deeper)</div>
          <div class="chart-box" id="trend-depth"></div>
        </div>

        <div class="card glass">
          <div class="card-label">Flagged rep rate</div>
          <div class="chart-box" id="trend-flags"></div>
        </div>
      </div>`;

    Charts.trendChart($("#trend-score"), { labels: t.labels, values: t.scores, color: "#22d3ee" });
    Charts.trendChart($("#trend-depth"), { labels: t.labels, values: t.depths, color: "#34d399", unit: "°" });
    Charts.trendChart($("#trend-flags"), { labels: t.labels, values: t.flagRates, color: "#fb7185", unit: "%" });
  }

  function renderSettings() {
    host.innerHTML = `
      <div class="screen stagger">
        <div class="screen-title">Settings</div>

        <div class="card glass">
          <div class="card-label">Appearance</div>
          <div class="theme-picker">
            <button class="theme-opt ${prefs.theme === "light" ? "active" : ""}" data-t="light">☀️ Light</button>
            <button class="theme-opt ${prefs.theme === "dark" ? "active" : ""}" data-t="dark">🌙 Dark</button>
            <button class="theme-opt ${prefs.theme === "system" ? "active" : ""}" data-t="system">⚙️ Auto</button>
          </div>
        </div>

        <div class="card glass">
          <div class="card-label">Analysis</div>
          <div class="settings-row">
            <div class="settings-icon">📊</div>
            <div class="settings-info">
              <div class="settings-name">Detailed view by default</div>
              <div class="settings-desc">Open sessions in full-data mode</div>
            </div>
            <label class="switch"><input type="checkbox" id="pref-detail" ${prefs.viewMode === "detailed" ? "checked" : ""}><span class="slider"></span></label>
          </div>
          <div class="settings-row">
            <div class="settings-icon">🎯</div>
            <div class="settings-info">
              <div class="settings-name">Custom flag thresholds</div>
              <div class="settings-desc">Tune sensitivity per exercise</div>
            </div>
            <span class="soon-tag">Soon</span>
          </div>
        </div>

        <div class="card glass">
          <div class="card-label">Coming soon</div>
          <div class="settings-row"><div class="settings-icon">📱</div><div class="settings-info"><div class="settings-name">Live analysis mode</div><div class="settings-desc">Real-time flags while lifting</div></div><span class="soon-tag">iOS</span></div>
          <div class="settings-row"><div class="settings-icon">🔔</div><div class="settings-info"><div class="settings-name">Audio form cues</div><div class="settings-desc">Spoken alerts mid-set</div></div><span class="soon-tag">Soon</span></div>
          <div class="settings-row"><div class="settings-icon">👥</div><div class="settings-info"><div class="settings-name">Coach sharing</div><div class="settings-desc">Send sessions to your coach</div></div><span class="soon-tag">Soon</span></div>
          <div class="settings-row"><div class="settings-icon">⌚</div><div class="settings-info"><div class="settings-name">Apple Watch companion</div><div class="settings-desc">Rep count + flags on wrist</div></div><span class="soon-tag">Soon</span></div>
        </div>

        <div class="card glass">
          <div class="card-label">About</div>
          <div class="kv"><span class="kv-key">Version</span><span class="kv-val">0.1.0 (prototype)</span></div>
          <div class="kv"><span class="kv-key">Pipeline</span><span class="kv-val">MediaPipe + SpinePose</span></div>
          <div class="kv"><span class="kv-key">Project</span><span class="kv-val">TUS Athlone Research</span></div>
        </div>
      </div>`;

    $$(".theme-opt").forEach(b => b.onclick = () => {
      prefs.theme = b.dataset.t;
      $$(".theme-opt").forEach(x => x.classList.toggle("active", x === b));
    });
    $("#pref-detail").onchange = e => { prefs.viewMode = e.target.checked ? "detailed" : "simple"; };
  }

  // ============================================================
  // SESSION DETAIL (Simple / Detailed)
  // ============================================================

  function openSession(id) {
    const s = LiftData.get(id);
    if (!s) return;
    let mode = prefs.viewMode;

    function render() {
      overlay.innerHTML = `
        <div class="detail-nav">
          <button class="icon-btn" id="detail-close">
            <svg viewBox="0 0 24 24"><path d="m15 5-7 7 7 7" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>
          </button>
          <div style="text-align:center">
            <div style="font-weight:800;font-size:16px">${cap(s.exercise)} session</div>
            <div style="font-size:12px;color:var(--text-2)">${fmtDate(s.date)} · ${fmtTime(s.date)} · ${s.video}</div>
          </div>
          <div style="width:40px"></div>
        </div>

        <div class="segmented">
          <button class="seg-btn ${mode === "simple" ? "active" : ""}" data-m="simple">Simple</button>
          <button class="seg-btn ${mode === "detailed" ? "active" : ""}" data-m="detailed">Detailed</button>
        </div>

        <div id="detail-body"></div>`;

      $("#detail-close").onclick = closeSession;
      $$(".seg-btn", overlay).forEach(b => b.onclick = () => {
        mode = b.dataset.m;
        $$(".seg-btn", overlay).forEach(x => x.classList.toggle("active", x === b));
        renderBody();
      });
      renderBody();
    }

    function renderBody() {
      const body = $("#detail-body");
      body.innerHTML = mode === "simple" ? simpleHTML(s) : detailedHTML(s);
      if (mode === "simple") {
        Charts.scoreRing($("#detail-ring"), s.score);
      } else {
        mountDetailedCharts(s);
      }
    }

    overlay.classList.remove("hidden", "leaving");
    render();
  }

  function closeSession() {
    overlay.classList.add("leaving");
    setTimeout(() => { overlay.classList.add("hidden"); overlay.innerHTML = ""; }, 300);
  }

  // ---------- Simple mode: score + plain-language insights ----------
  function simpleHTML(s) {
    const insights = buildInsights(s);
    const dots = s.reps.map((r, i) =>
      `<div class="rep-dot ${r.flags ? "dot-flag" : "dot-clean"}" style="--i:${i}">${r.rep}</div>`).join("");
    return `
      <div class="screen stagger">
        <div class="card glass" style="text-align:center">
          <div class="ring-wrap" id="detail-ring"></div>
          <div style="font-size:13.5px;color:var(--text-2);margin-top:6px">${scoreBlurb(s.score)}</div>
        </div>

        <div class="tile-grid">
          <div class="tile glass"><div class="tile-val">${s.repCount}</div><div class="tile-name">Reps</div></div>
          <div class="tile glass"><div class="tile-val">${bestDepth(s) ?? "–"}<span class="unit">°</span></div><div class="tile-name">Deepest rep</div></div>
          <div class="tile glass"><div class="tile-val">${s.flaggedReps}</div><div class="tile-name">Flagged reps</div></div>
        </div>

        <div class="card glass">
          <div class="card-label">Your reps</div>
          <div class="rep-dots">${dots}</div>
          <div style="font-size:12px;color:var(--text-2);margin-top:12px">Green = clean rep · Red = form flag raised</div>
        </div>

        <div class="card glass">
          <div class="card-label">What we noticed</div>
          ${insights.map(i => `
            <div class="insight">
              <div class="insight-icon ic-${i.kind}">${i.icon}</div>
              <div><div class="insight-title">${i.title}</div><div class="insight-body">${i.body}</div></div>
            </div>`).join("")}
        </div>
      </div>`;
  }

  function bestDepth(s) {
    const d = s.reps.map(r => r.depth).filter(v => v != null);
    return d.length ? Math.round(Math.min(...d)) : null;
  }

  function scoreBlurb(score) {
    if (score == null) return "Not enough data to score this session.";
    if (score >= 90) return "Excellent lifting — form held up across the whole set.";
    if (score >= 80) return "Strong session with minor things to tidy up.";
    if (score >= 65) return "Solid work — a few reps need attention.";
    return "Form broke down in this set. Worth reviewing before adding weight.";
  }

  function buildInsights(s) {
    const out = [];
    if (!s.calibrated) {
      out.push({ kind: "warn", icon: "⚠️", title: "No calibration baseline",
        body: "The video didn't start with you standing still, so spine flags couldn't be checked. Stand upright for ~2 seconds before your first rep." });
    }
    if (s.flaggedReps === 0 && s.calibrated) {
      out.push({ kind: "good", icon: "✅", title: "Spine position held",
        body: "Your lower back stayed within your neutral range on every rep. That's exactly what we want to see under load." });
    } else if (s.flaggedReps > 0) {
      const which = s.reps.filter(r => r.flags).map(r => r.rep).join(", ");
      out.push({ kind: "bad", icon: "🚩", title: `Lower-back rounding on rep ${which}`,
        body: "Your lumbar spine rounded past your normal range while standing up out of the hole. This usually shows up as fatigue sets in — consider stopping a rep earlier or dropping the load slightly." });
    }
    const depths = s.reps.map(r => r.depth).filter(v => v != null);
    if (depths.length >= 2) {
      const spread = Math.max(...depths) - Math.min(...depths);
      if (spread > 12) {
        out.push({ kind: "warn", icon: "📏", title: "Depth varied between reps",
          body: `Your deepest and shallowest reps differed by ${Math.round(spread)}°. Aim to hit the same depth every rep — a consistent bottom position makes every rep count the same.` });
      } else {
        out.push({ kind: "good", icon: "🎯", title: "Consistent depth",
          body: "Every rep reached roughly the same bottom position. Great motor control." });
      }
    }
    const durs = s.reps.map(r => r.duration).filter(v => v != null);
    if (durs.length >= 3 && durs[durs.length - 1] > durs[0] * 1.5) {
      out.push({ kind: "info", icon: "⏱", title: "Reps slowed down late in the set",
        body: "Later reps took noticeably longer — a normal fatigue signal, and a good cue for when to rack it." });
    }
    if (!out.length) out.push({ kind: "info", icon: "💡", title: "Session recorded",
      body: "Not enough rep data for deeper insights this time." });
    return out;
  }

  // ---------- Detailed mode: charts + tables + baselines ----------
  function detailedHTML(s) {
    return `
      <div class="screen stagger">
        <div class="card glass">
          <div class="card-label">Joint angles across the lift</div>
          <div class="chart-box" id="angle-chart"></div>
          <div class="chart-legend">
            <span class="legend-item"><span class="legend-swatch" style="background:#34d399"></span>Knee</span>
            <span class="legend-item"><span class="legend-swatch" style="background:#fbbf24"></span>Hip</span>
            <span class="legend-item"><span class="legend-swatch" style="background:#fb923c"></span>Trunk lean</span>
            <span class="legend-item"><span class="legend-swatch" style="background:#fb7185"></span>Lumbar lean</span>
            <span class="legend-item"><span class="legend-swatch" style="background:rgba(251,113,133,.4)"></span>Flagged span</span>
          </div>
        </div>

        <div class="card glass">
          <div class="card-label">Peak lean per rep</div>
          <div class="chart-box" id="rep-chart"></div>
          <div class="chart-legend">
            <span class="legend-item"><span class="legend-swatch" style="background:#fbbf24"></span>Peak trunk</span>
            <span class="legend-item"><span class="legend-swatch" style="background:#fb7185"></span>Peak lumbar (outlined = flagged)</span>
          </div>
        </div>

        <div class="card glass">
          <div class="card-label">Rep breakdown</div>
          <table class="rep-table">
            <thead><tr><th>Rep</th><th>Time</th><th>Depth</th><th>Trunk</th><th>Lumbar</th><th>Flags</th></tr></thead>
            <tbody>
              ${s.reps.map(r => `
                <tr>
                  <td>${r.rep}</td>
                  <td>${r.duration ?? "–"}s</td>
                  <td>${r.depth ?? "–"}°</td>
                  <td>${r.trunk ?? "–"}°</td>
                  <td>${r.lumbar ?? "–"}°</td>
                  <td class="${r.flags ? "flag-cell" : "clean-cell"}">${r.flags ? r.flags + " ⚑" : "✓"}</td>
                </tr>`).join("")}
            </tbody>
          </table>
        </div>

        <div class="card glass">
          <div class="card-label">Calibration & thresholds</div>
          <div class="kv"><span class="kv-key">Calibrated</span><span class="kv-val">${s.calibrated ? "Yes" : "No ⚠️"}</span></div>
          <div class="kv"><span class="kv-key">Lumbar baseline</span><span class="kv-val">${s.lumbarBaseline != null ? s.lumbarBaseline.toFixed(1) + "°" : "–"}</span></div>
          <div class="kv"><span class="kv-key">Trunk baseline</span><span class="kv-val">${s.trunkBaseline != null ? s.trunkBaseline.toFixed(1) + "°" : "–"}</span></div>
          <div class="kv"><span class="kv-key">Flag threshold</span><span class="kv-val">baseline + ${s.threshold}°</span></div>
          <div class="kv"><span class="kv-key">Frames analysed</span><span class="kv-val">${s.frames.length}</span></div>
          <div class="kv"><span class="kv-key">Processing rate</span><span class="kv-val">every ${s.everyN} frame(s) @ ${Math.round(s.fps)} fps</span></div>
        </div>
      </div>`;
  }

  function mountDetailedCharts(s) {
    const frames = s.frames;
    if (frames.length) {
      const xs = frames.map(f => f.frame);

      // flagged frame spans
      const flagged = frames.filter(f => f.lumbar_flag).map(f => f.frame);
      const spans = [];
      if (flagged.length) {
        let start = flagged[0];
        for (let i = 1; i < flagged.length; i++) {
          if (flagged[i] - flagged[i - 1] > s.everyN * 3) {
            spans.push([start, flagged[i - 1]]); start = flagged[i];
          }
        }
        spans.push([start, flagged[flagged.length - 1]]);
      }

      // rep completion markers
      const repMarks = [];
      let prev = 0;
      for (const f of frames) {
        if (f.rep_count > prev) { repMarks.push({ x: f.frame, label: "R" + f.rep_count }); prev = f.rep_count; }
      }

      const hLines = [];
      if (s.lumbarBaseline != null) {
        hLines.push({ y: s.lumbarBaseline, color: "#fb7185" });
        hLines.push({ y: s.lumbarBaseline + s.threshold, color: "#e11d48" });
      }

      Charts.lineChart($("#angle-chart"), {
        xs,
        series: [
          { name: "Knee",   color: "#34d399", values: frames.map(f => f.knee_angle) },
          { name: "Hip",    color: "#fbbf24", values: frames.map(f => f.hip_angle) },
          { name: "Trunk",  color: "#fb923c", values: frames.map(f => f.trunk_lean) },
          { name: "Lumbar", color: "#fb7185", values: frames.map(f => f.lumbar_lean), dashed: true },
        ],
        spans, repMarks, hLines,
      });
    }

    Charts.repBarChart($("#rep-chart"), {
      reps: s.reps,
      hLines: s.lumbarBaseline != null
        ? [{ y: s.lumbarBaseline, color: "#fb7185" }, { y: s.lumbarBaseline + s.threshold, color: "#e11d48" }]
        : [],
    });
  }

  // ============================================================
  // FILE IMPORT
  // ============================================================

  function readSessionFile(file) {
    const reader = new FileReader();
    reader.onload = () => {
      try {
        const s = LiftData.importJSON(reader.result);
        toast("Session imported ✓");
        openSession(s.id);
      } catch (err) {
        toast("Couldn't read that file — is it a session_*.json?");
      }
    };
    reader.readAsText(file);
  }
  fileInput.onchange = () => {
    if (fileInput.files[0]) readSessionFile(fileInput.files[0]);
    fileInput.value = "";
  };

  // ============================================================
  // ROUTER
  // ============================================================

  const SCREENS = {
    home: renderHome, history: renderHistory,
    analyze: renderAnalyze, trends: renderTrends, settings: renderSettings,
  };

  function switchTab(name) {
    $$(".tab").forEach(t => t.classList.toggle("active", t.dataset.tab === name));
    host.scrollTop = 0;
    SCREENS[name]();
  }

  $$(".tab").forEach(t => t.onclick = () => switchTab(t.dataset.tab));

  function bindSessionRows() {
    $$("[data-session]").forEach(r => r.onclick = () => openSession(r.dataset.session));
  }

  // ============================================================
  // BOOT — splash then shell
  // ============================================================

  setTimeout(() => {
    $("#splash").classList.add("leaving");
    $("#shell").classList.remove("hidden");
    switchTab("home");
    setTimeout(() => $("#splash").remove(), 600);
  }, 2100);
})();
