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
 * Seam-level integration tests for the parity batch.
 *
 * Each test crosses a module boundary: a value produced by one model module is
 * consumed by another. The contracts are C-01 to C-08 in the batch HLD.
 * Every test name starts with `ParitySeam#`.
 */

import { describe, expect, it } from '@ohos/hypium';
import { parseAcl } from '../main/ets/model/Acl';
import {
  RULE_KIND_DOMAIN, RULE_KIND_SUBNET, addRule, addRulesFromText, composeCustomRules, domainRule,
} from '../main/ets/model/CustomRules';
import {
  AppSettings, DEFAULT_LOCAL_DNS_PORT, DEFAULT_PROXY_PORT, portNumber, settingsFromJson,
} from '../main/ets/model/Diagnostics';
import { TrafficUpdate, trafficUpdate } from '../main/ets/model/NotificationContent';
import {
  APP_MODE_BYPASS, APP_MODE_OFF, APP_MODE_ON, VpnAppLists, appMode, joinNames, namesOf,
  vpnApplicationLists,
} from '../main/ets/model/PerApp';
import {
  DEFAULT_REMOTE_DNS, Profile, STATUS_ACTIVE, STATUS_OBSOLETE, STATUS_USER_CONFIGURED,
} from '../main/ets/model/Profile';
import {
  ProfileJson, ProxyAppsJson, UdpFallbackJson, exportProfiles, parseProfilesText,
} from '../main/ets/model/ProfilesFile';
import {
  ROUTE_ALL, ROUTE_BYPASS_LAN, ROUTE_CUSTOM_RULES, ROUTE_GFWLIST, aclFileForRoute, isValidRoute,
} from '../main/ets/model/Routes';
import { mergeSubscriptionRun, parseSubscriptionBody } from '../main/ets/model/Subscription';
import { formatBytes, formatRate, formatTraffic, withLive } from '../main/ets/model/TrafficStats';

/** The export text, or a failure when the export returned null. */
function exportText(profiles: Profile[]): string {
  const text = exportProfiles(profiles);
  if (text === null) {
    throw new Error('exportProfiles returned null');
  }
  return text;
}

/** The exported entries, parsed back for assertions. */
function exportEntries(profiles: Profile[]): ProfileJson[] {
  return JSON.parse(exportText(profiles)) as ProfileJson[];
}

/** An `ss://` URL whose transport fields this helper sets. */
function uriFor(name: string, host: string, port: number): string {
  const profile = new Profile();
  profile.name = name;
  profile.host = host;
  profile.remotePort = port;
  profile.password = 'new-pass';
  profile.method = 'chacha20-ietf-poly1305';
  return profile.toUri();
}

/** A parsed URL, or a failure when the URL did not parse. */
function parsedUrl(url: string, feature: Profile | null): Profile {
  const parsed = Profile.parseUrl(url, feature);
  if (parsed === null) {
    throw new Error('URL did not parse');
  }
  return parsed;
}

/** The profile with one id, or a failure when no profile has the id. */
function profileById(profiles: Profile[], id: string): Profile {
  for (const profile of profiles) {
    if (profile.id === id) {
      return profile;
    }
  }
  throw new Error(`no profile with id ${id}`);
}

/** The profile with one host, or a failure when no profile has the host. */
function profileByHost(profiles: Profile[], host: string): Profile {
  for (const profile of profiles) {
    if (profile.host === host) {
      return profile;
    }
  }
  throw new Error(`no profile with host ${host}`);
}

/** The proxy_apps block of an entry, or a failure when it is absent. */
function proxyAppsOf(entry: ProfileJson): ProxyAppsJson {
  const block = entry.proxy_apps;
  if (block === undefined) {
    throw new Error('entry has no proxy_apps block');
  }
  return block;
}

/** The nested fallback of an entry, or a failure when it is absent. */
function fallbackOf(entry: ProfileJson): UdpFallbackJson {
  const block = entry.udp_fallback;
  if (block === undefined) {
    throw new Error('entry has no udp_fallback block');
  }
  return block;
}

