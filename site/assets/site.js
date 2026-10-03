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
    if (!failed) return;
    const org = failed.dataset.org || 'Novolis-Platform';
    const snapshot = await fetchSnapshot(org);
    if (snapshot) applySnapshot(failed, org, snapshot);

    const live = await fetchLive(org);
    if (live) {
      const failures = liveFailures(live, snapshot);
      applyFailures(failed, org, failures);
      const count = document.getElementById('failed-count');
      if (count) count.textContent = String(failures.length);
      const stamp = document.getElementById('status-stamp');
      if (stamp) stamp.textContent = 'Live ' + formatWhen(new Date().toISOString());
      syncCards(live);
      return;
    }

    const painted = snapshot && Array.isArray(snapshot.failures) ? snapshot.failures : [];
    const stillFailed = await dropPassing(org, painted);
    applyFailures(failed, org, stillFailed);
    const count = document.getElementById('failed-count');
    if (count) count.textContent = String(stillFailed.length);
    const stamp = document.getElementById('status-stamp');
    if (stamp) stamp.textContent = 'Live ' + formatWhen(new Date().toISOString());
  }

  async function dropPassing(org, failures) {
    const checks = await Promise.all(failures.map(async (row) => {
      const file = (row.workflow || '').toLowerCase().includes('release') ? 'release.yml' : 'merge.yml';
      try {
        const response = await fetch(
          'https://img.shields.io/github/actions/workflow/status/'
          + encodeURIComponent(org) + '/' + encodeURIComponent(row.repo) + '/' + encodeURIComponent(file) + '.json');
        if (!response.ok) return row;
        const body = await response.json();
        return body && body.message === 'passing' ? null : row;
      } catch {
        return row;
      }
    }));
    return checks.filter(Boolean);
  }

  async function fetchSnapshot(org) {
    try {
      const response = await fetch(
        'https://raw.githubusercontent.com/' + encodeURIComponent(org) + '/.github/main/site/status.json');
      if (!response.ok) return null;
      return await response.json();
    } catch {
      return null;
    }
  }

  function applySnapshot(failed, org, snapshot) {
    const failures = Array.isArray(snapshot.failures) ? snapshot.failures : [];
    applyFailures(failed, org, failures);
    const count = document.getElementById('failed-count');
    if (count) count.textContent = String(failures.length);
    const shipped = document.querySelector('.telemetry-panel .mark-ship span');
    if (shipped && snapshot.releasedRepoCount != null) shipped.textContent = String(snapshot.releasedRepoCount);
    const packages = document.querySelector('.telemetry-panel .mark-package span');
    if (packages && snapshot.packageCount != null) packages.textContent = String(snapshot.packageCount);
    const stamp = document.getElementById('status-stamp');
    if (stamp && snapshot.generatedAt) stamp.textContent = 'Snapshot ' + snapshot.generatedAt;
    syncNuget(snapshot.repos || []);
  }

  async function fetchLive(org) {
    const query = `
      query($org: String!) {
        organization(login: $org) {
          repositories(first: 100, privacy: PUBLIC) {
            nodes {
              name
              isArchived
              defaultBranchRef {
                target {
                  ... on Commit {
                    statusCheckRollup { state }
                    checkSuites(first: 8) {
                      nodes {
                        conclusion
                        status
                        workflowRun { url displayTitle event createdAt workflow { name } }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }`;
    try {
      const response = await fetch('https://api.github.com/graphql', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ query: query, variables: { org: org } })
      });
      if (!response.ok) return null;
      const body = await response.json();
      const nodes = body && body.data && body.data.organization && body.data.organization.repositories
        ? body.data.organization.repositories.nodes
        : null;
      return Array.isArray(nodes) ? nodes : null;
    } catch {
      return null;
    }
  }

  function liveFailures(nodes, snapshot) {
    const rows = [];
    const decided = new Set();
    for (const repo of nodes) {
      if (!repo || repo.isArchived || repo.name === '.github') continue;
      const commit = repo.defaultBranchRef && repo.defaultBranchRef.target;
      const suites = commit && commit.checkSuites && commit.checkSuites.nodes ? commit.checkSuites.nodes : [];
      for (const workflow of ['Merge', 'Release']) {
        const suite = suites.find((item) => workflowNameOf(item) === workflow);
        if (!suite) continue;
        const file = workflow === 'Release' ? 'release.yml' : 'merge.yml';
        decided.add(repo.name + '\n' + file);
        if (isBad(suite.conclusion)) rows.push(failureRow(repo.name, workflow, suite, snapshot));
      }
    }
    // A commit that skipped CI has no suite. Keep that repository's snapshot row.
    for (const row of (snapshot && snapshot.failures) || []) {
      if (row && !decided.has(row.repo + '\n' + row.workflow)) rows.push(row);
    }
    rows.sort((a, b) => (a.when < b.when ? 1 : a.when > b.when ? -1 : 0));
    return rows;
  }

  function workflowNameOf(suite) {
    return suite.workflowRun && suite.workflowRun.workflow && suite.workflowRun.workflow.name;
  }

  function failureRow(repo, workflow, suite, snapshot) {
    const run = suite.workflowRun || {};
    const file = workflow === 'Release' ? 'release.yml' : 'merge.yml';
    const conclusion = String(suite.conclusion || '').toLowerCase() === 'cancelled' ? 'cancelled' : 'failure';
    const prior = snapshot && Array.isArray(snapshot.failures)
      ? snapshot.failures.find((row) => row.url === run.url)
      : null;
    return {
      repo: repo,
      workflow: file,
      conclusion: conclusion,
      when: formatWhen(run.createdAt),
      title: run.displayTitle || '',
      url: run.url || '',
      error: (prior && prior.error) || run.displayTitle || ''
    };
  }

  function isBad(conclusion) {
    const value = String(conclusion || '').toUpperCase();
    return value === 'FAILURE' || value === 'CANCELLED' || value === 'TIMED_OUT' || value === 'STARTUP_FAILURE';
  }

  function formatWhen(iso) {
    if (!iso) return '';
    const date = new Date(iso);
    if (Number.isNaN(date.getTime())) return '';
    const y = date.getUTCFullYear();
    const m = String(date.getUTCMonth() + 1).padStart(2, '0');
    const d = String(date.getUTCDate()).padStart(2, '0');
    const h = String(date.getUTCHours()).padStart(2, '0');
    const min = String(date.getUTCMinutes()).padStart(2, '0');
    return y + '-' + m + '-' + d + ' ' + h + ':' + min + ' UTC';
  }

  function syncCards(nodes) {
    const byName = new Map();
    for (const repo of nodes) {
      if (!repo || repo.isArchived) continue;
      const commit = repo.defaultBranchRef && repo.defaultBranchRef.target;
      const suites = commit && commit.checkSuites && commit.checkSuites.nodes ? commit.checkSuites.nodes : [];
      byName.set(repo.name, suites);
    }
    for (const card of document.querySelectorAll('.repo-card')) {
      const heading = card.querySelector('h3');
      const name = heading ? heading.textContent.trim() : '';
      if (!byName.has(name)) continue;
      const meta = card.querySelector('.repo-meta');
      if (!meta) continue;
      syncKind(meta, byName.get(name), 'Merge');
      syncKind(meta, byName.get(name), 'Release');
    }
  }

  function syncKind(meta, suites, workflowName) {
    const suite = suites.find((item) => workflowNameOf(item) === workflowName);
    if (!suite) return;
    for (const node of [...meta.querySelectorAll(':scope > a.status-label, :scope > span.status-label')]) {
      const text = node.textContent || '';
      if (text.includes(workflowName + ' failed') || text.includes(workflowName + ' cancelled')) node.remove();
    }
    if (!isBad(suite.conclusion) || !suite.workflowRun) return;
    const cancelled = String(suite.conclusion).toUpperCase() === 'CANCELLED';
    meta.appendChild(failChip(suite.workflowRun.url, workflowName + (cancelled ? ' cancelled' : ' failed')));
  }

  function failChip(href, label) {
    const link = document.createElement('a');
    link.className = 'status-label mark-fail';
    link.href = href || '#failed';
    const icon = document.querySelector('.mark-fail svg');
    if (icon) link.appendChild(icon.cloneNode(true));
    const span = document.createElement('span');
    span.textContent = label;
    link.appendChild(span);
    return link;
  }

  function syncNuget(repos) {
    const byName = new Map(repos.filter((repo) => repo && repo.name).map((repo) => [repo.name, repo]));
    for (const card of document.querySelectorAll('.repo-card')) {
      const heading = card.querySelector('h3');
      const name = heading ? heading.textContent.trim() : '';
      const repo = byName.get(name);
      const version = card.querySelector('.repo-meta .mark-nuget .status-mono');
      if (!repo || !version) continue;
      version.textContent = repo.nugetVersion ? repo.nugetVersion : 'missing';
    }
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

  function linkCell(href, text, className) {
    const td = document.createElement('td');
    const link = document.createElement('a');
    link.href = href;
    if (className) link.className = className;
    link.textContent = text;
    td.appendChild(link);
    return td;
  }

  function resultCell(conclusion, url) {
    const td = document.createElement('td');
    const link = document.createElement('a');
    link.href = url || '#';
    link.className = 'status-label ' + (conclusion === 'cancelled' ? 'mark-cancel' : 'mark-fail');
    const icon = document.querySelector(conclusion === 'cancelled' ? '.mark-cancel svg' : '.mark-fail svg');
    if (icon) link.appendChild(icon.cloneNode(true));
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
