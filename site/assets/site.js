(function () {
  const repoSearch = document.getElementById('portfolioSearch');
  const repoGrid = document.getElementById('repoGrid');
  const docSearch = document.getElementById('docSearch');
  const docGrid = document.getElementById('docGrid');
  const docRepoFilter = document.getElementById('docRepoFilter');
  const docKindFilter = document.getElementById('docKindFilter');
  const filterButtons = Array.from(document.querySelectorAll('.segmented [data-kind]'));
  let activeKind = 'all';

  function normalize(value) {
    return (value || '').trim().toLowerCase();
  }

  function applyRepoFilters() {
    if (!repoGrid) return;
    const query = normalize(repoSearch && repoSearch.value);
    const cards = Array.from(repoGrid.querySelectorAll('.repo-card'));
    for (const card of cards) {
      const matchesKind = activeKind === 'all' || card.dataset.kind === activeKind;
      const matchesQuery = !query || (card.dataset.search || '').includes(query);
      card.hidden = !(matchesKind && matchesQuery);
    }
  }

  function applyDocFilters() {
    if (!docGrid) return;
    const query = normalize(docSearch && docSearch.value);
    const repo = (docRepoFilter && docRepoFilter.value) || 'all';
    const kind = (docKindFilter && docKindFilter.value) || 'all';
    const cards = Array.from(docGrid.querySelectorAll('.doc-card'));
    for (const card of cards) {
      const matchesQuery = !query || (card.dataset.search || '').includes(query);
      const matchesRepo = repo === 'all' || card.dataset.docGroup === repo;
      const matchesKind = kind === 'all' || card.dataset.docKind === kind;
      card.hidden = !(matchesQuery && matchesRepo && matchesKind);
    }
  }

  function applyQueryParams() {
    const params = new URLSearchParams(window.location.search);
    const repo = params.get('repo');
    const kind = params.get('kind');
    const q = params.get('q');
    if (repo && docRepoFilter) {
      const option = Array.from(docRepoFilter.options).find((item) => item.value === repo);
      if (option) docRepoFilter.value = repo;
    }
    if (kind && docKindFilter) {
      const option = Array.from(docKindFilter.options).find((item) => item.value === kind);
      if (option) docKindFilter.value = kind;
    }
    if (q && docSearch) docSearch.value = q;
    applyDocFilters();
  }

  for (const button of filterButtons) {
    button.addEventListener('click', () => {
      activeKind = button.dataset.kind || 'all';
      for (const item of filterButtons) item.classList.toggle('active', item === button);
      applyRepoFilters();
    });
  }

  if (repoSearch) repoSearch.addEventListener('input', applyRepoFilters);
  if (docSearch) docSearch.addEventListener('input', applyDocFilters);
  if (docRepoFilter) docRepoFilter.addEventListener('change', applyDocFilters);
  if (docKindFilter) docKindFilter.addEventListener('change', applyDocFilters);

  applyRepoFilters();
  applyQueryParams();
})();
