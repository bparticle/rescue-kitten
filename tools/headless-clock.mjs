// Cache Wasmoon's Lua handles so meter calls don't grow the host's reference table.
export function installHeadlessClock(badge, tick) {
  const lua = badge.engine.global;
  const invoke = lua.get('__call');
  const timers = lua.get('__timers');
  const instructions = lua.get('__used');
  badge.call = invoke;
  badge.lastInstructions = instructions;
  badge.frames = async (count, interval = tick) => {
    for (let frame = 0; frame < count && !badge.exited; frame++) {
      badge.ms += interval;
      timers();
      badge.call('on_tick', interval);
    }
    return badge;
  };
}
