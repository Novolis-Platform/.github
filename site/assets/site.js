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
})();
