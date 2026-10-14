import {
  drawAnimatedCell, drawAnchored, drawAtlas, drawBackdrop, drawFloor, drawFrameInCell, findFrame,
} from "./assets.js";
import { REALMS, SKINS } from "./data.js";

// Deterministic per tick so a bolt holds its shape for one crackle frame.
function seededRandom(seed) {
  let value = (seed >>> 0) || 1;
  return () => {
    value = (value * 1664525 + 1013904223) >>> 0;
    return value / 4294967296;
  };
}

// Jagged zig-zag from (x, top) down to bottom, wandering up to ±spread/2.
function boltPoints(rand, x, top, bottom, spread) {
  const steps = Math.max(5, Math.round((bottom - top) / 28));
  const points = [[x, top]];
  for (let i = 1; i <= steps; i += 1) {
    const sway = i === steps ? spread * 0.2 : spread;
    points.push([x + (rand() - 0.5) * sway, top + ((bottom - top) * i) / steps]);
  }
  return points;
}

function strokeBolt(ctx, points, width, color) {
  ctx.strokeStyle = color;
  ctx.lineWidth = width;
  ctx.beginPath();
  ctx.moveTo(points[0][0], points[0][1]);
  for (let i = 1; i < points.length; i += 1) ctx.lineTo(points[i][0], points[i][1]);
  ctx.stroke();
}

export class GameRenderer {
  constructor(canvas, art) {
    this.canvas = canvas;
    this.ctx = canvas.getContext("2d");
    this.art = art;
    this.width = 0;
    this.height = 0;
    this.resize = this.resize.bind(this);
    this.observer = new ResizeObserver(this.resize);
    this.observer.observe(canvas);
    this.resize();
  }

  resize() {
    const rect = this.canvas.getBoundingClientRect();
    if (!rect.width || !rect.height) return;
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    this.canvas.width = Math.round(rect.width * dpr);
    this.canvas.height = Math.round(rect.height * dpr);
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    this.width = rect.width;
    this.height = rect.height;
  }

  getBounds() {
    const controlsReserve = Math.max(126, Math.min(182, this.height * 0.23));
    return {
      width: this.width,
      height: this.height,
      left: Math.max(22, this.width * 0.06),
      right: this.width - Math.max(22, this.width * 0.06),
      floorY: this.height - controlsReserve,
    };
  }

  draw(state, time) {
    const { ctx, width, height } = this;
    if (!width || !height) return;
    const realm = REALMS[state.realm];
    const id = String(state.realm + 1).padStart(2, "0");
    ctx.clearRect(0, 0, width, height);
    ctx.fillStyle = "#07101e";
    ctx.fillRect(0, 0, width, height);
    const backgroundKey = state.realmStage > 0 ? `REALM_BG_EXT_${id}` : `REALM_BG_${id}`;
    drawBackdrop(ctx, this.art.get(backgroundKey) || this.art.get(`REALM_BG_${id}`), width, height);

    const shade = ctx.createLinearGradient(0, 0, 0, height);
    shade.addColorStop(0, "rgba(3,8,22,.34)");
    shade.addColorStop(0.68, "rgba(3,8,22,.08)");
    shade.addColorStop(1, "rgba(2,5,16,.68)");
    ctx.fillStyle = shade;
    ctx.fillRect(0, 0, width, height);

    ctx.save();
    if (state.shake > 0) {
      const amount = Math.min(5, state.shake * 24);
      ctx.translate((Math.random() - 0.5) * amount, (Math.random() - 0.5) * amount);
    }
    drawFloor(ctx, this.art, realm.floor, state.floorY, width, Math.max(50, height * 0.085));
    this.drawWarnings(state, time);
    this.drawPickups(state, time);
    this.drawEnemyProjectiles(state);
    this.drawPlayerBullets(state, time);
    this.drawEnemies(state, time, id);
    this.drawBoss(state, time, id);
    this.drawEffects(state);
    this.drawRings(state);
    this.drawPlayer(state, time);
    this.drawParticles(state);
    ctx.restore();
    if (state.screenFlash > 0) {
      ctx.fillStyle = `rgba(210,245,255,${Math.min(0.72, state.screenFlash)})`;
      ctx.fillRect(0, 0, width, height);
    }
  }

