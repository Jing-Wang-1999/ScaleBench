"use strict";

const DATASET_SIZE = 200;
const REVIEW_STORAGE_KEY = "scalebench-reviewed-v1";

const state = {
  cases: [],
  auditByTask: new Map(),
  filteredCases: [],
  selectedTaskId: null,
  activeTab: "spec",
  contentCache: new Map(),
  reviewed: loadReviewedCases(),
};

const elements = {};

document.addEventListener("DOMContentLoaded", initialize);

async function initialize() {
  bindElements();
  bindControls();

  try {
    const [manifestResponse, auditResponse] = await Promise.all([
      fetch("./data/manifest.json"),
      fetch("./review/all_case_audit.csv"),
    ]);
    if (!manifestResponse.ok || !auditResponse.ok) {
      throw new Error("The dataset files could not be loaded.");
    }

    const cases = await manifestResponse.json();
    const auditRows = parseCsv(await auditResponse.text());
    validateDataset(cases, auditRows);

    state.cases = cases;
    state.auditByTask = new Map(auditRows.map((row) => [row.task_id, row]));
    updateSummary();
    applyFilters();

    const requestedTask = taskFromHash();
    const initialCase =
      state.cases.find((item) => item.task_id === requestedTask) || state.cases[0];
    selectCase(initialCase.task_id, { updateHash: !requestedTask });
  } catch (error) {
    renderLoadError(error);
  }
}

function bindElements() {
  const ids = [
    "stat-total",
    "stat-sequential",
    "stat-combinational",
    "stat-reviewed",
    "result-count",
    "search-input",
    "type-filter",
    "curation-filter",
    "review-filter",
    "sort-select",
    "case-list",
    "case-detail",
    "toast",
  ];
  for (const id of ids) {
    elements[toCamelCase(id)] = document.getElementById(id);
  }
}

function bindControls() {
  elements.searchInput.addEventListener("input", applyFilters);
  elements.typeFilter.addEventListener("change", applyFilters);
  elements.curationFilter.addEventListener("change", applyFilters);
  elements.reviewFilter.addEventListener("change", applyFilters);
  elements.sortSelect.addEventListener("change", applyFilters);
  window.addEventListener("hashchange", () => {
    const taskId = taskFromHash();
    if (taskId && taskId !== state.selectedTaskId) {
      const item = state.cases.find((candidate) => candidate.task_id === taskId);
      if (item) {
        selectCase(item.task_id, { updateHash: false });
      }
    }
  });
}

function validateDataset(cases, auditRows) {
  if (!Array.isArray(cases) || cases.length !== DATASET_SIZE) {
    throw new Error(`Expected ${DATASET_SIZE} cases, found ${cases?.length ?? 0}.`);
  }
  if (auditRows.length !== DATASET_SIZE) {
    throw new Error(`Expected ${DATASET_SIZE} audit rows, found ${auditRows.length}.`);
  }
  const taskIds = new Set();
  for (const item of cases) {
    if (!/^[a-z][a-z0-9_]*$/.test(item.task_id)) {
      throw new Error(`Invalid public task name at case ${item.index + 1}.`);
    }
    if (taskIds.has(item.task_id)) {
      throw new Error(`Duplicate public task name: ${item.task_id}`);
    }
    taskIds.add(item.task_id);
  }
}

function updateSummary() {
  const sequential = state.cases.filter((item) => item.is_sequential).length;
  elements.statTotal.textContent = state.cases.length;
  elements.statSequential.textContent = sequential;
  elements.statCombinational.textContent = state.cases.length - sequential;
  elements.statReviewed.textContent = state.reviewed.size;
}

function applyFilters() {
  const query = elements.searchInput.value.trim().toLowerCase();
  const type = elements.typeFilter.value;
  const curation = elements.curationFilter.value;
  const review = elements.reviewFilter.value;

  state.filteredCases = state.cases.filter((item) => {
    const matchesQuery =
      !query ||
      item.task_id.includes(query) ||
      humanize(item.task_id).toLowerCase().includes(query) ||
      String(item.index + 1).padStart(3, "0").includes(query);
    const matchesType =
      type === "all" ||
      (type === "sequential" && item.is_sequential) ||
      (type === "combinational" && !item.is_sequential);
    const category = curationCategory(item);
    const matchesCuration = curation === "all" || category === curation;
    const isReviewed = state.reviewed.has(item.task_id);
    const matchesReview =
      review === "all" ||
      (review === "reviewed" && isReviewed) ||
      (review === "unreviewed" && !isReviewed);
    return matchesQuery && matchesType && matchesCuration && matchesReview;
  });

  const sort = elements.sortSelect.value;
  state.filteredCases.sort((left, right) => {
    if (sort === "name") {
      return left.task_id.localeCompare(right.task_id);
    }
    if (sort === "loc-desc") {
      return right.loc - left.loc || left.index - right.index;
    }
    if (sort === "loc-asc") {
      return left.loc - right.loc || left.index - right.index;
    }
    return left.index - right.index;
  });

  renderCaseList();
}

