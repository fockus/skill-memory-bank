const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

if (!("IntersectionObserver" in window) || reduceMotion) {
  document.documentElement.classList.add("no-observer");
} else {
  const observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) {
          entry.target.classList.add("in-view");
          observer.unobserve(entry.target);
        }
      }
    },
    // threshold 0 (was 0.08): a tall block may never reach 8% visibility on
    // shorter viewports and would stay invisible forever.
    { rootMargin: "0px 0px -8% 0px", threshold: 0 }
  );

  for (const node of document.querySelectorAll(".reveal")) {
    observer.observe(node);
  }
}
