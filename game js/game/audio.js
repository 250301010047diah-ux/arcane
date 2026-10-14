// Audio files live in android-assets/audio and are served at /audio/<name>.mp3.
const AUDIO_BASE = "/audio/";

const SFX_FILES = [
  "shoot", "jump", "double_jump", "dash",
  "enemy_hit", "enemy_die", "enemy_shoot",
  "player_hurt", "shield_break", "counter",
  "coin", "powerup", "nova",
  "skill1", "skill2", "ultimate",
  "laser", "lightning",
  "boss_appear", "boss_attack", "boss_hit", "boss_defeat",
  "realm_start", "buff_select", "ui_click", "buy", "win", "lose",
];

// bgm1: realm 1-3, bgm2: realm 4-6, bgm3: realm 7-10.
const BGM_FILES = ["bgm1", "bgm2", "bgm3"];
const bgmForRealm = (index) => (index <= 2 ? "bgm1" : index <= 5 ? "bgm2" : "bgm3");

// Minimum seconds between repeats so rapid fire doesn't stack into noise.
const SFX_COOLDOWN = {
  shoot: 0.06, enemy_hit: 0.05, enemy_die: 0.03, enemy_shoot: 0.08, boss_hit: 0.07, coin: 0.04,
};

const SFX_LEVEL = 0.85;
const musicLevel = (volume) => Math.min(1, volume * 2.2);

