/*******************************************************************************
 *                                                                             *
 *  Copyright (C) 2026 by Max Lv <max.c.lv@gmail.com>                          *
 *                                                                             *
 *  This program is free software: you can redistribute it and/or modify       *
 *  it under the terms of the GNU General Public License as published by       *
 *  the Free Software Foundation, either version 3 of the License, or          *
 *  (at your option) any later version.                                        *
 *                                                                             *
 *  This program is distributed in the hope that it will be useful,            *
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of             *
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the              *
 *  GNU General Public License for more details.                               *
 *                                                                             *
 *  You should have received a copy of the GNU General Public License          *
 *  along with this program. If not, see <http://www.gnu.org/licenses/>.       *
 *                                                                             *
 *******************************************************************************/

/**
 * Pure decisions for the main shell: the drawer, the service button, the
 * progress ring, the stats bar and the failure text.
 *
 * The module imports Diagnostics and TrafficStats only. It calls no kit API
 * and does no I/O. The host runner loads it from test-arkts-host.sh.
 */

import {
  PHASE_CONNECTED, PHASE_CONNECTING, PHASE_FAILED, PHASE_IDLE, PHASE_PROBE_FAILED,
  PHASE_STOPPING, PHASE_VERIFYING,
} from './Diagnostics';
import { formatBytes, formatRate } from './TrafficStats';

/* ---- drawer destinations, in the Android menu order ---- */
export const DRAWER_PROFILES: string = 'profiles';
export const DRAWER_SUBSCRIPTIONS: string = 'subscriptions';
export const DRAWER_CUSTOM_RULES: string = 'customRules';
export const DRAWER_SETTINGS: string = 'globalSettings';
export const DRAWER_FAQ: string = 'faq';
export const DRAWER_ABOUT: string = 'about';

/** One row of the navigation drawer. */
export interface DrawerEntry {
  /** Destination id. One of the DRAWER_* constants. */
  id: string;
  /** True when the row can show a check mark and can become selected. */
  checkable: boolean;
}

/** The drawer rows, in display order. */
export const DRAWER_ENTRIES: DrawerEntry[] = [
  { id: DRAWER_PROFILES, checkable: true },
  { id: DRAWER_SUBSCRIPTIONS, checkable: true },
  { id: DRAWER_CUSTOM_RULES, checkable: true },
  { id: DRAWER_SETTINGS, checkable: true },
  { id: DRAWER_FAQ, checkable: false },
  { id: DRAWER_ABOUT, checkable: true },
];

/**
 * Whether the drawer shows a check mark for the id. True for a checkable
 * entry. False for FAQ and for an unknown id.
 */
export function isCheckableDrawerItem(id: string): boolean {
  for (let i = 0; i < DRAWER_ENTRIES.length; i++) {
    if (DRAWER_ENTRIES[i].id === id) {
      return DRAWER_ENTRIES[i].checkable;
    }
  }
  return false;
}

/** The checked destination after the page opens or returns. */
export function defaultDrawerSelection(): string {
  return DRAWER_PROFILES;
}

/**
 * The checked destination after a selection. A checkable item becomes
 * selected. FAQ and an unknown id keep the current item.
 */
export function drawerSelectionAfter(current: string, selected: string): string {
  if (isCheckableDrawerItem(selected)) {
    return selected;
  }
  return current;
}

/**
 * Whether a selection closes the drawer. Every checkable item closes it,
 * including the item that is already checked. FAQ keeps it open.
 */
export function drawerClosesAfter(current: string, selected: string): boolean {
  return isCheckableDrawerItem(selected);
}

/**
 * Whether a selection opens another page. FAQ does not. The checked item
 * does not. Another checkable item does.
 */
export function drawerNavigatesAfter(current: string, selected: string): boolean {
  if (!isCheckableDrawerItem(selected)) {
    return false;
  }
  return selected !== current;
}

/* ---- service button timing ---- */
/** Delay before the connecting ring appears. */
export const RING_DELAY_MS: number = 1200;
/** Duration of the connected ring fill. */
export const RING_FILL_MS: number = 400;
/** How long the snackbar stays on the page. */
export const SNACKBAR_DURATION_MS: number = 4000;
/** Gap between the service button and the bottom edge. */
export const FAB_MARGIN_VP: number = 16;

/**
 * Whether the phase can stop the service. True for connecting, verifying,
 * connected and probe-failed. False for idle, failed and stopping.
 */
