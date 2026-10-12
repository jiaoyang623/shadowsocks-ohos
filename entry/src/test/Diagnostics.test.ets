import { describe, expect, it } from '@ohos/hypium';
import {
  computeMbps, CONNECT_TIMEOUT_MS, formatLatency, formatMbps, formatRtt, interpretProbe, isStale,
  LatencyEntry, PHASE_CONNECTED, PHASE_CONNECTING, PHASE_FAILED, PHASE_IDLE,
  PROBE_NO_INTERNET, PROBE_NOT_TUNNELLED, PROBE_OK, routeProxiesByDefault, STATS_STALE_MS,
  summarizeStatus, VpnStatus, VPN_STATE_FAILED, VPN_STATE_RUNNING, VPN_STATE_STARTING,
  VPN_STATE_STOPPED,
} from '../main/ets/model/Diagnostics';
import { ROUTE_ALL, ROUTE_BYPASS_CHINA, ROUTE_CHINA_LIST, ROUTE_GFWLIST } from '../main/ets/model/Routes';

function status(state: string, timestamp: number): VpnStatus {
  const s: VpnStatus = {
    state: state, reason: '', detail: '', profileId: 'p1', profileName: 'test', timestamp: timestamp,
  };
  return s;
}

function latency(ok: boolean, ms: number): LatencyEntry {
  const entry: LatencyEntry = { ok: ok, ms: ms, detail: '' };
  return entry;
}

export default function diagnosticsTest() {
  describe('DiagnosticsTest', () => {
    it('computes throughput in megabits per second', 0, () => {
      expect(computeMbps(1000000, 1000)).assertEqual(8);
      expect(computeMbps(1000000, 2000)).assertEqual(4);
      expect(computeMbps(10000000, 2000)).assertEqual(40);
    });

    it('returns zero throughput instead of NaN or Infinity', 0, () => {
      expect(computeMbps(0, 1000)).assertEqual(0);
      expect(computeMbps(1000, 0)).assertEqual(0);
      expect(computeMbps(0, 0)).assertEqual(0);
      expect(computeMbps(-1, 1000)).assertEqual(0);
    });

    it('formats throughput', 0, () => {
      expect(formatMbps(0)).assertEqual('—');
      expect(formatMbps(-1)).assertEqual('—');
      expect(formatMbps(4.5)).assertEqual('4.50 Mbps');
      expect(formatMbps(12.34)).assertEqual('12.3 Mbps');
    });

    it('formats latency including the unmeasured and failed cases', 0, () => {
      expect(formatLatency(null)).assertEqual('—');
      expect(formatLatency(latency(false, 0))).assertEqual('fail');
      expect(formatLatency(latency(true, 42))).assertEqual('42 ms');
      expect(formatLatency(latency(true, 1500))).assertEqual('1.5 s');
    });

    it('formats round trip time', 0, () => {
      expect(formatRtt(0)).assertEqual('');
      expect(formatRtt(42)).assertEqual('42 ms');
    });

    it('treats a probe that moved no traffic as not tunnelled', 0, () => {
      const verdict = interpretProbe(true, 204, 100, 100, true, true, '');
      expect(verdict.verdict).assertEqual(PROBE_NOT_TUNNELLED);
      expect(verdict.reason.length > 0).assertTrue();
    });

    it('treats a probe that moved traffic as tunnelled', 0, () => {
      expect(interpretProbe(true, 204, 100, 200, true, true, '').verdict).assertEqual(PROBE_OK);
    });

    it('accepts a probe when the counters are unavailable', 0, () => {
      expect(interpretProbe(true, 204, 0, 0, false, true, '').verdict).assertEqual(PROBE_OK);
    });

    it('accepts a probe on a route that connects directly by default', 0, () => {
      // gfwlist/china-list send foreign hosts out directly, so a still counter
      // is the configured behaviour rather than a bypassed tunnel
      expect(interpretProbe(true, 204, 100, 100, true, false, '').verdict).assertEqual(PROBE_OK);
    });

    it('reports no internet for an HTTP failure', 0, () => {
      // the transport's own message is preferred: "could not resolve host" and
      // "connection timed out" point at different faults, and a generic label
      // would hide which one happened
      const verdict = interpretProbe(false, 0, 0, 0, true, true, 'could not resolve host');
      expect(verdict.verdict).assertEqual(PROBE_NO_INTERNET);
      expect(verdict.reason).assertEqual('could not resolve host');
      // with nothing from the transport, fall back to the status code, then to
      // a generic label
      expect(interpretProbe(false, 403, 0, 0, true, true, '').reason).assertEqual('HTTP 403');
      expect(interpretProbe(false, 0, 0, 0, true, true, '').reason).assertEqual('no response');
    });

    it('maps the persisted status to a phase regardless of its age', 0, () => {
      expect(summarizeStatus(null)).assertEqual(PHASE_IDLE);
      expect(summarizeStatus(status(VPN_STATE_STARTING, 1000))).assertEqual(PHASE_CONNECTING);
      // an old `running` record is still CONNECTED here: the status file only
      // changes on transitions, so its age says nothing about liveness
      expect(summarizeStatus(status(VPN_STATE_RUNNING, 1000))).assertEqual(PHASE_CONNECTED);
      expect(summarizeStatus(status(VPN_STATE_FAILED, 1000))).assertEqual(PHASE_FAILED);
      expect(summarizeStatus(status(VPN_STATE_STOPPED, 1000))).assertEqual(PHASE_IDLE);
    });

    it('detects a stale sample, which is the real liveness signal', 0, () => {
      expect(isStale(1000, 1000, STATS_STALE_MS)).assertFalse();
      expect(isStale(1000, 1000 + STATS_STALE_MS, STATS_STALE_MS)).assertFalse();
      expect(isStale(1000, 1001 + STATS_STALE_MS, STATS_STALE_MS)).assertTrue();
    });

    it('classifies which routes proxy a foreign destination by default', 0, () => {
      expect(routeProxiesByDefault(ROUTE_ALL)).assertTrue();
      expect(routeProxiesByDefault(ROUTE_BYPASS_CHINA)).assertTrue();
      expect(routeProxiesByDefault('bypass-lan')).assertTrue();
      expect(routeProxiesByDefault('bypass-lan-china')).assertTrue();
      expect(routeProxiesByDefault(ROUTE_GFWLIST)).assertFalse();
      expect(routeProxiesByDefault(ROUTE_CHINA_LIST)).assertFalse();
    });

    it('gives the UI bounded timings', 0, () => {
      expect(CONNECT_TIMEOUT_MS > 0).assertTrue();
      expect(STATS_STALE_MS > 0).assertTrue();
      // the stats file must be allowed to go quiet longer than the core's
      // 500 ms report interval or healthy tunnels would read as lost
      expect(STATS_STALE_MS > 1000).assertTrue();
    });
  });
}
