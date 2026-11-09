import { ArtLibrary } from "./assets.js";
import { createArcaneAudio } from "./audio.js";
import { makeBuffState, pickBuffChoices, POWERUPS, REALMS, SKINS } from "./data.js";
import { createInput } from "./input.js";
import { circleHit, pointInVerticalZone, stepPlayer } from "./physics.js";
import { GameRenderer } from "./renderer.js";
import { createUI } from "./ui.js";

const TWEAK_DEFAULTS = {
  playerSpeed: 265,
  jumpPower: 485,
  gravity: 1120,
  fireInterval: 0.2,
  spawnInterval: 1.15,
  waveDuration: 95,
  enemySpeed: 96,
  bossHealthScale: 1,
  effectsIntensity: 1,
  musicVolume: 0.22,
};

export function createGame({ mount, sdk, tweaks, assets }) {
  let teardown = () => {};

  return {
    start() {
      const ui = createUI(mount);
      const art = new ArtLibrary(assets);
      const balance = Object.fromEntries(Object.entries(TWEAK_DEFAULTS).map(([key, fallback]) => {
        try { return [key, Number(tweaks.get(key)) || fallback]; } catch { return [key, fallback]; }
      }));
      const unsubscribers = [];
      let destroyed = false;
      let renderer = null;
      let input = null;
      let audio = null;
      let animationFrame = 0;
      let lastTime = 0;
      let nextEntityId = 1;
      const defaultSave = () => ({
        version: 2, bestScore: 0, bestRealm: 0, wins: 0, coins: 0,
        unlockedSkins: [0], selectedSkin: 0, selectedRealm: 0,
        tutorialSeen: false, allAreas: false, settings: { music: 1, sfx: 1 },
      });
      // Area i opens once the player has reached it (or the cheat unlocked all).
      const areaUnlocked = (index) => saved.allAreas || index <= Math.min(9, saved.bestRealm);
      let saved = defaultSave();
      let state = null;

      const safeHaptic = (pattern) => {
        try {
          if (sdk.device.haptics.isSupported()) void sdk.device.haptics.vibrate(pattern).catch(() => {});
        } catch { /* Optional feedback. */ }
      };

      const makePlayer = (floorY, width) => ({
        x: width * 0.5,
        y: floorY,
        vx: 0,
        vy: 0,
        facing: 1,
        jumps: 0,
        dashTimer: 0,
        dashCooldown: 0,
        invulnerable: 0,
        hurtFlash: 0,
        shotFlash: 0,
        animSeed: Math.random() * 5,
        hp: 3,
        worldTime: 0,
        skillOneCooldown: 0,
        skillTwoCooldown: 0,
        ultimateCooldown: 0,
        // Full cooldown of the last cast, so the HUD rings start from a full circle.
        skillOneMax: 1,
        skillTwoMax: 1,
        ultimateMax: 1,
        castTimer: 0,
        castElapsed: 0,
        landTimer: 0,
        dustTimer: 0,
        castAnimation: "idle",
      });

      const freshState = () => {
        const bounds = renderer.getBounds();
        return {
          phase: "loadout",
          realm: Math.max(0, Math.min(9, saved.selectedRealm || 0)),
          selectedSkin: Math.max(0, Math.min(19, saved.selectedSkin || 0)),
          score: 0,
          runCoins: 0,
          kills: 0,
          worldTime: 0,
          realmStage: 0,
          screenFlash: 0,
          timeSlow: 0,
          cloneTimer: 0,
          counterTimer: 0,
          floorY: bounds.floorY,
          waveTime: balance.waveDuration,
          spawnTimer: 0.5,
          player: makePlayer(bounds.floorY, bounds.width),
          bullets: [],
          enemyBullets: [],
          enemies: [],
          pickups: [],
          effects: [],
          particles: [],
          rings: [],
          shake: 0,
          boss: null,
          bossDefeatTimer: 0,
          buffLevels: makeBuffState(),
          power: { gatling: 0, boots: 0, shield: 0 },
        };
      };

      function emitParticles(x, y, color, baseCount = 7) {
        const count = Math.max(2, Math.round(baseCount * balance.effectsIntensity));
        for (let i = 0; i < count; i += 1) {
          const angle = Math.random() * Math.PI * 2;
          const speed = 35 + Math.random() * 120;
          const life = 0.25 + Math.random() * 0.45;
          state.particles.push({
            x, y, color, size: 2 + Math.random() * 4,
            vx: Math.cos(angle) * speed, vy: Math.sin(angle) * speed,
            life, maxLife: life,
          });
        }
      }

      function addRing(x, y, radius, color, duration = 0.32) {
        state.rings.push({ x, y, radius, color, life: duration, maxLife: duration });
      }

      function addEffect(key, animation, x, y, size = 72, duration = 0.5) {
        state.effects.push({ key, animation, x, y, size, duration, age: 0, seed: Math.random() * 3 });
      }

      function playerBody() {
        return { x: state.player.x, y: state.player.y - 25, radius: 14 };
      }

      function spawnShot() {
        const player = state.player;
        const movingAngle = Math.abs(player.vx) > 28 ? Math.sign(player.vx) * 0.22 : 0;
        const split = state.buffLevels.split;
        const offsets = split >= 2 ? [-0.36, -0.18, 0, 0.18, 0.36] : split === 1 ? [-0.22, 0, 0.22] : [0];
        const speed = 620;
        const heavy = state.buffLevels.heavy;
        const skinPower = SKINS[state.selectedSkin].power;
        const cloneOffsets = state.cloneTimer > 0 ? [-0.12, 0.12] : [];
        for (const offset of [...offsets, ...cloneOffsets]) {
          const angle = movingAngle + offset;
          state.bullets.push({
            x: player.x + player.facing * 8,
            y: player.y - 44,
            vx: Math.sin(angle) * speed,
            vy: -Math.cos(angle) * speed,
            radius: 5.5 + heavy * 1.8,
            damage: (1 + heavy * 0.5) * skinPower,
            pierce: state.buffLevels.piercing,
            hitIds: new Set(),
            life: 1.8,
          });
        }
        player.shotFlash = 0.14;
        const muzzleX = player.x + (movingAngle ? Math.sign(movingAngle) * 24 : 0);
        addEffect("WEAPON_EFFECTS", "muzzle_flash", muzzleX, player.y - 45, 34, 0.22);
        audio.sfx("shoot");
      }

      function spawnSkillVolley(count, arc, damage, options = {}) {
        const player = state.player;
        const speed = options.speed || 690;
        for (let i = 0; i < count; i += 1) {
          const ratio = count === 1 ? 0.5 : i / (count - 1);
          const angle = (ratio - 0.5) * arc;
          state.bullets.push({
            x: player.x,
            y: player.y - 45,
            vx: Math.sin(angle) * speed,
            vy: -Math.cos(angle) * speed,
            radius: options.radius || 7,
            damage,
            pierce: options.pierce ?? 3,
            hitIds: new Set(),
            life: options.life || 2.2,
            homing: Boolean(options.homing),
            bounce: Boolean(options.bounce),
            forceFire: Boolean(options.fire),
            forceIce: Boolean(options.ice),
          });
        }
      }

      function damageAllEnemies(amount, { slow = 0, burn = 0 } = {}) {
        for (const enemy of [...state.enemies]) {
          if (!enemy.immune) enemy.hp -= amount;
          if (slow) enemy.slow = Math.max(enemy.slow, slow);
          if (burn) enemy.burn = Math.max(enemy.burn, burn);
          if (enemy.hp <= 0) killEnemy(enemy);
        }
      }

      function castSkill(slot) {
        const player = state.player;
        const skin = SKINS[state.selectedSkin];
        const index = state.selectedSkin;
        const power = skin.power;
        if (slot === "one") {
          if (player.skillOneCooldown > 0) return;
          player.skillOneCooldown = Math.max(3.4, 6 - index * 0.07);
          player.skillOneMax = player.skillOneCooldown;
          player.castAnimation = "skill_one";
          player.castTimer = 0.62;
          player.castElapsed = 0;
          const count = Math.min(24, 7 + Math.floor(index * 0.7));
          const options = { pierce: 2 + Math.floor(index / 5), radius: 6 + index * 0.12 };
          if ([1, 10, 11, 15].includes(index)) options.fire = true;
          if ([2, 11].includes(index)) options.ice = true;
          if ([8, 15].includes(index)) options.homing = true;
          if (index === 14) options.bounce = true;
          spawnSkillVolley(count, 0.7 + index * 0.025, (1.5 + index * 0.12) * power, options);
          if ([2, 4, 17].includes(index)) damageAllEnemies(0.8 * power, { slow: 2.8 });
          if ([3, 6, 18].includes(index)) {
            damageAllEnemies(1.2 * power);
            addEffect("DEFENSE_EFFECTS", "chain_lightning", renderer.width * 0.5, renderer.height * 0.4, renderer.width * 0.82, 0.5);
          }
          if ([7, 10, 13, 19].includes(index)) damageAllEnemies((1.4 + index * 0.08) * power, { burn: index === 10 ? 2.5 : 0 });
          ui.toast(skin.skillOne);
          audio.sfx("skill1");
          safeHaptic(24);
        } else if (slot === "two") {
          if (player.skillTwoCooldown > 0) return;
          player.skillTwoCooldown = Math.max(5.5, 10 - index * 0.12);
          player.skillTwoMax = player.skillTwoCooldown;
          player.castAnimation = "skill_two";
          player.castTimer = 0.82;
          player.castElapsed = 0;
          if ([0, 5, 13, 16].includes(index)) state.power.shield = Math.max(state.power.shield, 2 + Math.floor(index / 8));
          if ([1, 3, 9, 10, 12, 14].includes(index)) {
            player.x = player.facing > 0 ? renderer.getBounds().right : renderer.getBounds().left;
            player.invulnerable = Math.max(player.invulnerable, 0.8);
            damageAllEnemies(2.2 * power);
          }
          if ([2, 4, 8, 15].includes(index)) {
            state.timeSlow = 3.5 + index * 0.08;
            state.enemyBullets.length = 0;
            damageAllEnemies(1.2 * power, { slow: 4 });
          }
          if ([6, 18, 19].includes(index)) state.cloneTimer = 6 + index * 0.16;
          if ([7, 11, 19].includes(index)) state.power.gatling = Math.max(state.power.gatling, 7 + index * 0.12);
          if (index === 17) {
            state.counterTimer = 5;
            state.power.shield = Math.max(state.power.shield, 1);
          }
          if (index >= 14) player.hp = Math.min(3, player.hp + 1);
          addEffect("DEFENSE_EFFECTS", "nova_wave", player.x, player.y - 35, 130 + index * 4, 0.65);
          ui.toast(skin.skillTwo);
          audio.sfx("skill2");
          safeHaptic([20, 20, 30]);
        } else {
          if (player.ultimateCooldown > 0) return;
          player.ultimateCooldown = Math.max(14, 25 - index * 0.35);
          player.ultimateMax = player.ultimateCooldown;
          player.castAnimation = "ultimate";
          player.castTimer = 1.2;
          player.castElapsed = 0;
          player.invulnerable = 1.5;
          state.screenFlash = 0.9;
          state.enemyBullets.length = 0;
          const damage = (10 + index * 2.1) * power;
          damageAllEnemies(damage, { slow: 4, burn: 3 });
          if (state.boss) state.boss.hp -= state.boss.maxHp * (0.12 + index * 0.009) + damage;
          if (index >= 12) state.power.shield = Math.max(state.power.shield, 2);
          if (index >= 17) state.cloneTimer = Math.max(state.cloneTimer, 10);
          addEffect("DEFENSE_EFFECTS", "nova_wave", renderer.width * 0.5, renderer.height * 0.42,
            Math.max(renderer.width, renderer.height) * 1.15, 1.1);
          emitParticles(player.x, player.y - 40, skin.color, 45 + index * 2);
          ui.toast(skin.ultimate, 2.2);
          audio.sfx("ultimate");
          safeHaptic([45, 25, 70, 25, 90]);
        }
      }

      function spawnEnemy(type = Math.random() < 0.54 ? 0 : 1, mini = false) {
        const bounds = renderer.getBounds();
        const realm = state.realm;
        const speedScale = 1 + realm * 0.055;
        let enemy;
        const mode = type % 2;
        const elite = type >= 2;
        if (mode === 0) {
          const size = (mini ? 34 : 54 + Math.min(realm, 5) * 2) * 0.7;
          const hp = (mini ? 1 : 2 + Math.floor(realm / 3)) * (elite ? 2.2 : 1);
          enemy = {
            id: nextEntityId++, type, mode, elite, mini,
            x: bounds.left + Math.random() * (bounds.right - bounds.left),
            y: -size * 0.5,
            vx: mini ? (Math.random() < 0.5 ? -1 : 1) * 115 : 0,
            vy: balance.enemySpeed * speedScale * (state.realm === 4 ? 0.58 : 1),
            baseY: 0, hp, maxHp: hp,
            size, radius: size * 0.28, age: 0, shootCd: 1.3,
            attackTimer: 0, pendingAttack: false, burn: 0, burnTick: 0.5, slow: 0,
            animSeed: Math.random() * 4, facing: -1,
            immune: realm === 6,
          };
        } else {
          const fromLeft = Math.random() < 0.5;
          const size = (58 + Math.min(realm, 5) * 2) * 0.7;
          const y = bounds.height * (0.22 + Math.random() * 0.28);
          const hp = (3 + Math.floor(realm / 3)) * (elite ? 2.2 : 1);
          enemy = {
            id: nextEntityId++, type, mode, elite, mini: false,
            x: fromLeft ? -size : bounds.width + size,
            y, baseY: y,
            vx: (fromLeft ? 1 : -1) * balance.enemySpeed * (1.05 + realm * 0.045),
            vy: 0, hp, maxHp: hp,
            size, radius: size * 0.28, age: 0, shootCd: 0.8 + Math.random() * 1.2,
            attackTimer: 0, pendingAttack: false, burn: 0, burnTick: 0.5, slow: 0,
            animSeed: Math.random() * 4, facing: fromLeft ? -1 : 1,
          };
        }
        state.enemies.push(enemy);
      }

      function aimedVelocity(fromX, fromY, speed, spread = 0) {
        const target = playerBody();
        const angle = Math.atan2(target.y - fromY, target.x - fromX) + spread;
        return { vx: Math.cos(angle) * speed, vy: Math.sin(angle) * speed };
      }

      function addOrb(x, y, vx, vy, radius = 8, color = "#ff55cb", delay = 0, life = 5) {
        state.enemyBullets.push({ kind: "orb", x, y, vx, vy, radius, color, delay, age: 0, life });
      }

      function addLaser(x, width = 42, delay = 0.72, activeDuration = 0.55, top = 0) {
        // Celah Dimensi (realm 9) draws its beams as lightning strikes.
        state.enemyBullets.push({
          kind: "laser", x, width, delay, activeDuration, top, age: 0, life: delay + activeDuration,
          lightning: state.realm === 8, struck: false,
        });
      }

      function addZone(x, width = 70, delay = 0.72, activeDuration = 0.5) {
        state.enemyBullets.push({ kind: "zone", x, width, delay, activeDuration, age: 0, life: delay + activeDuration });
      }

      function executeEnemyAttack(enemy) {
        audio.sfx("enemy_shoot");
        const realm = state.realm;
        const speed = 155 + realm * 8;
        if (realm === 8 && enemy.mode === 1) {
          addLaser(enemy.x, 36, 0.62, 0.42, enemy.y);
          return;
        }
        if (realm === 4 && enemy.mode === 1) {
          enemy.vx *= 1.85;
          return;
        }
        if (realm === 5 && enemy.mode === 1) {
          enemy.vx *= -0.7;
          const velocity = aimedVelocity(enemy.x, enemy.y, speed, 0);
          addOrb(enemy.x, enemy.y, velocity.vx, velocity.vy, 9, "#b5f7ff");
          return;
        }
        if (realm === 3 && enemy.mode === 1) {
          [-0.28, 0.28].forEach((spread) => {
            const velocity = aimedVelocity(enemy.x, enemy.y, speed, spread);
            addOrb(enemy.x, enemy.y, velocity.vx, velocity.vy, 6, "#ffd568");
          });
          return;
        }
        const velocity = aimedVelocity(enemy.x, enemy.y, realm === 6 ? speed * 1.35 : speed, 0);
        addOrb(enemy.x, enemy.y, velocity.vx, velocity.vy, realm === 6 ? 10 : 8,
          realm === 0 ? "#8dff57" : REALMS[realm].colors[1]);
      }

      function handleGroundImpact(enemy) {
        const realm = state.realm;
        if (realm === 3) {
          for (let i = 0; i < 8; i += 1) {
            const angle = (Math.PI * 2 * i) / 8;
            addOrb(enemy.x, state.floorY - 8, Math.cos(angle) * 145, Math.sin(angle) * 145, 7, "#ffbe45");
          }
        } else if (realm === 7) {
          addOrb(enemy.x, state.floorY - 10, -210, -55, 8, "#a9f2ff");
          addOrb(enemy.x, state.floorY - 10, 210, -55, 8, "#a9f2ff");
        } else if (realm === 6) {
          addZone(enemy.x, 72, 0.12, 0.34);
        } else {
          emitParticles(enemy.x, state.floorY - 8, REALMS[realm].colors[0], 5);
        }
      }

      function dropPickup(enemy) {
        if (Math.random() > 0.13 || state.pickups.filter((item) => item.kind !== "coin").length >= 2) return;
        const data = POWERUPS[Math.floor(Math.random() * POWERUPS.length)];
        state.pickups.push({
          id: data.id, icon: data.icon, name: data.name,
          x: enemy.x, y: enemy.y, vy: 74, size: 45, animSeed: Math.random() * 6,
        });
      }

      function dropCoin(enemy) {
        const value = 1 + Math.floor(state.realm / 3) + (enemy.elite ? 2 : 0);
        state.pickups.push({
          kind: "coin", id: "coin", name: "Arcane Coin", value,
          x: enemy.x, y: enemy.y, vy: 64, size: 27, animSeed: Math.random() * 6,
        });
      }

      function killEnemy(enemy, allowDrop = true) {
        const index = state.enemies.indexOf(enemy);
        if (index === -1) return;
        state.enemies.splice(index, 1);
        state.score += 100 * (state.realm + 1);
        state.kills += 1;
        emitParticles(enemy.x, enemy.y, REALMS[state.realm].colors[0], 9);
        addEffect("WEAPON_EFFECTS", "impact_burst", enemy.x, enemy.y, enemy.size * 1.5, 0.45);
        addRing(enemy.x, enemy.y, enemy.size * (enemy.elite ? 1.5 : 1.1), REALMS[state.realm].colors[0]);
        state.shake = Math.max(state.shake, enemy.elite ? 0.22 : 0.12);
        audio.sfx("enemy_die");
        if (allowDrop) {
          dropCoin(enemy);
          dropPickup(enemy);
        }
        if (state.realm === 0 && enemy.type === 0 && !enemy.mini) {
          spawnEnemy(0, true);
          state.enemies.at(-1).x = enemy.x - 14;
          spawnEnemy(0, true);
          state.enemies.at(-1).x = enemy.x + 14;
        }
        if (state.buffLevels.vampiric > 0 && state.kills % 50 === 0) {
          state.player.hp = Math.min(3, state.player.hp + 1);
          ui.toast("Vampiric Chamber · +1 HP");
        }
      }

      function damageEnemy(enemy, damage, bullet) {
        if (enemy.immune) {
          emitParticles(bullet.x, bullet.y, "#ff744a", 4);
          return;
        }
        enemy.hp -= damage;
        enemy.hitFlash = 0.14;
        audio.sfx("enemy_hit");
        if (state.buffLevels.fire || bullet.forceFire) enemy.burn = 2.3;
        if (state.buffLevels.ice || bullet.forceIce) enemy.slow = 1.8 + Math.max(1, state.buffLevels.ice) * 0.55;
        if (state.realm === 8 && enemy.mode === 0) enemy.size = Math.min(76, enemy.size + 2);
        if (state.buffLevels.lightning) chainLightning(enemy, state.buffLevels.lightning);
        if (enemy.hp <= 0) killEnemy(enemy);
      }

      function chainLightning(origin, count) {
        let current = origin;
        const used = new Set([origin.id]);
        for (let jump = 0; jump < count; jump += 1) {
          const target = state.enemies
            .filter((enemy) => !used.has(enemy.id) && !enemy.immune)
            .sort((a, b) => Math.hypot(a.x - current.x, a.y - current.y) - Math.hypot(b.x - current.x, b.y - current.y))[0];
          if (!target || Math.hypot(target.x - current.x, target.y - current.y) > 180) break;
          used.add(target.id);
          target.hp -= 0.65;
          addEffect("DEFENSE_EFFECTS", "chain_lightning", (current.x + target.x) / 2,
            (current.y + target.y) / 2, Math.max(54, Math.hypot(target.x - current.x, target.y - current.y)), 0.28);
          if (target.hp <= 0) killEnemy(target);
          current = target;
        }
      }

      function collectPickup(pickup) {
        audio.sfx(pickup.kind === "coin" ? "coin" : pickup.id === "nova" ? "nova" : "powerup");
        safeHaptic(20);
        if (pickup.kind === "coin") {
          saved.coins += pickup.value;
          state.runCoins += pickup.value;
          void persist();
          return;
        }
        if (pickup.id === "gatling") state.power.gatling = 10;
        if (pickup.id === "boots") state.power.boots = 10;
        if (pickup.id === "shield") state.power.shield = 1;
        if (pickup.id === "nova") {
          addEffect("DEFENSE_EFFECTS", "nova_wave", state.player.x, state.player.y - 50,
            Math.max(renderer.width, renderer.height) * 0.72, 0.72);
          [...state.enemies].forEach((enemy) => killEnemy(enemy, false));
          if (state.boss) state.boss.hp -= state.boss.maxHp * 0.1;
          safeHaptic([30, 30, 45]);
        }
        ui.toast(pickup.name);
      }

      function hurtPlayer() {
        const player = state.player;
        if (player.invulnerable > 0 || player.dashTimer > 0 || state.phase === "gameover") return;
        if (state.counterTimer > 0) {
          state.counterTimer = 0;
          state.enemyBullets.length = 0;
          damageAllEnemies(8 * SKINS[state.selectedSkin].power);
          if (state.boss) state.boss.hp -= 12 * SKINS[state.selectedSkin].power;
          addEffect("DEFENSE_EFFECTS", "nova_wave", player.x, player.y - 35, 180, 0.65);
          player.invulnerable = 0.7;
          audio.sfx("counter");
          return;
        }
        if (state.power.shield > 0) {
          state.power.shield -= 1;
          player.invulnerable = 0.5;
          addEffect("DEFENSE_EFFECTS", "nova_wave", player.x, player.y - 36, 95, 0.42);
          audio.sfx("shield_break");
          safeHaptic(25);
          ui.toast("Aegis pecah");
          return;
        }
        player.hp -= 1;
        player.invulnerable = 1.1;
        player.hurtFlash = 0.55;
        emitParticles(player.x, player.y - 35, "#ff557a", 12);
        audio.sfx("player_hurt");
        safeHaptic([35, 25, 35]);
        if (player.hp <= 0) gameOver();
      }

      function updateEnemies(dt) {
        const bounds = renderer.getBounds();
        for (let i = state.enemies.length - 1; i >= 0; i -= 1) {
          const enemy = state.enemies[i];
          // hurtPlayer() can kill several enemies mid-loop (counter skill).
          if (!enemy) continue;
          enemy.age += dt;
          enemy.attackTimer = Math.max(0, enemy.attackTimer - dt);
          enemy.slow = Math.max(0, enemy.slow - dt);
          const slowFactor = enemy.slow > 0 ? 0.52 : 1;
          if (enemy.burn > 0) {
            enemy.burn -= dt;
            enemy.burnTick -= dt;
            if (enemy.burnTick <= 0) {
              enemy.burnTick = 0.5;
              enemy.hp -= 0.25 + state.buffLevels.fire * 0.18;
              if (enemy.hp <= 0) { killEnemy(enemy); continue; }
            }
          }
          if (enemy.mode === 0) {
            if (enemy.mini) {
              enemy.x += enemy.vx * dt * slowFactor;
              enemy.y = state.floorY - 18 + Math.sin(enemy.age * 9) * 3;
              if (enemy.x < bounds.left || enemy.x > bounds.right) enemy.vx *= -1;
              // Player shots fly upward and can't reach floor minis, so they fade
              // out on their own; otherwise the boss never spawns (needs 0 enemies).
              if (enemy.age > 8) {
                emitParticles(enemy.x, enemy.y, REALMS[state.realm].colors[0], 4);
                state.enemies.splice(i, 1);
                continue;
              }
            } else {
              if (state.realm === 1 && enemy.age < 0.8) enemy.x += (state.player.x - enemy.x) * dt * 1.1;
              enemy.y += enemy.vy * dt * slowFactor;
              if (state.realm === 8) enemy.vy *= 1.0007;
            }
          } else {
            enemy.x += enemy.vx * dt * slowFactor;
            const wave = state.realm === 1 ? Math.sin(enemy.age * 3) * 70 : Math.sin(enemy.age * 2.7 + enemy.animSeed) * 24;
            enemy.y = enemy.baseY + wave;
            enemy.shootCd -= dt * slowFactor;
            if (enemy.shootCd <= 0 && !enemy.pendingAttack) {
              enemy.shootCd = Math.max(0.75, 2.05 - state.realm * 0.07) + Math.random() * 0.7;
              enemy.attackTimer = 0.48;
              enemy.pendingAttack = true;
            }
            if (enemy.pendingAttack && enemy.attackTimer <= 0.2) {
              enemy.pendingAttack = false;
              executeEnemyAttack(enemy);
            }
          }

          if (circleHit(playerBody(), enemy, -3)) {
            hurtPlayer();
            if (!enemy.immune) killEnemy(enemy, false);
            continue;
          }
          if (enemy.mode === 0 && !enemy.mini && enemy.y >= state.floorY - 16) {
            handleGroundImpact(enemy);
            state.enemies.splice(i, 1);
            continue;
          }
          if (enemy.mode === 1 && (enemy.x < -enemy.size * 2 || enemy.x > bounds.width + enemy.size * 2)) {
            state.enemies.splice(i, 1);
          }
        }
      }

      function updatePlayerBullets(dt) {
        const bounds = renderer.getBounds();
        for (let i = state.bullets.length - 1; i >= 0; i -= 1) {
          const bullet = state.bullets[i];
          if (bullet.homing && state.enemies.length) {
            const target = [...state.enemies].sort((a, b) => Math.hypot(a.x - bullet.x, a.y - bullet.y) - Math.hypot(b.x - bullet.x, b.y - bullet.y))[0];
            const angle = Math.atan2(target.y - bullet.y, target.x - bullet.x);
            const speed = Math.hypot(bullet.vx, bullet.vy);
            bullet.vx += (Math.cos(angle) * speed - bullet.vx) * Math.min(1, dt * 4);
            bullet.vy += (Math.sin(angle) * speed - bullet.vy) * Math.min(1, dt * 4);
          }
          bullet.x += bullet.vx * dt;
          bullet.y += bullet.vy * dt;
          if (bullet.bounce && (bullet.x < bounds.left || bullet.x > bounds.right)) {
            bullet.vx *= -1;
            bullet.x = Math.max(bounds.left, Math.min(bounds.right, bullet.x));
          }
          bullet.life -= dt;
          let removed = false;
          for (const enemy of [...state.enemies]) {
            if (bullet.hitIds.has(enemy.id) || !circleHit(bullet, enemy)) continue;
            bullet.hitIds.add(enemy.id);
            damageEnemy(enemy, bullet.damage, bullet);
            addEffect("WEAPON_EFFECTS", "impact_burst", bullet.x, bullet.y, 52 + bullet.radius * 2, 0.3);
            bullet.pierce -= 1;
            if (bullet.pierce < 0) { state.bullets.splice(i, 1); removed = true; break; }
          }
          if (removed) continue;
          if (state.boss && circleHit(bullet, state.boss, state.boss.size * 0.2)) {
            state.boss.hp -= bullet.damage;
            state.boss.hitFlash = 0.1;
            audio.sfx("boss_hit");
            addEffect("WEAPON_EFFECTS", "impact_burst", bullet.x, bullet.y, 58, 0.3);
            emitParticles(bullet.x, bullet.y, REALMS[state.realm].colors[0], 3);
            state.bullets.splice(i, 1);
            continue;
          }
          if (bullet.life <= 0 || bullet.y < -50 || bullet.x < -50 || bullet.x > bounds.width + 50) {
            state.bullets.splice(i, 1);
          }
        }
      }

      function updateEnemyBullets(dt) {
        const body = playerBody();
        const bounds = renderer.getBounds();
        for (let i = state.enemyBullets.length - 1; i >= 0; i -= 1) {
          const bullet = state.enemyBullets[i];
          // hurtPlayer() can clear enemyBullets mid-loop (game over, counter).
          if (!bullet) continue;
          bullet.age += dt;
          const active = bullet.age >= (bullet.delay || 0);
          if (active && bullet.kind === "orb") {
            bullet.x += bullet.vx * dt;
            bullet.y += bullet.vy * dt;
            if (circleHit(body, bullet)) {
              hurtPlayer();
              state.enemyBullets.splice(i, 1);
              continue;
            }
          } else if (active && bullet.kind === "laser") {
            if (!bullet.struck) {
              bullet.struck = true;
              audio.sfx(bullet.lightning ? "lightning" : "laser");
              if (bullet.lightning) state.shake = Math.max(state.shake, 0.18);
            }
            if (pointInVerticalZone(body, bullet, state.floorY)) hurtPlayer();
          } else if (active && bullet.kind === "zone") {
            const inside = body.x > bullet.x - bullet.width / 2 && body.x < bullet.x + bullet.width / 2;
            if (inside && body.y > state.floorY - 48) hurtPlayer();
          }
          if (bullet.age >= bullet.life || bullet.x < -100 || bullet.x > bounds.width + 100 || bullet.y > bounds.height + 100) {
            state.enemyBullets.splice(i, 1);
          }
        }
      }

      function updatePickups(dt) {
        const body = playerBody();
        for (let i = state.pickups.length - 1; i >= 0; i -= 1) {
          const pickup = state.pickups[i];
          if (pickup.kind === "coin") {
            const distance = Math.hypot(body.x - pickup.x, body.y - pickup.y);
            if (distance < 150) pickup.x += (body.x - pickup.x) * dt * 4.5;
          }
          pickup.y += pickup.vy * dt;
          if (circleHit(body, { ...pickup, radius: pickup.size * 0.3 })) {
            state.pickups.splice(i, 1);
            collectPickup(pickup);
          } else if (pickup.y > state.floorY + 25) {
            state.pickups.splice(i, 1);
          }
        }
      }

      function updateFeedback(dt) {
        for (let i = state.effects.length - 1; i >= 0; i -= 1) {
          state.effects[i].age += dt;
          if (state.effects[i].age >= state.effects[i].duration) state.effects.splice(i, 1);
        }
        for (let i = state.particles.length - 1; i >= 0; i -= 1) {
          const particle = state.particles[i];
          particle.life -= dt;
          particle.x += particle.vx * dt;
          particle.y += particle.vy * dt;
          particle.vy += 95 * dt;
          if (particle.life <= 0) state.particles.splice(i, 1);
        }
        for (let i = state.rings.length - 1; i >= 0; i -= 1) {
          state.rings[i].life -= dt;
          if (state.rings[i].life <= 0) state.rings.splice(i, 1);
        }
        for (const enemy of state.enemies) enemy.hitFlash = Math.max(0, (enemy.hitFlash || 0) - dt);
        if (state.boss) state.boss.hitFlash = Math.max(0, (state.boss.hitFlash || 0) - dt);
        state.shake = Math.max(0, state.shake - dt);
      }

      function updateWave(dt) {
        state.waveTime = Math.max(0, state.waveTime - dt);
        const pressure = 1 - state.waveTime / balance.waveDuration;
        state.realmStage = pressure >= 0.42 ? 1 : 0;
        state.spawnTimer -= dt;
        if (state.waveTime > 0 && state.spawnTimer <= 0) {
          let enemyType = Math.random() < 0.54 ? 0 : 1;
          if (pressure > 0.72 && Math.random() < 0.62) enemyType = 4 + (Math.random() < 0.5 ? 0 : 1);
          else if (pressure > 0.38 && Math.random() < Math.min(0.58, 0.18 + pressure * 0.42)) enemyType = 2 + (Math.random() < 0.5 ? 0 : 1);
          spawnEnemy(enemyType);
          state.spawnTimer = Math.max(0.45, balance.spawnInterval - state.realm * 0.035 - pressure * 0.28);
        }
        if (state.waveTime <= 0 && state.enemies.length === 0) beginBoss();
      }

      function beginBoss() {
        const bounds = renderer.getBounds();
        const maxHp = Math.round((165 + state.realm * 28) * balance.bossHealthScale);
        state.phase = "boss";
        state.realmStage = 1;
        state.enemyBullets.length = 0;
        state.boss = {
          id: nextEntityId++, name: REALMS[state.realm].boss,
          x: bounds.width * 0.5, y: bounds.height * 0.22,
          size: Math.max(190, Math.min(bounds.width * 0.78, bounds.height * 0.42)),
          hp: maxHp, maxHp, patternTimer: 1.35, telegraph: 0, pendingAttack: false,
          attackAnim: 0, animation: "idle", animTime: 0, alpha: 1,
        };
        ui.toast(`BOSS · ${state.boss.name}`, 2.2);
        audio.sfx("boss_appear");
        safeHaptic([35, 45, 35]);
      }

      function radialBurst(boss, count, speed, color) {
        for (let i = 0; i < count; i += 1) {
          const angle = (Math.PI * 2 * i) / count + state.worldTime * 0.35;
          addOrb(boss.x, boss.y, Math.cos(angle) * speed, Math.sin(angle) * speed, 7, color);
        }
      }

      function bossPattern() {
        const boss = state.boss;
        const bounds = renderer.getBounds();
        const pattern = REALMS[state.realm].pattern;
        if (pattern === "treant") {
          for (let i = 0; i < 5; i += 1) addOrb(bounds.left + Math.random() * (bounds.right - bounds.left), -15 - i * 18, 0, 175, 11, "#8dff57", i * 0.08);
          addZone(state.player.x, 64, 0.62, 0.45);
        } else if (pattern === "golem") {
          addLaser(state.player.x, 44, 0.72, 0.55);
          addLaser(bounds.width * (Math.random() < 0.5 ? 0.25 : 0.75), 38, 0.92, 0.48);
        } else if (pattern === "necro") {
          for (let i = 0; i < 9; i += 1) addOrb(bounds.left + Math.random() * (bounds.right - bounds.left), -20 - i * 16, 0, 190 + Math.random() * 40, 7, "#c67bff", Math.random() * 0.45);
        } else if (pattern === "automaton") {
          [-0.4, -0.2, 0, 0.2, 0.4].forEach((spread) => {
            const velocity = aimedVelocity(boss.x, boss.y, 215, spread);
            addOrb(boss.x, boss.y, velocity.vx, velocity.vy, 9, "#ffd15a");
          });
        } else if (pattern === "kraken") {
          [0.22, 0.5, 0.78].forEach((ratio, i) => addZone(bounds.width * ratio, bounds.width * 0.16, 0.55 + i * 0.18, 0.5));
        } else if (pattern === "griffin") {
          for (let i = -1; i <= 1; i += 1) addOrb(boss.x + i * 70, boss.y, i * 35, 135, 16, "#d7fbff", i * 0.08 + 0.15);
        } else if (pattern === "phoenix") {
          radialBurst(boss, 12, 150, "#ff7041");
          for (let i = 0; i < 4; i += 1) addOrb(bounds.left + Math.random() * (bounds.right - bounds.left), -20, 0, 210, 9, "#ff425e", i * 0.1);
        } else if (pattern === "lich") {
          state.bullets.splice(0, Math.floor(state.bullets.length * 0.55));
          [-0.38, -0.19, 0, 0.19, 0.38].forEach((spread) => {
            const velocity = aimedVelocity(boss.x, boss.y, 180, spread);
            addOrb(boss.x, boss.y, velocity.vx, velocity.vy, 10, "#a9f2ff", 0.22);
          });
        } else if (pattern === "worm") {
          const side = Math.random() < 0.5 ? 0.28 : 0.72;
          addLaser(bounds.width * side, bounds.width * 0.22, 0.78, 0.7);
          addLaser(bounds.width * (1 - side), bounds.width * 0.13, 1.05, 0.55);
        } else {
          const healthRatio = boss.hp / boss.maxHp;
          radialBurst(boss, healthRatio > 0.66 ? 10 : healthRatio > 0.33 ? 14 : 18,
            healthRatio > 0.33 ? 170 : 210, "#ff3f81");
          if (healthRatio <= 0.66) addLaser(state.player.x, healthRatio > 0.33 ? 46 : 62, 0.7, 0.58);
          if (healthRatio <= 0.33) {
            addZone(bounds.width * 0.25, bounds.width * 0.22, 0.8, 0.55);
            addZone(bounds.width * 0.75, bounds.width * 0.22, 1.0, 0.55);
          }
        }
        audio.sfx("boss_attack");
      }

      function updateBoss(dt) {
        const boss = state.boss;
        if (!boss) return;
        boss.animTime += dt;
        boss.x = renderer.width * 0.5 + Math.sin(state.worldTime * 0.7) * renderer.width * 0.16;
        boss.attackAnim = Math.max(0, boss.attackAnim - dt);
        if (boss.telegraph > 0) {
          boss.telegraph -= dt;
          boss.animation = "telegraph";
          if (boss.telegraph <= 0 && boss.pendingAttack) {
            boss.pendingAttack = false;
            boss.attackAnim = 0.55;
            bossPattern();
          }
        } else if (boss.attackAnim > 0) {
          boss.animation = "attack";
        } else {
          boss.animation = "idle";
          boss.patternTimer -= dt;
          if (boss.patternTimer <= 0) {
            const ratio = boss.hp / boss.maxHp;
            boss.telegraph = ratio < 0.34 ? 0.48 : 0.65;
            boss.pendingAttack = true;
            boss.patternTimer = Math.max(1.35, 2.45 - state.realm * 0.055 - (1 - ratio) * 0.5);
          }
        }
        if (boss.hp <= 0) defeatBoss();
      }

      function defeatBoss() {
        if (!state.boss || state.phase === "bossDefeat") return;
        state.phase = "bossDefeat";
        state.boss.animation = "defeat";
        state.boss.animTime = 0;
        state.bossDefeatTimer = 1.55;
        state.enemyBullets.length = 0;
        state.bullets.length = 0;
        state.score += 1500 * (state.realm + 1);
        emitParticles(state.boss.x, state.boss.y, REALMS[state.realm].colors[0], 35);
        audio.sfx("boss_defeat");
        safeHaptic([45, 35, 70]);
        saved.bestRealm = Math.max(saved.bestRealm, state.realm + 1);
        void persist();
      }

      async function finishBossDefeat() {
        if (state.realm === REALMS.length - 1) {
          victory();
          return;
        }
        state.phase = "camp";
        state.boss = null;
        state.player.hp = Math.min(3, state.player.hp + 1);
        const choices = pickBuffChoices(state.buffLevels);
        const nextLoad = art.loadRealm(state.realm + 1);
        ui.showCamp(choices, state.buffLevels, (buff) => {
          state.buffLevels[buff.id] = Math.min(buff.max, (state.buffLevels[buff.id] || 0) + 1);
          audio.sfx("buff_select");
          safeHaptic(24);
          ui.hideOverlay();
          ui.setLoading(true, "Membuka portal realm…");
          void nextLoad.then(() => enterRealm(state.realm + 1)).catch(() => {
            ui.setLoading(false);
            ui.toast("Portal gagal terbuka — coba pilih lagi");
          });
        });
      }

      function updatePower(dt) {
        state.power.gatling = Math.max(0, state.power.gatling - dt);
        state.power.boots = Math.max(0, state.power.boots - dt);
        state.timeSlow = Math.max(0, state.timeSlow - dt);
        state.cloneTimer = Math.max(0, state.cloneTimer - dt);
        state.counterTimer = Math.max(0, state.counterTimer - dt);
        state.screenFlash = Math.max(0, state.screenFlash - dt * 1.8);
      }

      function updateActive(dt) {
        const bounds = renderer.getBounds();
        const wasGrounded = state.player.jumps === 0 && state.player.vy === 0;
        state.floorY = bounds.floorY;
        if (wasGrounded) state.player.y = state.floorY;
        state.player.worldTime = state.worldTime;
        const movement = stepPlayer(state.player, input, dt, bounds, balance, state.power, state.realm);
        if (movement.jumped) {
          audio.sfx(state.player.jumps === 2 ? "double_jump" : "jump");
          if (state.player.jumps === 2) addEffect("DEFENSE_EFFECTS", "double_jump_ring", state.player.x, state.player.y + 8, 72, 0.38);
        }
        if (movement.dashed) { audio.sfx("dash"); safeHaptic(16); }
        // Landing squash and footstep dust (drawn in renderer.drawPlayer).
        if (movement.landed) {
          state.player.landTimer = 0.14;
          emitParticles(state.player.x, state.floorY - 2, "#cfe3ff", 4);
        }
        state.player.landTimer = Math.max(0, state.player.landTimer - dt);
        if (state.player.jumps === 0 && Math.abs(state.player.vx) > 120) {
          state.player.dustTimer -= dt;
          if (state.player.dustTimer <= 0) {
            state.player.dustTimer = 0.16;
            emitParticles(state.player.x - state.player.facing * 10, state.floorY - 2, "#cfe3ff", 2);
          }
        }
        state.player.hurtFlash = Math.max(0, state.player.hurtFlash - dt);
        state.player.shotFlash = Math.max(0, state.player.shotFlash - dt);
        if (state.player.castTimer > 0) state.player.castElapsed += dt;
        state.player.castTimer = Math.max(0, state.player.castTimer - dt);
        state.player.skillOneCooldown = Math.max(0, state.player.skillOneCooldown - dt);
        state.player.skillTwoCooldown = Math.max(0, state.player.skillTwoCooldown - dt);
        state.player.ultimateCooldown = Math.max(0, state.player.ultimateCooldown - dt);
        if (input.consume("skill1")) castSkill("one");
        if (input.consume("skill2")) castSkill("two");
        if (input.consume("ultimate")) castSkill("ultimate");
        state.player.shootCooldown = Math.max(0, (state.player.shootCooldown || 0) - dt);
        if (input.isDown("fire") && state.player.shootCooldown <= 0) {
          const heavyPenalty = 1 + state.buffLevels.heavy * 0.12;
          state.player.shootCooldown = state.power.gatling > 0 ? 0.07 : balance.fireInterval * heavyPenalty;
          spawnShot();
        }
        const threatDt = dt * (state.timeSlow > 0 ? 0.34 : 1);
        updateEnemies(threatDt);
        updatePlayerBullets(dt);
        updateEnemyBullets(threatDt);
        updatePickups(dt);
        updatePower(dt);
        updateFeedback(dt);
      }

      async function enterRealm(index) {
        state.realm = index;
        state.phase = "wave";
        state.realmStage = 0;
        state.waveTime = balance.waveDuration;
        state.spawnTimer = 0.45;
        state.enemies.length = 0;
        state.enemyBullets.length = 0;
        state.bullets.length = 0;
        state.pickups.length = 0;
        state.boss = null;
        state.player.x = renderer.width * 0.5;
        state.player.y = renderer.getBounds().floorY;
        state.player.vx = 0;
        state.player.vy = 0;
        state.player.jumps = 0;
        // Drop presses made in menus/camp so they don't fire a skill on spawn.
        input?.clear();
        audio.setRealm(index);
        audio.sfx("realm_start");
        ui.setLoading(false);
        ui.setPrompt("");
        ui.toast(`REALM ${index + 1} · ${REALMS[index].short}`, 2.1);
        if (index < REALMS.length - 1) void art.loadRealm(index + 1).catch(() => {});
      }

      function openLoadout() {
        state.phase = "loadout";
        ui.setPrompt("");
        ui.showLoadout({
          skins: SKINS,
          realms: REALMS,
          coins: saved.coins,
          unlocked: saved.unlockedSkins,
          selectedSkin: state.selectedSkin,
          selectedRealm: state.realm,
          stats: { bestScore: saved.bestScore, bestRealm: saved.bestRealm, wins: saved.wins },
          areaUnlocked,
          onCheat() {
            saved.coins = 999;
            saved.allAreas = true;
            void persist();
            audio.sfx("buy");
            openLoadout();
            ui.toast("Koin 999 & semua area terbuka");
          },
          onSkin(index) {
            audio.sfx("ui_click");
            // Only show the loader if the sheet isn't cached, so browsing doesn't flash.
            const loaderTimer = window.setTimeout(() => ui.setLoading(true, "Menyiapkan skin…"), 150);
            const done = () => {
              window.clearTimeout(loaderTimer);
              ui.setLoading(false);
            };
            void art.loadSkinPreview(index).then(() => {
              done();
              state.selectedSkin = index;
              saved.selectedSkin = index;
              const count = SKINS.length;
              const prev = (index + count - 1) % count;
              const next = (index + 1) % count;
              art.retainSkins([index, prev, next]);
              openLoadout();
              // Warm up the neighbours so the arrows switch instantly.
              window.setTimeout(() => {
                if (state.phase !== "loadout") return;
                for (const neighbour of [next, prev]) void art.loadSkinPreview(neighbour).catch(() => {});
              }, 250);
            }).catch(done);
          },
          onArea(index) {
            if (!areaUnlocked(index)) return;
            audio.sfx("ui_click");
            state.realm = index;
            saved.selectedRealm = index;
            openLoadout();
            // Load that realm's artwork for the backdrop, then redraw the menu with it.
            void art.loadRealm(index).then(() => {
              if (state.phase === "loadout" && state.realm === index) openLoadout();
            }).catch(() => {});
          },
          onBuy(index) {
            const skin = SKINS[index];
            if (saved.unlockedSkins.includes(index) || saved.coins < skin.price) return;
            saved.coins -= skin.price;
            saved.unlockedSkins.push(index);
            saved.unlockedSkins.sort((a, b) => a - b);
            void persist();
            audio.sfx("buy");
            safeHaptic(24);
            openLoadout();
          },
          onReset: resetProgress,
          onStart() {
            void audio.unlock();
            audio.sfx("ui_click");
            saved.selectedSkin = state.selectedSkin;
            saved.selectedRealm = state.realm;
            ui.hideOverlay();
            ui.setLoading(true, "Membuka portal realm…");
            void Promise.all([art.loadSkin(state.selectedSkin), art.loadRealm(state.realm)])
              .then(() => {
                void persist();
                void enterRealm(state.realm);
                // A run that starts at the first realm (or a first-ever run)
                // opens with the tutorial; the game stays paused while it shows.
                if (state.realm === 0 || !saved.tutorialSeen) openTutorial(true);
              })
              .catch(() => ui.setLoading(false));
          },
        });
      }

      async function resetRun() {
        audio.sfx("ui_click");
        ui.hideOverlay();
        input?.clear();
        state = freshState();
        ui.setLoading(false);
        openLoadout();
      }

      function clampUnit(value, fallback) {
        const number = Number(value);
        return Number.isFinite(number) ? Math.max(0, Math.min(1, number)) : fallback;
      }

      function applySoundSettings() {
        audio?.setMix(saved.settings.music, saved.settings.sfx);
        ui.setMuted(saved.settings.music <= 0 && saved.settings.sfx <= 0);
      }

      // Save whenever the app may be leaving: Flutter dispatches "archer-save"
      // on pause/exit, and the browser fires pagehide/visibilitychange.
      // Leaving the app mid-run also pauses it, so the player returns to the pause menu.
      function saveNow() {
        void persist();
        openPause();
      }
      function saveWhenHidden() { if (document.hidden) saveNow(); }

      function openTutorial(first, onDone) {
        ui.showTutorial({
          first,
          onClose: () => {
            input?.clear();
            if (!saved.tutorialSeen) {
              saved.tutorialSeen = true;
              void persist();
            }
            onDone?.();
          },
        });
      }

      const isPlaying = () => Boolean(state) && (state.phase === "wave" || state.phase === "boss");

      function openPause() {
        if (!isPlaying() || ui.isModalOpen()) return;
        input?.clear();
        audio?.sfx("ui_click");
        ui.showPause({
          onResume: () => input?.clear(),
          onHelp: () => openTutorial(false, openPause),
          onMenu: () => ui.confirm({
            title: "Kembali ke main menu?",
            text: "Run ini akan berakhir. Koin yang sudah dikumpulkan tetap tersimpan.",
            confirmLabel: "KELUAR",
            onConfirm: quitToMenu,
            onCancel: openPause,
          }),
        });
      }

      function quitToMenu() {
        saved.bestScore = Math.max(saved.bestScore, Math.floor(state.score));
        void persist();
        void resetRun();
      }

      function openVolume() {
        ui.showVolume({
          music: saved.settings.music,
          sfx: saved.settings.sfx,
          onChange: (values) => {
            saved.settings = values;
            applySoundSettings();
          },
          onClose: (values) => {
            saved.settings = values;
            applySoundSettings();
            input?.clear();
            void persist();
          },
        });
      }

      function resetProgress() {
        ui.confirm({
          title: "Reset progres?",
          text: "Semua koin, Gun-Mage yang dibeli, dan skor terbaik akan dihapus. Tindakan ini tidak bisa dibatalkan.",
          confirmLabel: "RESET",
          onConfirm: () => {
            // Keep player preferences; wipe everything earned.
            saved = { ...defaultSave(), tutorialSeen: saved.tutorialSeen, settings: saved.settings };
            state = freshState();
            void persist();
            audio.sfx("ui_click");
            ui.setLoading(true, "Mereset progres…");
            void Promise.all([art.loadSkin(0), art.loadRealm(0)])
              .catch(() => {})
              .then(() => {
                ui.setLoading(false);
                openLoadout();
                ui.toast("Progres direset");
              });
          },
        });
      }

      async function persist() {
        saved.bestScore = Math.max(saved.bestScore, Math.floor(state?.score || 0));
        try { await sdk.gameState.save(saved); } catch { /* Run continues without persistence. */ }
      }

      function submitScore() {
        const value = Math.max(0, Math.min(Number.MAX_SAFE_INTEGER, Math.floor(state.score)));
        void sdk.leaderboard.submit(value).catch(() => {});
      }

      function gameOver() {
        if (state.phase === "gameover") return;
        state.phase = "gameover";
        state.player.vx = 0;
        state.player.vy = 0;
        state.enemyBullets.length = 0;
        state.bullets.length = 0;
        saved.bestScore = Math.max(saved.bestScore, Math.floor(state.score));
        saved.bestRealm = Math.max(saved.bestRealm, state.realm + 1);
        submitScore();
        void persist();
        audio.sfx("lose");
        ui.showGameOver(state.score, saved.bestScore, state.realm, () => { void resetRun(); });
      }

      function victory() {
        state.phase = "victory";
        state.boss = null;
        state.enemyBullets.length = 0;
        saved.wins += 1;
        saved.bestRealm = 10;
        saved.bestScore = Math.max(saved.bestScore, Math.floor(state.score));
        submitScore();
        void persist();
        audio.sfx("win");
        ui.showVictory(state.score, saved.bestScore, () => { void resetRun(); });
      }

      function update(dt) {
        if (!state) return;
        state.worldTime += dt;
        if (["wave", "boss"].includes(state.phase)) updateActive(dt);
        if (state.phase === "wave") updateWave(dt);
        if (state.phase === "boss") updateBoss(dt * (state.timeSlow > 0 ? 0.45 : 1));
        if (state.phase === "bossDefeat") {
          updateFeedback(dt);
          // Play the 5-frame defeat animation once, hold the last frame, then fade out.
          state.boss.animTime = Math.min(0.49, state.boss.animTime + dt);
          state.boss.alpha = Math.max(0, Math.min(1, state.bossDefeatTimer / 0.6));
          state.bossDefeatTimer -= dt;
          if (state.bossDefeatTimer <= 0) void finishBossDefeat();
        }
        audio.update(dt, state.phase === "boss" || state.realm >= 6);
      }

      function render() {
        if (!state) return;
        renderer.draw(state, state.worldTime);
        const bossRatio = state.boss ? state.boss.hp / state.boss.maxHp : 1;
        ui.update({
          score: state.score,
          coins: saved.coins,
          hp: state.player.hp,
          realm: state.realm,
          realmName: REALMS[state.realm].short,
          timer: state.phase === "wave" ? Math.ceil(state.waveTime) : state.phase === "boss" ? "BOSS" : "—",
          dashRatio: state.player.dashCooldown / 1.35,
          skillRatios: {
            one: state.player.skillOneCooldown / state.player.skillOneMax,
            two: state.player.skillTwoCooldown / state.player.skillTwoMax,
            ultimate: state.player.ultimateCooldown / state.player.ultimateMax,
          },
          skin: SKINS[state.selectedSkin],
          boss: state.boss ? {
            name: state.boss.name,
            hp: state.boss.hp,
            maxHp: state.boss.maxHp,
            phaseText: state.realm === 9 ? `FASE ${bossRatio > 0.66 ? 1 : bossRatio > 0.33 ? 2 : 3}` : "",
          } : null,
          buffLevels: state.buffLevels,
          power: state.power,
          playing: isPlaying(),
        });
      }

      function frame(now) {
        if (destroyed) return;
        const dt = lastTime ? Math.min(0.033, (now - lastTime) / 1000) : 0;
        lastTime = now;
        if (!ui.isModalOpen()) update(dt);
        // The main menu covers the arena with an opaque panel, so skip drawing
        // the game underneath it and leave the frame budget to the menu.
        if (state?.phase !== "loadout") render();
        else ui.shell.classList.remove("is-playing");
        animationFrame = requestAnimationFrame(frame);
      }

      async function boot() {
        try {
          const [loadedAudio, savedData] = await Promise.all([
            createArcaneAudio(sdk, balance.musicVolume),
            sdk.gameState.load().catch(() => null),
            art.loadInitial(),
          ]).then(([audioValue, saveValue]) => [audioValue, saveValue]);
          if (destroyed) { await loadedAudio.destroy(); return; }
          audio = loadedAudio;
          if (savedData && (savedData.version === 1 || savedData.version === 2)) {
            saved = {
              version: 2,
              bestScore: Number(savedData.bestScore) || 0,
              bestRealm: Number(savedData.bestRealm) || 0,
              wins: Number(savedData.wins) || 0,
              coins: Math.max(0, Number(savedData.coins) || 0),
              unlockedSkins: Array.isArray(savedData.unlockedSkins)
                ? [...new Set([0, ...savedData.unlockedSkins.filter((value) => Number.isInteger(value) && value >= 0 && value < 20)])]
                : [0],
              selectedSkin: Math.max(0, Math.min(19, Number(savedData.selectedSkin) || 0)),
              selectedRealm: Math.max(0, Math.min(9, Number(savedData.selectedRealm) || 0)),
              tutorialSeen: savedData.tutorialSeen === true,
              allAreas: savedData.allAreas === true,
              settings: {
                music: clampUnit(savedData.settings?.music, 1),
                sfx: clampUnit(savedData.settings?.sfx, 1),
              },
            };
          }
          applySoundSettings();
          if (!areaUnlocked(saved.selectedRealm)) saved.selectedRealm = 0;
          await Promise.all([art.loadSkin(saved.selectedSkin), art.loadRealm(saved.selectedRealm)]);
          ui.setArt(art);
          renderer = new GameRenderer(ui.canvas, art);
          state = freshState();
          input = createInput(ui.shell, ui.canvas, () => {
            void audio.unlock();
          });
          for (const key of Object.keys(TWEAK_DEFAULTS)) {
            try {
              unsubscribers.push(tweaks.subscribe(key, (value) => {
                balance[key] = Number(value) || TWEAK_DEFAULTS[key];
                if (key === "musicVolume") audio.setVolume(balance[key]);
              }));
            } catch { /* A missing live channel keeps the initial value. */ }
          }
          ui.setToolHandlers({ onVolume: openVolume, onHelp: () => openTutorial(false), onPause: openPause });
          window.addEventListener("pagehide", saveNow);
          window.addEventListener("archer-save", saveNow);
          document.addEventListener("visibilitychange", saveWhenHidden);
          ui.setLoading(false);
          openLoadout();
          ui.hideSplash();
          animationFrame = requestAnimationFrame(frame);
          void art.loadRealm(1).catch(() => {});
        } catch {
          ui.hideSplash();
          ui.setLoading(true, "Rune gagal dimuat · muat ulang game");
        }
      }

      void boot();

      teardown = () => {
        destroyed = true;
        window.removeEventListener("pagehide", saveNow);
        window.removeEventListener("archer-save", saveNow);
        document.removeEventListener("visibilitychange", saveWhenHidden);
        cancelAnimationFrame(animationFrame);
        unsubscribers.forEach((unsubscribe) => unsubscribe?.());
        input?.destroy();
        renderer?.destroy();
        void audio?.destroy();
        ui.destroy();
      };
    },
    destroy() {
      teardown();
      teardown = () => {};
    },
  };
}
