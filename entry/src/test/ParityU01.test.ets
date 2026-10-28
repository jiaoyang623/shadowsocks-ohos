import { describe, expect, it } from '@ohos/hypium';
import {
  MODE_PROXY, MODE_VPN, PHASE_CONNECTED, PHASE_CONNECTING, PHASE_FAILED, PHASE_IDLE,
  PHASE_PROBE_FAILED, PHASE_STOPPING, PHASE_VERIFYING,
} from '../main/ets/model/Diagnostics';
import {
  DRAWER_ABOUT, DRAWER_CUSTOM_RULES, DRAWER_ENTRIES, DRAWER_FAQ, DRAWER_PROFILES,
  DRAWER_SETTINGS, DRAWER_SUBSCRIPTIONS, FAB_MARGIN_VP, FAQ_URL, RING_DELAY_MS, RING_FILL_MS,
  SNACKBAR_DURATION_MS, StatsText, TEST_ERROR, TEST_IDLE, TEST_KIND_HTTP, TEST_KIND_NETWORK,
  TEST_KIND_SUCCESS, TEST_KIND_TUNNEL, TEST_SUCCESS, TEST_TESTING, TestResult, applyTunnelVerdict,
  canStart, canStop, classifyTest, defaultDrawerSelection, drawerClosesAfter, drawerNavigatesAfter,
  drawerSelectionAfter, failureText, formatStats, isCheckableDrawerItem, keyboardToggle,
  modeChanged, ringState, serviceButtonChecked, serviceButtonEnabled, serviceButtonGlyph,
  serviceButtonLabelKey, serviceButtonTap, statsHiddenAfterScroll, statsResetRequired,
  statsStatusKind, statsTapAction, statsVisible, testStatusAfterConnection,
} from '../main/ets/model/MainShell';
import { formatBytes, formatRate, liveCounters, TrafficStats } from '../main/ets/model/TrafficStats';

/** Every phase the service button and the stats bar can receive. */
const PHASES: string[] = [
  PHASE_IDLE, PHASE_CONNECTING, PHASE_VERIFYING, PHASE_CONNECTED,
  PHASE_PROBE_FAILED, PHASE_STOPPING, PHASE_FAILED,
];

/** The phases where the tunnel is up, so the service can stop. */
const UP_PHASES: string[] = [
  PHASE_CONNECTING, PHASE_VERIFYING, PHASE_CONNECTED, PHASE_PROBE_FAILED,
];

/** The drawer rows that can show a check mark. */
const CHECKABLE: string[] = [
  DRAWER_PROFILES, DRAWER_SUBSCRIPTIONS, DRAWER_CUSTOM_RULES, DRAWER_SETTINGS, DRAWER_ABOUT,
];

