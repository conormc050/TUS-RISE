/* ============================================================
   LiftIQ — data layer
   Mock session generator + importer for real VidCalc session JSON
   ============================================================ */

const LiftData = (() => {

  // ---------- Synthetic frame generation ----------
  // Produces realistic knee/hip/trunk/lumbar curves so charts look
  // like genuine pipeline output rather than random noise.
  function genFrames({ reps, fps, everyN, lumbarBaseline, trunkBaseline, badReps, threshold }) {
    const frames = [];
    let frameIdx = 0;
    const push = (obj) => { frameIdx += everyN; frames.push({ frame: frameIdx, ...obj }); };
    const noise = (amp) => (Math.random() - 0.5) * amp;

    // standing/calibration lead-in
    for (let i = 0; i < 45; i++) {
      push({
        knee_angle: 172 + noise(3), hip_angle: 170 + noise(3),
        trunk_lean: trunkBaseline + noise(2.5), lumbar_lean: lumbarBaseline + noise(2),
        phase: "STANDING", rep_count: 0, lumbar_flag: false,
      });
    }

    for (let r = 1; r <= reps; r++) {
      const isBad = badReps.includes(r);
      const depth = 78 + noise(10);                 // bottom knee angle
      const repFrames = 46 + Math.floor(Math.random() * 14);
      const half = Math.floor(repFrames / 2);

      for (let i = 0; i < repFrames; i++) {
        const t = i / (repFrames - 1);              // 0..1 through the rep
        // knee: cosine dip 172 -> depth -> 172
        const knee = depth + (172 - depth) * Math.abs(Math.cos(Math.PI * t)) ** 1.3;
        const hip  = 60 + (170 - 60) * Math.abs(Math.cos(Math.PI * t)) ** 1.1;
        // trunk lean rises toward the bottom
        const trunk = trunkBaseline + 26 * Math.sin(Math.PI * t) + noise(2);
        // lumbar: on bad reps it spikes during ascent (t > .5)
        let lumbar = lumbarBaseline + 7 * Math.sin(Math.PI * t) + noise(1.6);
        let flag = false;
        if (isBad && t > 0.5 && t < 0.85) {
          lumbar = lumbarBaseline + threshold + 4 + 5 * Math.sin(Math.PI * (t - 0.5) / 0.35) + noise(1.5);
          flag = lumbar > lumbarBaseline + threshold;
        }
        const phase = i < half - 4 ? "DESCENDING" : (i < half + 4 ? "BOTTOM" : "ASCENDING");
        push({
          knee_angle: knee + noise(1.5), hip_angle: hip + noise(1.5),
          trunk_lean: trunk, lumbar_lean: lumbar,
          phase, rep_count: r - 1, lumbar_flag: flag && phase === "ASCENDING",
        });
      }
      // brief standing pause between reps
      for (let i = 0; i < 8; i++) {
        push({
          knee_angle: 171 + noise(3), hip_angle: 169 + noise(3),
          trunk_lean: trunkBaseline + noise(2.5), lumbar_lean: lumbarBaseline + noise(2),
          phase: "STANDING", rep_count: r, lumbar_flag: false,
        });
      }
    }
    return frames;
  }

  function repStatsFromFrames(frames, repCount, fps, everyN) {
    const buckets = {};
    for (const f of frames) {
      if (f.phase === "STANDING") continue;
      const rep = f.rep_count + 1;
      if (rep > repCount) continue;
      (buckets[rep] = buckets[rep] || []).push(f);
    }
    return Object.keys(buckets).sort((a, b) => a - b).map(rep => {
      const fr = buckets[rep];
      const knees   = fr.map(f => f.knee_angle).filter(v => v != null);
      const trunks  = fr.map(f => f.trunk_lean).filter(v => v != null);
      const lumbars = fr.map(f => f.lumbar_lean).filter(v => v != null);
      return {
        rep: +rep,
        duration: +(fr.length * everyN / fps).toFixed(1),
        depth:  knees.length   ? +Math.min(...knees).toFixed(1)   : null,
        trunk:  trunks.length  ? +Math.max(...trunks).toFixed(1)  : null,
        lumbar: lumbars.length ? +Math.max(...lumbars).toFixed(1) : null,
        flags:  fr.filter(f => f.lumbar_flag).length,
      };
    });
  }

  function mockSession({ id, daysAgo, exercise, reps, badReps, name }) {
    const fps = 30, everyN = 2;
    const lumbarBaseline = 6 + Math.random() * 4;
    const trunkBaseline  = 9 + Math.random() * 4;
    const threshold = 12;
    const frames = genFrames({ reps, fps, everyN, lumbarBaseline, trunkBaseline, badReps, threshold });
    const date = new Date(Date.now() - daysAgo * 86400e3);
    date.setHours(9 + Math.floor(Math.random() * 10), Math.floor(Math.random() * 60));
    return normalize({
      schema_version: 1,
      video: name,
      exercise,
      date: date.toISOString(),
      fps, process_every_n: everyN,
      rep_count: reps,
      lumbar_baseline: lumbarBaseline,
      trunk_baseline: trunkBaseline,
      lumbar_flex_threshold: threshold,
      calibrated: true,
      reps: repStatsFromFrames(frames, reps, fps, everyN),
      frames,
    }, id, true);
  }

  // ---------- Normalizer (mock + real VidCalc JSON share one shape) ----------
  function normalize(raw, id, isMock = false) {
    const reps = raw.reps || [];
    const flaggedReps = reps.filter(r => r.flags > 0).length;
    return {
      id: id || ("s_" + Math.random().toString(36).slice(2, 9)),
      isMock,
      video: raw.video || "unknown.mp4",
      exercise: raw.exercise || "squat",
      date: raw.date ? new Date(raw.date) : new Date(),
      fps: raw.fps || 30,
      everyN: raw.process_every_n || 1,
      repCount: raw.rep_count ?? reps.length,
      lumbarBaseline: raw.lumbar_baseline,
      trunkBaseline: raw.trunk_baseline,
      threshold: raw.lumbar_flex_threshold ?? 12,
      calibrated: raw.calibrated !== false && raw.lumbar_baseline != null,
      reps,
      frames: raw.frames || [],
      flaggedReps,
      score: formScore(raw, reps),
    };
  }

  // ---------- Form score heuristic (0–100) ----------
  // Penalises flagged frames, rewards depth + consistency.
  function formScore(raw, reps) {
    if (!reps.length) return null;
    let score = 100;
    const totalFlags = reps.reduce((s, r) => s + (r.flags || 0), 0);
    score -= Math.min(45, totalFlags * 2.2);                       // lumbar flags
    const depths = reps.map(r => r.depth).filter(v => v != null);
    if (depths.length) {
      const avgDepth = depths.reduce((a, b) => a + b) / depths.length;
      if (avgDepth > 100) score -= Math.min(20, (avgDepth - 100) * 0.8);  // shallow
      const spread = Math.max(...depths) - Math.min(...depths);
      score -= Math.min(15, Math.max(0, spread - 12) * 0.9);       // inconsistent depth
    }
    if (raw.calibrated === false) score -= 10;
    return Math.max(0, Math.round(score));
  }

  // ---------- Session store ----------
  let sessions = [
    mockSession({ id: "m1", daysAgo: 0,  exercise: "squat",    reps: 5, badReps: [3],       name: "Squat3.mp4" }),
    mockSession({ id: "m2", daysAgo: 2,  exercise: "squat",    reps: 8, badReps: [6, 7],    name: "Squat_heavy.mp4" }),
    mockSession({ id: "m3", daysAgo: 5,  exercise: "deadlift", reps: 5, badReps: [],        name: "DL_warmup.mp4" }),
    mockSession({ id: "m4", daysAgo: 9,  exercise: "squat",    reps: 6, badReps: [],        name: "Squat_light.mp4" }),
    mockSession({ id: "m5", daysAgo: 14, exercise: "deadlift", reps: 4, badReps: [4],       name: "DL_top_set.mp4" }),
    mockSession({ id: "m6", daysAgo: 20, exercise: "squat",    reps: 10, badReps: [8, 9, 10], name: "Squat_amrap.mp4" }),
  ];

  function all()      { return [...sessions].sort((a, b) => b.date - a.date); }
  function get(id)    { return sessions.find(s => s.id === id); }
  function latest()   { return all()[0]; }

  function importJSON(text) {
    const raw = JSON.parse(text);
    if (!raw.frames && !raw.reps) throw new Error("Not a LiftIQ session file");
    const s = normalize(raw, null, false);
    sessions.unshift(s);
    return s;
  }

  // ---------- Aggregates for Home / Trends ----------
  function weekStats() {
    const cutoff = Date.now() - 7 * 86400e3;
    const wk = all().filter(s => s.date >= cutoff);
    const totalReps = wk.reduce((s, x) => s + x.repCount, 0);
    const scores = wk.map(s => s.score).filter(v => v != null);
    return {
      sessions: wk.length,
      reps: totalReps,
      avgScore: scores.length ? Math.round(scores.reduce((a, b) => a + b) / scores.length) : null,
    };
  }

  function trendSeries() {
    const chron = all().reverse();
    return {
      labels: chron.map(s => (s.date.getMonth() + 1) + "/" + s.date.getDate()),
      scores: chron.map(s => s.score),
      depths: chron.map(s => {
        const d = s.reps.map(r => r.depth).filter(v => v != null);
        return d.length ? d.reduce((a, b) => a + b) / d.length : null;
      }),
      flagRates: chron.map(s => s.repCount ? s.flaggedReps / s.repCount * 100 : 0),
    };
  }

  return { all, get, latest, importJSON, weekStats, trendSeries };
})();
