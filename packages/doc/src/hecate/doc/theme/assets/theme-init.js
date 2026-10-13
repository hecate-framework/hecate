/* Runs in <head> before first paint: applies the stored colour theme and flags that
   scripting is available. Stored value: "light" or "dark"; absent means "follow the system". */
(function () {
  var root = document.documentElement;
  try {
    var stored = localStorage.getItem("hecate-theme");
    if (stored === "light" || stored === "dark") root.setAttribute("data-theme", stored);
  } catch (error) { /* storage unavailable: follow the system */ }
  root.classList.add("js");
})();
