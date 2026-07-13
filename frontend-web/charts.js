/* ============================================================
   LiftIQ — lightweight SVG chart renderers (no dependencies)
   ============================================================ */

const Charts = (() => {
  const NS = "http://www.w3.org/2000/svg";

  function el(tag, attrs = {}) {
    const e = document.createElementNS(NS, tag);
    for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, v);
    return e;
  }

  function pathFrom(points) {
    if (!points.length) return "";
    let d = `M ${points[0][0].toFixed(1)} ${points[0][1].toFixed(1)}`;
    for (let i = 1; i < points.length; i++)
      d += ` L ${points[i][0].toFixed(1)} ${points[i][1].toFixed(1)}`;
    return d;
  }

  // ---------- Multi-series line chart (angle timeline) ----------
  // series: [{ name, color, values, dashed }], xs shared, spans: flagged frame spans
  function lineChart(container, { xs, series, spans = [], hLines = [], repMarks = [], height = 230 }) {
    container.innerHTML = "";
    const W = 720, H = height, padL = 34, padR = 10, padT = 12, padB = 22;
    const svg = el("svg", { viewBox: `0 0 ${W} ${H}` });

    const allVals = series.flatMap(s => s.values).filter(v => v != null && !isNaN(v));
    if (!allVals.length) { container.appendChild(svg); return; }
    let yMin = Math.min(...allVals, ...hLines.map(h => h.y));
    let yMax = Math.max(...allVals, ...hLines.map(h => h.y));
    const pad = (yMax - yMin) * 0.08 || 5;
    yMin -= pad; yMax += pad;

    const xMin = xs[0], xMax = xs[xs.length - 1];
    const X = x => padL + (x - xMin) / (xMax - xMin || 1) * (W - padL - padR);
    const Y = y => padT + (1 - (y - yMin) / (yMax - yMin || 1)) * (H - padT - padB);

    // grid + y labels
    const gridN = 4;
    for (let i = 0; i <= gridN; i++) {
      const yv = yMin + (yMax - yMin) * i / gridN;
      svg.appendChild(el("line", {
        x1: padL, x2: W - padR, y1: Y(yv), y2: Y(yv),
        stroke: "var(--chart-grid)", "stroke-width": 1,
      }));
      const t = el("text", { x: padL - 6, y: Y(yv) + 4, "text-anchor": "end",
        "font-size": 10, fill: "var(--text-3)" });
      t.textContent = Math.round(yv) + "°";
      svg.appendChild(t);
    }

    // flagged spans
    for (const [s, e] of spans) {
      svg.appendChild(el("rect", {
        x: X(s), y: padT, width: Math.max(2, X(e) - X(s)), height: H - padT - padB,
        fill: "#fb7185", opacity: 0.13, rx: 3,
      }));
    }

    // rep completion markers
    for (const m of repMarks) {
      svg.appendChild(el("line", {
        x1: X(m.x), x2: X(m.x), y1: padT, y2: H - padB,
        stroke: "#a78bfa", "stroke-width": 1, "stroke-dasharray": "4 4", opacity: 0.7,
      }));
      const t = el("text", { x: X(m.x) + 4, y: padT + 10, "font-size": 9.5, fill: "#a78bfa" });
      t.textContent = m.label;
      svg.appendChild(t);
    }

    // horizontal reference lines (baselines / thresholds)
    for (const h of hLines) {
      svg.appendChild(el("line", {
        x1: padL, x2: W - padR, y1: Y(h.y), y2: Y(h.y),
        stroke: h.color, "stroke-width": 1.2, "stroke-dasharray": "5 4", opacity: 0.65,
      }));
    }

    // series
    for (const s of series) {
      const pts = [];
      for (let i = 0; i < xs.length; i++) {
        const v = s.values[i];
        if (v == null || isNaN(v)) continue;
        pts.push([X(xs[i]), Y(v)]);
      }
      const p = el("path", {
        d: pathFrom(pts), fill: "none", stroke: s.color,
        "stroke-width": 2, "stroke-linejoin": "round",
        class: "anim-line",
      });
      if (s.dashed) p.setAttribute("stroke-dasharray", "6 4");
      svg.appendChild(p);
    }

    container.appendChild(svg);
  }

  // ---------- Grouped bar chart (per-rep peaks) ----------
  function repBarChart(container, { reps, hLines = [], height = 210 }) {
    container.innerHTML = "";
    const W = 720, H = height, padL = 34, padR = 10, padT = 12, padB = 28;
    const svg = el("svg", { viewBox: `0 0 ${W} ${H}` });

    const vals = reps.flatMap(r => [r.trunk, r.lumbar]).filter(v => v != null);
    if (!vals.length) { container.appendChild(svg); return; }
    const yMax = Math.max(...vals, ...hLines.map(h => h.y)) * 1.12;
    const Y = y => padT + (1 - y / yMax) * (H - padT - padB);

    const gridN = 4;
    for (let i = 0; i <= gridN; i++) {
      const yv = yMax * i / gridN;
      svg.appendChild(el("line", { x1: padL, x2: W - padR, y1: Y(yv), y2: Y(yv),
        stroke: "var(--chart-grid)", "stroke-width": 1 }));
      const t = el("text", { x: padL - 6, y: Y(yv) + 4, "text-anchor": "end",
        "font-size": 10, fill: "var(--text-3)" });
      t.textContent = Math.round(yv) + "°";
      svg.appendChild(t);
    }

    const slot = (W - padL - padR) / reps.length;
    const bw = Math.min(26, slot * 0.28);

    reps.forEach((r, i) => {
      const cx = padL + slot * (i + 0.5);
      const flagged = r.flags > 0;
      if (r.trunk != null) {
        svg.appendChild(el("rect", {
          x: cx - bw - 2, y: Y(r.trunk), width: bw, height: H - padB - Y(r.trunk),
          rx: 4, fill: "#fbbf24", opacity: 0.85, class: "anim-bar",
          style: `animation-delay:${i * 0.06}s`,
        }));
      }
      if (r.lumbar != null) {
        svg.appendChild(el("rect", {
          x: cx + 2, y: Y(r.lumbar), width: bw, height: H - padB - Y(r.lumbar),
          rx: 4, fill: "#fb7185", opacity: 0.9, class: "anim-bar",
          style: `animation-delay:${i * 0.06 + 0.03}s`,
          stroke: flagged ? "#e11d48" : "none", "stroke-width": flagged ? 2 : 0,
        }));
      }
      const t = el("text", { x: cx, y: H - 8, "text-anchor": "middle",
        "font-size": 10.5, fill: flagged ? "#fb7185" : "var(--text-3)",
        "font-weight": flagged ? 800 : 500 });
      t.textContent = "R" + r.rep;
      svg.appendChild(t);
    });

    for (const h of hLines) {
      svg.appendChild(el("line", { x1: padL, x2: W - padR, y1: Y(h.y), y2: Y(h.y),
        stroke: h.color, "stroke-width": 1.2, "stroke-dasharray": "5 4", opacity: 0.7 }));
    }

    container.appendChild(svg);
  }

  // ---------- Sparkline / trend line ----------
  function trendChart(container, { labels, values, color = "#22d3ee", height = 170, unit = "" }) {
    container.innerHTML = "";
    const W = 720, H = height, padL = 34, padR = 12, padT = 14, padB = 26;
    const svg = el("svg", { viewBox: `0 0 ${W} ${H}` });

    const clean = values.map((v, i) => [v, i]).filter(([v]) => v != null);
    if (!clean.length) { container.appendChild(svg); return; }
    const vs = clean.map(([v]) => v);
    let yMin = Math.min(...vs), yMax = Math.max(...vs);
    const pad = (yMax - yMin) * 0.15 || 4;
    yMin -= pad; yMax += pad;

    const X = i => padL + i / (values.length - 1 || 1) * (W - padL - padR);
    const Y = v => padT + (1 - (v - yMin) / (yMax - yMin || 1)) * (H - padT - padB);

    for (let i = 0; i <= 3; i++) {
      const yv = yMin + (yMax - yMin) * i / 3;
      svg.appendChild(el("line", { x1: padL, x2: W - padR, y1: Y(yv), y2: Y(yv),
        stroke: "var(--chart-grid)", "stroke-width": 1 }));
      const t = el("text", { x: padL - 6, y: Y(yv) + 4, "text-anchor": "end",
        "font-size": 10, fill: "var(--text-3)" });
      t.textContent = Math.round(yv) + unit;
      svg.appendChild(t);
    }

    const pts = clean.map(([v, i]) => [X(i), Y(v)]);

    // area fill
    const gid = "tg" + Math.random().toString(36).slice(2, 7);
    const defs = el("defs");
    const grad = el("linearGradient", { id: gid, x1: 0, y1: 0, x2: 0, y2: 1 });
    grad.appendChild(el("stop", { offset: "0", "stop-color": color, "stop-opacity": 0.28 }));
    grad.appendChild(el("stop", { offset: "1", "stop-color": color, "stop-opacity": 0 }));
    defs.appendChild(grad);
    svg.appendChild(defs);

    if (pts.length > 1) {
      const area = pathFrom(pts) +
        ` L ${pts[pts.length - 1][0]} ${H - padB} L ${pts[0][0]} ${H - padB} Z`;
      svg.appendChild(el("path", { d: area, fill: `url(#${gid})` }));
    }

    svg.appendChild(el("path", {
      d: pathFrom(pts), fill: "none", stroke: color,
      "stroke-width": 2.5, "stroke-linecap": "round", "stroke-linejoin": "round",
      class: "anim-line",
    }));

    // dots + x labels
    clean.forEach(([v, i], k) => {
      svg.appendChild(el("circle", { cx: X(i), cy: Y(v), r: 3.4, fill: color }));
      if (labels && (values.length <= 8 || k % 2 === 0)) {
        const t = el("text", { x: X(i), y: H - 8, "text-anchor": "middle",
          "font-size": 9.5, fill: "var(--text-3)" });
        t.textContent = labels[i];
        svg.appendChild(t);
      }
    });

    container.appendChild(svg);
  }

  // ---------- Score ring ----------
  function scoreRing(container, score, size = 168) {
    container.innerHTML = "";
    const stroke = 13, r = (size - stroke) / 2, c = 2 * Math.PI * r;
    const val = score == null ? 0 : score;

    const holder = document.createElement("div");
    holder.className = "ring-holder";

    const svg = el("svg", { width: size, height: size, class: "ring-svg" });
    const defs = el("defs");
    const grad = el("linearGradient", { id: "ringGrad", x1: 0, y1: 0, x2: 1, y2: 1 });
    grad.appendChild(el("stop", { offset: "0", "stop-color": "#67e8f9" }));
    grad.appendChild(el("stop", { offset: "1", "stop-color": "#0ea5e9" }));
    defs.appendChild(grad);
    svg.appendChild(defs);

    svg.appendChild(el("circle", { cx: size / 2, cy: size / 2, r, class: "ring-track", "stroke-width": stroke, stroke: "var(--surface-2)" }));
    const ring = el("circle", {
      cx: size / 2, cy: size / 2, r, class: "ring-val",
      "stroke-width": stroke, "stroke-dasharray": c, "stroke-dashoffset": c,
    });
    svg.appendChild(ring);
    holder.appendChild(svg);

    const center = document.createElement("div");
    center.className = "ring-center";
    center.innerHTML = `<div class="ring-score" data-count="${val}">0</div><div class="ring-label">Form score</div>`;
    holder.appendChild(center);
    container.appendChild(holder);

    requestAnimationFrame(() => {
      ring.style.strokeDashoffset = c * (1 - val / 100);
      animateCount(center.querySelector(".ring-score"), val);
    });
  }

  function animateCount(node, target, dur = 1000) {
    const t0 = performance.now();
    function tick(t) {
      const p = Math.min(1, (t - t0) / dur);
      node.textContent = Math.round(target * (1 - Math.pow(1 - p, 3)));
      if (p < 1) requestAnimationFrame(tick);
    }
    requestAnimationFrame(tick);
  }

  return { lineChart, repBarChart, trendChart, scoreRing, animateCount };
})();
