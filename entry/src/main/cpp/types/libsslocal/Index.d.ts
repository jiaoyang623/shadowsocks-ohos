export const start: (configJson: string) => number;
export const startTunFd: (configJson: string, tunFd: number) => number;
export const setStatAddress: (addr: string) => number;
export const stop: () => number;
export const isRunning: () => boolean;
export const lastError: () => string | null;
/**
 * Recent core log records, newest last, newline separated, each prefixed with
 * a monotonically increasing sequence number. Null until the core logs
 * anything. The core's diagnostics are otherwise discarded — there is no
 * console on a device — so this is the only way to see why a tunnel that came
 * up is failing to carry traffic.
 */
export const recentLogs: () => string | null;
export const version: () => string;