function renderCaseList() {
  elements.resultCount.textContent = `${state.filteredCases.length} of ${state.cases.length}`;
  if (state.filteredCases.length === 0) {
    elements.caseList.innerHTML =
      '<div class="no-results">No cases match these filters.</div>';
    return;
  }

  elements.caseList.innerHTML = state.filteredCases
    .map((item) => {
      const selected = item.task_id === state.selectedTaskId;
      const reviewedClass = state.reviewed.has(item.task_id) ? " is-reviewed" : "";
      const designType = item.is_sequential ? "Sequential" : "Combinational";
      return `
        <button
          class="case-row"
          type="button"
          role="option"
          aria-selected="${selected}"
          data-task-id="${escapeHtml(item.task_id)}"
        >
          <span class="case-number">#${formatCaseNumber(item.index)}</span>
          <span>
            <span class="case-name">${escapeHtml(item.task_id)}</span>
            <span class="case-subtitle">${designType} · ${item.loc} LoC</span>
          </span>
          <span class="review-dot${reviewedClass}" aria-label="${
            reviewedClass ? "Reviewed" : "Not reviewed"
          }"></span>
        </button>`;
    })
    .join("");

  for (const row of elements.caseList.querySelectorAll("[data-task-id]")) {
    row.addEventListener("click", () => selectCase(row.dataset.taskId));
  }
}

function selectCase(taskId, options = {}) {
  const item = state.cases.find((candidate) => candidate.task_id === taskId);
  if (!item) {
    return;
  }
  state.selectedTaskId = taskId;
  state.activeTab = "spec";
  if (options.updateHash !== false) {
    history.replaceState(null, "", `#case=${encodeURIComponent(taskId)}`);
  }
  renderCaseList();
  renderCaseDetail(item);
  void loadActiveFile(item);
}

