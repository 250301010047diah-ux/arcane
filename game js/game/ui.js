import { BUFFS } from "./data.js";
import { drawAnimatedFit, drawAtlas, drawFrameInCell, findFrame } from "./assets.js";

const SPLASH_MIN_MS = 1400;

export function createUI(mount) {
  const splashShownAt = performance.now();
  const shell = document.createElement("section");
  shell.className = "game-shell";
  shell.innerHTML = `
    <canvas class="game-canvas game-surface" aria-label="Arena Arcane Siege"></canvas>
    <div class="hud-layer">
      <div class="hud-row main-hud">
        <div class="hud-cluster">
          <div class="pip-row hp-row" aria-label="HP"></div>
          <span class="badge score-badge">✦ <strong data-ui="score">0</strong></span>
          <span class="badge coin-badge"><canvas data-ui="coin-icon"></canvas><strong data-ui="coins">0</strong></span>
        </div>
        <div class="realm-chip">
          <small data-ui="realm-step">REALM 1/10</small>
          <strong data-ui="realm-name">Hutan Terpesona</strong>
        </div>
        <span class="badge timer-badge" data-ui="timer">45</span>
      </div>
      <div class="boss-meter" data-ui="boss-meter" hidden>
        <div class="boss-label"><span data-ui="boss-name">BOSS</span><span data-ui="boss-phase"></span></div>
        <div class="boss-track"><i data-ui="boss-fill"></i></div>
      </div>
      <div class="buff-strip" data-ui="buff-strip"></div>
    </div>
    <div class="center-prompt" data-ui="prompt">Sentuh kontrol untuk mulai</div>
    <div class="toast" data-ui="toast" hidden></div>
    <div class="overlay" data-ui="overlay" hidden></div>
    <div class="hud-tools">
      <button class="tool-btn pause-btn" data-ui="pause-btn" aria-label="Jeda">
        <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 5h3.5v14H7zM13.5 5H17v14h-3.5z" fill="currentColor"/></svg>
      </button>
      <button class="tool-btn" data-ui="volume-btn" aria-label="Pengaturan suara">
        <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 9h4l5-4v14l-5-4H4z" fill="currentColor"/><path class="sound-waves" d="M16 8.5a4.5 4.5 0 0 1 0 7M18.5 6a8 8 0 0 1 0 12" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><path class="sound-off" d="M16.5 9.5l5 5m0-5l-5 5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>
      </button>
      <button class="tool-btn" data-ui="help-btn" aria-label="Tutorial">?</button>
    </div>
    <div class="modal" data-ui="modal" hidden></div>
    <div class="controls-row game-controls" aria-label="Kontrol permainan">
      <div class="move-controls">
        <div class="joystick" data-ui="joystick" role="slider" aria-label="Gerak kiri/kanan"><i class="joystick-knob"></i></div>
      </div>
      <div class="action-controls">
        <button class="control-btn action-btn skill-btn skill-one-btn" data-action="skill1" aria-label="S1"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M13.5 2 5 13.5h6.2L9.5 22 19 9.8h-6.3z" fill="currentColor"/></svg><span class="control-label">S1</span><i data-ui="skill1-ring"></i></button>
        <button class="control-btn action-btn skill-btn skill-two-btn" data-action="skill2" aria-label="S2"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2.8 19.2 6v5.8c0 4.6-3 8-7.2 9.6-4.2-1.6-7.2-5-7.2-9.6V6z" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linejoin="round"/><path d="m8.6 12 2.4 2.4 4.6-4.8" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg><span class="control-label">S2</span><i data-ui="skill2-ring"></i></button>
        <button class="control-btn action-btn ultimate-btn" data-action="ultimate" aria-label="ULT"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="m12 1.8 2.7 6.5 7 .6-5.3 4.6 1.6 6.9L12 16.8l-6 3.6 1.6-6.9L2.3 8.9l7-.6z" fill="currentColor"/></svg><span class="control-label">ULT</span><i data-ui="ultimate-ring"></i></button>
        <button class="control-btn action-btn dash-btn" data-action="dash" aria-label="DASH"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M2.5 8h7M1.5 12h8M2.5 16h7" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/><path d="M12 5.5 21 12l-9 6.5z" fill="currentColor"/></svg><span class="control-label">DASH</span><i data-ui="dash-ring"></i></button>
        <button class="control-btn action-btn jump-btn" data-action="jump" aria-label="JUMP"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="m5.5 13.5 6.5-6.5 6.5 6.5M5.5 19.5l6.5-6.5 6.5 6.5" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/></svg><span class="control-label">JUMP</span></button>
        <button class="control-btn action-btn fire-btn" data-action="fire" aria-label="FIRE"><svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="6.5" fill="none" stroke="currentColor" stroke-width="2.2"/><circle cx="12" cy="12" r="1.8" fill="currentColor"/><path d="M12 1.5v4M12 18.5v4M1.5 12h4M18.5 12h4" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/></svg><span class="control-label">FIRE</span></button>
      </div>
    </div>
    <div class="splash" data-ui="splash" aria-hidden="true"><img src="/generated-assets/logo.png" alt="" /><i></i></div>
    <div class="loading-sigil" data-ui="loading"><i></i><span>Menyelaraskan rune…</span></div>
  `;
  mount.replaceChildren(shell);

  const canvas = shell.querySelector("canvas");
  const actionButtons = Object.fromEntries([...shell.querySelectorAll("[data-action]")].map((button) => [button.dataset.action, button]));
  const query = (name) => shell.querySelector(`[data-ui="${name}"]`);

  // Keyboard play: Enter/Space press the overlay's main button, digits pick a
  // rune (camp) or start area (loadout), and arrows browse Gun-Mages.
  const overlayKeys = (event) => {
    const modal = query("modal");
    if (!modal.hidden) {
      // A modal pauses the game, so keep keys away from the game input.
      event.stopImmediatePropagation();
      if (event.repeat) return;
      if (event.code === "Escape" || event.key === "Escape") {
        event.preventDefault();
        closeModal();
        return;
      }
      const isConfirm = ["Enter", "NumpadEnter", "Space"].includes(event.code) || event.key === "Enter" || event.key === " ";
      const button = isConfirm ? modal.querySelector(".modal-primary") : null;
      if (!button) return;
      event.preventDefault();
      button.click();
      return;
    }
    const overlay = query("overlay");
    if (overlay.hidden) {
      // Escape / P pause the run while playing.
      const isPause = event.code === "Escape" || event.key === "Escape" || event.code === "KeyP" || event.key === "p" || event.key === "P";
      if (!isPause || !shell.classList.contains("is-playing")) return;
      event.preventDefault();
      event.stopImmediatePropagation();
      if (!event.repeat) toolHandlers.onPause?.();
      return;
    }
    let target = null;
    // Match on event.key too: some Android key events have no event.code.
    if (["Enter", "NumpadEnter", "Space"].includes(event.code) || event.key === "Enter" || event.key === " ") {
      target = overlay.querySelector(".retry-btn");
    } else if (/^Arrow(Left|Right)$/.test(event.code || event.key)) {
      // ◀ ▶ browse Gun-Mages in the main menu.
      target = overlay.querySelector((event.code || event.key) === "ArrowLeft" ? ".skin-prev" : ".skin-next");
    } else {
      const digit = /^(?:Digit|Numpad)(\d)$/.exec(event.code)?.[1] ?? (/^\d$/.test(event.key) ? event.key : null);
      if (digit) target = overlay.querySelectorAll(".buff-card, .area-grid button")[(Number(digit) + 9) % 10];
    }
    if (!target) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    if (!event.repeat) target.click();
  };
  window.addEventListener("keydown", overlayKeys, true);
  let toolHandlers = {};
  query("pause-btn").addEventListener("click", () => {
    if (query("modal").hidden) toolHandlers.onPause?.();
  });
  query("volume-btn").addEventListener("click", () => {
    if (query("modal").hidden) toolHandlers.onVolume?.();
  });
  query("help-btn").addEventListener("click", () => {
    if (query("modal").hidden) toolHandlers.onHelp?.();
  });
  let art = null;
  let toastTimer = 0;
  let lastHp = null;
  let lastBuffSignature = "";

  function paintIcon(canvasElement, iconName) {
    if (!art || !canvasElement) return;
    const size = 64;
    canvasElement.width = size;
    canvasElement.height = size;
    const context = canvasElement.getContext("2d");
    context.clearRect(0, 0, size, size);
    drawAtlas(context, art, "UI_ICON_ATLAS", iconName, 2, 2, size - 4, size - 4);
  }

  function paintCoin(canvasElement) {
    if (!art || !canvasElement) return;
    canvasElement.width = 48;
    canvasElement.height = 48;
    const context = canvasElement.getContext("2d");
    const entry = art.get("COIN_SHEET");
    drawFrameInCell(context, entry, findFrame(entry, "coin_1"), 0, 0, 48, 48);
  }

  function paintSkin(canvasElement, skin, time = 0.2) {
    if (!art || !canvasElement) return;
    // 512px backing store so the character stays sharp on high-DPI phone screens.
    const size = 512;
    if (canvasElement.width !== size) {
      canvasElement.width = size;
      canvasElement.height = size;
    }
    const context = canvasElement.getContext("2d");
    context.clearRect(0, 0, size, size);
    // Fixed scale + foot anchor across frames: no jumping or resizing. Almost the
    // whole canvas is used so each Gun-Mage reads big and its details are visible.
    drawAnimatedFit(context, art, skin.key, "idle", time, 4, 4, size - 8, size - 12);
  }

  // The loadout preview plays the skin's idle loop while the menu is open.
  let previewFrame = 0;
  function stopPreview() {
    cancelAnimationFrame(previewFrame);
    previewFrame = 0;
  }
  function startPreview(canvasElement, skin) {
    stopPreview();
    const startedAt = performance.now();
    let lastFrame = -1;
    const tick = (now) => {
      // The idle loop runs at 10 fps, so only repaint when the frame changes.
      const seconds = (now - startedAt) / 1000;
      const frame = Math.floor(seconds * 10);
      if (frame !== lastFrame) {
        lastFrame = frame;
        paintSkin(canvasElement, skin, seconds);
      }
      previewFrame = requestAnimationFrame(tick);
    };
    previewFrame = requestAnimationFrame(tick);
  }

  function setHp(hp, maxHp = 3) {
    const row = shell.querySelector(".hp-row");
    row.replaceChildren();
    for (let i = 0; i < maxHp; i += 1) {
      const pip = document.createElement("canvas");
      pip.className = `pip hp-pip${i >= hp ? " is-empty" : ""}`;
      pip.setAttribute("aria-hidden", "true");
      row.append(pip);
      paintIcon(pip, "hp_crystal");
    }
  }

  function updateBuffStrip(levels, power) {
    const strip = query("buff-strip");
    const active = BUFFS.filter((buff) => levels[buff.id] > 0);
    strip.replaceChildren();
    active.slice(0, 5).forEach((buff) => {
      const chip = document.createElement("span");
      chip.className = "buff-chip";
      chip.title = buff.name;
      const icon = document.createElement("canvas");
      icon.className = "mini-icon";
      paintIcon(icon, buff.icon);
      chip.append(icon, document.createTextNode(` ${levels[buff.id]}`));
      strip.append(chip);
    });
    if (power?.gatling > 0) strip.dataset.power = "GATLING";
    else if (power?.boots > 0) strip.dataset.power = "PEGASUS";
    else if (power?.shield > 0) strip.dataset.power = "AEGIS";
    else delete strip.dataset.power;
  }

  function showOverlay(content) {
    stopPreview();
    const overlay = query("overlay");
    overlay.classList.remove("is-menu");
    overlay.replaceChildren(content);
    overlay.hidden = false;
  }

  function hideOverlay() {
    stopPreview();
    const overlay = query("overlay");
    overlay.hidden = true;
    overlay.replaceChildren();
  }

  // Modals (tutorial, volume, confirm) sit above the menus; the game pauses
  // while one is open (see isModalOpen in game.js).
  let modalOnClose = null;

  function openModal(panel, onClose) {
    const modal = query("modal");
    modal.replaceChildren(panel);
    modal.hidden = false;
    modalOnClose = onClose || null;
  }

  function closeModal() {
    const modal = query("modal");
    if (modal.hidden) return;
    modal.hidden = true;
    modal.replaceChildren();
    const callback = modalOnClose;
    modalOnClose = null;
    callback?.();
  }

  function modalButton(label, className, onClick) {
    const button = document.createElement("button");
    button.className = className;
    button.textContent = label;
    button.addEventListener("click", onClick);
    return button;
  }

  const TUTORIAL_PAGES = [
    {
      title: "Selamat datang, Gun-Mage!",
      text: "Bertahanlah dari gelombang musuh, kalahkan boss di setiap realm, dan taklukkan 10 realm sampai Singgasana Iblis.",
    },
    {
      title: "Bergerak",
      rows: [
        ["◀ ▶", "Geser joystick untuk berjalan ke kiri dan kanan."],
        ["JUMP", "Lompat. Tekan lagi di udara untuk lompat ganda."],
        ["DASH", "Melesat cepat dan kebal sesaat."],
      ],
    },
    {
      title: "Menyerang",
      rows: [
        ["FIRE", "Tahan untuk terus menembak ke atas."],
        ["S1 · S2", "Skill khusus tiap Gun-Mage. Tunggu cooldown-nya."],
        ["ULT", "Serangan pamungkas yang menghantam semua musuh."],
      ],
    },
    {
      title: "Bertahan hidup",
      rows: [
        ["❤ ×3", "Kamu punya 3 nyawa. Hindari peluru dan musuh yang jatuh.", ""],
        ["⚠", "Laser dan petir selalu diberi tanda dulu. Segera menjauh!", ""],
        ["◆", "Kumpulkan koin untuk membeli Gun-Mage yang lebih kuat.", ""],
      ],
    },
    {
      title: "Power-up & rune",
      rows: [
        ["Gatling", "Tembakan super cepat selama 10 detik.", ""],
        ["Pegasus", "Lari dan lompat lebih tinggi selama 10 detik.", ""],
        ["Aegis", "Perisai yang menahan satu serangan.", ""],
        ["Nova", "Ledakan yang membersihkan musuh di layar.", ""],
      ],
      text: "Setelah boss kalah, pilih satu rune di camp untuk memperkuat run-mu.",
    },
  ];

  function renderTutorial(page, first, onDone) {
    const data = TUTORIAL_PAGES[page];
    const last = page === TUTORIAL_PAGES.length - 1;
    const panel = document.createElement("div");
    panel.className = "overlay-panel modal-panel tutorial-panel";
    panel.innerHTML = `<small>TUTORIAL · ${page + 1}/${TUTORIAL_PAGES.length}</small><h2>${data.title}</h2>`;
    if (data.rows) {
      const list = document.createElement("div");
      list.className = "tutorial-rows";
      data.rows.forEach(([label, text]) => {
        const row = document.createElement("div");
        row.className = "tutorial-row";
        row.innerHTML = `<b>${label}</b><span>${text}</span>`;
        list.append(row);
      });
      panel.append(list);
    }
    if (data.text) {
      const text = document.createElement("p");
      text.textContent = data.text;
      panel.append(text);
    }
    const dots = document.createElement("div");
    dots.className = "tutorial-dots";
    TUTORIAL_PAGES.forEach((_, index) => {
      const dot = document.createElement("i");
      if (index === page) dot.className = "is-active";
      dots.append(dot);
    });
    panel.append(dots);

    const actions = document.createElement("div");
    actions.className = "modal-actions";
    if (page > 0) {
      actions.append(modalButton("KEMBALI", "ghost-btn", () => renderTutorial(page - 1, first, onDone)));
    } else {
      actions.append(modalButton(first ? "LEWATI" : "TUTUP", "ghost-btn", () => closeModal()));
    }
    actions.append(modalButton(last ? (first ? "MULAI MAIN" : "MENGERTI") : "LANJUT", "retry-btn modal-primary", () => {
      if (last) closeModal();
      else renderTutorial(page + 1, first, onDone);
    }));
    panel.append(actions);
    // Keep onDone across page changes; it fires once when the modal closes.
    openModal(panel, onDone);
  }

  return {
    shell,
    canvas,
    setArt(value) { art = value; setHp(3); paintCoin(query("coin-icon")); lastHp = 3; },
    // First-launch splash: fades out once the game is ready (or failed to boot).
    hideSplash() {
      const splash = query("splash");
      if (!splash) return;
      // Keep the logo on screen for a moment even when the assets load instantly.
      const wait = Math.max(0, SPLASH_MIN_MS - (performance.now() - splashShownAt));
      window.setTimeout(() => {
        splash.classList.add("is-done");
        window.setTimeout(() => splash.remove(), 500);
      }, wait);
    },
    setLoading(visible, message = "Menyelaraskan rune…") {
      const loading = query("loading");
      loading.hidden = !visible;
      loading.querySelector("span").textContent = message;
    },
    setPrompt(message) {
      const prompt = query("prompt");
      prompt.textContent = message || "";
      prompt.hidden = !message;
    },
    toast(message, duration = 1.7) {
      const toast = query("toast");
      toast.textContent = message;
      toast.hidden = false;
      window.clearTimeout(toastTimer);
      toastTimer = window.setTimeout(() => { toast.hidden = true; }, duration * 1000);
    },
    update({ score, coins, hp, realm, realmName, timer, dashRatio, skillRatios, skin, boss, buffLevels, power, playing }) {
      shell.classList.toggle("is-playing", Boolean(playing));
      query("score").textContent = Math.floor(score).toLocaleString("id-ID");
      query("coins").textContent = Math.floor(coins || 0).toLocaleString("id-ID");
      query("realm-step").textContent = `REALM ${realm + 1}/10`;
      query("realm-name").textContent = realmName;
      query("timer").textContent = timer;
      query("dash-ring").style.setProperty("--cooldown", `${Math.max(0, Math.min(1, dashRatio)) * 360}deg`);
      query("skill1-ring").style.setProperty("--cooldown", `${Math.max(0, Math.min(1, skillRatios?.one || 0)) * 360}deg`);
      query("skill2-ring").style.setProperty("--cooldown", `${Math.max(0, Math.min(1, skillRatios?.two || 0)) * 360}deg`);
      query("ultimate-ring").style.setProperty("--cooldown", `${Math.max(0, Math.min(1, skillRatios?.ultimate || 0)) * 360}deg`);
      // Dim buttons that are cooling down; skills pulse once they are ready again.
      const cooldowns = { dash: dashRatio, skill1: skillRatios?.one, skill2: skillRatios?.two, ultimate: skillRatios?.ultimate };
      for (const [action, ratio] of Object.entries(cooldowns)) {
        const cooling = (ratio || 0) > 0.001;
        actionButtons[action].classList.toggle("is-cooling", cooling);
        if (action !== "dash") actionButtons[action].classList.toggle("is-ready", !cooling);
      }
      if (skin) {
        shell.querySelector(".skill-one-btn").title = skin.skillOne;
        shell.querySelector(".skill-two-btn").title = skin.skillTwo;
        shell.querySelector(".ultimate-btn").title = skin.ultimate;
      }
      if (hp !== lastHp) {
        setHp(hp);
        lastHp = hp;
      }
      const buffSignature = `${Object.values(buffLevels).join(":")}|${power.gatling > 0}|${power.boots > 0}|${power.shield > 0}`;
      if (buffSignature !== lastBuffSignature) {
        updateBuffStrip(buffLevels, power);
        lastBuffSignature = buffSignature;
      }
      const meter = query("boss-meter");
      meter.hidden = !boss;
      if (boss) {
        query("boss-name").textContent = boss.name;
        query("boss-phase").textContent = boss.phaseText || "";
        query("boss-fill").style.width = `${Math.max(0, boss.hp / boss.maxHp) * 100}%`;
      }
    },
    showCamp(choices, levels, onPick) {
      const panel = document.createElement("div");
      panel.className = "overlay-panel camp-panel";
      panel.innerHTML = `<small>RESTING CAMP</small><h2>Pilih satu rune</h2><p>Buff ini bertahan sampai run berakhir.</p>`;
      const list = document.createElement("div");
      list.className = "buff-choice-list";
      choices.forEach((buff) => {
        const level = levels[buff.id] || 0;
        const button = document.createElement("button");
        button.className = "buff-card";
        const icon = document.createElement("canvas");
        icon.className = "buff-icon";
        paintIcon(icon, buff.icon);
        const copy = document.createElement("span");
        copy.innerHTML = `<strong>${buff.name}</strong><small>Tier ${level + 1}/${buff.max}</small><em>${buff.description[Math.min(level, buff.description.length - 1)]}</em>`;
        button.append(icon, copy);
        button.addEventListener("click", () => onPick(buff));
        list.append(button);
      });
      panel.append(list);
      showOverlay(panel);
    },
    showLoadout({ skins, realms, coins, unlocked, selectedSkin, selectedRealm, stats = {}, onSkin, onArea, onBuy, onStart, onReset }) {
      const panel = document.createElement("div");
      panel.className = "overlay-panel loadout-panel";
      const skin = skins[selectedSkin];
      const maxPower = Math.max(...skins.map((item) => item.power));
      const format = (value) => Math.floor(value || 0).toLocaleString("id-ID");
      const owned = unlocked.includes(skin.id);
      const pad = (value) => String(value).padStart(2, "0");
      panel.innerHTML = `
        <div class="menu-hero">
          <div class="menu-logo"><small>ROGUELITE · 10 REALM · 20 GUN-MAGE</small><h1>ARCANE <span>SIEGE</span></h1></div>
          <span class="loadout-coins">◆ ${format(coins)}</span>
        </div>
        <div class="menu-stats">
          <div><small>SKOR TERBAIK</small><strong>${format(stats.bestScore)}</strong></div>
          <div><small>REALM TERJAUH</small><strong>${Math.min(10, stats.bestRealm || 0)}/10</strong></div>
          <div><small>MENANG</small><strong>${format(stats.wins)}</strong></div>
        </div>`;

      // Showcase: one Gun-Mage at a time on a pedestal, browsed with ‹ ›.
      const showcase = document.createElement("div");
      showcase.className = "showcase";
      showcase.style.setProperty("--skin-color", skin.color);
      const stage = document.createElement("div");
      stage.className = "showcase-stage";
      const previewCanvas = document.createElement("canvas");
      previewCanvas.className = "skin-preview-canvas";
      const step = (delta) => onSkin((selectedSkin + delta + skins.length) % skins.length);
      const prev = modalButton("‹", "skin-nav skin-prev", () => step(-1));
      prev.setAttribute("aria-label", "Gun-Mage sebelumnya");
      const next = modalButton("›", "skin-nav skin-next", () => step(1));
      next.setAttribute("aria-label", "Gun-Mage berikutnya");
      const tag = document.createElement("span");
      tag.className = "skin-index";
      tag.textContent = `#${pad(skin.id + 1)}/${skins.length}`;
      stage.append(previewCanvas, prev, next, tag);

      const copy = document.createElement("div");
      copy.className = "skin-copy";
      copy.innerHTML = `
        <span class="skin-badge ${owned ? "is-owned" : "is-trial"}">${owned ? "✓ DIMILIKI" : "UJI GRATIS"}</span>
        <strong>${skin.name}</strong>
        <div class="power-meter"><i style="width:${Math.round((skin.power / maxPower) * 100)}%"></i><span>POWER ×${skin.power.toFixed(2)}</span></div>
        <ul class="skill-list">
          <li><b>S1</b><span>${skin.skillOne}</span></li>
          <li><b>S2</b><span>${skin.skillTwo}</span></li>
          <li class="is-ult"><b>ULT</b><span>${skin.ultimate}</span></li>
        </ul>`;
      if (!owned) {
        const affordable = coins >= skin.price;
        const buy = modalButton(affordable ? `BELI · ◆ ${format(skin.price)}` : `BUTUH ◆ ${format(skin.price)}`, "buy-skin", () => onBuy(skin.id));
        buy.disabled = !affordable;
        copy.append(buy);
      }
      showcase.append(stage, copy);
      panel.append(showcase);

      // Quick jump: all 20 Gun-Mages as numbered chips, always fully visible.
      const strip = document.createElement("div");
      strip.className = "skin-strip";
      skins.forEach((item) => {
        const has = unlocked.includes(item.id);
        const chip = modalButton(String(item.id + 1), `skin-chip${item.id === selectedSkin ? " is-selected" : ""}${has ? " is-owned" : ""}`, () => {
          if (item.id !== selectedSkin) onSkin(item.id);
        });
        chip.style.setProperty("--skin-color", item.color);
        chip.title = `${item.name}${has ? "" : ` · ◆ ${format(item.price)}`}`;
        strip.append(chip);
      });
      panel.append(strip);

      const areaTitle = document.createElement("div");
      areaTitle.className = "area-title";
      areaTitle.innerHTML = `<strong>Pilih area awal</strong><small>Semua realm bebas untuk testing</small>`;
      panel.append(areaTitle);
      const areaGrid = document.createElement("div");
      areaGrid.className = "area-grid";
      realms.forEach((item, index) => {
        const button = document.createElement("button");
        button.className = index === selectedRealm ? "is-selected" : "";
        button.style.setProperty("--realm-a", item.colors[0]);
        button.style.setProperty("--realm-b", item.colors[1]);
        button.innerHTML = `<b>${index + 1}</b><span>${item.short}</span>`;
        button.addEventListener("click", () => onArea(index));
        areaGrid.append(button);
      });
      panel.append(areaGrid);
      const start = document.createElement("button");
      start.className = "retry-btn start-run-btn";
      start.innerHTML = `<span class="control-label">▶ MASUK REALM ${selectedRealm + 1} · ${realms[selectedRealm].short}</span><small class="start-sub">Boss · ${realms[selectedRealm].boss}</small>`;
      start.addEventListener("click", onStart);
      panel.append(start);
      if (onReset) {
        const reset = document.createElement("button");
        reset.className = "reset-progress-btn";
        reset.textContent = "Reset progres";
        reset.addEventListener("click", onReset);
        panel.append(reset);
      }
      // Picking a skin/area re-renders the menu: skip the intro animation and
      // keep the scroll positions so the panel doesn't jump.
      const overlay = query("overlay");
      const previous = !overlay.hidden && overlay.classList.contains("is-menu") ? overlay.querySelector(".loadout-panel") : null;
      const panelScroll = previous?.scrollTop ?? 0;
      if (previous) panel.classList.add("is-refresh");
      showOverlay(panel);
      overlay.classList.add("is-menu");
      // The selected realm's artwork becomes the menu backdrop and its colors
      // drive the accents, so the menu always matches where you're about to go.
      const realmArt = art?.get(`REALM_BG_${String(selectedRealm + 1).padStart(2, "0")}`);
      overlay.style.setProperty("--menu-bg", realmArt?.image ? `url("${realmArt.image.src}")` : "none");
      overlay.style.setProperty("--realm-a", realms[selectedRealm].colors[0]);
      overlay.style.setProperty("--realm-b", realms[selectedRealm].colors[1]);
      panel.scrollTop = panelScroll;
      startPreview(previewCanvas, skin);
    },
    showPause({ onResume, onHelp, onMenu }) {
      const panel = document.createElement("div");
      panel.className = "overlay-panel modal-panel pause-panel";
      panel.innerHTML = `<small>PERMAINAN DIJEDA</small><h2>Jeda</h2><p>Tarik napas, Gun-Mage. Realm menunggumu.</p>`;
      const actions = document.createElement("div");
      actions.className = "pause-actions";
      actions.append(
        modalButton("LANJUTKAN", "retry-btn modal-primary", () => closeModal()),
        modalButton("TUTORIAL", "ghost-btn", () => onHelp?.()),
        modalButton("MAIN MENU", "danger-btn", () => onMenu?.()),
      );
      panel.append(actions);
      openModal(panel, onResume);
    },
    showGameOver(score, best, realm, onRetry) {
      const panel = document.createElement("div");
      panel.className = "overlay-panel result-panel";
      panel.innerHTML = `<small>RUNE CHAMBER RETAK</small><h2>Run berakhir</h2><div class="result-score">${Math.floor(score).toLocaleString("id-ID")}</div><p>Realm ${realm + 1} · Terbaik ${Math.floor(best).toLocaleString("id-ID")}</p>`;
      const button = document.createElement("button");
      button.className = "retry-btn";
      button.innerHTML = `<span class="control-label">COBA LAGI</span>`;
      button.addEventListener("click", onRetry);
      panel.append(button);
      showOverlay(panel);
    },
    showVictory(score, best, onRetry) {
      const panel = document.createElement("div");
      panel.className = "overlay-panel result-panel victory-panel";
      panel.innerHTML = `<small>SEPULUH REALM TERSELAMATKAN</small><h2>Demon Gunsmith tumbang</h2><div class="result-score">${Math.floor(score).toLocaleString("id-ID")}</div><p>Build magitech-mu menjadi legenda.</p>`;
      const button = document.createElement("button");
      button.className = "retry-btn";
      button.innerHTML = `<span class="control-label">RUN BARU</span>`;
      button.addEventListener("click", onRetry);
      panel.append(button);
      showOverlay(panel);
    },
    hideOverlay,
    setToolHandlers(handlers) { toolHandlers = handlers || {}; },
    isModalOpen: () => !query("modal").hidden,
    closeModal,
    setMuted(muted) { query("volume-btn").classList.toggle("is-muted", muted); },
    showTutorial({ first = false, onClose } = {}) {
      renderTutorial(0, first, onClose);
    },
    showVolume({ music, sfx, onChange, onClose }) {
      const values = { music, sfx };
      const panel = document.createElement("div");
      panel.className = "overlay-panel modal-panel volume-panel";
      panel.innerHTML = `<small>PENGATURAN</small><h2>Volume</h2>`;
      [["music", "Musik"], ["sfx", "Efek suara"]].forEach(([key, label]) => {
        const row = document.createElement("label");
        row.className = "volume-row";
        const name = document.createElement("span");
        name.textContent = label;
        const slider = document.createElement("input");
        slider.type = "range";
        slider.min = "0";
        slider.max = "100";
        slider.step = "5";
        slider.value = String(Math.round(values[key] * 100));
        const readout = document.createElement("output");
        readout.textContent = `${slider.value}%`;
        slider.addEventListener("input", () => {
          values[key] = Number(slider.value) / 100;
          readout.textContent = `${slider.value}%`;
          onChange?.({ ...values });
        });
        row.append(name, slider, readout);
        panel.append(row);
      });
      const actions = document.createElement("div");
      actions.className = "modal-actions";
      actions.append(modalButton("SELESAI", "retry-btn modal-primary", () => closeModal()));
      panel.append(actions);
      openModal(panel, () => onClose?.({ ...values }));
    },
    confirm({ title, text, confirmLabel, onConfirm, onCancel }) {
      let confirmed = false;
      const panel = document.createElement("div");
      panel.className = "overlay-panel modal-panel confirm-panel";
      panel.innerHTML = `<small>KONFIRMASI</small><h2>${title}</h2><p>${text}</p>`;
      const actions = document.createElement("div");
      actions.className = "modal-actions";
      // Enter/Space cancel here, so a destructive action always needs a deliberate click.
      actions.append(modalButton("BATAL", "retry-btn modal-primary", () => closeModal()));
      actions.append(modalButton(confirmLabel, "danger-btn", () => {
        confirmed = true;
        closeModal();
        onConfirm();
      }));
      panel.append(actions);
      // BATAL, Escape and Enter all land here as a cancel.
      openModal(panel, () => { if (!confirmed) onCancel?.(); });
    },
    destroy() {
      stopPreview();
      window.removeEventListener("keydown", overlayKeys, true);
      window.clearTimeout(toastTimer);
      mount.replaceChildren();
    },
  };
}