export async function createArcaneAudio(sdk, initialVolume = 0.22) {
  let audio = null;
  let context = null;
  let volume = initialVolume;
  let musicTimer = 0;
  let musicStep = 0;
  let realm = 0;
  let music = null;
  let destroyed = false;
  // Player volume settings (0..1) on top of the tweak-driven base levels.
  let musicMix = 1;
  let sfxMix = 1;

  try {
    audio = await sdk.audio.getContext();
    context = audio.context;
  } catch {
    return silentAudio();
  }

  const sfxBus = context?.createGain();
  const musicBus = context?.createGain();
  if (context) {
    sfxBus.gain.value = SFX_LEVEL * sfxMix;
    musicBus.gain.value = musicLevel(volume) * musicMix;
    sfxBus.connect(context.destination);
    musicBus.connect(context.destination);
  }

  // Android can suspend the context when another sound takes the speaker, which
  // silences BGM and SFX together. Bring it back while the app is on screen; the
  // app's own background pause (main.dart sets __pausedByApp) is left alone.
  let lastResumeTry = 0;
  const keepAlive = () => {
    if (!context || context.state === "running" || context.state === "closed") return;
    if (context.__pausedByApp || document.hidden) return;
    const now = performance.now();
    if (now - lastResumeTry < 500) return;
    lastResumeTry = now;
    void context.resume().catch(() => {});
  };
  context?.addEventListener("statechange", keepAlive);

  // name -> AudioBuffer, or null when the file is missing, broken or a silent
  // placeholder (then the synthesized fallback below plays instead).
  const buffers = new Map();
  const failed = new Set();
  const lastPlayed = new Map();

  const isSilent = (buffer) => {
    for (let channel = 0; channel < buffer.numberOfChannels; channel += 1) {
      const data = buffer.getChannelData(channel);
      for (let i = 0; i < data.length; i += 16) if (Math.abs(data[i]) > 1e-4) return false;
    }
    return true;
  };

  const load = async (name) => {
    try {
      const response = await fetch(`${AUDIO_BASE}${name}.mp3`);
      if (!response.ok) throw new Error(`${name}.mp3 ${response.status}`);
      const buffer = await context.decodeAudioData(await response.arrayBuffer());
      buffers.set(name, isSilent(buffer) ? null : buffer);
    } catch {
      buffers.set(name, null);
      failed.add(name);
    }
  };
  // Load in the background so a slow or missing file never blocks boot.
  if (context) {
    const names = [...SFX_FILES, ...BGM_FILES];
    void Promise.all(names.map(load)).then(() => {
      const placeholders = names.filter((name) => !buffers.get(name) && !failed.has(name));
      const active = names.length - placeholders.length - failed.size;
      console.log(`[audio] ${active}/${names.length} file aktif`
        + (placeholders.length ? `; placeholder hening (pakai suara bawaan): ${placeholders.join(", ")}` : "")
        + (failed.size ? `; GAGAL dimuat: ${[...failed].join(", ")}` : ""));
    });
  }

  const tone = (frequency, duration, type = "sine", gainValue = 0.08, slide = 1) => {
    if (!context || context.state !== "running") return;
    const now = context.currentTime;
    const oscillator = context.createOscillator();
    const gain = context.createGain();
    oscillator.type = type;
    oscillator.frequency.setValueAtTime(frequency, now);
    oscillator.frequency.exponentialRampToValueAtTime(Math.max(30, frequency * slide), now + duration);
    gain.gain.setValueAtTime(Math.max(0.0001, gainValue), now);
    gain.gain.exponentialRampToValueAtTime(0.0001, now + duration);
    oscillator.connect(gain).connect(context.destination);
    oscillator.start(now);
    oscillator.stop(now + duration);
  };

  const noise = (duration = 0.08, gainValue = 0.04) => {
    if (!context || context.state !== "running") return;
    const length = Math.max(1, Math.floor(context.sampleRate * duration));
    const buffer = context.createBuffer(1, length, context.sampleRate);
    const data = buffer.getChannelData(0);
    for (let i = 0; i < length; i += 1) data[i] = (Math.random() * 2 - 1) * (1 - i / length);
    const source = context.createBufferSource();
    const gain = context.createGain();
    source.buffer = buffer;
    gain.gain.value = gainValue;
    source.connect(gain).connect(context.destination);
    source.start();
  };

  // The original synthesized sounds, used until a real file replaces the placeholder.
  const synth = {
    shot: (v) => tone(760, 0.08, "square", v * 0.32, 1.55),
    hit: (v) => { noise(0.07, v * 0.38); tone(230, 0.1, "triangle", v * 0.28, 0.55); },
    dash: (v) => { noise(0.12, v * 0.28); tone(310, 0.13, "sawtooth", v * 0.2, 2.2); },
    burst: (v) => { noise(0.22, v * 0.5); tone(150, 0.3, "sawtooth", v * 0.45, 0.45); },
    pickup: (v) => { tone(540, 0.1, "sine", v * 0.5, 1.45); setTimeout(() => tone(800, 0.12, "sine", v * 0.42, 1.2), 55); },
    warning: (v) => tone(110, 0.42, "sawtooth", v * 0.45, 0.72),
    jump: (v) => tone(420, 0.09, "triangle", v * 0.25, 1.5),
  };
  // Events that had a sound before keep it; new events stay silent until a file exists.
  const FALLBACK = {
    shoot: synth.shot,
    jump: synth.jump,
    double_jump: synth.jump,
    dash: synth.dash,
    skill2: synth.dash,
    enemy_die: synth.hit,
    player_hurt: synth.hit,
    shield_break: synth.burst,
    counter: synth.burst,
    nova: synth.burst,
    skill1: synth.burst,
    ultimate: synth.burst,
    lightning: synth.burst,
    boss_defeat: synth.burst,
    coin: synth.pickup,
    powerup: synth.pickup,
    buff_select: synth.pickup,
    buy: synth.pickup,
    boss_appear: synth.warning,
    boss_attack: synth.warning,
  };

  const stopMusic = () => {
    try { music?.source.stop(); } catch { /* already stopped */ }
    music = null;
  };

  const syncMusic = () => {
    const wanted = bgmForRealm(realm);
    if (music?.name === wanted) return;
    const buffer = buffers.get(wanted);
    stopMusic();
    if (!buffer) return;
    const source = context.createBufferSource();
    source.buffer = buffer;
    source.loop = true;
    source.connect(musicBus);
    source.start();
    music = { name: wanted, source };
  };

  const api = {
    async unlock() {
      try { await audio.unlock(); } catch { /* The game remains playable in silence. */ }
    },
    setRealm(value) { realm = value; musicStep = 0; },
    setVolume(value) {
      volume = Number(value) || 0;
      if (musicBus) musicBus.gain.value = musicLevel(volume) * musicMix;
    },
    setMix(music, sfx) {
      musicMix = Math.max(0, Math.min(1, Number(music) || 0));
      sfxMix = Math.max(0, Math.min(1, Number(sfx) || 0));
      if (musicBus) musicBus.gain.value = musicLevel(volume) * musicMix;
      if (sfxBus) sfxBus.gain.value = SFX_LEVEL * sfxMix;
    },
    sfx(name) {
      if (!context || context.state !== "running" || sfxMix <= 0) return;
      const now = context.currentTime;
      if (now - (lastPlayed.get(name) ?? -Infinity) < (SFX_COOLDOWN[name] || 0)) return;
      lastPlayed.set(name, now);
      const buffer = buffers.get(name);
      if (buffer) {
        const source = context.createBufferSource();
        source.buffer = buffer;
        source.connect(sfxBus);
        source.start();
        return;
      }
      FALLBACK[name]?.(Math.max(0.02, volume * 0.7) * sfxMix);
    },
    update(dt, intense = false) {
      if (destroyed || !context) return;
      if (context.state !== "running") {
        // statechange can be missed on some WebViews, so also retry from the frame loop.
        keepAlive();
        return;
      }
      syncMusic();
      if (music || volume <= 0 || musicMix <= 0) return;
      // No real BGM file for this realm yet: play the procedural theme.
      musicTimer -= dt;
      if (musicTimer > 0) return;
      const roots = [196, 220, 174, 165];
      const root = roots[Math.min(3, Math.floor(realm / 3))];
      const scale = realm === 9 ? [1, 1.122, 1.335, 1.498, 1.682] : [1, 1.189, 1.335, 1.498, 1.782];
      const note = root * scale[musicStep % scale.length] * (musicStep % 8 > 4 ? 2 : 1);
      tone(note, intense ? 0.25 : 0.36, musicStep % 2 ? "triangle" : "sine", volume * 0.16 * musicMix, 0.99);
      if (musicStep % 4 === 0) tone(root / 2, 0.3, "triangle", volume * 0.12 * musicMix, 0.98);
      musicStep += 1;
      musicTimer = intense ? 0.24 : 0.34;
    },
    async destroy() {
      destroyed = true;
      stopMusic();
      try { await audio.dispose(); } catch { /* no-op */ }
    },
  };
  return api;
}

function silentAudio() {
  return {
    unlock: async () => {}, setRealm() {}, setVolume() {}, setMix() {}, sfx() {}, update() {}, destroy: async () => {},
  };
}