export default function parityU01Test() {
  describe('ParityU01Test', () => {
    it('U01#drawer-has-six-entries', 0, () => {
      expect(DRAWER_ENTRIES.length).assertEqual(6);
      const ids: string[] = [];
      for (let i = 0; i < DRAWER_ENTRIES.length; i++) {
        ids.push(DRAWER_ENTRIES[i].id);
      }
      expect(ids).assertEqual([
        DRAWER_PROFILES, DRAWER_SUBSCRIPTIONS, DRAWER_CUSTOM_RULES,
        DRAWER_SETTINGS, DRAWER_FAQ, DRAWER_ABOUT,
      ]);
      // The ids match the Android menu ids in navigation_main.xml.
      expect(ids).assertEqual([
        'profiles', 'subscriptions', 'customRules', 'globalSettings', 'faq', 'about',
      ]);
      // Each row reports its own checkability, and FAQ is the only plain row.
      for (let i = 0; i < DRAWER_ENTRIES.length; i++) {
        expect(isCheckableDrawerItem(DRAWER_ENTRIES[i].id))
          .assertEqual(DRAWER_ENTRIES[i].checkable);
      }
      expect(DRAWER_ENTRIES[4].id).assertEqual(DRAWER_FAQ);
      expect(DRAWER_ENTRIES[4].checkable).assertFalse();
      expect(isCheckableDrawerItem('nope')).assertFalse();
    });

    it('U01#drawer-keeps-one-checked-item', 0, () => {
      // A checkable row becomes the checked one from any current selection.
      for (let i = 0; i < CHECKABLE.length; i++) {
        expect(drawerSelectionAfter(DRAWER_PROFILES, CHECKABLE[i])).assertEqual(CHECKABLE[i]);
      }
      const afterSettings: string = drawerSelectionAfter(DRAWER_PROFILES, DRAWER_SETTINGS);
      expect(afterSettings).assertEqual(DRAWER_SETTINGS);
      // The next selection replaces the old one, so one row stays checked.
      expect(drawerSelectionAfter(afterSettings, DRAWER_PROFILES)).assertEqual(DRAWER_PROFILES);
      expect(drawerSelectionAfter(afterSettings, afterSettings)).assertEqual(afterSettings);
      // An unknown id leaves the check where it was.
      expect(drawerSelectionAfter(afterSettings, 'nope')).assertEqual(afterSettings);
    });

    it('U01#drawer-same-item-only-closes', 0, () => {
      // The checked row closes the drawer and opens no other page.
      expect(drawerClosesAfter(DRAWER_PROFILES, DRAWER_PROFILES)).assertTrue();
      expect(drawerNavigatesAfter(DRAWER_PROFILES, DRAWER_PROFILES)).assertFalse();
      expect(drawerClosesAfter(DRAWER_SETTINGS, DRAWER_SETTINGS)).assertTrue();
      expect(drawerNavigatesAfter(DRAWER_SETTINGS, DRAWER_SETTINGS)).assertFalse();
      // Every checkable row closes the drawer. Only another row navigates.
      for (let i = 0; i < CHECKABLE.length; i++) {
        expect(drawerClosesAfter(DRAWER_SETTINGS, CHECKABLE[i])).assertTrue();
        expect(drawerNavigatesAfter(DRAWER_SETTINGS, CHECKABLE[i]))
          .assertEqual(CHECKABLE[i] !== DRAWER_SETTINGS);
      }
    });

    it('U01#drawer-faq-keeps-open-and-checks-nothing', 0, () => {
      for (let i = 0; i < CHECKABLE.length; i++) {
        expect(drawerClosesAfter(CHECKABLE[i], DRAWER_FAQ)).assertFalse();
        expect(drawerNavigatesAfter(CHECKABLE[i], DRAWER_FAQ)).assertFalse();
        expect(drawerSelectionAfter(CHECKABLE[i], DRAWER_FAQ)).assertEqual(CHECKABLE[i]);
      }
      expect(isCheckableDrawerItem(DRAWER_FAQ)).assertFalse();
      // An unknown id behaves like FAQ.
      expect(isCheckableDrawerItem('nope')).assertFalse();
      expect(drawerClosesAfter(DRAWER_PROFILES, 'nope')).assertFalse();
      expect(drawerNavigatesAfter(DRAWER_PROFILES, 'nope')).assertFalse();
      expect(drawerSelectionAfter(DRAWER_PROFILES, 'nope')).assertEqual(DRAWER_PROFILES);
      // The drawer opens the Android FAQ link.
      expect(FAQ_URL).assertEqual(
        'https://github.com/shadowsocks/shadowsocks-android/blob/master/.github/faq.md');
    });

    it('U01#drawer-defaults-to-profiles', 0, () => {
      expect(defaultDrawerSelection()).assertEqual(DRAWER_PROFILES);
      expect(defaultDrawerSelection()).assertEqual('profiles');
      expect(isCheckableDrawerItem(defaultDrawerSelection())).assertTrue();
      // The default is the first row, so the page opens on the profile list.
      expect(DRAWER_ENTRIES[0].id).assertEqual(defaultDrawerSelection());
      // A page return resets the check to Profiles from any other row.
      expect(drawerSelectionAfter(DRAWER_SETTINGS, defaultDrawerSelection()))
        .assertEqual(DRAWER_PROFILES);
    });

    it('U01#can-stop-covers-every-up-phase', 0, () => {
      for (let i = 0; i < UP_PHASES.length; i++) {
        expect(canStop(UP_PHASES[i])).assertTrue();
        expect(canStart(UP_PHASES[i])).assertFalse();
      }
      expect(canStop(PHASE_IDLE)).assertFalse();
      expect(canStart(PHASE_IDLE)).assertTrue();
      expect(canStop(PHASE_FAILED)).assertFalse();
      expect(canStart(PHASE_FAILED)).assertTrue();
      // The teardown window allows neither action.
      expect(canStop(PHASE_STOPPING)).assertFalse();
      expect(canStart(PHASE_STOPPING)).assertFalse();
      for (let i = 0; i < PHASES.length; i++) {
        expect(canStop(PHASES[i]) && canStart(PHASES[i])).assertFalse();
      }
    });

    it('U01#button-disabled-while-stopping', 0, () => {
      expect(serviceButtonEnabled(PHASE_STOPPING)).assertFalse();
      for (let i = 0; i < PHASES.length; i++) {
        if (PHASES[i] !== PHASE_STOPPING) {
          expect(serviceButtonEnabled(PHASES[i])).assertTrue();
        }
        expect(serviceButtonEnabled(PHASES[i]))
          .assertEqual(canStop(PHASES[i]) || canStart(PHASES[i]));
      }
    });

    it('U01#button-checked-only-when-connected', 0, () => {
      expect(serviceButtonChecked(PHASE_CONNECTED)).assertTrue();
      expect(serviceButtonChecked(PHASE_PROBE_FAILED)).assertTrue();
      // Verifying means the tunnel is up and the first probe is in flight.
      expect(serviceButtonChecked(PHASE_VERIFYING)).assertTrue();
      const unchecked: string[] = [
        PHASE_IDLE, PHASE_CONNECTING, PHASE_STOPPING, PHASE_FAILED,
      ];
      for (let i = 0; i < unchecked.length; i++) {
        expect(serviceButtonChecked(unchecked[i])).assertFalse();
      }
      // The checked fill means the tunnel is up, so the service can stop.
      for (let i = 0; i < PHASES.length; i++) {
        expect(serviceButtonChecked(PHASES[i])).assertEqual(statsVisible(PHASES[i]));
        if (serviceButtonChecked(PHASES[i])) {
          expect(canStop(PHASES[i])).assertTrue();
        }
      }
    });

    it('U01#button-label-and-glyph-follow-the-phase', 0, () => {
      for (let i = 0; i < UP_PHASES.length; i++) {
        expect(serviceButtonLabelKey(UP_PHASES[i])).assertEqual('index_disconnect');
      }
      expect(serviceButtonLabelKey(PHASE_IDLE)).assertEqual('index_connect');
      expect(serviceButtonLabelKey(PHASE_FAILED)).assertEqual('index_connect');
      expect(serviceButtonLabelKey(PHASE_STOPPING)).assertEqual('index_connect');
      // The glyph token follows the phase table, in PHASES order.
      const glyphs: string[] = [
        'connect', 'stop', 'stop', 'check', 'check', 'wait', 'connect',
      ];
      for (let i = 0; i < PHASES.length; i++) {
        expect(serviceButtonGlyph(PHASES[i])).assertEqual(glyphs[i]);
      }
    });

    it('U01#button-tap-stops-or-starts', 0, () => {
      // The tap action follows the phase table, in PHASES order.
      const taps: string[] = [
        'start', 'stop', 'stop', 'stop', 'stop', 'none', 'start',
      ];
      for (let i = 0; i < PHASES.length; i++) {
        expect(serviceButtonTap(PHASES[i])).assertEqual(taps[i]);
        // A tap does something exactly when the button is enabled.
        expect(serviceButtonTap(PHASES[i]) !== 'none')
          .assertEqual(serviceButtonEnabled(PHASES[i]));
      }
    });

    it('U01#ring-waits-then-shows-indeterminate', 0, () => {
      expect(RING_DELAY_MS).assertEqual(1200);
      expect(RING_FILL_MS).assertEqual(400);
      expect(ringState(PHASE_CONNECTING, 0)).assertEqual('hidden');
      expect(ringState(PHASE_CONNECTING, RING_DELAY_MS - 1)).assertEqual('hidden');
      expect(ringState(PHASE_CONNECTING, RING_DELAY_MS)).assertEqual('indeterminate');
      expect(ringState(PHASE_CONNECTING, RING_DELAY_MS * 10)).assertEqual('indeterminate');
      // No other phase shows the connecting ring, however long it waits.
      for (let i = 0; i < PHASES.length; i++) {
        if (PHASES[i] !== PHASE_CONNECTING) {
          expect(ringState(PHASES[i], RING_DELAY_MS * 10)).assertEqual('hidden');
        }
      }
    });

    it('U01#keyboard-toggle-maps-to-stop-or-start', 0, () => {
      for (let i = 0; i < UP_PHASES.length; i++) {
        expect(keyboardToggle(UP_PHASES[i])).assertEqual('stop');
      }
      expect(keyboardToggle(PHASE_IDLE)).assertEqual('start');
      expect(keyboardToggle(PHASE_FAILED)).assertEqual('start');
      // Ctrl+G during stopping asks for a start. The page rejects it with a
      // phase guard, so the button itself stays inactive.
      expect(keyboardToggle(PHASE_STOPPING)).assertEqual('start');
      expect(serviceButtonTap(PHASE_STOPPING)).assertEqual('none');
    });

    it('U01#stats-bar-visible-only-when-connected', 0, () => {
      expect(statsVisible(PHASE_CONNECTED)).assertTrue();
      expect(statsVisible(PHASE_PROBE_FAILED)).assertTrue();
      // The bar appears as soon as the tunnel is up, before the probe verdict.
      expect(statsVisible(PHASE_VERIFYING)).assertTrue();
      const hidden: string[] = [
        PHASE_IDLE, PHASE_CONNECTING, PHASE_STOPPING, PHASE_FAILED,
      ];
      for (let i = 0; i < hidden.length; i++) {
        expect(statsVisible(hidden[i])).assertFalse();
      }
      // The full phase table, in PHASES order.
      const expected: boolean[] = [false, false, true, true, true, false, false];
      for (let i = 0; i < PHASES.length; i++) {
        expect(statsVisible(PHASES[i])).assertEqual(expected[i]);
      }
    });

    it('U01#stats-bar-hides-and-returns-on-scroll', 0, () => {
      // A positive delta means the content moved up, so the bar hides.
      expect(statsHiddenAfterScroll(false, 1)).assertTrue();
      expect(statsHiddenAfterScroll(true, 1)).assertTrue();
      expect(statsHiddenAfterScroll(false, 48)).assertTrue();
      // A negative delta brings the bar back.
      expect(statsHiddenAfterScroll(true, -1)).assertFalse();
      expect(statsHiddenAfterScroll(false, -1)).assertFalse();
      expect(statsHiddenAfterScroll(true, -48)).assertFalse();
      // A zero delta keeps the current state.
      expect(statsHiddenAfterScroll(true, 0)).assertTrue();
      expect(statsHiddenAfterScroll(false, 0)).assertFalse();
    });

    it('U01#stats-status-while-not-connected', 0, () => {
      expect(statsStatusKind(PHASE_IDLE, TEST_IDLE)).assertEqual('not-connected');
      // The tunnel is up while the first probe runs, so the bar shows the tap
      // prompt rather than "not connected".
      expect(statsStatusKind(PHASE_VERIFYING, TEST_IDLE)).assertEqual('connected-tap');
      expect(statsStatusKind(PHASE_FAILED, TEST_IDLE)).assertEqual('not-connected');
      expect(statsStatusKind(PHASE_CONNECTING, TEST_IDLE)).assertEqual('connecting');
      expect(statsStatusKind(PHASE_STOPPING, TEST_IDLE)).assertEqual('shutting-down');
      // A test status cannot make a hidden bar look connected.
      expect(statsStatusKind(PHASE_CONNECTING, TEST_SUCCESS)).assertEqual('connecting');
      expect(statsStatusKind(PHASE_STOPPING, TEST_ERROR)).assertEqual('shutting-down');
      expect(statsStatusKind(PHASE_FAILED, TEST_SUCCESS)).assertEqual('not-connected');
    });

    it('U01#stats-status-follows-the-test', 0, () => {
      // A connected phase shows the tap prompt until a test sets a state.
      expect(statsStatusKind(PHASE_CONNECTED, TEST_IDLE)).assertEqual('connected-tap');
      expect(statsStatusKind(PHASE_CONNECTED, TEST_TESTING)).assertEqual('testing');
      expect(statsStatusKind(PHASE_CONNECTED, TEST_SUCCESS)).assertEqual('success');
      expect(statsStatusKind(PHASE_CONNECTED, TEST_ERROR)).assertEqual('error');
      // A probe-failed phase shows its own failure until a test sets a state.
      expect(statsStatusKind(PHASE_PROBE_FAILED, TEST_IDLE)).assertEqual('probe-failed');
      expect(statsStatusKind(PHASE_PROBE_FAILED, TEST_TESTING)).assertEqual('testing');
      expect(statsStatusKind(PHASE_PROBE_FAILED, TEST_SUCCESS)).assertEqual('success');
      expect(statsStatusKind(PHASE_PROBE_FAILED, TEST_ERROR)).assertEqual('error');
    });

    it('U01#test-status-resets-when-leaving-connected', 0, () => {
      expect(testStatusAfterConnection(TEST_TESTING, PHASE_CONNECTED)).assertEqual(TEST_TESTING);
      expect(testStatusAfterConnection(TEST_SUCCESS, PHASE_CONNECTED)).assertEqual(TEST_SUCCESS);
      expect(testStatusAfterConnection(TEST_ERROR, PHASE_CONNECTED)).assertEqual(TEST_ERROR);
      expect(testStatusAfterConnection(TEST_SUCCESS, PHASE_PROBE_FAILED)).assertEqual(TEST_SUCCESS);
      expect(testStatusAfterConnection(TEST_ERROR, PHASE_PROBE_FAILED)).assertEqual(TEST_ERROR);
      // The bar is up during the first probe, so the status survives it.
      expect(testStatusAfterConnection(TEST_SUCCESS, PHASE_VERIFYING)).assertEqual(TEST_SUCCESS);
      const leaving: string[] = [
        PHASE_IDLE, PHASE_CONNECTING, PHASE_STOPPING, PHASE_FAILED,
      ];
      for (let i = 0; i < leaving.length; i++) {
        expect(testStatusAfterConnection(TEST_SUCCESS, leaving[i])).assertEqual(TEST_IDLE);
        expect(testStatusAfterConnection(TEST_ERROR, leaving[i])).assertEqual(TEST_IDLE);
      }
      // The status survives exactly while the stats bar shows.
      for (let i = 0; i < PHASES.length; i++) {
        expect(testStatusAfterConnection(TEST_SUCCESS, PHASES[i]) === TEST_SUCCESS)
          .assertEqual(statsVisible(PHASES[i]));
      }
    });

    it('U01#test-classifies-204-and-empty-200', 0, () => {
      const empty204: TestResult = classifyTest(true, 204, 0, '');
      expect(empty204.kind).assertEqual(TEST_KIND_SUCCESS);
      expect(empty204.code).assertEqual(204);
      expect(empty204.reason).assertEqual('');
      const empty200: TestResult = classifyTest(true, 200, 0, '');
      expect(empty200.kind).assertEqual(TEST_KIND_SUCCESS);
      expect(empty200.code).assertEqual(200);
      // The rule reads the code and the body length, not the ok flag.
      expect(classifyTest(false, 200, 0, '').kind).assertEqual(TEST_KIND_SUCCESS);
      // A 200 response with a body is not the empty probe answer.
      expect(classifyTest(true, 200, 120, '').kind).assertEqual(TEST_KIND_HTTP);
      // A success becomes a tunnel error when the counters did not move.
      const tunnelled: TestResult =
        applyTunnelVerdict(empty204, false, 'traffic did not go through the tunnel');
      expect(tunnelled.kind).assertEqual(TEST_KIND_TUNNEL);
      expect(tunnelled.reason).assertEqual('traffic did not go through the tunnel');
      // A moving counter keeps the success, and the HTTP code stays in place.
      const kept: TestResult = applyTunnelVerdict(empty204, true, '');
      expect(kept.kind).assertEqual(TEST_KIND_SUCCESS);
      expect(kept.code).assertEqual(204);
    });

    it('U01#test-reports-an-http-error-code', 0, () => {
      const withBody: TestResult = classifyTest(true, 200, 120, '');
      expect(withBody.kind).assertEqual(TEST_KIND_HTTP);
      expect(withBody.code).assertEqual(200);
      const notFound: TestResult = classifyTest(true, 404, 0, 'HTTP 404');
      expect(notFound.kind).assertEqual(TEST_KIND_HTTP);
      expect(notFound.code).assertEqual(404);
      expect(notFound.reason).assertEqual('HTTP 404');
      const redirect: TestResult = classifyTest(true, 301, 0, '');
      expect(redirect.kind).assertEqual(TEST_KIND_HTTP);
      expect(redirect.code).assertEqual(301);
      // The tunnel verdict leaves an HTTP result unchanged.
      const kept: TestResult =
        applyTunnelVerdict(notFound, false, 'traffic did not go through the tunnel');
      expect(kept.kind).assertEqual(TEST_KIND_HTTP);
      expect(kept.code).assertEqual(404);
      expect(kept.reason).assertEqual('HTTP 404');
    });

    it('U01#test-reports-a-network-error', 0, () => {
      const timedOut: TestResult = classifyTest(false, 0, 0, 'probe timed out after 8000 ms');
      expect(timedOut.kind).assertEqual(TEST_KIND_NETWORK);
      expect(timedOut.code).assertEqual(0);
      expect(timedOut.reason).assertEqual('probe timed out after 8000 ms');
      const refused: TestResult = classifyTest(false, 0, 0, 'Connection refused');
      expect(refused.kind).assertEqual(TEST_KIND_NETWORK);
      expect(refused.reason).assertEqual('Connection refused');
      // The tunnel verdict leaves a network result unchanged.
      const kept: TestResult =
        applyTunnelVerdict(timedOut, false, 'traffic did not go through the tunnel');
      expect(kept.kind).assertEqual(TEST_KIND_NETWORK);
      expect(kept.code).assertEqual(0);
      expect(kept.reason).assertEqual('probe timed out after 8000 ms');
    });

    it('U01#stats-format-totals-and-rates', 0, () => {
      const zero: StatsText = formatStats(0, 0, 0, 0);
      expect(zero.txTotal).assertEqual('▲ 0 B');
      expect(zero.txRate).assertEqual('0 B/s');
      expect(zero.rxTotal).assertEqual('▼ 0 B');
      expect(zero.rxRate).assertEqual('0 B/s');
      const sample: StatsText = formatStats(1536, 1048576, 2048, 1024);
      expect(sample.txTotal).assertEqual('▲ 1.5 KB');
      expect(sample.txRate).assertEqual('2.0 KB/s');
      expect(sample.rxTotal).assertEqual('▼ 1.0 MB');
      expect(sample.rxRate).assertEqual('1.0 KB/s');
      // The totals and rates use the same text as the profile rows.
      const big: StatsText = formatStats(1023, 1073741824, 512, 0);
      expect(big.txTotal).assertEqual(`▲ ${formatBytes(1023)}`);
      expect(big.txTotal).assertEqual('▲ 1023 B');
      expect(big.rxTotal).assertEqual(`▼ ${formatBytes(1073741824)}`);
      expect(big.rxTotal).assertEqual('▼ 1.00 GB');
      expect(big.txRate).assertEqual(formatRate(512));
      expect(big.txRate).assertEqual('512 B/s');
    });

    it('U01#stats-reset-when-leaving-connected', 0, () => {
      expect(statsResetRequired(PHASE_CONNECTED, PHASE_IDLE)).assertTrue();
      expect(statsResetRequired(PHASE_CONNECTED, PHASE_STOPPING)).assertTrue();
      expect(statsResetRequired(PHASE_PROBE_FAILED, PHASE_FAILED)).assertTrue();
      expect(statsResetRequired(PHASE_PROBE_FAILED, PHASE_CONNECTING)).assertTrue();
      expect(statsResetRequired(PHASE_CONNECTED, PHASE_CONNECTED)).assertFalse();
      expect(statsResetRequired(PHASE_CONNECTED, PHASE_PROBE_FAILED)).assertFalse();
      expect(statsResetRequired(PHASE_PROBE_FAILED, PHASE_CONNECTED)).assertFalse();
      expect(statsResetRequired(PHASE_IDLE, PHASE_CONNECTED)).assertFalse();
      expect(statsResetRequired(PHASE_CONNECTING, PHASE_CONNECTED)).assertFalse();
      expect(statsResetRequired(PHASE_IDLE, PHASE_FAILED)).assertFalse();
      // The counters reset exactly when the bar leaves a visible phase.
      for (let i = 0; i < PHASES.length; i++) {
        for (let j = 0; j < PHASES.length; j++) {
          expect(statsResetRequired(PHASES[i], PHASES[j]))
            .assertEqual(statsVisible(PHASES[i]) && !statsVisible(PHASES[j]));
        }
      }
    });

    it('U01#stats-tap-starts-a-test-only-when-connected', 0, () => {
      expect(statsTapAction(PHASE_CONNECTED)).assertEqual('test');
      expect(statsTapAction(PHASE_PROBE_FAILED)).assertEqual('test');
      // A tap during the first probe starts a fresh test and abandons the
      // automatic one.
      expect(statsTapAction(PHASE_VERIFYING)).assertEqual('test');
      const none: string[] = [
        PHASE_IDLE, PHASE_CONNECTING, PHASE_STOPPING, PHASE_FAILED,
      ];
      for (let i = 0; i < none.length; i++) {
        expect(statsTapAction(none[i])).assertEqual('none');
      }
      // A tap starts a test exactly while the bar shows.
      for (let i = 0; i < PHASES.length; i++) {
        expect(statsTapAction(PHASES[i]) === 'test').assertEqual(statsVisible(PHASES[i]));
      }
    });

    it('U01#failure-text-appends-the-detail', 0, () => {
      expect(failureText('Failed to connect the remote server', 'Connection refused'))
        .assertEqual('Failed to connect the remote server: Connection refused');
      // Both sides lose their surrounding whitespace.
      expect(failureText('  Failed to connect the remote server  ', '  Connection refused  '))
        .assertEqual('Failed to connect the remote server: Connection refused');
      // One value stands alone.
      expect(failureText('Could not establish the VPN interface', ''))
        .assertEqual('Could not establish the VPN interface');
      expect(failureText('', 'probe timed out')).assertEqual('probe timed out');
      expect(failureText('', '')).assertEqual('');
      expect(failureText('   ', ' \t ')).assertEqual('');
    });

    it('U01#failure-text-keeps-a-profile-error-unprefixed', 0, () => {
      // The extension reasons carry no detail, so the page shows them as they are.
      expect(failureText('No profile configured', '')).assertEqual('No profile configured');
      expect(failureText('Could not establish the VPN interface', '  '))
        .assertEqual('Could not establish the VPN interface');
      expect(failureText('The core stopped right after starting', ''))
        .assertEqual('The core stopped right after starting');
      // No separator appears without a detail.
      expect(failureText('No profile configured', '').indexOf(': ')).assertEqual(-1);
    });

    it('U01#mode-change-stops-the-old-service', 0, () => {
      expect(modeChanged(MODE_VPN, MODE_PROXY)).assertTrue();
      expect(modeChanged(MODE_PROXY, MODE_VPN)).assertTrue();
      expect(modeChanged(MODE_VPN, 'transparent')).assertTrue();
      // The same mode does not disturb a running service.
      expect(modeChanged(MODE_VPN, MODE_VPN)).assertFalse();
      expect(modeChanged(MODE_PROXY, MODE_PROXY)).assertFalse();
      // An empty running mode means nothing runs, so no change happened.
      expect(modeChanged('', MODE_VPN)).assertFalse();
      expect(modeChanged('', '')).assertFalse();
    });

    it('U01#snackbar-duration-and-fab-margin-are-set', 0, () => {
      expect(SNACKBAR_DURATION_MS).assertEqual(4000);
      expect(FAB_MARGIN_VP).assertEqual(16);
    });

    it('U01#live-counters-exclude-settled-and-missing-records', 0, () => {
      const live: TrafficStats = {
        tx: 10, rx: 20, timestamp: 1, profileId: 'p', token: 't',
        stats: true, closed: false, settled: false,
      };
      // A live record is used as it is, even with zero counters.
      expect(liveCounters(live) === live).assertTrue();
      const zero: TrafficStats = {
        tx: 0, rx: 0, timestamp: 1, profileId: 'p', token: 't',
        stats: true, closed: false, settled: false,
      };
      expect(liveCounters(zero) === zero).assertTrue();
      // A settled record belongs to a session that is already counted.
      const settled: TrafficStats = {
        tx: 10, rx: 20, timestamp: 1, profileId: 'p', token: 't',
        stats: true, closed: true, settled: true,
      };
      expect(liveCounters(settled) === null).assertTrue();
      // A record without a stat endpoint carries no counters, only a heartbeat.
      const heartbeat: TrafficStats = {
        tx: 0, rx: 0, timestamp: 1, profileId: 'p', token: 't',
        stats: false, closed: false, settled: false,
      };
      expect(liveCounters(heartbeat) === null).assertTrue();
      expect(liveCounters(null) === null).assertTrue();
    });
  });
}
