export function stepPlayer(player, input, dt, bounds, balance, power, realmIndex) {
  const onIce = realmIndex === 7;
  const inWater = realmIndex === 4;
  const inWind = realmIndex === 5;
  const speedBoost = power.boots > 0 ? 1.35 : 1;
  const maxSpeed = balance.playerSpeed * speedBoost;
  // -1..1; analog from the joystick, digital from the keyboard.
  const direction = input.moveAxis();
  const accel = onIce ? maxSpeed * 4 : maxSpeed * 10;
  const friction = onIce ? 0.975 : 0.82;

  if (direction) {
    player.vx += direction * accel * dt;
    player.facing = Math.sign(direction);
  } else {
    player.vx *= friction ** (dt * 60);
  }
  if (inWind) player.vx += Math.sin(player.worldTime * 0.8) * 48 * dt;
  const speedCap = direction ? maxSpeed * Math.abs(direction) : maxSpeed;
  player.vx = Math.max(-speedCap, Math.min(speedCap, player.vx));

  let jumped = false;
  if (input.consume("jump") && player.jumps < 2) {
    player.vy = -balance.jumpPower * (inWater ? 1.12 : 1) * (power.boots > 0 ? 1.18 : 1);
    player.jumps += 1;
    jumped = true;
  }

  let dashed = false;
  if (input.consume("dash") && player.dashCooldown <= 0) {
    const dashDirection = direction || player.facing || 1;
    player.dashTimer = 0.18;
    player.dashCooldown = 1.35;
    player.vx = dashDirection * maxSpeed * 2.45;
    player.invulnerable = Math.max(player.invulnerable, 0.24);
    dashed = true;
  }

  if (player.dashTimer > 0) {
    player.dashTimer -= dt;
    player.vy *= 0.82;
  } else {
    player.vy += balance.gravity * (inWater ? 0.72 : 1) * dt;
  }

  player.x += player.vx * dt;
  player.y += player.vy * dt;
  player.x = Math.max(bounds.left, Math.min(bounds.right, player.x));
  let landed = false;
  if (player.y >= bounds.floorY) {
    landed = player.vy > 80;
    player.y = bounds.floorY;
    player.vy = 0;
    player.jumps = 0;
  }
  player.dashCooldown = Math.max(0, player.dashCooldown - dt);
  player.invulnerable = Math.max(0, player.invulnerable - dt);
  return { jumped, dashed, landed };
}

export function circleHit(a, b, padding = 0) {
  const dx = a.x - b.x;
  const dy = a.y - b.y;
  const radius = (a.radius || a.size * 0.35 || 8) + (b.radius || b.size * 0.35 || 8) + padding;
  return dx * dx + dy * dy <= radius * radius;
}

export function pointInVerticalZone(player, zone, floorY) {
  return player.x > zone.x - zone.width / 2 && player.x < zone.x + zone.width / 2 && player.y > (zone.top || 0) && player.y <= floorY + 8;
}