export default function paritySeamTest() {
  describe('ParitySeam', () => {
    /* ---- C-01: profile record ---- */

    it('ParitySeam#profileRecordSurvivesUriAndFile', 0, () => {
      const feature = new Profile();
      feature.route = ROUTE_BYPASS_LAN;
      feature.ipv6 = true;
      feature.udpdns = true;
      feature.metered = true;

      const base = new Profile();
      base.name = 'Node A';
      base.host = 'a.example';
      base.remotePort = 8388;
      base.password = 'secret';
      base.method = 'aes-256-gcm';
      base.plugin = 'obfs-local';
      base.pluginOpts = 'obfs=tls';

      // A URL parse gives the transport fields and inherits the features.
      const first = parsedUrl(base.toUri(), feature);
      expect(first.name).assertEqual('Node A');
      expect(first.host).assertEqual('a.example');
      expect(first.remotePort).assertEqual(8388);
      expect(first.method).assertEqual('aes-256-gcm');
      expect(first.password).assertEqual('secret');
      expect(first.plugin).assertEqual('obfs-local');
      expect(first.pluginOpts).assertEqual('obfs=tls');
      expect(first.route).assertEqual(ROUTE_BYPASS_LAN);
      expect(first.ipv6).assertTrue();
      expect(first.udpdns).assertTrue();
      expect(first.metered).assertTrue();

      // The written URL reads back to the same record.
      const second = parsedUrl(first.toUri(), feature);
      expect(second.toUri()).assertEqual(first.toUri());
      expect(second.name).assertEqual('Node A');
      expect(second.host).assertEqual('a.example');
      expect(second.remotePort).assertEqual(8388);
      expect(second.method).assertEqual('aes-256-gcm');
      expect(second.password).assertEqual('secret');
      expect(second.plugin).assertEqual('obfs-local');
      expect(second.pluginOpts).assertEqual('obfs=tls');

      // The file export and import keep the feature fields.
      const imported = parseProfilesText(exportText([second]));
      expect(imported.length).assertEqual(1);
      const restored = imported[0];
      expect(restored.id.length > 0).assertTrue();
      expect(restored.name).assertEqual('Node A');
      expect(restored.host).assertEqual('a.example');
      expect(restored.remotePort).assertEqual(8388);
      expect(restored.method).assertEqual('aes-256-gcm');
      expect(restored.password).assertEqual('secret');
      expect(restored.plugin).assertEqual('obfs-local');
      expect(restored.pluginOpts).assertEqual('obfs=tls');
      expect(restored.route).assertEqual(ROUTE_BYPASS_LAN);
      expect(restored.ipv6).assertTrue();
      expect(restored.udpdns).assertTrue();
      expect(restored.metered).assertTrue();
      expect(restored.remoteDns).assertEqual(DEFAULT_REMOTE_DNS);
    });

    it('ParitySeam#exportWritesAndroidShape', 0, () => {
      const main = new Profile();
      main.id = 'main-1';
      main.name = 'Main';
      main.host = 'main.example';
      main.remotePort = 8388;
      main.password = 'pw-main';
      main.method = 'chacha20-ietf-poly1305';
      main.plugin = 'obfs-local';
      main.pluginOpts = 'obfs=tls';
      main.route = ROUTE_GFWLIST;
      main.remoteDns = '9.9.9.9';
      main.ipv6 = true;
      main.metered = true;
      main.udpdns = true;
      main.proxyAppsEnabled = true;
      main.proxyAppsBypass = true;
      main.proxyAppsList = joinNames(['com.a.one', 'com.b.two']);

      const fallback = new Profile();
      fallback.id = 'fallback-1';
      fallback.name = 'Fallback';
      fallback.host = 'fallback.example';
      fallback.remotePort = 8389;
      fallback.password = 'pw-fb';
      fallback.method = 'aes-256-gcm';
      main.udpFallbackId = fallback.id;

      const text = exportText([main, fallback]);
      const entries = JSON.parse(text) as ProfileJson[];
      expect(entries.length).assertEqual(2);

      const entry = entries[0];
      expect(entry.server).assertEqual('main.example');
      expect(entry.server_port).assertEqual(8388);
      expect(entry.password).assertEqual('pw-main');
      expect(entry.method).assertEqual('chacha20-ietf-poly1305');
      expect(entry.plugin).assertEqual('obfs-local');
      expect(entry.plugin_opts).assertEqual('obfs=tls');
      expect(entry.remarks).assertEqual('Main');
      expect(entry.route).assertEqual(ROUTE_GFWLIST);
      expect(entry.remote_dns).assertEqual('9.9.9.9');
      expect(entry.ipv6).assertTrue();
      expect(entry.metered).assertTrue();
      expect(entry.udpdns).assertTrue();

      const apps = proxyAppsOf(entry);
      expect(apps.enabled).assertTrue();
      expect(apps.bypass).assertTrue();
      expect(apps.android_list).assertEqual(['com.a.one', 'com.b.two']);

      const nested = fallbackOf(entry);
      expect(nested.server).assertEqual('fallback.example');
      expect(nested.server_port).assertEqual(8389);
      expect(nested.password).assertEqual('pw-fb');
      expect(nested.method).assertEqual('aes-256-gcm');

      // The fallback row is its own entry, and it carries no fallback.
      expect(entries[1].server).assertEqual('fallback.example');
      expect(entries[1].udp_fallback === undefined).assertTrue();
      expect(proxyAppsOf(entries[1]).enabled).assertFalse();

      // The store-only fields never reach the file.
      expect(text.indexOf('pluginConfigs') < 0).assertTrue();
      expect(text.indexOf('proxyAppsList') < 0).assertTrue();
      expect(text.indexOf('udpFallbackId') < 0).assertTrue();
    });

    it('ParitySeam#fallbackRoundTripKeepsOneRow', 0, () => {
      const main = new Profile();
      main.id = 'main-1';
      main.name = 'Main';
      main.host = 'main.example';
      main.remotePort = 8388;
      main.password = 'pw-main';
      main.method = 'aes-256-gcm';

      const fallback = new Profile();
      fallback.id = 'fallback-1';
      fallback.name = 'Fallback';
      fallback.host = 'fallback.example';
      fallback.remotePort = 8389;
      fallback.password = 'pw-fb';
      fallback.method = 'aes-256-gcm';
      main.udpFallbackId = fallback.id;

      // The file holds the main entry with a nested udp_fallback block and the
      // fallback row as its own entry, as shadowsocks-android writes it.
      const roundTrip = parseProfilesText(exportText([main, fallback]));

      // The import must reuse the fallback row for the main profile.
      let fallbackRows = 0;
      for (const profile of roundTrip) {
        if (profile.host === 'fallback.example') {
          fallbackRows++;
        }
      }
      expect(fallbackRows).assertEqual(1);
      expect(roundTrip.length).assertEqual(2);

      const restoredMain = profileByHost(roundTrip, 'main.example');
      expect(profileById(roundTrip, restoredMain.udpFallbackId).host)
        .assertEqual('fallback.example');
    });

    /* ---- C-02: start request ---- */

    it('ParitySeam#tunConfigCarriesCoreFields', 0, () => {
      const settings: AppSettings = settingsFromJson({ localDnsPort: '5460' });
      const dnsPort: number = portNumber(settings.localDnsPort, DEFAULT_LOCAL_DNS_PORT);
      expect(dnsPort).assertEqual(5460);
      expect(dnsPort === DEFAULT_LOCAL_DNS_PORT).assertFalse();

      const profile = new Profile();
      profile.host = 'server.example';
      profile.remotePort = 8388;
      profile.password = 'pw';
      profile.method = 'aes-256-gcm';
      profile.plugin = 'obfs-local';
      profile.pluginOpts = 'obfs=tls';
      profile.remoteDns = 'dns.example:5353';
      profile.route = ROUTE_GFWLIST;

      const fileName: string = aclFileForRoute(profile.route);
      expect(fileName).assertEqual('gfwlist.acl');
      const aclPath = `/data/app/files/acl/${fileName}`;

      const config: object = JSON.parse(
        profile.toTunConfig(aclPath, '172.19.0.1/30', '192.168.1.1', dnsPort)) as object;
      expect(config['server']).assertEqual('server.example');
      expect(config['server_port']).assertEqual(8388);
      expect(config['method']).assertEqual('aes-256-gcm');
      expect(config['password']).assertEqual('pw');
      expect(config['plugin']).assertEqual('obfs-local');
      expect(config['plugin_opts']).assertEqual('obfs=tls');
      expect(config['acl']).assertEqual(aclPath);
      // A plugin forwards TCP only.
      expect(config['mode']).assertEqual('tcp_only');

      expect(config['locals'][0]['protocol']).assertEqual('tun');
      expect(config['locals'][0]['tun_interface_address']).assertEqual('172.19.0.1/30');
      expect(config['locals'][0]['dns_gateway']).assertEqual('127.0.0.1:5460');

      // The resolver listens on the settings port.
      expect(config['locals'][1]['protocol']).assertEqual('dns');
      expect(config['locals'][1]['local_address']).assertEqual('127.0.0.1');
      expect(config['locals'][1]['local_port']).assertEqual(dnsPort);
      expect(config['locals'][1]['local_dns_address']).assertEqual('192.168.1.1');
      expect(config['locals'][1]['local_dns_port']).assertEqual(53);
      expect(config['locals'][1]['remote_dns_address']).assertEqual('dns.example');
      expect(config['locals'][1]['remote_dns_port']).assertEqual(5353);
      expect(config['locals'][1]['remote_dns_protocol']).assertEqual('tcp_only');
    });

    it('ParitySeam#localConfigUsesSettingsPort', 0, () => {
      const settings: AppSettings = settingsFromJson({ proxyPort: '1088' });
      const port: number = portNumber(settings.proxyPort, DEFAULT_PROXY_PORT);
      expect(port).assertEqual(1088);

      const profile = new Profile();
      profile.host = 'server.example';
      profile.remotePort = 8388;
      profile.password = 'pw';
      profile.method = 'aes-256-gcm';
      profile.plugin = 'v2ray-plugin';
      profile.pluginOpts = 'mode=websocket';
      expect(profile.localPort).assertEqual(DEFAULT_PROXY_PORT);

      const config: object = JSON.parse(profile.toLocalConfig(port, false)) as object;
      expect(config['locals'][0]['protocol']).assertEqual('socks');
      expect(config['locals'][0]['local_address']).assertEqual('127.0.0.1');
      // The listener takes the settings port, not the profile field.
      expect(config['locals'][0]['local_port']).assertEqual(port);
      expect(config['server']).assertEqual('server.example');
      expect(config['server_port']).assertEqual(8388);
      expect(config['method']).assertEqual('aes-256-gcm');
      expect(config['password']).assertEqual('pw');
      expect(config['plugin']).assertEqual('v2ray-plugin');
      expect(config['plugin_opts']).assertEqual('mode=websocket');
      expect(config['dns']).assertEqual('google');

      // Sharing binds every interface.
      const shared: object = JSON.parse(profile.toLocalConfig(port, true)) as object;
      expect(shared['locals'][0]['local_address']).assertEqual('0.0.0.0');
      expect(shared['locals'][0]['local_port']).assertEqual(port);

      // A cleared stored port falls back to the default port.
      const fallback: number = portNumber('', DEFAULT_PROXY_PORT);
      expect(fallback).assertEqual(DEFAULT_PROXY_PORT);
      const plain: object = JSON.parse(profile.toLocalConfig(fallback, false)) as object;
      expect(plain['locals'][0]['local_port']).assertEqual(DEFAULT_PROXY_PORT);
    });

    /* ---- C-04: traffic sample ---- */

    it('ParitySeam#trafficRatesFromSamples', 0, () => {
      const first: TrafficUpdate = trafficUpdate({ tx: -1, rx: -1, at: 0 }, 1000, 2000, 10000, true);
      expect(first.publish).assertFalse();
      expect(first.rates.up).assertEqual(0);
      expect(first.rates.down).assertEqual(0);
      expect(first.sample.tx).assertEqual(1000);
      expect(first.sample.rx).assertEqual(2000);
      expect(first.sample.at).assertEqual(10000);

      // Two seconds later the counters moved 3000 up and 750 down.
      const second: TrafficUpdate = trafficUpdate(first.sample, 4000, 2750, 12000, true);
      expect(second.publish).assertTrue();
      expect(second.rates.up).assertEqual(1500);
      expect(second.rates.down).assertEqual(375);
      expect(formatRate(second.rates.up)).assertEqual('1.5 KB/s');
      expect(formatRate(second.rates.down)).assertEqual('375 B/s');
      expect(formatTraffic(second.sample.tx, second.sample.rx))
        .assertEqual('↑ 3.9 KB  ↓ 2.7 KB');

      // A reset counter never produces a negative rate.
      const reset: TrafficUpdate = trafficUpdate(second.sample, 100, 50, 14000, true);
      expect(reset.publish).assertTrue();
      expect(reset.rates.up).assertEqual(0);
      expect(reset.rates.down).assertEqual(0);

      // A screen that is off clears the baseline.
      const dark: TrafficUpdate = trafficUpdate(second.sample, 4000, 2750, 16000, false);
      expect(dark.publish).assertFalse();
      expect(dark.sample.tx).assertEqual(-1);
      expect(dark.sample.rx).assertEqual(-1);
      expect(dark.sample.at).assertEqual(0);
    });

    it('ParitySeam#trafficTotalsUseLiveSample', 0, () => {
      const profile = new Profile();
      profile.tx = 2048;
      profile.rx = 1024;

      // The stored counter includes the finished sessions.
      expect(withLive(profile.tx, 512, true)).assertEqual(2560);
      expect(withLive(profile.rx, 512, true)).assertEqual(1536);
      expect(formatTraffic(withLive(profile.tx, 512, true), withLive(profile.rx, 512, true)))
        .assertEqual('↑ 2.5 KB  ↓ 1.5 KB');

      // A stopped session adds nothing.
      expect(withLive(profile.tx, 512, false)).assertEqual(2048);
      expect(formatTraffic(profile.tx, profile.rx)).assertEqual('↑ 2.0 KB  ↓ 1.0 KB');

      expect(formatTraffic(0, 0)).assertEqual('');
      expect(formatBytes(512)).assertEqual('512 B');
      expect(formatBytes(1536)).assertEqual('1.5 KB');
      expect(formatBytes(3 * 1024 * 1024 * 1024)).assertEqual('3.00 GB');
      expect(formatRate(1536)).assertEqual('1.5 KB/s');
    });

    /* ---- C-05: subscription merge ---- */

    it('ParitySeam#subscriptionBodyUpsertsAndRetires', 0, () => {
      const feature = new Profile();
      feature.route = ROUTE_BYPASS_LAN;
      feature.ipv6 = true;
      feature.udpdns = true;
      feature.proxyAppsEnabled = true;
      feature.proxyAppsBypass = false;
      feature.proxyAppsList = 'com.a.one';

      const bodyText = `${uriFor('A', 'a.example', 8388)}\n${uriFor('C', 'c.example', 443)}`;
      const body = Profile.encodeBase64(Profile.encodeUtf8(bodyText), false, true);
      const fresh = parseSubscriptionBody(body, 'sub-1', feature);
      expect(fresh.length).assertEqual(2);
      expect(fresh[0].subscriptionId).assertEqual('sub-1');
      expect(fresh[0].route).assertEqual(ROUTE_BYPASS_LAN);
      expect(fresh[0].ipv6).assertTrue();
      expect(fresh[0].udpdns).assertTrue();
      expect(fresh[0].id.length > 0).assertTrue();
      expect(fresh[1].host).assertEqual('c.example');

      const storedA = new Profile();
      storedA.id = 'kept-a';
      storedA.name = 'A';
      storedA.host = 'a.example';
      storedA.remotePort = 8388;
      storedA.password = 'old-pass';
      storedA.method = 'aes-256-gcm';
      storedA.route = ROUTE_GFWLIST;
      storedA.subscriptionId = 'sub-1';
      storedA.subscriptionStatus = STATUS_ACTIVE;
      storedA.tx = 500;
      storedA.userOrder = 2;

      const storedB = new Profile();
      storedB.id = 'gone-b';
      storedB.name = 'B';
      storedB.host = 'b.example';
      storedB.remotePort = 8388;
      storedB.password = 'pw-b';
      storedB.method = 'aes-256-gcm';
      storedB.subscriptionId = 'sub-1';
      storedB.subscriptionStatus = STATUS_ACTIVE;
      storedB.userOrder = 3;

      const manual = new Profile();
      manual.id = 'manual';
      manual.name = 'Mine';
      manual.host = 'mine.example';
      manual.remotePort = 8388;
      manual.password = 'pw-m';
      manual.method = 'aes-256-gcm';
      manual.subscriptionStatus = STATUS_USER_CONFIGURED;
      manual.userOrder = 4;

      const merged = mergeSubscriptionRun([storedA, storedB, manual], fresh, 'kept-a');
      expect(merged.profiles.length).assertEqual(4);
      expect(merged.currentId).assertEqual('kept-a');
      expect(merged.deleted).assertEqual(0);

      // The re-listed profile keeps its identity, counters and own route.
      const a = profileById(merged.profiles, 'kept-a');
      expect(a.name).assertEqual('A');
      expect(a.password).assertEqual('new-pass');
      expect(a.method).assertEqual('chacha20-ietf-poly1305');
      expect(a.route).assertEqual(ROUTE_GFWLIST);
      expect(a.tx).assertEqual(500);
      expect(a.userOrder).assertEqual(2);
      expect(a.subscriptionStatus).assertEqual(STATUS_ACTIVE);

      // The profile the subscription dropped stays, marked obsolete.
      expect(profileById(merged.profiles, 'gone-b').subscriptionStatus)
        .assertEqual(STATUS_OBSOLETE);
      // A hand-made profile is never touched.
      expect(profileById(merged.profiles, 'manual').subscriptionStatus)
        .assertEqual(STATUS_USER_CONFIGURED);

      // The new profile takes the feature settings and lands at the end.
      const c = profileByHost(merged.profiles, 'c.example');
      expect(c.subscriptionStatus).assertEqual(STATUS_ACTIVE);
      expect(c.subscriptionId).assertEqual('sub-1');
      expect(c.route).assertEqual(ROUTE_BYPASS_LAN);
      expect(c.userOrder).assertEqual(5);

      // The export leaves the obsolete profile out.
      const entries = exportEntries(merged.profiles);
      expect(entries.length).assertEqual(3);
      expect(entries[0].server).assertEqual('a.example');
      expect(entries[0].route).assertEqual(ROUTE_GFWLIST);
      expect(entries[1].server).assertEqual('mine.example');
      expect(entries[2].server).assertEqual('c.example');
      expect(entries[2].route).assertEqual(ROUTE_BYPASS_LAN);
    });

    it('ParitySeam#subscriptionMergeInheritsFeatureSettings', 0, () => {
      const feature = new Profile();
      feature.route = ROUTE_CUSTOM_RULES;
      feature.ipv6 = true;
      feature.metered = true;
      feature.udpdns = true;
      feature.proxyAppsEnabled = true;
      feature.proxyAppsBypass = true;
      feature.proxyAppsList = joinNames(['com.one.app', 'com.two.app']);

      const body = '{"servers":[' +
        '{"server":"s1.example","server_port":8388,"password":"p1",' +
        '"method":"aes-256-gcm","remarks":"S1"},' +
        '{"server":"s2.example","server_port":443,"password":"p2",' +
        '"method":"chacha20-ietf-poly1305","remarks":"S2"}]}';
      const fresh = parseSubscriptionBody(body, 'sub-2', feature);
      expect(fresh.length).assertEqual(2);
      expect(fresh[0].route).assertEqual(ROUTE_CUSTOM_RULES);
      expect(fresh[0].ipv6).assertTrue();
      expect(fresh[0].metered).assertTrue();
      expect(fresh[0].udpdns).assertTrue();
      expect(fresh[0].proxyAppsEnabled).assertTrue();
      expect(fresh[0].proxyAppsBypass).assertTrue();
      expect(fresh[0].proxyAppsList).assertEqual('com.one.app\ncom.two.app');
      expect(fresh[0].subscriptionId).assertEqual('sub-2');

      const merged = mergeSubscriptionRun([], fresh, '');
      expect(merged.profiles.length).assertEqual(2);
      expect(merged.profiles[0].subscriptionStatus).assertEqual(STATUS_ACTIVE);
      expect(merged.profiles[0].userOrder).assertEqual(1);
      expect(merged.profiles[1].subscriptionStatus).assertEqual(STATUS_ACTIVE);
      expect(merged.profiles[1].userOrder).assertEqual(2);

      // The exported file carries the inherited features.
      const entries = exportEntries(merged.profiles);
      expect(entries.length).assertEqual(2);
      expect(entries[0].route).assertEqual(ROUTE_CUSTOM_RULES);
      expect(entries[0].ipv6).assertTrue();
      expect(entries[0].metered).assertTrue();
      expect(entries[0].udpdns).assertTrue();
      const apps = proxyAppsOf(entries[0]);
      expect(apps.enabled).assertTrue();
      expect(apps.bypass).assertTrue();
      expect(apps.android_list).assertEqual(['com.one.app', 'com.two.app']);
    });

    /* ---- C-06: ACL composition ---- */

    it('ParitySeam#customRulesComposeForRoute', 0, () => {
      expect(isValidRoute(ROUTE_CUSTOM_RULES)).assertTrue();
      expect(aclFileForRoute(ROUTE_CUSTOM_RULES)).assertEqual('custom-rules.acl');

      let userText = addRule('', RULE_KIND_DOMAIN, 'example.com');
      userText = addRule(userText, RULE_KIND_SUBNET, '10.0.0.0/8');

      const composed = composeCustomRules(userText);
      const doc = parseAcl(composed);
      // The route means "proxy what is listed", so the default is bypass.
      expect(doc.bypass).assertTrue();
      expect(doc.proxyEntries.length).assertEqual(2);
      expect(doc.proxyEntries[0]).assertEqual(domainRule('example.com'));
      expect(doc.proxyEntries[1]).assertEqual('10.0.0.0/8');

      // A file that says "proxy all but these" turns round.
      const turned = parseAcl(composeCustomRules('[proxy_all]\n\n[bypass_list]\ndirect.test\n'));
      expect(turned.bypass).assertTrue();
      expect(turned.bypassEntries.length).assertEqual(1);
      expect(turned.bypassEntries[0]).assertEqual('direct.test');

      // The imported child adds its entries and keeps the bypass default.
      const child = '[bypass_all]\n\n[proxy_list]\nchild.one\nchild.two\n';
      const imported = parseAcl(addRulesFromText(composed, child));
      expect(imported.bypass).assertTrue();
      expect(imported.proxyEntries.length).assertEqual(4);
      expect(imported.proxyEntries[2]).assertEqual('child.one');
      expect(imported.proxyEntries[3]).assertEqual('child.two');
    });

    it('ParitySeam#aclPathReachesTunConfig', 0, () => {
      const profile = new Profile();
      profile.host = 'server.example';
      profile.remotePort = 8388;
      profile.password = 'pw';
      profile.method = 'aes-256-gcm';

      expect(aclFileForRoute(ROUTE_ALL)).assertEqual('');
      expect(aclFileForRoute(ROUTE_GFWLIST)).assertEqual('gfwlist.acl');
      expect(aclFileForRoute(ROUTE_CUSTOM_RULES)).assertEqual('custom-rules.acl');

      // The `all` route needs no file, so a path is ignored.
      profile.route = ROUTE_ALL;
      const plain: object = JSON.parse(
        profile.toTunConfig('/files/acl/gfwlist.acl', '172.19.0.1/30')) as object;
      expect(plain['acl'] === undefined).assertTrue();

      // A policy route receives the deployed file path.
      profile.route = ROUTE_GFWLIST;
      const filtered: object = JSON.parse(
        profile.toTunConfig('/files/acl/gfwlist.acl', '172.19.0.1/30')) as object;
      expect(filtered['acl']).assertEqual('/files/acl/gfwlist.acl');

      profile.route = ROUTE_CUSTOM_RULES;
      const custom: object = JSON.parse(
        profile.toTunConfig('/files/acl/custom-rules.acl', '172.19.0.1/30')) as object;
      expect(custom['acl']).assertEqual('/files/acl/custom-rules.acl');

      // A policy route with no deployed file injects no ACL.
      const missing: object = JSON.parse(
        profile.toTunConfig('', '172.19.0.1/30')) as object;
      expect(missing['acl'] === undefined).assertTrue();
    });

    /* ---- C-08: app selection ---- */

    it('ParitySeam#perAppListsStayExclusive', 0, () => {
      const profile = new Profile();
      profile.proxyAppsEnabled = true;
      profile.proxyAppsBypass = false;
      profile.proxyAppsList = joinNames(['com.a.one', 'com.a.two', 'com.b.three']);
      const client = 'com.xbt.project';

      expect(appMode(profile.proxyAppsEnabled, profile.proxyAppsBypass)).assertEqual(APP_MODE_ON);
      const on: VpnAppLists = vpnApplicationLists(profile.proxyAppsEnabled,
        profile.proxyAppsBypass, profile.proxyAppsList, client);
      expect(on.trusted).assertEqual(['com.a.one', 'com.a.two', 'com.b.three']);
      expect(on.blocked.length).assertEqual(0);

      // Bypass mode blocks the client bundle and the selected names.
      profile.proxyAppsBypass = true;
      expect(appMode(profile.proxyAppsEnabled, profile.proxyAppsBypass))
        .assertEqual(APP_MODE_BYPASS);
      const bypass: VpnAppLists = vpnApplicationLists(profile.proxyAppsEnabled,
        profile.proxyAppsBypass, profile.proxyAppsList, client);
      expect(bypass.trusted.length).assertEqual(0);
      expect(bypass.blocked.length).assertEqual(4);
      expect(bypass.blocked[0]).assertEqual(client);
      expect(bypass.blocked[1]).assertEqual('com.a.one');

      // The client bundle appears once, even when the user selected it.
      const withClient = joinNames([client, 'com.a.one']);
      const deduped: VpnAppLists = vpnApplicationLists(true, true, withClient, client);
      expect(deduped.blocked).assertEqual([client, 'com.a.one']);

      // Mode off produces no list.
      const off: VpnAppLists = vpnApplicationLists(false, true, profile.proxyAppsList, client);
      expect(off.trusted.length).assertEqual(0);
      expect(off.blocked.length).assertEqual(0);
      expect(appMode(false, true)).assertEqual(APP_MODE_OFF);

      // Only one list is ever non-empty.
      for (const lists of [on, bypass, deduped, off]) {
        expect(lists.trusted.length === 0 || lists.blocked.length === 0).assertTrue();
      }
    });

    it('ParitySeam#perAppSelectionSurvivesFileRoundTrip', 0, () => {
      const profile = new Profile();
      profile.name = 'Main';
      profile.host = 'main.example';
      profile.remotePort = 8388;
      profile.password = 'pw';
      profile.method = 'aes-256-gcm';
      profile.proxyAppsEnabled = true;
      profile.proxyAppsBypass = true;
      profile.proxyAppsList = joinNames(['com.a.one', 'com.a.two', 'com.b.three']);

      const imported = parseProfilesText(exportText([profile]));
      expect(imported.length).assertEqual(1);
      const restored = imported[0];
      expect(restored.proxyAppsEnabled).assertTrue();
      expect(restored.proxyAppsBypass).assertTrue();
      expect(restored.proxyAppsList).assertEqual('com.a.one\ncom.a.two\ncom.b.three');
      expect(namesOf(restored.proxyAppsList).length).assertEqual(3);

      // The imported fields drive the same exclusive VPN lists.
      const client = 'com.xbt.project';
      const lists: VpnAppLists = vpnApplicationLists(restored.proxyAppsEnabled,
        restored.proxyAppsBypass, restored.proxyAppsList, client);
      expect(lists.trusted.length).assertEqual(0);
      expect(lists.blocked.length).assertEqual(4);
      expect(lists.blocked[0]).assertEqual(client);
      expect(lists.blocked[1]).assertEqual('com.a.one');
      expect(lists.trusted.length === 0 || lists.blocked.length === 0).assertTrue();
    });
  });
}
