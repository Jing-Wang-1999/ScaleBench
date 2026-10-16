"use strict";

const TASK_KEY = "spec2rtl";
const PAGE_SIZE = 50;
const REVIEW_STORAGE_KEY = "scalebench-reviewed-cases-v1";
const MANIFEST_URL = "./data/manifest.json";
const AUDIT_URL = "./review/all_case_audit.csv";

const content = document.querySelector("#content");
const toast = document.querySelector("#toast");

const state = {
  cases: [],
  caseById: new Map(),
  auditById: new Map(),
  reviewed: loadReviewedCases(),
  searchTimer: null,
};

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function humanize(value) {
  return String(value ?? "")
    .replaceAll("_", " ")
    .replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function caseNumber(record) {
  return String(record.index + 1).padStart(3, "0");
}

function loadReviewedCases() {
  try {
    const saved = JSON.parse(localStorage.getItem(REVIEW_STORAGE_KEY) || "[]");
    return new Set(Array.isArray(saved) ? saved : []);
  } catch {
    return new Set();
  }
}

function saveReviewedCases() {
  localStorage.setItem(REVIEW_STORAGE_KEY, JSON.stringify([...state.reviewed].sort()));
}

function showToast(message) {
  toast.textContent = message;
  toast.classList.add("visible");
  window.clearTimeout(showToast.timer);
  showToast.timer = window.setTimeout(() => toast.classList.remove("visible"), 1800);
}

function parseCsv(text) {
  const rows = [];
  let row = [];
  let field = "";
  let quoted = false;

  for (let index = 0; index < text.length; index += 1) {
    const character = text[index];
    const next = text[index + 1];

    if (character === '"' && quoted && next === '"') {
      field += '"';
      index += 1;
    } else if (character === '"') {
      quoted = !quoted;
    } else if (character === "," && !quoted) {
      row.push(field);
      field = "";
    } else if ((character === "\n" || character === "\r") && !quoted) {
      if (character === "\r" && next === "\n") {
        index += 1;
      }
      row.push(field);
      if (row.some((value) => value !== "")) {
        rows.push(row);
      }
      row = [];
      field = "";
    } else {
      field += character;
    }
  }

  if (field || row.length) {
    row.push(field);
    rows.push(row);
  }

  const [header = [], ...records] = rows;
  return records.map((values) =>
    Object.fromEntries(header.map((name, index) => [name, values[index] ?? ""])),
  );
}

function currentRoute() {
  return new URLSearchParams(window.location.hash.slice(1));
}

function hashFor(values) {
  const params = new URLSearchParams();
  Object.entries(values).forEach(([key, value]) => {
    if (value !== undefined && value !== null && value !== "") {
      params.set(key, String(value));
    }
  });
  return `#${params.toString()}`;
}

function curationGroup(record) {
  if (record.curation_status.startsWith("repaired_")) {
    return "repaired";
  }
  if (record.curation_status === "review_ready") {
    return "ready";
  }
  return "attention";
}

function curationLabel(record) {
  const labels = {
    review_ready: "Review ready",
    repaired_review_ready: "Repaired · review ready",
    repaired_evaluation_ready: "Repaired · evaluation ready",
    quarantined_golden_pathology: "Quarantined reference",
    blocked_missing_memory_image: "Blocked · missing memory image",
  };
  return labels[record.curation_status] || humanize(record.curation_status);
}

function curationPill(record) {
  const group = curationGroup(record);
  const className = group === "attention" ? "pill-attention" : `pill-${group}`;
  return `<span class="pill ${className}">${escapeHtml(curationLabel(record))}</span>`;
}

function resultPill(value) {
  const normalized = String(value || "—").trim();
  if (!normalized || normalized === "—") {
    return '<span class="pill pill-pending">Not run</span>';
  }
  const passed = normalized.toUpperCase() === "PASS";
  return `<span class="pill ${passed ? "pill-pass" : "pill-fail"}">${escapeHtml(normalized)}</span>`;
}

function breadcrumbs(parts) {
  const entries = ['<a href="./review.html">Case browser</a>'];
  parts.forEach((part) => {
    entries.push(`<span aria-hidden="true">/</span>${part}`);
  });
  return `<nav class="browser-crumbs" aria-label="Breadcrumb">${entries.join("")}</nav>`;
}

function renderDashboard() {
  const sequential = state.cases.filter((record) => record.is_sequential).length;
  const attention = state.cases.filter((record) => curationGroup(record) === "attention").length;
  content.innerHTML = `
    ${breadcrumbs([])}
    <div class="browser-title-row">
      <div>
        <h1>ScaleBench case browser</h1>
        <p>Choose the benchmark task, then inspect its cases, audit decisions, and verification assets.</p>
      </div>
      <a class="button button-secondary button-small" href="#guide">Review guide</a>
    </div>
    <section class="dashboard-grid" aria-label="Case browser summary">
      <article class="dashboard-stat"><strong>${state.cases.length}</strong><span>Total cases</span></article>
      <article class="dashboard-stat"><strong>${sequential}</strong><span>Sequential</span></article>
      <article class="dashboard-stat"><strong>${state.cases.length - sequential}</strong><span>Combinational</span></article>
      <article class="dashboard-stat"><strong>${attention}</strong><span>Need attention</span></article>
    </section>
    <section aria-labelledby="task-list-title">
      <div class="browser-title-row">
        <div>
          <h2 id="task-list-title">Benchmark task</h2>
          <p>ScaleBench contains one direct, module-level generation task.</p>
        </div>
      </div>
      <article class="browser-card task-card">
        <span class="task-number" aria-hidden="true">01</span>
        <div>
          <h2>Specification-to-RTL generation</h2>
          <p>Natural-language specification → complete Verilog module → JasperGold SEC · 200 cases</p>
        </div>
        <a class="button button-primary button-small" href="#task=${TASK_KEY}">Browse 200 cases →</a>
      </article>
    </section>
  `;
}

function filteredCases(route) {
  const query = (route.get("q") || "").trim().toLowerCase();
  const type = route.get("type") || "all";
  const curation = route.get("curation") || "all";
  const review = route.get("review") || "all";

  return state.cases.filter((record) => {
    const matchesQuery = !query || record.task_id.toLowerCase().includes(query);
    const recordType = record.is_sequential ? "sequential" : "combinational";
    const matchesType = type === "all" || type === recordType;
    const matchesCuration = curation === "all" || curation === curationGroup(record);
    const isReviewed = state.reviewed.has(record.task_id);
    const matchesReview =
      review === "all" ||
      (review === "reviewed" && isReviewed) ||
      (review === "unreviewed" && !isReviewed);
    return matchesQuery && matchesType && matchesCuration && matchesReview;
  });
}

function selectOptions(options, selected) {
  return options
    .map(
      ([value, label]) =>
        `<option value="${escapeHtml(value)}" ${value === selected ? "selected" : ""}>${escapeHtml(label)}</option>`,
    )
    .join("");
}

function renderCaseList(route) {
  const matches = filteredCases(route);
  const requestedPage = Number.parseInt(route.get("page") || "1", 10);
  const totalPages = Math.max(1, Math.ceil(matches.length / PAGE_SIZE));
  const page = Math.min(Math.max(Number.isFinite(requestedPage) ? requestedPage : 1, 1), totalPages);
  const start = (page - 1) * PAGE_SIZE;
  const visibleCases = matches.slice(start, start + PAGE_SIZE);
  const type = route.get("type") || "all";
  const curation = route.get("curation") || "all";
  const review = route.get("review") || "all";
  const query = route.get("q") || "";

  const rows = visibleCases
    .map((record) => {
      const reviewed = state.reviewed.has(record.task_id);
      return `
        <tr>
          <td>${caseNumber(record)}</td>
          <td>
            <a class="design-name" href="${hashFor({ task: TASK_KEY, case: record.task_id })}">${escapeHtml(record.task_id)}</a>
          </td>
          <td>${record.is_sequential ? "Sequential" : "Combinational"}</td>
          <td>${record.loc}</td>
          <td>${curationPill(record)}</td>
          <td>${reviewed ? '<span class="pill pill-reviewed">Reviewed</span>' : '<span class="pill">Not reviewed</span>'}</td>
        </tr>
      `;
    })
    .join("");

  content.innerHTML = `
    ${breadcrumbs(["Specification-to-RTL"])}
    <div class="browser-title-row">
      <div>
        <h1>Specification-to-RTL generation</h1>
        <p>All cases use semantic design names. Select a row to inspect its complete human-review package.</p>
      </div>
      <span class="pill">${matches.length} of ${state.cases.length} cases</span>
    </div>
    <form class="filter-bar" id="case-filters">
      <label class="field">
        <span>Search semantic design names</span>
        <input name="q" type="search" value="${escapeHtml(query)}" placeholder="e.g. timer, packet, counter" autocomplete="off" />
      </label>
      <label class="field">
        <span>Design type</span>
        <select name="type">${selectOptions([
          ["all", "All types"],
          ["sequential", "Sequential"],
          ["combinational", "Combinational"],
        ], type)}</select>
      </label>
      <label class="field">
        <span>Curation</span>
        <select name="curation">${selectOptions([
          ["all", "All statuses"],
          ["ready", "Review ready"],
          ["repaired", "Prompt repaired"],
          ["attention", "Needs attention"],
        ], curation)}</select>
      </label>
      <label class="field">
        <span>Manual review</span>
        <select name="review">${selectOptions([
          ["all", "Any progress"],
          ["unreviewed", "Not reviewed"],
          ["reviewed", "Reviewed"],
        ], review)}</select>
      </label>
    </form>
    <div class="case-table-wrap">
      <table class="case-table">
        <thead>
          <tr>
            <th scope="col">Case</th>
            <th scope="col">Semantic design name</th>
            <th scope="col">Type</th>
            <th scope="col">Ref. LoC</th>
            <th scope="col">Curation status</th>
            <th scope="col">Manual review</th>
          </tr>
        </thead>
        <tbody>${rows || '<tr><td class="empty-table" colspan="6">No cases match these filters.</td></tr>'}</tbody>
      </table>
    </div>
    <div class="pager">
      <p>${matches.length ? `Showing ${start + 1}–${Math.min(start + PAGE_SIZE, matches.length)} of ${matches.length}` : "No matching cases"}</p>
      <div class="pager-actions">
        <button class="pager-button" type="button" data-page="${page - 1}" ${page <= 1 ? "disabled" : ""}>← Previous</button>
        <button class="pager-button" type="button" data-page="${page + 1}" ${page >= totalPages ? "disabled" : ""}>Next →</button>
      </div>
    </div>
  `;

  bindListControls(route);
}

function updateListRoute(route, changes) {
  const next = new URLSearchParams(route);
  Object.entries(changes).forEach(([key, value]) => {
    if (!value || value === "all") {
      next.delete(key);
    } else {
      next.set(key, value);
    }
  });
  next.set("task", TASK_KEY);
  if (!("page" in changes)) {
    next.delete("page");
  }
  window.location.hash = next.toString();
}

function bindListControls(route) {
  const form = document.querySelector("#case-filters");
  form.querySelectorAll("select").forEach((select) => {
    select.addEventListener("change", () => updateListRoute(route, { [select.name]: select.value }));
  });
  const search = form.querySelector('input[name="q"]');
  search.addEventListener("input", () => {
    window.clearTimeout(state.searchTimer);
    state.searchTimer = window.setTimeout(() => updateListRoute(route, { q: search.value.trim() }), 220);
  });
  document.querySelectorAll("[data-page]").forEach((button) => {
    button.addEventListener("click", () => updateListRoute(route, { page: button.dataset.page }));
  });
}

function auditRows(record, audit) {
  if (!audit) {
    return "<p>Audit data is unavailable for this case.</p>";
  }

  const fresh = [
    ["GPT-4o", audit.gpt4o_fresh],
    ["Claude Sonnet 4.5", audit.claude_sonnet_4_5_fresh],
    ["Qwen 3.5 397B", audit.qwen3_5_397b_fresh],
    ["DeepSeek V3.2", audit.deepseek_v3_2_fresh],
  ]
    .filter(([, value]) => value && value !== "—")
    .map(([model, value]) => `${escapeHtml(model)} ${resultPill(value)}`)
    .join(" ");

  return `
    <dl class="audit-list">
      <div><dt>Historical GPT-4o</dt><dd>${resultPill(audit.gpt4o_historical)}</dd></div>
      <div><dt>Historical Claude</dt><dd>${resultPill(audit.claude_sonnet_4_5_historical)}</dd></div>
      <div><dt>Failed by both</dt><dd>${audit.consistently_failed === "yes" ? '<span class="pill pill-fail">Yes</span>' : '<span class="pill pill-pass">No</span>'}</dd></div>
      <div><dt>Audit finding</dt><dd>${escapeHtml(audit.failure_reason_or_audit_finding)}</dd></div>
      <div><dt>Fix status</dt><dd>${escapeHtml(audit.fix_status)}</dd></div>
      <div><dt>Fresh evaluation</dt><dd>${fresh || '<span class="pill pill-pending">Not in fresh cohort</span>'}</dd></div>
    </dl>
  `;
}

function fileCard(record, key, title, filename, boundary, description) {
  return `
    <a class="file-card" href="${hashFor({ task: TASK_KEY, case: record.task_id, file: key })}">
      <span class="pill ${boundary.className}">${escapeHtml(boundary.label)}</span>
      <code>${escapeHtml(filename)}</code>
      <span>${escapeHtml(description)}</span>
    </a>
  `;
}

function renderCase(record) {
  const audit = state.auditById.get(record.task_id);
  const previous = state.cases[record.index - 1];
  const next = state.cases[record.index + 1];
  const reviewed = state.reviewed.has(record.task_id);
  const fixes = record.description_fixes || [];

  content.innerHTML = `
    ${breadcrumbs([
      `<a href="#task=${TASK_KEY}">Specification-to-RTL</a>`,
      escapeHtml(record.task_id),
    ])}
    <section class="case-heading">
      <div class="case-heading-top">
        <div>
          <p class="case-index">Case ${caseNumber(record)}</p>
          <h1>${escapeHtml(record.task_id)}</h1>
          <div class="pill-row">
            <span class="pill">${record.is_sequential ? "Sequential" : "Combinational"}</span>
            <span class="pill">${record.loc} reference LoC</span>
            ${curationPill(record)}
            ${fixes.length ? '<span class="pill pill-repaired">Description repaired</span>' : ""}
          </div>
        </div>
        <label class="review-toggle">
          <input id="reviewed-toggle" type="checkbox" ${reviewed ? "checked" : ""} />
          Reviewed locally
        </label>
      </div>
    </section>

    <div class="case-grid">
      <section class="browser-card" aria-labelledby="entry-title">
        <h2 id="entry-title">Agent entry point</h2>
        <table class="entry-table">
          <tbody>
            <tr><th scope="row">Model input</th><td><code class="inline-code">spec.txt</code></td></tr>
            <tr><th scope="row">Required output</th><td>One complete synthesizable Verilog module</td></tr>
            <tr><th scope="row">Top module</th><td><code class="inline-code">${escapeHtml(record.top_module)}</code></td></tr>
            <tr><th scope="row">Verification</th><td>JasperGold sequential equivalence checking</td></tr>
            <tr><th scope="row">Pass condition</th><td>Formal equivalence to the hidden reference design</td></tr>
          </tbody>
        </table>
        <p class="boundary-note"><strong>Evaluation boundary:</strong> give the evaluated model only <code>spec.txt</code>. The reference RTL, SEC script, audit findings, and historical results are human-review material.</p>
      </section>

      <section class="browser-card" aria-labelledby="audit-title">
        <h2 id="audit-title">Case audit</h2>
        ${auditRows(record, audit)}
      </section>

      <section class="browser-card file-section" aria-labelledby="files-title">
        <h2 id="files-title">Case files</h2>
        <div class="file-groups">
          ${fileCard(
            record,
            "spec",
            "Public model input",
            "spec.txt",
            { label: "Model input", className: "pill-ready" },
            "Natural-language design description and exact module interface.",
          )}
          ${fileCard(
            record,
            "reference",
            "Model-hidden reference",
            "reference.v",
            { label: "Model-hidden", className: "pill-hidden" },
            "Golden RTL used by the formal verification flow.",
          )}
          ${fileCard(
            record,
            "sec",
            "Human-only verification",
            "sec.tcl",
            { label: "Human-only", className: "pill-attention" },
            "JasperGold SEC setup retained with the case.",
          )}
        </div>
      </section>

      <nav class="case-navigation" aria-label="Adjacent cases">
        ${previous ? `<a href="${hashFor({ task: TASK_KEY, case: previous.task_id })}">← ${escapeHtml(previous.task_id)}</a>` : "<span></span>"}
        ${next ? `<a href="${hashFor({ task: TASK_KEY, case: next.task_id })}">${escapeHtml(next.task_id)} →</a>` : "<span></span>"}
      </nav>
    </div>
  `;

  document.querySelector("#reviewed-toggle").addEventListener("change", (event) => {
    if (event.target.checked) {
      state.reviewed.add(record.task_id);
      showToast(`Case ${caseNumber(record)} marked reviewed.`);
    } else {
      state.reviewed.delete(record.task_id);
      showToast(`Case ${caseNumber(record)} marked not reviewed.`);
    }
    saveReviewedCases();
  });
}

function fileDefinition(record, fileKey) {
  const definitions = {
    spec: {
      label: "Specification",
      filename: "spec.txt",
      path: record.spec_path,
      boundary: "Model input",
      boundaryClass: "pill-ready",
    },
    reference: {
      label: "Reference RTL",
      filename: "reference.v",
      path: record.reference_path,
      boundary: "Model-hidden",
      boundaryClass: "pill-hidden",
    },
    sec: {
      label: "SEC script",
      filename: "sec.tcl",
      path: record.sec_tcl_path,
      boundary: "Human-only",
      boundaryClass: "pill-attention",
    },
  };
  return definitions[fileKey];
}

async function renderFile(record, fileKey) {
  const definition = fileDefinition(record, fileKey);
  if (!definition) {
    renderNotFound("Unknown case file.");
    return;
  }

  const routeIdentity = window.location.hash;
  content.innerHTML = `
    ${breadcrumbs([
      `<a href="#task=${TASK_KEY}">Specification-to-RTL</a>`,
      `<a href="${hashFor({ task: TASK_KEY, case: record.task_id })}">${escapeHtml(record.task_id)}</a>`,
      escapeHtml(definition.filename),
    ])}
    <div class="browser-card">
      <div class="file-header">
        <div>
          <div class="pill-row"><span class="pill ${definition.boundaryClass}">${escapeHtml(definition.boundary)}</span></div>
          <h1>${escapeHtml(definition.label)} · ${escapeHtml(definition.filename)}</h1>
          <p>${escapeHtml(definition.path)}</p>
        </div>
        <a class="button button-secondary button-small" href="./${encodeURI(definition.path)}" download>Download raw file</a>
      </div>
      <div class="loading-state"><span class="loading-mark" aria-hidden="true"></span><p>Loading file…</p></div>
    </div>
  `;

  try {
    const response = await fetch(`./${definition.path}`);
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }
    const fileText = await response.text();
    if (window.location.hash !== routeIdentity) {
      return;
    }
    const card = content.querySelector(".browser-card");
    card.querySelector(".loading-state").remove();
    const code = document.createElement("pre");
    code.className = "code-viewer";
    code.textContent = fileText;
    card.append(code);
  } catch (error) {
    if (window.location.hash !== routeIdentity) {
      return;
    }
    content.querySelector(".loading-state").innerHTML = `<p>Could not load this file: ${escapeHtml(error.message)}</p>`;
  }
}