  drawPlayer(state, time) {
    const player = state.player;
    const targetHeight = Math.max(48, Math.min(74, this.height * 0.102, this.width * 0.168));
    const skin = SKINS[state.selectedSkin || 0];
    let key = skin.key;
    let animation = "idle";
    let drawHeight = targetHeight;
    let animationTime = time + player.animSeed;
    if (state.phase === "gameover") {
      key = skin.finishKey;
      animation = "death";
      drawHeight *= 1.18;
    } else if (state.phase === "victory") {
      key = skin.finishKey;
      animation = "victory";
      drawHeight *= 1.2;
    } else if (state.phase === "camp") {
      key = skin.finishKey;
      animation = "camp_idle";
      drawHeight *= 1.14;
    } else if (player.castTimer > 0) {
      animation = player.castAnimation;
      drawHeight *= animation === "ultimate" ? 1.85 : 1.35;
      animationTime = player.castElapsed;
    } else if (player.dashTimer > 0) {
      key = skin.combatKey;
      animation = "dash";
      animationTime = ((0.18 - player.dashTimer) / 0.18) * 0.49;
    } else if (player.hurtFlash > 0) {
      key = skin.combatKey;
      animation = "hurt";
      animationTime = ((0.55 - player.hurtFlash) / 0.55) * 0.49;
    } else if (player.shotFlash > 0) {
      key = skin.combatKey;
      animation = Math.abs(player.vx) > 28 ? "fire_diagonal" : "fire_up";
      animationTime = ((0.14 - player.shotFlash) / 0.14) * 0.49;
    }
    const alpha = player.invulnerable > 0 && Math.floor(time * 18) % 2 ? 0.42 : 1;

    // Skin sheets only ship an idle loop (no run/jump frames), so movement is
    // animated on top of it: a running hop and lean, stretch while rising,
    // squash on landing, and a slow breath when standing still.
    const playing = state.phase === "wave" || state.phase === "boss";
    const airHeight = Math.max(0, state.floorY - player.y);
    const airborne = airHeight > 1;
    const speedRatio = Math.min(1, Math.abs(player.vx) / 265);
    let bob = 0;
    let lean = 0;
    let scaleX = 1;
    let scaleY = 1;
    if (playing && player.castTimer <= 0 && player.dashTimer <= 0) {
      if (airborne) {
        const stretch = Math.max(-0.6, Math.min(1, -player.vy / 600));
        scaleY = 1 + 0.08 * stretch;
        scaleX = 1 - 0.05 * stretch;
        lean = player.facing * 0.07 * speedRatio;
      } else if (speedRatio > 0.08) {
        const stride = time * (9 + 6 * speedRatio);
        bob = -Math.abs(Math.sin(stride)) * targetHeight * 0.07 * speedRatio;
        lean = player.facing * 0.1 * speedRatio;
        scaleY = 1 + Math.sin(stride * 2) * 0.035 * speedRatio;
        scaleX = 1 - (scaleY - 1) * 0.6;
        if (animation === "idle") animationTime = time * (1 + 1.4 * speedRatio) + player.animSeed;
      } else {
        scaleY = 1 + Math.sin(time * 2.4 + player.animSeed) * 0.012;
      }
      if (player.landTimer > 0) {
        const squash = player.landTimer / 0.14;
        scaleY *= 1 - 0.14 * squash;
        scaleX *= 1 + 0.1 * squash;
      }
    }

    // Contact shadow: shrinks and fades as the player rises off the floor.
    const shadowScale = Math.max(0.35, 1 - airHeight / 220);
    this.ctx.save();
    this.ctx.fillStyle = `rgba(0, 0, 0, ${0.32 * shadowScale})`;
    this.ctx.beginPath();
    this.ctx.ellipse(player.x, state.floorY + 1, targetHeight * 0.3 * shadowScale, targetHeight * 0.07 * shadowScale, 0, 0, Math.PI * 2);
    this.ctx.fill();
    this.ctx.restore();

    if (player.dashTimer > 0) {
      drawAnimatedCell(this.ctx, this.art, "DEFENSE_EFFECTS", "dash_afterimage", time,
        player.x - targetHeight * 0.9, player.y - targetHeight * 0.68, targetHeight * 1.8, targetHeight * 0.7, 0.7);
    }
    // Pivot at the feet so the lean and squash keep the character planted.
    this.ctx.save();
    this.ctx.translate(player.x, player.y + bob);
    this.ctx.rotate(lean);
    this.ctx.scale(scaleX, scaleY);
    drawAnchored(this.ctx, this.art, key, animation, animationTime, 0, 0, drawHeight, player.facing < 0, alpha);
    this.ctx.restore();
    if (state.power.shield > 0) this.drawShield(player.x, player.y - targetHeight * 0.48, targetHeight * 0.62, time);
  }

