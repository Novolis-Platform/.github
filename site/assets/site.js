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
  refreshFailedRuns();

  function refreshFailedRuns() {
    const failed = document.getElementById('failed');
    if (!failed) return;
    const org = failed.dataset.org;
    const rows = [...failed.querySelectorAll('tbody tr[data-repo][data-workflow]')];
    if (!org || rows.length === 0) return;

    Promise.all(rows.map((row) => refreshFailedRow(org, row))).then(() => {
      const left = failed.querySelectorAll('tbody tr').length;
      const count = document.getElementById('failed-count');
      if (count) count.textContent = String(left);
      if (left === 0) {
        const table = failed.querySelector('.status-scroll');
        if (table) table.remove();
        const empty = document.createElement('p');
        empty.textContent = 'No failed or cancelled merge runs.';
        failed.appendChild(empty);
      }
      const stamp = document.getElementById('status-stamp');
      if (stamp && !stamp.dataset.live) {
        stamp.dataset.live = '1';
        stamp.textContent = stamp.textContent + ' · latest runs checked';
      }
    });
  }

  async function refreshFailedRow(org, row) {
    const repo = row.dataset.repo;
    const workflow = row.dataset.workflow;
    const url = 'https://api.github.com/repos/' + encodeURIComponent(org) + '/' + encodeURIComponent(repo) +
      '/actions/workflows/' + encodeURIComponent(workflow) + '/runs?per_page=8&exclude_pull_requests=true';
    let payload;
    try {
      const response = await fetch(url, { headers: { Accept: 'application/vnd.github+json' } });
      if (!response.ok) return;
      payload = await response.json();
    } catch {
      return;
    }

    const latest = (payload.workflow_runs || [])[0];
    if (!latest) return;
    const previous = row.dataset.run || '';
    const next = latest.html_url || previous;

    if (latest.status !== 'completed') {
      setFailedResult(row, previous, next, 'running');
      return;
    }

    if (latest.conclusion === 'success') {
      dropFailedLinks(previous);
      row.remove();
      return;
    }

    if (latest.conclusion !== 'failure' && latest.conclusion !== 'cancelled') return;

    const when = row.querySelector('td');
    if (when && latest.created_at) when.textContent = formatUtc(latest.created_at);
    setFailedResult(row, previous, next, latest.conclusion);
    if (next !== previous && latest.display_title) {
      const cells = row.querySelectorAll('td');
      const error = cells[cells.length - 1];
      if (error) error.textContent = latest.display_title;
    }
    row.dataset.run = next;
  }

  function setFailedResult(row, previous, next, conclusion) {
    const link = row.querySelector('td:nth-child(4) a, td:nth-child(4) .status-label');
    if (!link) return;
    if (previous && next && previous !== next) {
      for (const other of document.querySelectorAll('a.mark-fail')) {
        if (other.getAttribute('href') === previous) other.setAttribute('href', next);
      }
    }
    if (next && link.getAttribute('href') !== undefined) link.setAttribute('href', next);
    const span = link.querySelector('span');
    const word = conclusion === 'failure' ? 'failed' : conclusion === 'cancelled' ? 'cancelled' : 'running';
    if (span) span.textContent = word;
    link.classList.remove('mark-fail', 'mark-cancel', 'mark-merge');
    link.classList.add(conclusion === 'cancelled' ? 'mark-cancel' : conclusion === 'failure' ? 'mark-fail' : 'mark-merge');
  }

  function dropFailedLinks(url) {
    if (!url) return;
    for (const link of [...document.querySelectorAll('a.mark-fail')]) {
      if (link.getAttribute('href') === url) link.remove();
    }
  }

  function formatUtc(iso) {
    const date = new Date(iso);
    if (Number.isNaN(date.getTime())) return iso;
    const pad = (value) => String(value).padStart(2, '0');
    return date.getUTCFullYear() + '-' + pad(date.getUTCMonth() + 1) + '-' + pad(date.getUTCDate()) +
      ' ' + pad(date.getUTCHours()) + ':' + pad(date.getUTCMinutes()) + ' UTC';
  }
})();