export function canStop(phase: string): boolean {
  return phase === PHASE_CONNECTING || phase === PHASE_VERIFYING ||
    phase === PHASE_CONNECTED || phase === PHASE_PROBE_FAILED;
}

/** Whether the phase can start the service. True for idle and failed. */
export function canStart(phase: string): boolean {
  return phase === PHASE_IDLE || phase === PHASE_FAILED;
}

/**
 * Whether the service button accepts a tap. False during the teardown
 * window, when neither start nor stop is valid.
 */
export function serviceButtonEnabled(phase: string): boolean {
  return canStop(phase) || canStart(phase);
}

/** Whether the button uses the checked fill. True while the tunnel is up. */
export function serviceButtonChecked(phase: string): boolean {
  return phase === PHASE_VERIFYING || phase === PHASE_CONNECTED ||
    phase === PHASE_PROBE_FAILED;
}

/**
 * The string key of the button label. Stop when the phase can stop. Connect
 * for every other phase.
 */
export function serviceButtonLabelKey(phase: string): string {
  return canStop(phase) ? 'index_disconnect' : 'index_connect';
}

/**
 * The glyph token of the button: connect, stop, check or wait.
 * An unknown phase returns connect.
 */
export function serviceButtonGlyph(phase: string): string {
  if (phase === PHASE_IDLE || phase === PHASE_FAILED) {
    return 'connect';
  }
  if (phase === PHASE_CONNECTING || phase === PHASE_VERIFYING) {
    return 'stop';
  }
  if (phase === PHASE_CONNECTED || phase === PHASE_PROBE_FAILED) {
    return 'check';
  }
  if (phase === PHASE_STOPPING) {
    return 'wait';
  }
  return 'connect';
}

/**
 * The action of a button tap: stop, start or none. Stopping and unknown
 * phases do nothing.
 */
export function serviceButtonTap(phase: string): string {
  if (phase === PHASE_STOPPING) {
    return 'none';
  }
  if (canStop(phase)) {
    return 'stop';
  }
  if (canStart(phase)) {
    return 'start';
  }
  return 'none';
}

/**
 * The action of Ctrl+G: stop when the phase can stop, start otherwise. The
 * page rejects a start during stopping with a phase guard.
 */
export function keyboardToggle(phase: string): string {
  return canStop(phase) ? 'stop' : 'start';
}

/**
 * The ring mode: indeterminate after the delay while connecting, hidden
 * otherwise.
 */
export function ringState(phase: string, connectingForMs: number): string {
  if (phase === PHASE_CONNECTING && connectingForMs >= RING_DELAY_MS) {
    return 'indeterminate';
  }
  return 'hidden';
}

/* ---- connection test states ---- */
export const TEST_IDLE: string = 'idle';
export const TEST_TESTING: string = 'testing';
export const TEST_SUCCESS: string = 'success';
export const TEST_ERROR: string = 'error';

/* ---- connection test result kinds ---- */
export const TEST_KIND_SUCCESS: string = 'success';
export const TEST_KIND_HTTP: string = 'http';
export const TEST_KIND_NETWORK: string = 'network';
export const TEST_KIND_TUNNEL: string = 'tunnel';

/** One classified probe result. */
export interface TestResult {
  /** One of the TEST_KIND_* constants. */
  kind: string;
  /** HTTP status, 0 when no response arrived. */
  code: number;
  /** Failure text. Empty for a success. */
  reason: string;
}

/**
 * Classifies one probe outcome. A 204 response is a success. A 200 response
 * with no body is a success. Any other code above zero is an HTTP error. A
 * zero code is a network error.
 *
 * `ok` is not read. It is true exactly for a 2xx response, so the code and
 * the body length carry every decision.
 */
export function classifyTest(ok: boolean, httpCode: number, bodyLength: number,
  reason: string): TestResult {
  if (httpCode === 204 || (httpCode === 200 && bodyLength === 0)) {
    const success: TestResult = { kind: TEST_KIND_SUCCESS, code: httpCode, reason: '' };
    return success;
  }
  if (httpCode > 0) {
    const http: TestResult = { kind: TEST_KIND_HTTP, code: httpCode, reason: reason };
    return http;
  }
  const network: TestResult = { kind: TEST_KIND_NETWORK, code: 0, reason: reason };
  return network;
}

/**
 * Replaces a success with a tunnel error when the traffic did not cross the
 * tunnel. An HTTP or network result stays the same.
 */