  drawShield(x, y, radius, time) {
    const gradient = this.ctx.createRadialGradient(x, y, radius * 0.55, x, y, radius);
    gradient.addColorStop(0, "rgba(49,232,255,0)");
    gradient.addColorStop(0.72, "rgba(49,232,255,.08)");
    gradient.addColorStop(0.92, "rgba(49,232,255,.52)");
    gradient.addColorStop(1, "rgba(205,68,255,.12)");
    this.ctx.save();
    this.ctx.globalCompositeOperation = "screen";
    this.ctx.fillStyle = gradient;
    this.ctx.beginPath();
    this.ctx.arc(x, y, radius * (1 + Math.sin(time * 5) * 0.025), 0, Math.PI * 2);
    this.ctx.fill();
    this.ctx.restore();
  }

  drawEnemies(state, time, id) {
    const realm = REALMS[state.realm];
    for (const enemy of state.enemies) {
      const isReinforcement = enemy.type >= 4;
      const isElite = enemy.type >= 2 && enemy.type < 4;
      const familyIndex = enemy.type % 2;
      const animation = isReinforcement
        ? `reinforce_${familyIndex === 0 ? "a" : "b"}_${enemy.attackTimer > 0 ? "attack" : "move"}`
        : isElite
          ? `elite_${familyIndex === 0 ? "a" : "b"}_${enemy.attackTimer > 0 ? "attack" : "move"}`
          : (enemy.attackTimer > 0 ? realm.enemyAnims[enemy.type][1] : realm.enemyAnims[enemy.type][0]);
      const sheetKey = isReinforcement ? `REALM_REINFORCEMENTS_${id}` : isElite ? `REALM_ELITES_${id}` : `REALM_ENEMIES_${id}`;
      const flash = Math.min(1, (enemy.hitFlash || 0) / 0.14);
      // Jitter the sprite briefly while it is flashing from a hit.
      const jitter = flash > 0 ? (Math.random() - 0.5) * enemy.size * 0.08 : 0;
      const anchorX = enemy.x + jitter;
      const anchorY = enemy.y + enemy.size * 0.42;
      drawAnchored(this.ctx, this.art, sheetKey, animation,
        time + enemy.animSeed, anchorX, anchorY, enemy.size, enemy.facing > 0, enemy.alpha ?? 1);
      if (flash > 0) this.drawHitFlash(sheetKey, animation, time + enemy.animSeed, anchorX, anchorY, enemy.size, enemy.facing > 0, flash);
      if (enemy.burn > 0) {
        drawAnimatedCell(this.ctx, this.art, "BUFF_EFFECTS", "fire_burn", time,
          enemy.x - enemy.size * 0.36, enemy.y - enemy.size * 0.35, enemy.size * 0.72, enemy.size * 0.72, 0.76);
      }
      if (enemy.slow > 0) {
        drawAnimatedCell(this.ctx, this.art, "BUFF_EFFECTS", "ice_shatter", time,
          enemy.x - enemy.size * 0.34, enemy.y - enemy.size * 0.32, enemy.size * 0.68, enemy.size * 0.68, 0.55);
      }
    }
  }

