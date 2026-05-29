(function () {
  var header = document.querySelector("[data-site-header]");
  var toggle = document.querySelector("[data-nav-toggle]");
  var links = document.querySelector("[data-nav-links]");
  var reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  function setScrolledState() {
    if (!header) return;
    header.classList.toggle("is-scrolled", window.scrollY > 8);
  }

  function closeMenu() {
    if (!toggle || !links) return;
    toggle.setAttribute("aria-expanded", "false");
    links.classList.remove("is-open");
    document.body.classList.remove("nav-open");
  }

  if (toggle && links) {
    toggle.addEventListener("click", function () {
      var isOpen = toggle.getAttribute("aria-expanded") === "true";
      toggle.setAttribute("aria-expanded", String(!isOpen));
      links.classList.toggle("is-open", !isOpen);
      document.body.classList.toggle("nav-open", !isOpen);
    });

    links.addEventListener("click", function (event) {
      if (event.target && event.target.tagName === "A") {
        closeMenu();
      }
    });

    window.addEventListener("keydown", function (event) {
      if (event.key === "Escape") {
        closeMenu();
      }
    });
  }

  if (!reducedMotion) {
    var revealItems = Array.prototype.slice.call(
      document.querySelectorAll(
        ".section-heading, .two-column > *, .feature-card, .mock-panel, .split-feature > div:last-child, .privacy-layout > *, .privacy-points > div, .steps article, .faq-grid details, .launch-panel > *, .content-card, .policy-aside, .support-aside"
      )
    );

    document.body.classList.add("motion-ready");

    revealItems.forEach(function (item, index) {
      item.classList.add("reveal-item");
      item.style.setProperty("--reveal-delay", Math.min((index % 6) * 70, 350) + "ms");
    });

    if ("IntersectionObserver" in window) {
      var observer = new IntersectionObserver(
        function (entries) {
          entries.forEach(function (entry) {
            if (entry.isIntersecting) {
              entry.target.classList.add("is-visible");
              observer.unobserve(entry.target);
            }
          });
        },
        { rootMargin: "0px 0px -12% 0px", threshold: 0.16 }
      );

      revealItems.forEach(function (item) {
        observer.observe(item);
      });
    } else {
      revealItems.forEach(function (item) {
        item.classList.add("is-visible");
      });
    }
  }

  setScrolledState();
  window.addEventListener("scroll", setScrolledState, { passive: true });
})();
