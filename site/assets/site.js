(function () {
  const repoSearch = document.getElementById('portfolioSearch');
  const repoGrid = document.getElementById('repoGrid');

  function normalize(value) {
    return (value || '').trim().toLowerCase();
  }

  function applyRepoFilters() {
    if (!repoGrid) return;
    const query = normalize(repoSearch && repoSearch.value);
    for (const card of repoGrid.querySelectorAll('.repo-card')) {
      card.hidden = query && !(card.dataset.search || '').includes(query);
    }
  }

  if (repoSearch) repoSearch.addEventListener('input', applyRepoFilters);
  applyRepoFilters();
  loadLandingStatus();

  async function loadLandingStatus() {
    const failed = document.getElementById('failed');
    if (!failed || !failed.dataset.org) return;
    const org = failed.dataset.org;
    let snapshot;
    try {
      const response = await fetch(
        'https://api.github.com/repos/' + encodeURIComponent(org) + '/.github/contents/site/status.json?ref=main',
        { headers: { Accept: 'application/vnd.github.raw+json' } });
      if (!response.ok) return;
      snapshot = await response.json();
    } catch {
      return;
    }

    const failures = Array.isArray(snapshot.failures) ? snapshot.failures : [];
    applyFailures(failed, org, failures);
    const count = document.getElementById('failed-count');
    if (count) count.textContent = String(failures.length);
    const stamp = document.getElementById('status-stamp');
    if (stamp && snapshot.generatedAt) stamp.textContent = 'Snapshot ' + snapshot.generatedAt;
  }

  function applyFailures(failed, org, failures) {
    const wanted = new Map(failures.map((row) => [row.repo + '\n' + row.workflow, row]));
    for (const existing of [...failed.querySelectorAll('tbody tr[data-repo]')]) {
      const key = existing.dataset.repo + '\n' + existing.dataset.workflow;
      const next = wanted.get(key);
      if (!next) {
        dropFailedLink(existing.dataset.run);
        existing.remove();
        continue;
      }
      wanted.delete(key);
      fillFailureRow(existing, org, next);
    }

    const leftover = [...wanted.values()];
    if (leftover.length === 0 && failed.querySelectorAll('tbody tr').length === 0) {
      showEmptyFailures(failed);
      return;
    }
    if (leftover.length === 0) return;

    const tbody = ensureFailureTable(failed);
    for (const row of leftover) tbody.appendChild(fillFailureRow(document.createElement('tr'), org, row));
  }

  function ensureFailureTable(failed) {
    const empty = [...failed.querySelectorAll('p')].find((node) => node.textContent.startsWith('No failed'));
    if (empty) empty.remove();
    let tbody = failed.querySelector('tbody');
    if (tbody) return tbody;
    const wrap = document.createElement('div');
    wrap.className = 'status-scroll';
    wrap.innerHTML = '<table class="status-table"><thead><tr><th>When</th><th>Repository</th><th>Workflow</th><th>Result</th><th>Error</th></tr></thead><tbody></tbody></table>';
    failed.appendChild(wrap);
    return wrap.querySelector('tbody');
  }

  function showEmptyFailures(failed) {
    const table = failed.querySelector('.status-scroll');
    if (table) table.remove();
    if ([...failed.querySelectorAll('p')].some((node) => node.textContent.startsWith('No failed'))) return;
    const empty = document.createElement('p');
    empty.textContent = 'No failed or cancelled merge runs.';
    failed.appendChild(empty);
  }

  function fillFailureRow(tr, org, row) {
    const previous = tr.dataset.run || '';
    tr.dataset.repo = row.repo || '';
    tr.dataset.workflow = row.workflow || '';
    tr.dataset.run = row.url || '';
    tr.replaceChildren(
      textCell(row.when || '', 'status-mono'),
      linkCell('https://github.com/' + org + '/' + row.repo, row.repo || ''),
      textCell(workflowName(row.workflow), ''),
      resultCell(row.conclusion, row.url),
      textCell(row.error || row.title || '', ''));
    if (previous && previous !== row.url) dropFailedLink(previous);
    return tr;
  }

  function textCell(text, className) {
    const td = document.createElement('td');
    if (className) td.className = className;
    td.textContent = text;
    return td;
  }

  function linkCell(href, text) {
    const td = document.createElement('td');
    const link = document.createElement('a');
    link.href = href;
    link.textContent = text;
    td.appendChild(link);
    return td;
  }

  function resultCell(conclusion, url) {
    const td = document.createElement('td');
    const link = document.createElement('a');
    link.href = url || '#';
    link.className = 'status-label ' + (conclusion === 'cancelled' ? 'mark-cancel' : 'mark-fail');
    const span = document.createElement('span');
    span.textContent = conclusion === 'cancelled' ? 'cancelled' : 'failed';
    link.appendChild(span);
    td.appendChild(link);
    return td;
  }

  function workflowName(workflow) {
    return (workflow || '').toLowerCase().includes('release') ? 'release' : 'merge';
  }

  function dropFailedLink(url) {
    if (!url) return;
    for (const link of [...document.querySelectorAll('a.mark-fail')]) {
      if (link.getAttribute('href') === url) link.remove();
    }
  }
})();
