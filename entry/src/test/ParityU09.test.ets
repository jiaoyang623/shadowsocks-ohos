import { describe, expect, it } from '@ohos/hypium';
import {
  advancedSummaryRows, AppSettings, AppSettingsJson, CONNECT_TIMEOUT_MS, DEFAULT_LOCAL_DNS_PORT,
  DEFAULT_PROBE_URL, DEFAULT_PROXY_PORT, DEFAULT_SPEED_URL, isServiceStopped, MODE_PROXY, MODE_VPN,
  PORT_UNSET, portNumber, portSummary, sanitizePortInput, SERVICE_MODE_CHOICES, serviceModeEntry,
  SETTINGS_ROW_AUTO_CONNECT, SETTINGS_ROW_LOCAL_DNS_PORT, SETTINGS_ROW_PROXY_PORT,
  SETTINGS_ROW_SERVICE_MODE, settingsFromJson, settingsJsonFrom, settingsNeedSeed, settingsRows,
  STATS_STALE_MS, VpnStatus, VPN_STATE_FAILED, VPN_STATE_RUNNING, VPN_STATE_STARTING,
  VPN_STATE_STOPPED,
} from '../main/ets/model/Diagnostics';
import { Profile } from '../main/ets/model/Profile';

/** A status file record for one state, written at `timestamp`. */
function vpnStatus(state: string, timestamp: number): VpnStatus {
  return {
    state: state, reason: '', detail: '', profileId: 'p1', profileName: 'Test',
    timestamp: timestamp,
  };
}

/** A stored object with the four keys the seed check requires. */
function completeJson(): AppSettingsJson {
  return {
    serviceMode: MODE_VPN, proxyPort: '1080', localDnsPort: '5450', autoConnect: false,
  };
}

/** A profile with the fields the two config serializers need. */
function testProfile(): Profile {
  const profile = new Profile();
  profile.host = 'example.com';
  profile.remotePort = 8388;
  profile.password = 'pw';
  return profile;
}