function renderGuide() {
  content.innerHTML = `
    ${breadcrumbs(["Review guide"])}
    <div class="browser-title-row">
      <div>
        <h1>Review guide</h1>
        <p>Use this browser to audit benchmark content. Keep the evaluation boundary intact when running a model.</p>
      </div>
      <a class="button button-primary button-small" href="#task=${TASK_KEY}">Browse cases →</a>
    </div>
    <div class="guide-grid">
      <section class="browser-card">
        <h2>Recommended review order</h2>
        <ol>
          <li>Read <code>spec.txt</code> and confirm that its behavior and interface are complete.</li>
          <li>Inspect <code>reference.v</code> for consistency with the specification.</li>
          <li>Check <code>sec.tcl</code> and the case curation status.</li>
          <li>Read the historical failure finding and any prompt-repair status.</li>
          <li>Mark the case reviewed locally before moving to the next case.</li>
        </ol>
      </section>
      <section class="browser-card">
        <h2>Evaluation boundary</h2>
        <ul>
          <li><strong>Give the model:</strong> only <code>spec.txt</code>.</li>
          <li><strong>Collect:</strong> one complete Verilog implementation with the named top module.</li>
          <li><strong>Keep hidden:</strong> <code>reference.v</code>, <code>sec.tcl</code>, audit findings, and baseline outcomes.</li>
          <li><strong>Score:</strong> pass only when JasperGold SEC proves equivalence.</li>
        </ul>
      </section>
      <section class="browser-card">
        <h2>Curation labels</h2>
        <p><span class="pill pill-ready">Review ready</span> has no confirmed dataset defect.</p>
        <p><span class="pill pill-repaired">Repaired</span> has a documented description repair.</p>
        <p><span class="pill pill-attention">Needs attention</span> is quarantined or blocked and should not enter aggregate evaluation unchanged.</p>
      </section>
      <section class="browser-card">
        <h2>Manual review state</h2>
        <p>The “Reviewed locally” checkbox is stored only in this browser. It does not alter repository data and is never uploaded.</p>
        <p>Use the filters in the all-case table to show reviewed, unreviewed, repaired, or attention-required cases.</p>
      </section>
    </div>
  `;
}

