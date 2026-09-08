(() => {
  const header = document.querySelector(".site-header");
  const toggle = document.querySelector(".nav-toggle");
  const nav = document.querySelector(".site-nav");

  if (header) {
    const onScroll = () => header.classList.toggle("is-scrolled", window.scrollY > 8);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
  }

  if (toggle && nav) {
    toggle.addEventListener("click", () => {
      const open = nav.classList.toggle("is-open");
      toggle.setAttribute("aria-expanded", String(open));
    });
    nav.querySelectorAll("a").forEach((link) => {
      link.addEventListener("click", () => {
        nav.classList.remove("is-open");
        toggle.setAttribute("aria-expanded", "false");
      });
    });
  }

  document.querySelectorAll("[data-year]").forEach((el) => {
    el.textContent = String(new Date().getFullYear());
  });

  const watch = document.querySelector(".watch");
  const switcher = document.querySelector(".watch-switch");
  if (watch && switcher) {
    switcher.querySelectorAll("button").forEach((btn) => {
      btn.addEventListener("click", () => {
        switcher.querySelectorAll("button").forEach((other) => {
          other.setAttribute("aria-selected", String(other === btn));
        });
        watch.dataset.bezel = btn.dataset.watch;
      });
    });
  }

  setupDemo();
})();

function setupDemo() {
  const usBtn = document.querySelector('[data-side="us"]');
  const themBtn = document.querySelector('[data-side="them"]');
  if (!usBtn || !themBtn) return;

  const usScore = document.getElementById("score-us");
  const themScore = document.getElementById("score-them");
  const gamesEl = document.getElementById("demo-games");
  const statusEl = document.getElementById("demo-status");
  const resetBtn = document.getElementById("demo-reset");

  const LABELS = ["0", "15", "30", "40"];
  const state = resetState();
  let undo = null;
  let undoTimer = 0;

  function resetState() {
    return {
      us: 0,
      them: 0,
      usGames: 0,
      themGames: 0,
      server: "us",
      message: "Tap to score",
      hot: false,
    };
  }

  function pointLabel(side, other) {
    if (side >= 3 && other >= 3) {
      if (side === other) return "40";
      if (side === other + 1) return "Ad";
      return "40";
    }
    return LABELS[Math.min(side, 3)];
  }

  function render() {
    usScore.textContent = pointLabel(state.us, state.them);
    themScore.textContent = pointLabel(state.them, state.us);
    gamesEl.textContent = `${state.usGames} – ${state.themGames}`;
    statusEl.textContent = state.message;
    statusEl.classList.toggle("is-hot", state.hot);
    usBtn.classList.toggle("is-serving", state.server === "us");
    themBtn.classList.toggle("is-serving", state.server === "them");
  }

  function clearUndo() {
    if (undo) {
      cancelAnimationFrame(undoTimer);
      undo.btn.style.removeProperty("--p");
      undo.ring.hidden = true;
      undo = null;
    }
  }

  function startUndo(side, btn) {
    clearUndo();
    const ring = btn.querySelector(".undo-ring");
    ring.hidden = false;
    const started = performance.now();
    undo = { side, btn, ring, started };
    const tick = (now) => {
      if (!undo) return;
      const p = Math.min(100, ((now - undo.started) / 3000) * 100);
      btn.style.setProperty("--p", String(p));
      if (p >= 100) {
        clearUndo();
        return;
      }
      undoTimer = requestAnimationFrame(tick);
    };
    undoTimer = requestAnimationFrame(tick);
  }

  function award(side) {
    if (undo && undo.side === side) {
      undoPoint();
      return;
    }

    state[side] += 1;
    const other = side === "us" ? "them" : "us";
    const wonGame = state[side] >= 4 && state[side] - state[other] >= 2;

    usBtn.classList.toggle("demo-flash", side === "us");
    themBtn.classList.toggle("demo-flash", side === "them");
    setTimeout(() => {
      usBtn.classList.remove("demo-flash");
      themBtn.classList.remove("demo-flash");
    }, 280);

    if (wonGame) {
      clearUndo();
      state[`${side}Games`] += 1;
      state.us = 0;
      state.them = 0;
      state.server = state.server === "us" ? "them" : "us";
      const setOver =
        (state.usGames >= 6 || state.themGames >= 6) &&
        Math.abs(state.usGames - state.themGames) >= 2;

      if (setOver) {
        state.message = `Set ${state.usGames}–${state.themGames}`;
        state.hot = true;
        render();
        setTimeout(() => {
          Object.assign(state, resetState());
          state.message = "New set — tap to score";
          render();
        }, 1600);
        return;
      }

      state.message = side === "us" ? "Game, us" : "Game, them";
      state.hot = false;
      render();
      return;
    }

    if (state.us >= 3 && state.them >= 3 && state.us === state.them) {
      state.message = "Deuce";
      state.hot = false;
    } else if (state.us >= 4 && state.us === state.them + 1) {
      state.message = "Advantage us";
      state.hot = true;
    } else if (state.them >= 4 && state.them === state.us + 1) {
      state.message = "Advantage them";
      state.hot = true;
    } else {
      state.message = "Point";
      state.hot = false;
    }

    startUndo(side, side === "us" ? usBtn : themBtn);
    render();
  }

  function undoPoint() {
    if (!undo) return;
    state[undo.side] = Math.max(0, state[undo.side] - 1);
    state.message = "Point undone";
    state.hot = false;
    clearUndo();
    render();
  }

  usBtn.addEventListener("click", () => award("us"));
  themBtn.addEventListener("click", () => award("them"));
  resetBtn?.addEventListener("click", () => {
    clearUndo();
    Object.assign(state, resetState());
    render();
  });

  render();
}
