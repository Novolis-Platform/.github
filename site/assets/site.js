(function () {
  const repoSearch = document.getElementById('portfolioSearch');
  const repoGrid = document.getElementById('repoGrid');
  const docSearch = document.getElementById('docSearch');
  const docGrid = document.getElementById('docGrid');
  const filterButtons = Array.from(document.querySelectorAll('[data-kind]'));
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
    const cards = Array.from(docGrid.querySelectorAll('.doc-card'));
    for (const card of cards) {
      card.hidden = query && !(card.dataset.search || '').includes(query);
    }
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
})();