export default function parityU09Test() {
  describe('U09', () => {
    it('U09#collapsed-rows', 0, () => {
      const rows = settingsRows(false);
      expect(rows.length).assertEqual(1);
      expect(rows[0]).assertEqual(SETTINGS_ROW_AUTO_CONNECT);
      // The collapsed view hides the service mode and both ports.
      expect(rows.indexOf(SETTINGS_ROW_SERVICE_MODE)).assertEqual(-1);
      expect(rows.indexOf(SETTINGS_ROW_PROXY_PORT)).assertEqual(-1);
      expect(rows.indexOf(SETTINGS_ROW_LOCAL_DNS_PORT)).assertEqual(-1);
      // Each call returns a new array, so a caller cannot change the next result.
      const other = settingsRows(false);
      expect(rows === other).assertFalse();
      other.push(SETTINGS_ROW_PROXY_PORT);
      expect(settingsRows(false).length).assertEqual(1);
    });

    it('U09#expanded-rows', 0, () => {
      const rows = settingsRows(true);
      expect(rows.length).assertEqual(4);
      // The display order is Auto Connect, Service mode, then the two ports.
      expect(rows[0]).assertEqual(SETTINGS_ROW_AUTO_CONNECT);
      expect(rows[1]).assertEqual(SETTINGS_ROW_SERVICE_MODE);
      expect(rows[2]).assertEqual(SETTINGS_ROW_PROXY_PORT);
      expect(rows[3]).assertEqual(SETTINGS_ROW_LOCAL_DNS_PORT);
      // Each call returns a new array.
      expect(rows === settingsRows(true)).assertFalse();
    });

    it('U09#advanced-summary', 0, () => {
      const hidden = advancedSummaryRows();
      expect(hidden.length).assertEqual(3);
      expect(hidden[0]).assertEqual(SETTINGS_ROW_SERVICE_MODE);
      expect(hidden[1]).assertEqual(SETTINGS_ROW_PROXY_PORT);
      expect(hidden[2]).assertEqual(SETTINGS_ROW_LOCAL_DNS_PORT);
      // The visible Auto Connect row is not part of the summary.
      expect(hidden.indexOf(SETTINGS_ROW_AUTO_CONNECT)).assertEqual(-1);
      // Each call returns a new array.
      expect(hidden === advancedSummaryRows()).assertFalse();
    });

    it('U09#no-expansion-key', 0, () => {
      const settings = settingsFromJson(null);
      const json = settingsJsonFrom(settings);
      const keys = Object.keys(json);
      // The store shape holds the seven settings fields and nothing else.
      expect(keys.length).assertEqual(7);
      expect(keys.indexOf('expanded')).assertEqual(-1);
      expect(keys.indexOf('serviceMode') >= 0).assertTrue();
      expect(keys.indexOf('proxyPort') >= 0).assertTrue();
      expect(keys.indexOf('localDnsPort') >= 0).assertTrue();
      expect(keys.indexOf('autoConnect') >= 0).assertTrue();
      // The seed check reads the four required keys only, so the page local
      // expansion state never forces a write.
      expect(settingsNeedSeed(completeJson())).assertFalse();
    });

    it('U09#mode-entry-mark', 0, () => {
      // The menu holds the two modes HarmonyOS offers, in the Android order.
      expect(SERVICE_MODE_CHOICES.length).assertEqual(2);
      expect(SERVICE_MODE_CHOICES[0]).assertEqual(MODE_PROXY);
      expect(SERVICE_MODE_CHOICES[1]).assertEqual(MODE_VPN);
      // The entry that matches the stored mode returns the stored mode. The
      // page marks the entry equal to it.
      expect(serviceModeEntry(MODE_PROXY)).assertEqual(MODE_PROXY);
      expect(serviceModeEntry(MODE_VPN)).assertEqual(MODE_VPN);
      expect(SERVICE_MODE_CHOICES.indexOf(serviceModeEntry(MODE_PROXY))).assertEqual(0);
      expect(SERVICE_MODE_CHOICES.indexOf(serviceModeEntry(MODE_VPN))).assertEqual(1);
      // An unknown stored mode marks no entry.
      expect(serviceModeEntry('transproxy')).assertEqual('');
      expect(SERVICE_MODE_CHOICES.indexOf(serviceModeEntry('transproxy'))).assertEqual(-1);
      expect(serviceModeEntry('')).assertEqual('');
      // Each entry stores its own value under serviceMode.
      expect(settingsJsonFrom(settingsFromJson({ serviceMode: MODE_PROXY })).serviceMode)
        .assertEqual(MODE_PROXY);
      expect(settingsJsonFrom(settingsFromJson({ serviceMode: MODE_VPN })).serviceMode)
        .assertEqual(MODE_VPN);
    });

    it('U09#mode-default-and-unknown', 0, () => {
      // An absent or empty stored mode means VPN, the Android default.
      expect(settingsFromJson(null).serviceMode).assertEqual(MODE_VPN);
      expect(settingsFromJson({}).serviceMode).assertEqual(MODE_VPN);
      expect(settingsFromJson({ serviceMode: '' }).serviceMode).assertEqual(MODE_VPN);
      // A stored value that HarmonyOS does not offer stays in the setting.
      const unknown = settingsFromJson({ serviceMode: 'transproxy' });
      expect(unknown.serviceMode).assertEqual('transproxy');
      expect(serviceModeEntry(unknown.serviceMode)).assertEqual('');
      // A value that is not text falls back to VPN.
      const numeric = JSON.parse('{"serviceMode":42}') as AppSettingsJson;
      expect(settingsFromJson(numeric).serviceMode).assertEqual(MODE_VPN);
      // Each offered mode reads back as itself.
      expect(settingsFromJson({ serviceMode: MODE_PROXY }).serviceMode).assertEqual(MODE_PROXY);
      expect(settingsFromJson({ serviceMode: MODE_VPN }).serviceMode).assertEqual(MODE_VPN);
    });

    it('U09#settings-round-trip', 0, () => {
      const original: AppSettings = {
        probeUrl: 'http://probe.example/204',
        speedTestUrl: 'https://speed.example/10mb',
        serviceMode: MODE_PROXY,
        proxyPort: '1088',
        localDnsPort: '',
        autoConnect: true,
        shareOverLan: true,
      };
      const json = settingsJsonFrom(original);
      // The two ports stay text in the stored object.
      expect(typeof json.proxyPort).assertEqual('string');
      expect(typeof json.localDnsPort).assertEqual('string');
      expect(Object.keys(json).length).assertEqual(7);
      // The stored object reads back into the same values.
      const back = settingsFromJson(JSON.parse(JSON.stringify(json)) as AppSettingsJson);
      expect(back.probeUrl).assertEqual(original.probeUrl);
      expect(back.speedTestUrl).assertEqual(original.speedTestUrl);
      expect(back.serviceMode).assertEqual(original.serviceMode);
      expect(back.proxyPort).assertEqual(original.proxyPort);
      expect(back.localDnsPort).assertEqual(original.localDnsPort);
      expect(back.autoConnect).assertEqual(original.autoConnect);
      expect(back.shareOverLan).assertEqual(original.shareOverLan);
    });

    it('U09#port-text-unchanged', 0, () => {
      // The page stores the text as the user typed it. A load must not clamp it.
      const stored = settingsFromJson(
        JSON.parse('{"proxyPort":"080","localDnsPort":"54500"}') as AppSettingsJson);
      expect(stored.proxyPort).assertEqual('080');
      expect(stored.localDnsPort).assertEqual('54500');
      // The store writes that text unchanged.
      const json = settingsJsonFrom(stored);
      expect(json.proxyPort).assertEqual('080');
      expect(json.localDnsPort).assertEqual('54500');
      // An empty text is a stored value too, and it survives the round trip.
      const cleared = settingsFromJson(JSON.parse('{"proxyPort":""}') as AppSettingsJson);
      expect(cleared.proxyPort).assertEqual('');
      expect(settingsJsonFrom(cleared).proxyPort).assertEqual('');
      // The summary shows the stored text, and the read path takes the default.
      expect(portSummary(stored.proxyPort)).assertEqual('080');
      expect(portNumber(stored.proxyPort, DEFAULT_PROXY_PORT)).assertEqual(DEFAULT_PROXY_PORT);
    });

    it('U09#port-read-default', 0, () => {
      // An empty or unreadable text takes the fallback.
      expect(portNumber('', DEFAULT_LOCAL_DNS_PORT)).assertEqual(DEFAULT_LOCAL_DNS_PORT);
      expect(portNumber('abc', DEFAULT_PROXY_PORT)).assertEqual(DEFAULT_PROXY_PORT);
      expect(portNumber('54x0', DEFAULT_LOCAL_DNS_PORT)).assertEqual(DEFAULT_LOCAL_DNS_PORT);
      expect(portNumber(' 5450', DEFAULT_LOCAL_DNS_PORT)).assertEqual(DEFAULT_LOCAL_DNS_PORT);
      // A value below 1025 takes the fallback too.
      expect(portNumber('80', DEFAULT_PROXY_PORT)).assertEqual(DEFAULT_PROXY_PORT);
      // A usable text reads as its value.
      expect(portNumber('5450', DEFAULT_PROXY_PORT)).assertEqual(5450);
      expect(portNumber('1080', DEFAULT_LOCAL_DNS_PORT)).assertEqual(1080);
      // A stored empty port shows Not set and reads as the default.
      const cleared = settingsFromJson(JSON.parse('{"localDnsPort":""}') as AppSettingsJson);
      expect(portSummary(cleared.localDnsPort)).assertEqual(PORT_UNSET);
      expect(portNumber(cleared.localDnsPort, DEFAULT_LOCAL_DNS_PORT))
        .assertEqual(DEFAULT_LOCAL_DNS_PORT);
    });

    it('U09#port-bounds', 0, () => {
      // The usable range is 1025 through 65535.
      expect(portNumber('1024', DEFAULT_PROXY_PORT)).assertEqual(DEFAULT_PROXY_PORT);
      expect(portNumber('1025', DEFAULT_PROXY_PORT)).assertEqual(1025);
      expect(portNumber('65535', DEFAULT_PROXY_PORT)).assertEqual(65535);
      expect(portNumber('65536', DEFAULT_PROXY_PORT)).assertEqual(DEFAULT_PROXY_PORT);
      expect(portNumber('0', DEFAULT_PROXY_PORT)).assertEqual(DEFAULT_PROXY_PORT);
      expect(portNumber('999999', DEFAULT_PROXY_PORT)).assertEqual(DEFAULT_PROXY_PORT);
      // A sign or a decimal point is not a port digit.
      expect(portNumber('-1', DEFAULT_PROXY_PORT)).assertEqual(DEFAULT_PROXY_PORT);
      expect(portNumber('+1080', DEFAULT_PROXY_PORT)).assertEqual(DEFAULT_PROXY_PORT);
      expect(portNumber('1080.0', DEFAULT_PROXY_PORT)).assertEqual(DEFAULT_PROXY_PORT);
    });

    it('U09#port-summary-unset', 0, () => {
      expect(PORT_UNSET).assertEqual('not-set');
      expect(portSummary('')).assertEqual(PORT_UNSET);
      expect(portSummary('1080')).assertEqual('1080');
      expect(portSummary('5450')).assertEqual('5450');
      // The summary shows the stored text, not a normalized value.
      expect(portSummary('0080')).assertEqual('0080');
      expect(portSummary('abc')).assertEqual('abc');
    });

    it('U09#port-input-filter', 0, () => {
      expect(sanitizePortInput('1a2b3')).assertEqual('123');
      expect(sanitizePortInput('port 1080')).assertEqual('1080');
      expect(sanitizePortInput('')).assertEqual('');
      expect(sanitizePortInput('abc')).assertEqual('');
      expect(sanitizePortInput('12345')).assertEqual('12345');
      // A sixth digit is dropped, so the field keeps five characters.
      expect(sanitizePortInput('123456')).assertEqual('12345');
      expect(sanitizePortInput('1 2 3 4 5 6')).assertEqual('12345');
      // A full width digit is not an ASCII digit, so the filter drops it.
      expect(sanitizePortInput('１２３')).assertEqual('');
    });

    it('U09#settings-defaults', 0, () => {
      const defaults = settingsFromJson(null);
      expect(defaults.probeUrl).assertEqual(DEFAULT_PROBE_URL);
      expect(defaults.speedTestUrl).assertEqual(DEFAULT_SPEED_URL);
      expect(defaults.serviceMode).assertEqual(MODE_VPN);
      expect(defaults.proxyPort).assertEqual('1080');
      expect(defaults.localDnsPort).assertEqual('5450');
      // Auto Connect starts off, which is the fresh install value.
      expect(defaults.autoConnect).assertFalse();
      expect(defaults.shareOverLan).assertFalse();
      expect(DEFAULT_PROXY_PORT).assertEqual(1080);
      expect(DEFAULT_LOCAL_DNS_PORT).assertEqual(5450);
      // An empty file object yields the same defaults.
      const empty = settingsFromJson({});
      expect(empty.probeUrl).assertEqual(DEFAULT_PROBE_URL);
      expect(empty.speedTestUrl).assertEqual(DEFAULT_SPEED_URL);
      expect(empty.serviceMode).assertEqual(MODE_VPN);
      expect(empty.proxyPort).assertEqual('1080');
      expect(empty.localDnsPort).assertEqual('5450');
      expect(empty.autoConnect).assertFalse();
      expect(empty.shareOverLan).assertFalse();
      // A blank URL falls back to its default.
      expect(settingsFromJson({ probeUrl: '', speedTestUrl: '' }).probeUrl)
        .assertEqual(DEFAULT_PROBE_URL);
    });

    it('U09#seed-missing-keys', 0, () => {
      // An absent file needs a seed.
      expect(settingsNeedSeed(null)).assertTrue();
      expect(settingsNeedSeed(completeJson())).assertFalse();
      // Each of the four required keys forces a seed when it is absent.
      expect(settingsNeedSeed({ proxyPort: '1080', localDnsPort: '5450', autoConnect: false }))
        .assertTrue();
      expect(settingsNeedSeed({ serviceMode: MODE_VPN, localDnsPort: '5450',
        autoConnect: false })).assertTrue();
      expect(settingsNeedSeed({ serviceMode: MODE_VPN, proxyPort: '1080', autoConnect: false }))
        .assertTrue();
      expect(settingsNeedSeed({ serviceMode: MODE_VPN, proxyPort: '1080', localDnsPort: '5450' }))
        .assertTrue();
      // A stored empty port is a deliberate clear, not a missing key.
      expect(settingsNeedSeed({
        serviceMode: MODE_VPN, proxyPort: '', localDnsPort: '', autoConnect: false,
      })).assertFalse();
      // The optional keys do not force a seed.
      expect(settingsNeedSeed({
        serviceMode: MODE_PROXY, proxyPort: '1088', localDnsPort: '5451', autoConnect: true,
      })).assertFalse();
    });

    it('U09#legacy-number-port', 0, () => {
      // A 5.3.5 file stores the two ports as numbers.
      const legacy = JSON.parse('{"proxyPort":1080,"localDnsPort":5450}') as AppSettingsJson;
      const settings = settingsFromJson(legacy);
      expect(settings.proxyPort).assertEqual('1080');
      expect(settings.localDnsPort).assertEqual('5450');
      // The next write stores text, which is the new shape.
      const json = settingsJsonFrom(settings);
      expect(typeof json.proxyPort).assertEqual('string');
      expect(typeof json.localDnsPort).assertEqual('string');
      expect(json.proxyPort).assertEqual('1080');
      expect(json.localDnsPort).assertEqual('5450');
      // A value that is neither text nor a number reads as Not set.
      const odd = settingsFromJson(
        JSON.parse('{"proxyPort":true,"localDnsPort":null}') as AppSettingsJson);
      expect(odd.proxyPort).assertEqual('');
      expect(odd.localDnsPort).assertEqual('');
      expect(portSummary(odd.proxyPort)).assertEqual(PORT_UNSET);
    });

    it('U09#rows-locked-when-running', 0, () => {
      const now = 1000000;
      const running = vpnStatus(VPN_STATE_RUNNING, now - 1000);
      // A recent status record means the tunnel is still up.
      expect(isServiceStopped(running, 0, now, false)).assertFalse();
      // A starting extension locks the rows too.
      expect(isServiceStopped(vpnStatus(VPN_STATE_STARTING, now), 0, now, false)).assertFalse();
      // A live traffic sample keeps the rows locked without a new status record.
      const oldStatus = vpnStatus(VPN_STATE_RUNNING, now - 100000);
      expect(isServiceStopped(oldStatus, now - 1000, now, false)).assertFalse();
      // A running proxy locks the rows whatever the status file says.
      expect(isServiceStopped(null, 0, now, true)).assertFalse();
      expect(isServiceStopped(running, now, now, true)).assertFalse();
    });

    it('U09#rows-unlock-when-stale', 0, () => {
      const now = 1000000;
      // No status file means the service is stopped.
      expect(isServiceStopped(null, 0, now, false)).assertTrue();
      // A stopped or failed record unlocks the rows at once.
      expect(isServiceStopped(vpnStatus(VPN_STATE_STOPPED, now - 10), 0, now, false))
        .assertTrue();
      expect(isServiceStopped(vpnStatus(VPN_STATE_FAILED, now - 10), 0, now, false)).assertTrue();
      // A running record whose status and sample have both gone stale unlocks.
      const limit = CONNECT_TIMEOUT_MS + STATS_STALE_MS;
      const oldStatus = vpnStatus(VPN_STATE_RUNNING, now - limit - 1);
      expect(isServiceStopped(oldStatus, 0, now, false)).assertTrue();
      expect(isServiceStopped(oldStatus, now - STATS_STALE_MS - 1, now, false)).assertTrue();
      // A record exactly at the limit still counts as recent.
      expect(isServiceStopped(vpnStatus(VPN_STATE_RUNNING, now - limit), 0, now, false))
        .assertFalse();
      // A live sample holds the rows locked even when the status is old.
      expect(isServiceStopped(oldStatus, now - STATS_STALE_MS, now, false)).assertFalse();
    });

    it('U09#dns-port-in-tun-config', 0, () => {
      const profile = testProfile();
      // The default is the store default of 5450.
      const config: object = JSON.parse(profile.toTunConfig('', '172.19.0.1/30')) as object;
      expect(config['locals'][0]['dns_gateway']).assertEqual('127.0.0.1:5450');
      expect(config['locals'][1]['protocol']).assertEqual('dns');
      expect(config['locals'][1]['local_port']).assertEqual(5450);
      // A stored port becomes both the gateway port and the resolver port.
      const custom: object =
        JSON.parse(profile.toTunConfig('', '172.19.0.1/30', '', 5451)) as object;
      expect(custom['locals'][0]['tun_interface_address']).assertEqual('172.19.0.1/30');
      expect(custom['locals'][0]['dns_gateway']).assertEqual('127.0.0.1:5451');
      expect(custom['locals'][1]['local_port']).assertEqual(5451);
    });

    it('U09#proxy-config-has-no-dns-gateway', 0, () => {
      const profile = testProfile();
      // Proxy mode creates no tunnel, so it has no gateway and no resolver.
      const proxy: object = JSON.parse(profile.toLocalConfig(1080, false)) as object;
      expect(proxy['locals'][0]['protocol']).assertEqual('socks');
      expect(proxy['locals'][0]['local_port']).assertEqual(1080);
      expect(JSON.stringify(proxy).indexOf('dns_gateway')).assertEqual(-1);
      // A tun config without an interface address has no gateway either.
      const bare: object = JSON.parse(profile.toTunConfig()) as object;
      expect(bare['locals'].length).assertEqual(1);
      expect(bare['locals'][0]['dns_gateway'] === undefined).assertTrue();
      expect(JSON.stringify(bare).indexOf('dns_gateway')).assertEqual(-1);
    });
  });
}