function renderCaseDetail(item) {
  const audit = state.auditByTask.get(item.task_id);
  const category = curationCategory(item);
  const statusLabel = curationLabel(item.curation_status);
  const position = state.filteredCases.findIndex(
    (candidate) => candidate.task_id === item.task_id,
  );
  const previous = position > 0 ? state.filteredCases[position - 1] : null;
  const next =
    position >= 0 && position < state.filteredCases.length - 1
      ? state.filteredCases[position + 1]
      : null;

  elements.caseDetail.innerHTML = `
    <header class="detail-header">
      <div class="detail-kicker">
        <span>Case ${formatCaseNumber(item.index)} of ${state.cases.length}</span>
        <span>${item.loc} reference LoC</span>
      </div>
      <h2>${escapeHtml(item.task_id)}</h2>
      <p class="human-title">${escapeHtml(humanize(item.task_id))}</p>
      <div class="meta-strip">
        <span class="badge">${item.is_sequential ? "Sequential" : "Combinational"}</span>
        <span class="badge badge-${category}">${escapeHtml(statusLabel)}</span>
        ${item.description_fixes.length ? '<span class="badge badge-repaired">Prompt repaired</span>' : ""}
        ${item.review_flags.length ? `<span class="badge badge-attention">${item.review_flags.length} review flag${item.review_flags.length === 1 ? "" : "s"}</span>` : ""}
      </div>
      <label class="review-toggle">
        <input id="review-checkbox" type="checkbox" ${
          state.reviewed.has(item.task_id) ? "checked" : ""
        } />
        Mark this case reviewed on this browser
      </label>
    </header>
    ${renderAuditCard(audit)}
    <div class="tab-bar" role="tablist" aria-label="Case files">
      ${tabButton("spec", "Specification")}
      ${tabButton("reference", "Reference RTL")}
      ${tabButton("sec", "SEC script")}
    </div>
    <section class="code-panel" aria-label="Selected case file">
      <div class="code-toolbar">
        <span id="file-label">${escapeHtml(fileDescriptor(item, state.activeTab).label)}</span>
        <span class="code-actions">
          <button id="copy-button" type="button">Copy</button>
          <a id="raw-file-link" href="./${escapeHtml(
            fileDescriptor(item, state.activeTab).path,
          )}" download>Download</a>
        </span>
      </div>
      <pre><code id="file-content" class="loading-code">Loading file…</code></pre>
    </section>
    <nav class="case-navigation" aria-label="Case navigation">
      <button type="button" id="previous-case" ${previous ? "" : "disabled"}>
        ${previous ? `← #${formatCaseNumber(previous.index)} ${escapeHtml(previous.task_id)}` : "← Previous"}
      </button>
      <button type="button" id="next-case" ${next ? "" : "disabled"}>
        ${next ? `#${formatCaseNumber(next.index)} ${escapeHtml(next.task_id)} →` : "Next →"}
      </button>
    </nav>`;

  document.getElementById("review-checkbox").addEventListener("change", (event) => {
    setReviewed(item.task_id, event.target.checked);
  });
  for (const button of elements.caseDetail.querySelectorAll("[data-tab]")) {
    button.addEventListener("click", () => setActiveTab(item, button.dataset.tab));
  }
  document.getElementById("copy-button").addEventListener("click", copyActiveFile);
  if (previous) {
    document
      .getElementById("previous-case")
      .addEventListener("click", () => selectCase(previous.task_id));
  }
  if (next) {
    document
      .getElementById("next-case")
      .addEventListener("click", () => selectCase(next.task_id));
  }
}

function renderAuditCard(audit) {
  if (!audit) {
    return "";
  }
  const bothFail = audit.consistently_failed === "yes" ? "Yes" : "No";
  return `
    <section class="audit-card" aria-label="Evaluation and curation audit">
      <h3>Evaluation and curation audit</h3>
      <div class="audit-grid">
        ${auditItem("Historical GPT-4o", audit.gpt4o_historical)}
        ${auditItem("Historical Claude", audit.claude_sonnet_4_5_historical)}
        ${auditItem("Failed both", bothFail)}
        ${auditItem("Fix status", audit.fix_status)}
        ${auditItem("Fresh GPT-4o", audit.gpt4o_fresh)}
        ${auditItem("Fresh Qwen / DeepSeek", `${audit.qwen3_5_397b_fresh} / ${audit.deepseek_v3_2_fresh}`)}
      </div>
      <p class="audit-finding">${escapeHtml(audit.failure_reason_or_audit_finding)}</p>
    </section>`;
}

function auditItem(label, value) {
  const display = value && value !== "—" ? value : "Not rerun";
  return `<div class="audit-item"><span>${escapeHtml(label)}</span><strong>${escapeHtml(
    display,
  )}</strong></div>`;
}

function tabButton(tab, label) {
  const selected = tab === state.activeTab;
  return `<button class="tab-button" type="button" role="tab" data-tab="${tab}" aria-selected="${selected}">${label}</button>`;
}

function setActiveTab(item, tab) {
  state.activeTab = tab;
  for (const button of elements.caseDetail.querySelectorAll("[data-tab]")) {
    button.setAttribute("aria-selected", String(button.dataset.tab === tab));
  }
  const descriptor = fileDescriptor(item, tab);
  document.getElementById("file-label").textContent = descriptor.label;
  document.getElementById("raw-file-link").href = `./${descriptor.path}`;
  const content = document.getElementById("file-content");
  content.classList.add("loading-code");
  content.textContent = "Loading file…";
  void loadActiveFile(item);
}

async function loadActiveFile(item) {
  const descriptor = fileDescriptor(item, state.activeTab);
  const selectedPath = descriptor.path;
  const contentElement = document.getElementById("file-content");
  if (!contentElement) {
    return;
  }
  try {
    let content = state.contentCache.get(selectedPath);
    if (content === undefined) {
      const response = await fetch(`./${selectedPath}`);
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
      }
      content = await response.text();
      state.contentCache.set(selectedPath, content);
    }
    const current = state.cases.find(
      (candidate) => candidate.task_id === state.selectedTaskId,
    );
    if (!current || fileDescriptor(current, state.activeTab).path !== selectedPath) {
      return;
    }
    contentElement.classList.remove("loading-code");
    contentElement.textContent = content;
  } catch (error) {
    contentElement.classList.remove("loading-code");
    contentElement.textContent = `Unable to load ${selectedPath}: ${error.message}`;
  }
}

function fileDescriptor(item, tab) {
  if (tab === "reference") {
    return { path: item.reference_path, label: "reference.v" };
  }
  if (tab === "sec") {
    return { path: item.sec_tcl_path, label: "sec.tcl" };
  }
  return { path: item.spec_path, label: "spec.txt" };
}

async function copyActiveFile() {
  const content = document.getElementById("file-content")?.textContent || "";
  try {
    await navigator.clipboard.writeText(content);
    showToast("Copied to clipboard");
  } catch {
    const textarea = document.createElement("textarea");
    textarea.value = content;
    textarea.style.position = "fixed";
    textarea.style.opacity = "0";
    document.body.appendChild(textarea);
    textarea.select();
    document.execCommand("copy");
    textarea.remove();
    showToast("Copied to clipboard");
  }
}

function setReviewed(taskId, isReviewed) {
  if (isReviewed) {
    state.reviewed.add(taskId);
  } else {
    state.reviewed.delete(taskId);
  }
  localStorage.setItem(REVIEW_STORAGE_KEY, JSON.stringify([...state.reviewed].sort()));
  updateSummary();
  applyFilters();
  showToast(isReviewed ? "Marked reviewed" : "Review mark removed");
}

function loadReviewedCases() {
  try {
    const saved = JSON.parse(localStorage.getItem(REVIEW_STORAGE_KEY) || "[]");
    return new Set(Array.isArray(saved) ? saved : []);
  } catch {
    return new Set();
  }
}

function curationCategory(item) {
  if (
    item.curation_status.startsWith("blocked_") ||
    item.curation_status.startsWith("quarantined_") ||
    item.review_flags.length
  ) {
    return "attention";
  }
  if (item.curation_status.startsWith("repaired_") || item.description_fixes.length) {
    return "repaired";
  }
  return "ready";
}

function curationLabel(status) {
  const labels = {
    review_ready: "Review ready",
    repaired_review_ready: "Repaired · review ready",
    repaired_evaluation_ready: "Repaired · evaluation ready",
    blocked_missing_memory_image: "Blocked · missing memory image",
    quarantined_golden_pathology: "Golden RTL quarantined",
  };
  return labels[status] || humanize(status);
}

function formatCaseNumber(index) {
  return String(index + 1).padStart(3, "0");
}

function humanize(value) {
  return value
    .split("_")
    .filter(Boolean)
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(" ");
}

function taskFromHash() {
  const match = location.hash.match(/^#case=(.+)$/);
  return match ? decodeURIComponent(match[1]) : null;
}

function renderLoadError(error) {
  elements.caseDetail.innerHTML = `
    <div class="error-state">
      <h2>Viewer data did not load</h2>
      <p>${escapeHtml(error.message)} Serve the built site over HTTP rather than opening it as a local file.</p>
    </div>`;
  elements.resultCount.textContent = "Unavailable";
}

function showToast(message) {
  elements.toast.textContent = message;
  elements.toast.classList.add("is-visible");
  window.clearTimeout(showToast.timeoutId);
  showToast.timeoutId = window.setTimeout(() => {
    elements.toast.classList.remove("is-visible");
  }, 1800);
}

function parseCsv(text) {
  const records = [];
  let record = [];
  let field = "";
  let quoted = false;

  for (let index = 0; index < text.length; index += 1) {
    const character = text[index];
    if (quoted) {
      if (character === '"' && text[index + 1] === '"') {
        field += '"';
        index += 1;
      } else if (character === '"') {
        quoted = false;
      } else {
        field += character;
      }
    } else if (character === '"') {
      quoted = true;
    } else if (character === ",") {
      record.push(field);
      field = "";
    } else if (character === "\n") {
      record.push(field.replace(/\r$/, ""));
      records.push(record);
      record = [];
      field = "";
    } else {
      field += character;
    }
  }
  if (field || record.length) {
    record.push(field);
    records.push(record);
  }

  const [headers, ...rows] = records.filter((row) => row.some(Boolean));
  return rows.map((row) =>
    Object.fromEntries(headers.map((header, index) => [header, row[index] ?? ""])),
  );
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function toCamelCase(value) {
  return value.replace(/-([a-z])/g, (_, letter) => letter.toUpperCase());
}