function renderNotFound(message) {
  content.innerHTML = `
    <div class="error-state">
      <h1>Case not found</h1>
      <p>${escapeHtml(message)}</p>
      <p><a href="#task=${TASK_KEY}">Return to all cases</a></p>
    </div>
  `;
}

function renderRoute() {
  const route = currentRoute();
  if (route.has("guide")) {
    renderGuide();
  } else if (route.get("case")) {
    const record = state.caseById.get(route.get("case"));
    if (!record) {
      renderNotFound("The requested semantic design name is not in ScaleBench.");
    } else if (route.get("file")) {
      renderFile(record, route.get("file"));
    } else {
      renderCase(record);
    }
  } else if (route.get("task")) {
    renderCaseList(route);
  } else {
    renderDashboard();
  }
  window.scrollTo({ top: 0, behavior: "auto" });
}

async function initialize() {
  try {
    const [manifestResponse, auditResponse] = await Promise.all([
      fetch(MANIFEST_URL),
      fetch(AUDIT_URL),
    ]);
    if (!manifestResponse.ok || !auditResponse.ok) {
      throw new Error("The benchmark index could not be loaded.");
    }

    state.cases = await manifestResponse.json();
    if (state.cases.length !== 200) {
      throw new Error(`Expected 200 cases, found ${state.cases.length}.`);
    }
    state.caseById = new Map(state.cases.map((record) => [record.task_id, record]));
    const auditRowsData = parseCsv(await auditResponse.text());
    state.auditById = new Map(auditRowsData.map((row) => [row.task_id, row]));

    window.addEventListener("hashchange", renderRoute);
    renderRoute();
  } catch (error) {
    content.innerHTML = `
      <div class="error-state">
        <h1>Could not load ScaleBench</h1>
        <p>${escapeHtml(error.message)}</p>
        <p>Serve the built site over HTTP; browser security blocks dataset loading from a local file URL.</p>
      </div>
    `;
  }
}

initialize();