export function applyTunnelVerdict(result: TestResult, tunnelOk: boolean,
  tunnelReason: string): TestResult {
  if (result.kind !== TEST_KIND_SUCCESS || tunnelOk) {
    return result;
  }
  const tunnelled: TestResult = {
    kind: TEST_KIND_TUNNEL,
    code: result.code,
    reason: tunnelReason,
  };
  return tunnelled;
}

/**
 * The test status after a phase change. A visible stats bar keeps the
 * current status. Every other phase resets it to idle.
 */
export function testStatusAfterConnection(current: string, phase: string): string {
  if (statsVisible(phase)) {
    return current;
  }
  return TEST_IDLE;
}

/**
 * Whether the stats bar belongs to the phase. True while the tunnel is up:
 * connected, the first probe still in flight (`verifying`), or up with the
 * probe failed. Android shows its bar as soon as the service reports
 * connected, so the bar must not wait for the probe verdict.
 */
export function statsVisible(phase: string): boolean {
  return phase === PHASE_VERIFYING || phase === PHASE_CONNECTED ||
    phase === PHASE_PROBE_FAILED;
}

/**
 * The status line token for the phase and the test status. The page maps the
 * token to a string.
 */
export function statsStatusKind(phase: string, test: string): string {
  if (phase === PHASE_CONNECTING) {
    return 'connecting';
  }
  if (phase === PHASE_STOPPING) {
    return 'shutting-down';
  }
  if (phase === PHASE_CONNECTED || phase === PHASE_VERIFYING) {
    if (test === TEST_TESTING) {
      return 'testing';
    }
    if (test === TEST_SUCCESS) {
      return 'success';
    }
    if (test === TEST_ERROR) {
      return 'error';
    }
    return 'connected-tap';
  }
  if (phase === PHASE_PROBE_FAILED) {
    if (test === TEST_TESTING) {
      return 'testing';
    }
    if (test === TEST_SUCCESS) {
      return 'success';
    }
    if (test === TEST_ERROR) {
      return 'error';
    }
    return 'probe-failed';
  }
  return 'not-connected';
}

/**
 * The hidden state after a scroll delta. A positive delta hides the bar. A
 * negative delta shows it. A zero delta keeps the current state.
 */
export function statsHiddenAfterScroll(hidden: boolean, delta: number): boolean {
  if (delta > 0) {
    return true;
  }
  if (delta < 0) {
    return false;
  }
  return hidden;
}

/**
 * Whether the counters must reset. True when the previous phase shows the
 * stats bar and the next phase does not.
 */
export function statsResetRequired(previous: string, next: string): boolean {
  return statsVisible(previous) && !statsVisible(next);
}

/** The action of a stats bar tap: test or none. */
export function statsTapAction(phase: string): string {
  return statsVisible(phase) ? 'test' : 'none';
}

/** The four strings of the stats bar: two totals and two rates. */
export interface StatsText {
  /** Upload total, with a leading triangle. */
  txTotal: string;
  /** Upload rate, per second. */
  txRate: string;
  /** Download total, with a leading triangle. */
  rxTotal: string;
  /** Download rate, per second. */
  rxRate: string;
}

/** The stats bar text for the two totals and the two rates. */
export function formatStats(tx: number, rx: number, txRate: number,
  rxRate: number): StatsText {
  const text: StatsText = {
    txTotal: `▲ ${formatBytes(tx)}`,
    txRate: formatRate(txRate),
    rxTotal: `▼ ${formatBytes(rx)}`,
    rxRate: formatRate(rxRate),
  };
  return text;
}

/** The failure text: the reason, then the detail after a colon. */
export function failureText(reason: string, detail: string): string {
  const trimmedReason: string = reason.trim();
  const trimmedDetail: string = detail.trim();
  if (trimmedReason.length > 0 && trimmedDetail.length > 0) {
    return `${trimmedReason}: ${trimmedDetail}`;
  }
  if (trimmedReason.length > 0) {
    return trimmedReason;
  }
  return trimmedDetail;
}

/**
 * Whether the stored mode differs from the mode that runs. An empty running
 * mode means nothing runs, so the mode did not change.
 */
export function modeChanged(runningMode: string, settingsMode: string): boolean {
  return runningMode.length > 0 && runningMode !== settingsMode;
}

/** The FAQ page that the drawer opens in a browser. */
export const FAQ_URL: string =
  'https://github.com/shadowsocks/shadowsocks-android/blob/master/.github/faq.md';