  drawBoss(state, time, id) {
    const boss = state.boss;
    if (!boss) return;
    const height = Math.max(220, Math.min(this.width * 0.92, this.height * 0.48));
    drawAnchored(this.ctx, this.art, `REALM_BOSS_${id}`, boss.animation,
      boss.animTime, boss.x, boss.y + height * 0.48, height, false, boss.alpha ?? 1);
    const flash = Math.min(1, (boss.hitFlash || 0) / 0.1);
    if (flash > 0) {
      this.drawHitFlash(`REALM_BOSS_${id}`, boss.animation, boss.animTime,
        boss.x, boss.y + height * 0.48, height, false, flash * 0.55);
    }
  }

  // Redraw the sprite additively so it flashes bright white on hit.
  drawHitFlash(key, animation, time, anchorX, anchorY, height, flip, strength) {
    this.ctx.save();
    this.ctx.globalCompositeOperation = "lighter";
    drawAnchored(this.ctx, this.art, key, animation, time, anchorX, anchorY, height, flip, strength * 0.85);
    this.ctx.restore();
  }

  drawRings(state) {
    this.ctx.save();
    this.ctx.globalCompositeOperation = "lighter";
    for (const ring of state.rings) {
      const progress = 1 - ring.life / ring.maxLife;
      this.ctx.globalAlpha = Math.max(0, 1 - progress);
      this.ctx.strokeStyle = ring.color;
      this.ctx.lineWidth = Math.max(1, 6 * (1 - progress));
      this.ctx.beginPath();
      this.ctx.arc(ring.x, ring.y, ring.radius * (0.25 + progress * 0.75), 0, Math.PI * 2);
      this.ctx.stroke();
    }
    this.ctx.restore();
  }

  drawPlayerBullets(state, time) {
    for (const bullet of state.bullets) {
      this.ctx.save();
      this.ctx.translate(bullet.x, bullet.y);
      this.ctx.rotate(Math.atan2(bullet.vy, bullet.vx) + Math.PI / 2);
      const length = bullet.radius * 4.2;
      drawAnimatedCell(this.ctx, this.art, "WEAPON_EFFECTS", "cyan_bolt", time,
        -bullet.radius * 1.45, -length * 0.5, bullet.radius * 2.9, length);
      this.ctx.restore();
    }
  }

  drawEnemyProjectiles(state) {
    for (const bullet of state.enemyBullets) {
      if (bullet.kind === "laser" || bullet.kind === "zone") continue;
      const active = bullet.age >= (bullet.delay || 0);
      const radius = bullet.radius || 8;
      const gradient = this.ctx.createRadialGradient(bullet.x, bullet.y, 1, bullet.x, bullet.y, radius * 1.8);
      gradient.addColorStop(0, active ? "#ffffff" : "#ffe48d");
      gradient.addColorStop(0.25, bullet.color || "#ff55cb");
      gradient.addColorStop(1, "rgba(255,45,177,0)");
      this.ctx.save();
      this.ctx.globalCompositeOperation = "lighter";
      this.ctx.fillStyle = gradient;
      this.ctx.beginPath();
      this.ctx.arc(bullet.x, bullet.y, radius * 1.8, 0, Math.PI * 2);
      this.ctx.fill();
      this.ctx.restore();
    }
  }

