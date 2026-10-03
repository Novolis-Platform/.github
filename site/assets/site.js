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
    if (!failed || !repoGrid) return;
    const org = failed.dataset.org || 'Novolis-Platform';
    const stamp = document.getElementById('status-stamp');
    if (stamp) stamp.textContent = 'Checking GitHub…';
    const count = document.getElementById('failed-count');
    if (count) count.textContent = '…';

    const cards = [...repoGrid.querySelectorAll('.repo-card')];
    const checks = await Promise.all(cards.map((card) => checkMerge(org, card)));
    const failures = checks.filter((row) => row && row.conclusion === 'failure');
    applyFailures(failed, org, failures);
    if (count) count.textContent = String(failures.length);
    if (stamp) stamp.textContent = 'Live ' + formatWhen(new Date().toISOString());
  }

  async function checkMerge(org, card) {
    const heading = card.querySelector('h3');
    const repo = heading ? heading.textContent.trim() : '';
    if (!repo) return null;
    const href = 'https://github.com/' + org + '/' + repo + '/actions/workflows/merge.yml';
    let message = '';
    try {
      const response = await fetch(
        'https://img.shields.io/github/actions/workflow/status/'
        + encodeURIComponent(org) + '/' + encodeURIComponent(repo) + '/merge.yml.json');
      if (response.ok) {
        const body = await response.json();
        message = body && body.message ? body.message : '';
      }
    } catch {
      message = '';
    }

    const meta = card.querySelector('.repo-meta');
    if (meta) {
      for (const node of [...meta.querySelectorAll(':scope > a.live-merge, :scope > a.status-label')]) {
        const text = node.textContent || '';
        if (node.classList.contains('live-merge') || text.includes('Merge failed') || text.includes('Merge cancelled')) {
          node.remove();
        }
      }
    }

    if (message === 'passing') {
      if (meta) meta.appendChild(statusChip(href, 'ok', 'Merge passed'));
      return null;
    }
    if (message !== 'failing' && message !== 'cancelled') return null;
    if (meta) meta.appendChild(statusChip(href, 'fail', message === 'cancelled' ? 'Merge cancelled' : 'Merge failed'));
    return {
      repo: repo,
      workflow: 'merge.yml',
      conclusion: message === 'cancelled' ? 'cancelled' : 'failure',
      when: 'latest',
      url: href,
      error: 'Latest merge workflow is ' + message + '.'
    };
  }

  function statusChip(href, kind, label) {
    const link = document.createElement('a');
    link.className = 'status-label live-merge mark-' + (kind === 'ok' ? 'ok' : 'fail');
    link.href = href;
    const icon = document.querySelector(kind === 'ok' ? '.mark-ok svg' : '.mark-fail svg');
    if (icon) link.appendChild(icon.cloneNode(true));
    const span = document.createElement('span');
    span.textContent = label;
    link.appendChild(span);
    return link;
  }

  function formatWhen(iso) {
    const date = new Date(iso);
    const y = date.getUTCFullYear();
    const m = String(date.getUTCMonth() + 1).padStart(2, '0');
    const d = String(date.getUTCDate()).padStart(2, '0');
    const h = String(date.getUTCHours()).padStart(2, '0');
    const min = String(date.getUTCMinutes()).padStart(2, '0');
    return y + '-' + m + '-' + d + ' ' + h + ':' + min + ' UTC';
  }

  function applyFailures(failed, org, failures) {
    const wanted = new Map(failures.map((row) => [row.repo + '\n' + row.workflow, row]));
    for (const existing of [...failed.querySelectorAll('tbody tr[data-repo]')]) {
      const key = existing.dataset.repo + '\n' + existing.dataset.workflow;
      const next = wanted.get(key);
      if (!next) {
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
    const empty = [...failed.querySelectorAll('p')].find((node) => /^(No failed|Checking)/.test(node.textContent));
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
    tr.dataset.repo = row.repo || '';
    tr.dataset.workflow = row.workflow || '';
    tr.dataset.run = row.url || '';
    tr.replaceChildren(
      textCell(row.when || '', 'status-mono'),
      linkCell('https://github.com/' + org + '/' + row.repo, row.repo || ''),
      textCell('merge', ''),
      resultCell(row.conclusion, row.url),
      textCell(row.error || '', ''));
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
    const cancelled = conclusion === 'cancelled';
    link.className = 'status-label ' + (cancelled ? 'mark-cancel' : 'mark-fail');
    const icon = document.querySelector(cancelled ? '.mark-cancel svg' : '.mark-fail svg');
    if (icon) link.appendChild(icon.cloneNode(true));
    const span = document.createElement('span');
    span.textContent = cancelled ? 'cancelled' : 'failed';
    link.appendChild(span);
    td.appendChild(link);
    return td;
  }
})();
