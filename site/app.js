const yearNodes = document.querySelectorAll("[data-current-year]");

for (const node of yearNodes) {
  node.textContent = String(new Date().getFullYear());
}