  drawWarnings(state, time) {
    for (const bullet of state.enemyBullets) {
      if (bullet.kind !== "laser" && bullet.kind !== "zone") continue;
      const active = bullet.age >= (bullet.delay || 0);
      if (bullet.lightning) {
        this.drawLightning(bullet, state.floorY, time, active);
        continue;
      }
      this.ctx.save();
      if (bullet.kind === "laser") {
        this.ctx.fillStyle = active ? "rgba(255,70,176,.7)" : "rgba(255,224,112,.15)";
        this.ctx.fillRect(bullet.x - bullet.width / 2, bullet.top || 0, bullet.width, state.floorY - (bullet.top || 0));
        this.ctx.strokeStyle = active ? "#ffffff" : "#ffd96a";
        this.ctx.lineWidth = active ? 3 : 2;
        this.ctx.setLineDash(active ? [] : [8, 8]);
        this.ctx.strokeRect(bullet.x - bullet.width / 2, bullet.top || 0, bullet.width, state.floorY - (bullet.top || 0));
      } else {
        this.ctx.fillStyle = active ? "rgba(255,75,89,.6)" : "rgba(255,207,87,.16)";
        this.ctx.fillRect(bullet.x - bullet.width / 2, state.floorY - 16, bullet.width, 18);
        this.ctx.strokeStyle = active ? "#fff" : "#ffd05a";
        this.ctx.lineWidth = 2;
        this.ctx.strokeRect(bullet.x - bullet.width / 2, state.floorY - 17, bullet.width, 18);
      }
      this.ctx.restore();
    }
  }

