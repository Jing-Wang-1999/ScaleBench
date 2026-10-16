"use strict";

const TASK_KEY = "spec2rtl";
const PAGE_SIZE = 50;
const MANIFEST_URL = "./data/manifest.json";

const content = document.querySelector("#content");
const state = {
  cases: [],
  caseById: new Map(),
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

function caseNumber(record) {
  return String(record.index + 1).padStart(3, "0");
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

function breadcrumbs(parts) {
  const entries = ['<a href="./review.html">Case browser</a>'];
  parts.forEach((part) => {
    entries.push(`<span aria-hidden="true">/</span><span>${part}</span>`);
  });
  return `<nav class="browser-crumbs" aria-label="Breadcrumb">${entries.join("")}</nav>`;
}

function renderDashboard() {
  const sequential = state.cases.filter((record) => record.is_sequential).length;
  const locations = state.cases.map((record) => record.loc);
  content.innerHTML = `
    ${breadcrumbs([])}
    <div class="browser-title-row">
      <div>
        <h1>ScaleBench case browser</h1>
        <p>Open the benchmark task to inspect every specification, reference implementation, and verification script.</p>
      </div>
      <a class="button button-secondary button-small" href="#guide">Evaluation guide</a>
    </div>
    <section class="dashboard-grid" aria-label="Case browser summary">
      <article class="dashboard-stat"><strong>${state.cases.length}</strong><span>Total cases</span></article>
      <article class="dashboard-stat"><strong>${sequential}</strong><span>Sequential</span></article>
      <article class="dashboard-stat"><strong>${state.cases.length - sequential}</strong><span>Combinational</span></article>
      <article class="dashboard-stat"><strong>${Math.min(...locations)}–${Math.max(...locations)}</strong><span>Reference LoC</span></article>
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

  return state.cases.filter((record) => {
    const matchesQuery = !query || record.task_id.toLowerCase().includes(query);
    const recordType = record.is_sequential ? "sequential" : "combinational";
    return matchesQuery && (type === "all" || type === recordType);
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
  const safeRequestedPage = Number.isFinite(requestedPage) ? requestedPage : 1;
  const page = Math.min(Math.max(safeRequestedPage, 1), totalPages);
  const start = (page - 1) * PAGE_SIZE;
  const visibleCases = matches.slice(start, start + PAGE_SIZE);
  const type = route.get("type") || "all";
  const query = route.get("q") || "";

  const rows = visibleCases
    .map(
      (record) => `
        <tr>
          <td>${caseNumber(record)}</td>
          <td>
            <a class="design-name" href="${hashFor({ task: TASK_KEY, case: record.task_id })}">${escapeHtml(record.task_id)}</a>
          </td>
          <td>${record.is_sequential ? "Sequential" : "Combinational"}</td>
          <td>${record.loc}</td>
        </tr>
      `,
    )
    .join("");

  content.innerHTML = `
    ${breadcrumbs(["Specification-to-RTL"])}
    <div class="browser-title-row">
      <div>
        <h1>Specification-to-RTL generation</h1>
        <p>All 200 cases use semantic design names. Select a row to inspect its complete case package.</p>
      </div>
      <span class="pill">${matches.length} of ${state.cases.length} cases</span>
    </div>
    <form class="filter-bar filter-bar-compact" id="case-filters">
      <label class="field">
        <span>Search semantic design names</span>
        <input name="q" type="search" value="${escapeHtml(query)}" placeholder="e.g. timer, packet, counter" autocomplete="off" />
      </label>
      <label class="field">
        <span>Design type</span>
        <select name="type">${selectOptions(
          [
            ["all", "All types"],
            ["sequential", "Sequential"],
            ["combinational", "Combinational"],
          ],
          type,
        )}</select>
      </label>
    </form>
    <div class="case-table-wrap">
      <table class="case-table">
        <thead>
          <tr>
            <th scope="col">Case</th>
            <th scope="col">Semantic design name</th>
            <th scope="col">Type</th>
            <th scope="col">Reference LoC</th>
          </tr>
        </thead>
        <tbody>${rows || '<tr><td class="empty-table" colspan="4">No cases match these filters.</td></tr>'}</tbody>
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
  const type = form.querySelector('select[name="type"]');
  type.addEventListener("change", () => updateListRoute(route, { type: type.value }));

  const search = form.querySelector('input[name="q"]');
  search.addEventListener("input", () => {
    window.clearTimeout(state.searchTimer);
    state.searchTimer = window.setTimeout(
      () => updateListRoute(route, { q: search.value.trim() }),
      220,
    );
  });

  document.querySelectorAll("[data-page]").forEach((button) => {
    button.addEventListener("click", () => updateListRoute(route, { page: button.dataset.page }));
  });
}

function fileCard(record, key, filename, boundary, description) {
  return `
    <a class="file-card" href="${hashFor({ task: TASK_KEY, case: record.task_id, file: key })}">
      <span class="pill ${boundary.className}">${escapeHtml(boundary.label)}</span>
      <code>${escapeHtml(filename)}</code>
      <span>${escapeHtml(description)}</span>
    </a>
  `;
}

function renderCase(record) {
  const previous = state.cases[record.index - 1];
  const next = state.cases[record.index + 1];

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
          </div>
        </div>
      </div>
    </section>

    <div class="case-grid case-grid-single">
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
        <p class="boundary-note"><strong>Evaluation boundary:</strong> give the evaluated model only <code>spec.txt</code>. Keep <code>reference.v</code> and <code>sec.tcl</code> hidden until scoring.</p>
      </section>

      <section class="browser-card file-section" aria-labelledby="files-title">
        <h2 id="files-title">Case files</h2>
        <div class="file-groups">
          ${fileCard(
            record,
            "spec",
            "spec.txt",
            { label: "Model input", className: "pill-public" },
            "Natural-language design description and exact module interface.",
          )}
          ${fileCard(
            record,
            "reference",
            "reference.v",
            { label: "Model-hidden", className: "pill-hidden" },
            "Golden RTL used by the formal verification flow.",
          )}
          ${fileCard(
            record,
            "sec",
            "sec.tcl",
            { label: "Verifier", className: "pill-verifier" },
            "JasperGold sequential-equivalence setup for the case.",
          )}
        </div>
      </section>

      <nav class="case-navigation" aria-label="Adjacent cases">
        ${previous ? `<a href="${hashFor({ task: TASK_KEY, case: previous.task_id })}">← ${escapeHtml(previous.task_id)}</a>` : "<span></span>"}
        ${next ? `<a href="${hashFor({ task: TASK_KEY, case: next.task_id })}">${escapeHtml(next.task_id)} →</a>` : "<span></span>"}
      </nav>
    </div>
  `;
}

function fileDefinition(record, fileKey) {
  const definitions = {
    spec: {
      label: "Specification",
      filename: "spec.txt",
      path: record.spec_path,
      boundary: "Model input",
      boundaryClass: "pill-public",
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
      boundary: "Verifier",
      boundaryClass: "pill-verifier",
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
    ${breadcrumbs(["Evaluation guide"])}
    <div class="browser-title-row">
      <div>
        <h1>Evaluation guide</h1>
        <p>Use the case browser to understand the task package while keeping model input separate from verifier assets.</p>
      </div>
      <a class="button button-primary button-small" href="#task=${TASK_KEY}">Browse cases →</a>
    </div>
    <div class="guide-grid">
      <section class="browser-card">
        <h2>Case package</h2>
        <ol>
          <li><code>spec.txt</code> defines the required behavior, top module, and interface.</li>
          <li><code>reference.v</code> is the golden implementation used only for scoring.</li>
          <li><code>sec.tcl</code> configures JasperGold sequential equivalence checking.</li>
        </ol>
      </section>
      <section class="browser-card">
        <h2>Evaluation boundary</h2>
        <ul>
          <li><strong>Give the model:</strong> only <code>spec.txt</code>.</li>
          <li><strong>Collect:</strong> one complete Verilog implementation with the named top module.</li>
          <li><strong>Keep hidden:</strong> <code>reference.v</code> and <code>sec.tcl</code>.</li>
          <li><strong>Score:</strong> pass only when JasperGold SEC proves equivalence.</li>
        </ul>
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
    const manifestResponse = await fetch(MANIFEST_URL);
    if (!manifestResponse.ok) {
      throw new Error("The benchmark index could not be loaded.");
    }

    state.cases = await manifestResponse.json();
    if (state.cases.length !== 200) {
      throw new Error(`Expected 200 cases, found ${state.cases.length}.`);
    }
    state.caseById = new Map(state.cases.map((record) => [record.task_id, record]));

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
