const KEY_ACTIONS = new Map([
  ["ArrowLeft", "left"], ["KeyA", "left"], ["ArrowRight", "right"], ["KeyD", "right"],
  ["Space", "jump"], ["ArrowUp", "jump"], ["KeyW", "jump"],
  ["ShiftLeft", "dash"], ["ShiftRight", "dash"], ["KeyK", "dash"],
  ["KeyJ", "fire"],
  ["KeyU", "skill1"], ["KeyI", "skill2"], ["KeyO", "ultimate"],
]);

// Some Android key events arrive without event.code, so fall back to event.key.
const KEY_FALLBACK = new Map([
  ["arrowleft", "left"], ["a", "left"], ["arrowright", "right"], ["d", "right"],
  [" ", "jump"], ["arrowup", "jump"], ["w", "jump"],
  ["shift", "dash"], ["k", "dash"],
  ["j", "fire"],
  ["u", "skill1"], ["i", "skill2"], ["o", "ultimate"],
]);

const actionFor = (event) => KEY_ACTIONS.get(event.code) ?? KEY_FALLBACK.get((event.key || "").toLowerCase());

export function createInput(root, canvas, onEngage) {
  const down = new Set();
  const pressed = new Set();
  let engaged = false;

  const engage = () => {
    if (engaged) return;
    engaged = true;
    onEngage?.();
  };

  const setDown = (action) => {
    engage();
    if (!down.has(action)) pressed.add(action);
    down.add(action);
  };

  const setUp = (action) => down.delete(action);

  const keyDown = (event) => {
    const action = actionFor(event);
    if (!action) return;
    event.preventDefault();
    setDown(action);
  };
  const keyUp = (event) => {
    const action = actionFor(event);
    if (!action) return;
    event.preventDefault();
    setUp(action);
  };

  window.addEventListener("keydown", keyDown);
  window.addEventListener("keyup", keyUp);

  const buttonCleanups = [];
  root.querySelectorAll("[data-action]").forEach((button) => {
    const action = button.dataset.action;
    const start = (event) => {
      event.preventDefault();
      button.setPointerCapture?.(event.pointerId);
      button.classList.add("is-held");
      setDown(action);
    };
    const end = (event) => {
      event.preventDefault();
      button.classList.remove("is-held");
      setUp(action);
    };
    button.addEventListener("pointerdown", start);
    button.addEventListener("pointerup", end);
    button.addEventListener("pointercancel", end);
    button.addEventListener("lostpointercapture", end);
    buttonCleanups.push(() => {
      button.removeEventListener("pointerdown", start);
      button.removeEventListener("pointerup", end);
      button.removeEventListener("pointercancel", end);
      button.removeEventListener("lostpointercapture", end);
    });
  });

  // Virtual joystick: horizontal axis drives movement analog (-1..1).
  const JOY_DEADZONE = 0.18;
  const joystick = root.querySelector("[data-ui='joystick']");
  const knob = joystick?.querySelector(".joystick-knob");
  let joyPointer = null;
  let joyX = 0;

  const resetJoystick = () => {
    joyPointer = null;
    joyX = 0;
    joystick?.classList.remove("is-held");
    knob?.style.setProperty("--jx", "0px");
    knob?.style.setProperty("--jy", "0px");
  };

  const joyTrack = (event) => {
    const rect = joystick.getBoundingClientRect();
    const radius = rect.width / 2;
    const reach = radius * 0.56;
    let dx = event.clientX - (rect.left + radius);
    let dy = event.clientY - (rect.top + radius);
    const distance = Math.hypot(dx, dy);
    if (distance > reach) {
      dx *= reach / distance;
      dy *= reach / distance;
    }
    knob.style.setProperty("--jx", `${dx}px`);
    knob.style.setProperty("--jy", `${dy}px`);
    const x = dx / reach;
    joyX = Math.abs(x) < JOY_DEADZONE ? 0 : Math.sign(x) * (Math.abs(x) - JOY_DEADZONE) / (1 - JOY_DEADZONE);
  };

  const joyStart = (event) => {
    if (joyPointer !== null) return;
    event.preventDefault();
    joyPointer = event.pointerId;
    joystick.setPointerCapture?.(event.pointerId);
    joystick.classList.add("is-held");
    engage();
    joyTrack(event);
  };
  const joyMove = (event) => {
    if (event.pointerId !== joyPointer) return;
    event.preventDefault();
    joyTrack(event);
  };
  const joyEnd = (event) => {
    if (event.pointerId !== joyPointer) return;
    resetJoystick();
  };

  // Releasing keys while the window is unfocused never fires keyup, so drop them.
  const releaseAll = () => {
    down.clear();
    pressed.clear();
    resetJoystick();
  };
  window.addEventListener("blur", releaseAll);

  if (joystick) {
    joystick.addEventListener("pointerdown", joyStart);
    joystick.addEventListener("pointermove", joyMove);
    joystick.addEventListener("pointerup", joyEnd);
    joystick.addEventListener("pointercancel", joyEnd);
    joystick.addEventListener("lostpointercapture", joyEnd);
  }

  const canvasEngage = (event) => {
    if (event.target.closest?.("button, [role='button'], .overlay")) return;
    engage();
  };
  canvas.addEventListener("pointerdown", canvasEngage);

  return {
    isDown: (action) => down.has(action),
    moveAxis() {
      if (joyX) return joyX;
      return (down.has("right") ? 1 : 0) - (down.has("left") ? 1 : 0);
    },
    consume(action) {
      const had = pressed.has(action);
      pressed.delete(action);
      return had;
    },
    clear: releaseAll,
    destroy() {
      window.removeEventListener("keydown", keyDown);
      window.removeEventListener("keyup", keyUp);
      window.removeEventListener("blur", releaseAll);
      canvas.removeEventListener("pointerdown", canvasEngage);
      if (joystick) {
        joystick.removeEventListener("pointerdown", joyStart);
        joystick.removeEventListener("pointermove", joyMove);
        joystick.removeEventListener("pointerup", joyEnd);
        joystick.removeEventListener("pointercancel", joyEnd);
        joystick.removeEventListener("lostpointercapture", joyEnd);
      }
      buttonCleanups.forEach((cleanup) => cleanup());
    },
  };
}