  // Lightning column: a glowing floor marker while charging, then jagged forked
  // bolts that re-crackle every frame tick while the strike is active.
  drawLightning(bullet, floorY, time, active) {
    const ctx = this.ctx;
    const top = bullet.top || 0;
    const half = bullet.width / 2;
    const tick = Math.floor(time * 24);
    ctx.save();
    ctx.globalCompositeOperation = "lighter";
    ctx.lineJoin = "round";
    ctx.lineCap = "round";

    if (!active) {
      const charge = Math.min(1, bullet.age / Math.max(0.01, bullet.delay));
      const pulse = 0.5 + Math.sin(time * 26) * 0.5;
      ctx.fillStyle = `rgba(206,85,255,${0.05 + charge * 0.08})`;
      ctx.fillRect(bullet.x - half, top, bullet.width, floorY - top);
      const marker = ctx.createRadialGradient(bullet.x, floorY, 2, bullet.x, floorY, half + 18);
      marker.addColorStop(0, `rgba(235,220,255,${0.35 + charge * 0.4})`);
      marker.addColorStop(0.45, `rgba(206,85,255,${0.2 + pulse * 0.25 * charge})`);
      marker.addColorStop(1, "rgba(206,85,255,0)");
      ctx.fillStyle = marker;
      ctx.beginPath();
      ctx.ellipse(bullet.x, floorY - 4, half + 18, 16, 0, 0, Math.PI * 2);
      ctx.fill();
      // Small crackles at the source hint where the bolt will fall.
      if (charge > 0.35 && tick % 3 === 0) {
        const rand = seededRandom(tick * 7919 + Math.round(bullet.x * 13));
        const crackle = boltPoints(rand, bullet.x, top, top + 40 + charge * 70, half * 0.8 + 10);
        strokeBolt(ctx, crackle, 3, `rgba(206,85,255,${0.35 * charge})`);
        strokeBolt(ctx, crackle, 1.2, `rgba(220,250,255,${0.6 * charge})`);
      }
      ctx.restore();
      return;
    }

    const elapsed = bullet.age - bullet.delay;
    const fadeStart = bullet.activeDuration * 0.6;
    const alpha = elapsed < fadeStart ? 1 : Math.max(0, 1 - (elapsed - fadeStart) / (bullet.activeDuration - fadeStart));

    // Initial white flash down the whole column.
    if (elapsed < 0.1) {
      const strength = (0.1 - elapsed) * 6;
      const glowHalf = half + 24;
      const flash = ctx.createLinearGradient(bullet.x - glowHalf, 0, bullet.x + glowHalf, 0);
      flash.addColorStop(0, "rgba(139,118,255,0)");
      flash.addColorStop(0.5, `rgba(235,245,255,${strength})`);
      flash.addColorStop(1, "rgba(139,118,255,0)");
      ctx.fillStyle = flash;
      ctx.fillRect(bullet.x - glowHalf, top, glowHalf * 2, floorY - top);
    }

    const bolts = Math.max(2, Math.min(6, Math.round(bullet.width / 22)));
    const rand = seededRandom(tick * 7919 + Math.round(bullet.x * 13));
    for (let i = 0; i < bolts; i += 1) {
      const center = bullet.x + (bolts === 1 ? 0 : (i / (bolts - 1) - 0.5) * bullet.width * 0.7);
      const points = boltPoints(rand, center, top, floorY, Math.max(18, half * 0.9));
      strokeBolt(ctx, points, 10, `rgba(139,118,255,${0.28 * alpha})`);
      strokeBolt(ctx, points, 4.5, `rgba(41,230,255,${0.65 * alpha})`);
      strokeBolt(ctx, points, 1.8, `rgba(255,255,255,${0.95 * alpha})`);
      // Two short forks branching off each bolt.
      for (let f = 0; f < 2; f += 1) {
        const from = points[1 + Math.floor(rand() * (points.length - 2))];
        const dir = rand() < 0.5 ? -1 : 1;
        const fork = [from];
        for (let s = 1; s <= 3; s += 1) {
          fork.push([from[0] + dir * s * (10 + rand() * 12), from[1] + s * (14 + rand() * 10)]);
        }
        strokeBolt(ctx, fork, 4, `rgba(206,85,255,${0.4 * alpha})`);
        strokeBolt(ctx, fork, 1.2, `rgba(230,250,255,${0.85 * alpha})`);
      }
    }

    // Impact glow where the strike hits the floor.
    const flicker = 0.75 + rand() * 0.25;
    const impact = ctx.createRadialGradient(bullet.x, floorY, 2, bullet.x, floorY, half + 34);
    impact.addColorStop(0, `rgba(255,255,255,${0.9 * alpha * flicker})`);
    impact.addColorStop(0.35, `rgba(41,230,255,${0.55 * alpha * flicker})`);
    impact.addColorStop(1, "rgba(139,118,255,0)");
    ctx.fillStyle = impact;
    ctx.beginPath();
    ctx.ellipse(bullet.x, floorY - 6, half + 34, 26, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  }

  drawPickups(state, time) {
    for (const pickup of state.pickups) {
      const bob = Math.sin(time * 6 + pickup.animSeed) * 4;
      if (pickup.kind === "coin") {
        const entry = this.art.get("COIN_SHEET");
        const frame = findFrame(entry, `coin_${1 + Math.floor(time * 10 + pickup.animSeed) % 5}`);
        drawFrameInCell(this.ctx, entry, frame, pickup.x - pickup.size / 2,
          pickup.y - pickup.size / 2 + bob, pickup.size, pickup.size);
      } else {
        drawAtlas(this.ctx, this.art, "UI_ICON_ATLAS", pickup.icon,
          pickup.x - pickup.size / 2, pickup.y - pickup.size / 2 + bob, pickup.size, pickup.size);
      }
    }
  }

  drawEffects(state) {
    for (const effect of state.effects) {
      const progress = Math.min(1, effect.age / effect.duration);
      const alpha = Math.max(0, 1 - progress);
      // Play the 5-frame sheet once over the effect's lifetime, from frame 0.
      drawAnimatedCell(this.ctx, this.art, effect.key, effect.animation,
        Math.min(0.49, progress * 0.5), effect.x - effect.size / 2, effect.y - effect.size / 2,
        effect.size, effect.size, alpha);
    }
  }

  drawParticles(state) {
    this.ctx.save();
    this.ctx.globalCompositeOperation = "lighter";
    for (const particle of state.particles) {
      this.ctx.globalAlpha = Math.max(0, particle.life / particle.maxLife);
      this.ctx.fillStyle = particle.color;
      this.ctx.fillRect(particle.x - particle.size / 2, particle.y - particle.size / 2, particle.size, particle.size);
    }
    this.ctx.restore();
  }

  destroy() {
    this.observer.disconnect();
  }
}
