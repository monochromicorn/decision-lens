// Progressive enhancement only: the app works with plain HTML form posts.
(function () {
  var form = document.querySelector("[data-analyze-form]");
  if (!form) return;

  var textarea = form.querySelector("textarea");
  var counter = form.querySelector("[data-count]");
  var submit = form.querySelector("[data-submit]");
  var max = parseInt(textarea.dataset.max, 10);

  function updateCount() {
    var length = textarea.value.trim().length;
    counter.textContent = length;
    counter.parentElement.classList.toggle("over", length > max);
  }

  form.querySelectorAll("[data-sample-text]").forEach(function (link) {
    link.addEventListener("click", function (event) {
      event.preventDefault();
      textarea.value = link.dataset.sampleText;
      updateCount();
      textarea.focus();
    });
  });

  textarea.addEventListener("input", updateCount);

  form.addEventListener("submit", function (event) {
    if (submit.disabled) {
      event.preventDefault();
      return;
    }
    submit.disabled = true;
    submit.setAttribute("aria-busy", "true");
    submit.textContent = "Analyzing…";
  });

  // Restore the button when returning via the back/forward cache.
  window.addEventListener("pageshow", function () {
    submit.disabled = false;
    submit.removeAttribute("aria-busy");
    submit.textContent = "Analyze decision";
  });

  updateCount();
})();
