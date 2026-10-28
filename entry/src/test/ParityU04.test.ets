import { describe, expect, it } from '@ohos/hypium';
import {
  DEFAULT_REMOTE_DNS, Profile, STATUS_OBSOLETE, copyFeatureSettings, newManualProfile,
} from '../main/ets/model/Profile';
import {
  ProfileJson, ProxyAppsJson, UdpFallbackJson, applyImport, collectProfiles, exportProfileUrls,
  exportProfiles, parseProfileDocument, parseProfilesText,
} from '../main/ets/model/ProfilesFile';
import { ProfileStore } from '../main/ets/model/ProfileStore';
import { ROUTE_ALL, ROUTE_BYPASS_CHINA, ROUTE_GFWLIST } from '../main/ets/model/Routes';

/** A profile with a usable server, so a test can set only what it reads. */
function profile(host: string, port: number, name: string): Profile {
  const entry = new Profile();
  entry.id = `${host}-${port}`;
  entry.host = host;
  entry.remotePort = port;
  entry.password = 'pw';
  entry.method = 'aes-256-gcm';
  entry.name = name;
  return entry;
}

/** The selected profile of every feature inheritance test. */
function featureProfile(): Profile {
  const feature = new Profile();
  feature.id = 'feature';
  feature.name = 'Selected';
  feature.host = 'feature.example';
  feature.remotePort = 1080;
  feature.password = 'feature-pw';
  feature.method = 'aes-256-gcm';
  feature.route = ROUTE_BYPASS_CHINA;
  feature.ipv6 = true;
  feature.metered = true;
  feature.udpdns = true;
  feature.proxyAppsEnabled = true;
  feature.proxyAppsBypass = true;
  feature.proxyAppsList = 'com.example.one\ncom.example.two';
  feature.remoteDns = '9.9.9.9';
  // These two are never inherited.
  feature.plugin = 'obfs-local';
  feature.pluginOpts = 'obfs=tls';
  return feature;
}

/** The export text, or a failure when the export returned null. */
function exportText(entries: Profile[] | null, sip008: boolean = false): string {
  const text = exportProfiles(entries, sip008);
  if (text === null) {
    throw new Error('exportProfiles returned null');
  }
  return text;
}

/** The exported entries, parsed back for assertions. */
function exportEntries(entries: Profile[], sip008: boolean = false): ProfileJson[] {
  return JSON.parse(exportText(entries, sip008)) as ProfileJson[];
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

/** A parsed URL, or a failure when the URL did not parse. */
function parsedUrl(url: string, feature: Profile | null): Profile {
  const parsed = Profile.parseUrl(url, feature);
  if (parsed === null) {
    throw new Error('URL did not parse');
  }
  return parsed;
}

/** The JSON of one entry with a valid server and the text appended. */
function serverEntry(body: string): string {
  return '{"server":"a.example","server_port":8388,"password":"pw",' +
    `"method":"aes-256-gcm"${body}}`;
}

export default function parityU04Test() {
  describe('U04', () => {
    it('U04#jsonImportInheritsFeatureSettings', 0, () => {
      const feature = featureProfile();
      const parsed = parseProfileDocument(
        serverEntry(',"remarks":"Imported"'), feature);
      expect(parsed.length).assertEqual(1);
      const imported = parsed[0];
      expect(imported.route).assertEqual(ROUTE_BYPASS_CHINA);
      expect(imported.ipv6).assertTrue();
      expect(imported.metered).assertTrue();
      expect(imported.udpdns).assertTrue();
      expect(imported.proxyAppsEnabled).assertTrue();
      expect(imported.proxyAppsBypass).assertTrue();
      expect(imported.proxyAppsList).assertEqual('com.example.one\ncom.example.two');
      // remote_dns, the plugin and the name are never inherited
      expect(imported.remoteDns).assertEqual(DEFAULT_REMOTE_DNS);
      expect(imported.plugin).assertEqual('');
      expect(imported.pluginOpts).assertEqual('');
      expect(imported.name).assertEqual('Imported');
    });

    it('U04#jsonImportOverridesInheritedSettings', 0, () => {
      const feature = featureProfile();
      const parsed = parseProfileDocument(
        serverEntry(',"route":"gfwlist","ipv6":false,"metered":"yes",' +
          '"remote_dns":"1.1.1.1",' +
          '"proxy_apps":{"enabled":true,"bypass":false,' +
          '"android_list":["new.one","new.two"]}'), feature);
      expect(parsed.length).assertEqual(1);
      const imported = parsed[0];
      // a JSON boolean and a JSON route replace the inherited values
      expect(imported.route).assertEqual(ROUTE_GFWLIST);
      expect(imported.ipv6).assertFalse();
      expect(imported.proxyAppsEnabled).assertTrue();
      expect(imported.proxyAppsBypass).assertFalse();
      expect(imported.proxyAppsList).assertEqual('new.one\nnew.two');
      expect(imported.remoteDns).assertEqual('1.1.1.1');
      // a non-boolean value and a missing field keep the inherited values
      expect(imported.metered).assertTrue();
      expect(imported.udpdns).assertTrue();

      // an empty route keeps the inherited route
      const emptyRoute = parseProfileDocument(serverEntry(',"route":""'), feature);
      expect(emptyRoute[0].route).assertEqual(ROUTE_BYPASS_CHINA);
    });

    it('U04#jsonImportUsesDefaultsWithoutSelectedProfile', 0, () => {
      const parsed = parseProfileDocument(serverEntry(''), null);
      expect(parsed.length).assertEqual(1);
      const imported = parsed[0];
      expect(imported.route).assertEqual(ROUTE_ALL);
      expect(imported.ipv6).assertFalse();
      expect(imported.metered).assertFalse();
      expect(imported.udpdns).assertFalse();
      expect(imported.proxyAppsEnabled).assertFalse();
      expect(imported.proxyAppsBypass).assertFalse();
      expect(imported.proxyAppsList).assertEqual('');
      expect(imported.remoteDns).assertEqual(DEFAULT_REMOTE_DNS);
      expect(imported.plugin).assertEqual('');
      // without remarks the address is the name
      expect(imported.name).assertEqual('a.example');
    });

    it('U04#jsonImportReadsProxyApps', 0, () => {
      const parsed = parseProfileDocument(
        serverEntry(',"proxy_apps":{"enabled":true,"bypass":true,' +
          '"android_list":["com.a","com.b","com.a","","  com.c  ",7]}'), null);
      expect(parsed.length).assertEqual(1);
      const imported = parsed[0];
      expect(imported.proxyAppsEnabled).assertTrue();
      expect(imported.proxyAppsBypass).assertTrue();
      // blank lines and duplicates are dropped, and so are non-string items
      expect(imported.proxyAppsList).assertEqual('com.a\ncom.b\ncom.c');

      // a disabled block ignores the bypass flag and the list
      const disabled = parseProfileDocument(
        serverEntry(',"proxy_apps":{"enabled":false,"bypass":true,' +
          '"android_list":["com.a"]}'), null);
      expect(disabled[0].proxyAppsEnabled).assertFalse();
      expect(disabled[0].proxyAppsBypass).assertFalse();
      expect(disabled[0].proxyAppsList).assertEqual('');

      // a non-boolean enabled value keeps the inherited flag
      const inherited = new Profile();
      inherited.proxyAppsEnabled = true;
      const kept = parseProfileDocument(
        serverEntry(',"proxy_apps":{"enabled":"on","android_list":["com.z"]}'), inherited);
      expect(kept[0].proxyAppsEnabled).assertTrue();
      expect(kept[0].proxyAppsList).assertEqual('com.z');

      // the Android list round trips through the export
      const roundTrip = parseProfileDocument(exportText([imported]), null);
      expect(roundTrip.length).assertEqual(1);
      expect(roundTrip[0].proxyAppsEnabled).assertTrue();
      expect(roundTrip[0].proxyAppsBypass).assertTrue();
      expect(roundTrip[0].proxyAppsList).assertEqual('com.a\ncom.b\ncom.c');
    });

    it('U04#importsFallbackAsSecondProfile', 0, () => {
      const parsed = parseProfileDocument(
        serverEntry(',"remarks":"Main","udp_fallback":' +
          '{"server":"b.example","server_port":443,"password":"pw2",' +
          '"method":"chacha20-ietf-poly1305","remarks":"Fallback",' +
          '"plugin":"obfs-local","plugin_opts":"obfs=tls"}'), null);
      expect(parsed.length).assertEqual(2);
      const main = parsed[0];
      const fallback = parsed[1];
      expect(main.name).assertEqual('Main');
      expect(fallback.host).assertEqual('b.example');
      expect(fallback.remotePort).assertEqual(443);
      expect(fallback.password).assertEqual('pw2');
      expect(fallback.method).assertEqual('chacha20-ietf-poly1305');
      expect(fallback.name).assertEqual('Fallback');
      expect(fallback.plugin).assertEqual('obfs-local');
      expect(fallback.pluginOpts).assertEqual('obfs=tls');
      expect(fallback.remoteDns).assertEqual(DEFAULT_REMOTE_DNS);
      expect(fallback.udpFallbackId).assertEqual('');
      expect(main.udpFallbackId).assertEqual(fallback.id);
      expect(main.id.length > 0).assertTrue();
      expect(fallback.id.length > 0).assertTrue();
      expect(main.id === fallback.id).assertFalse();

      // a fallback that fails validation is ignored
      const alone = parseProfileDocument(
        serverEntry(',"udp_fallback":{"server":"b.example"}'), null);
      expect(alone.length).assertEqual(1);
      expect(alone[0].udpFallbackId).assertEqual('');
    });

    it('U04#fallbackReadsOnlyPluginRemarksAndRoute', 0, () => {
      const parsed = parseProfileDocument(
        serverEntry(',"remarks":"Main","ipv6":false,"metered":false,' +
          '"udpdns":false,"remote_dns":"1.1.1.1","route":"all",' +
          '"proxy_apps":{"enabled":false,"bypass":false,"android_list":["ignored"]},' +
          '"udp_fallback":{"server":"b.example","server_port":443,"password":"pw2",' +
          '"method":"chacha20-ietf-poly1305","remarks":"Fallback",' +
          '"route":"gfwlist","plugin":"v2ray-plugin",' +
          '"plugin_opts":"mode=websocket","remote_dns":"1.1.1.1","ipv6":false,' +
          '"metered":false,"udpdns":false,' +
          '"proxy_apps":{"enabled":false,"bypass":false,"android_list":["ignored"]}}'),
        featureProfile());
      expect(parsed.length).assertEqual(2);
      const fallback = parsed[1];
      // a fallback reads the plugin, the remarks and the route
      expect(fallback.plugin).assertEqual('v2ray-plugin');
      expect(fallback.pluginOpts).assertEqual('mode=websocket');
      expect(fallback.name).assertEqual('Fallback');
      expect(fallback.route).assertEqual(ROUTE_GFWLIST);
      // it reads no remote_dns, no boolean and no proxy_apps
      expect(fallback.remoteDns).assertEqual(DEFAULT_REMOTE_DNS);
      expect(fallback.ipv6).assertTrue();
      expect(fallback.metered).assertTrue();
      expect(fallback.udpdns).assertTrue();
      expect(fallback.proxyAppsEnabled).assertTrue();
      expect(fallback.proxyAppsBypass).assertTrue();
      expect(fallback.proxyAppsList).assertEqual('com.example.one\ncom.example.two');
    });

    it('U04#fallbackReusesStoredProfile', 0, () => {
      const stored = profile('b.example', 443, 'Stored fallback');
      stored.id = 'stored-fallback';
      stored.password = 'pw2';
      stored.method = 'chacha20-ietf-poly1305';
      stored.plugin = '';
      stored.userOrder = 5;
      const imported = parseProfileDocument(
        serverEntry(',"remarks":"Main","udp_fallback":' +
          '{"server":"b.example","server_port":443,"password":"pw2",' +
          '"method":"chacha20-ietf-poly1305"}'), null);
      const result = applyImport([stored], imported, false);
      // the imported fallback row is dropped and its main points at the stored row
      expect(result.length).assertEqual(2);
      expect(result[0].id).assertEqual('stored-fallback');
      expect(result[1].host).assertEqual('a.example');
      expect(result[1].udpFallbackId).assertEqual('stored-fallback');
      expect(result[1].userOrder).assertEqual(6);
      expect(result.filter((entry: Profile) => entry.id === 'stored-fallback').length)
        .assertEqual(1);
    });

    it('U04#fallbackIsCreatedWhenNoStoredMatch', 0, () => {
      const stored = profile('b.example', 443, 'Stored');
      stored.id = 'stored';
      stored.password = 'different';
      stored.plugin = '';
      stored.userOrder = 4;
      const imported = parseProfileDocument(
        serverEntry(',"udp_fallback":' +
          '{"server":"b.example","server_port":443,"password":"pw2",' +
          '"method":"chacha20-ietf-poly1305"}'), null);
      const result = applyImport([stored], imported, false);
      expect(result.length).assertEqual(3);
      const main = result[1];
      const fallback = result[2];
      expect(fallback.host).assertEqual('b.example');
      expect(fallback.password).assertEqual('pw2');
      expect(main.udpFallbackId).assertEqual(fallback.id);
      expect(main.userOrder).assertEqual(5);
      expect(fallback.userOrder).assertEqual(6);

      // a stored profile with a plugin is not a fallback match
      const plugged = profile('b.example', 443, 'Plugged');
      plugged.id = 'plugged';
      plugged.password = 'pw2';
      plugged.method = 'chacha20-ietf-poly1305';
      plugged.plugin = 'obfs-local';
      plugged.userOrder = 1;
      const second = applyImport([plugged], imported, false);
      expect(second.length).assertEqual(3);
      expect(second[1].udpFallbackId === 'plugged').assertFalse();
    });

    it('U04#exportWritesAndroidJsonShape', 0, () => {
      const main = profile('a.example', 8388, 'Main');
      main.id = 'main-1';
      main.plugin = 'obfs-local';
      main.pluginOpts = 'obfs=tls';
      main.route = ROUTE_BYPASS_CHINA;
      main.remoteDns = '9.9.9.9';
      main.ipv6 = true;
      main.metered = true;
      main.udpdns = true;
      main.proxyAppsEnabled = true;
      main.proxyAppsBypass = true;
      main.proxyAppsList = 'com.a\ncom.b';
      const fallback = profile('b.example', 443, 'Fallback');
      fallback.id = 'fallback-1';
      fallback.password = 'pw2';
      fallback.method = 'chacha20-ietf-poly1305';
      main.udpFallbackId = 'fallback-1';

      const text = exportText([main, fallback]);
      const entries = JSON.parse(text) as ProfileJson[];
      expect(entries.length).assertEqual(2);
      const entry = entries[0];
      expect(entry.server).assertEqual('a.example');
      expect(entry.server_port).assertEqual(8388);
      expect(entry.password).assertEqual('pw');
      expect(entry.method).assertEqual('aes-256-gcm');
      expect(entry.plugin).assertEqual('obfs-local');
      expect(entry.plugin_opts).assertEqual('obfs=tls');
      expect(entry.remarks).assertEqual('Main');
      expect(entry.route).assertEqual(ROUTE_BYPASS_CHINA);
      expect(entry.remote_dns).assertEqual('9.9.9.9');
      expect(entry.ipv6).assertTrue();
      expect(entry.metered).assertTrue();
      expect(entry.udpdns).assertTrue();
      const apps = proxyAppsOf(entry);
      expect(apps.enabled).assertTrue();
      expect(apps.bypass).assertTrue();
      expect(apps.android_list).assertEqual(['com.a', 'com.b']);
      const nested = fallbackOf(entry);
      expect(nested.server).assertEqual('b.example');
      expect(nested.server_port).assertEqual(443);
      expect(nested.password).assertEqual('pw2');
      expect(nested.method).assertEqual('chacha20-ietf-poly1305');
      // two-space indentation, as shadowsocks-android writes it
      expect(text.indexOf('\n  {') >= 0).assertTrue();
    });

    it('U04#exportOmitsPluginFieldsWithoutPlugin', 0, () => {
      const plain = profile('a.example', 8388, 'Plain');
      const entry = exportEntries([plain])[0];
      expect(entry.plugin === undefined).assertTrue();
      expect(entry.plugin_opts === undefined).assertTrue();
      // the four SIP008 fields are always present
      expect(entry.server).assertEqual('a.example');
      expect(entry.server_port).assertEqual(8388);
      expect(entry.password).assertEqual('pw');
      expect(entry.method).assertEqual('aes-256-gcm');
    });

    it('U04#exportOmitsFallbackWithPlugin', 0, () => {
      const main = profile('a.example', 8388, 'Main');
      main.id = 'main';
      const fallback = profile('b.example', 443, 'Fallback');
      fallback.id = 'fallback';
      fallback.plugin = 'obfs-local';
      main.udpFallbackId = 'fallback';
      const entry = exportEntries([main, fallback])[0];
      expect(entry.udp_fallback === undefined).assertTrue();

      // an obsolete fallback is not active, so it is not written either
      const secondMain = profile('c.example', 8388, 'Second');
      secondMain.id = 'second-main';
      const obsolete = profile('d.example', 443, 'Obsolete');
      obsolete.id = 'obsolete';
      obsolete.subscriptionStatus = STATUS_OBSOLETE;
      secondMain.udpFallbackId = 'obsolete';
      const entries = exportEntries([secondMain, obsolete]);
      expect(entries.length).assertEqual(1);
      expect(entries[0].udp_fallback === undefined).assertTrue();
    });

    it('U04#exportSkipsObsoleteProfiles', 0, () => {
      const active = profile('a.example', 8388, 'Active');
      const obsolete = profile('b.example', 443, 'Obsolete');
      obsolete.subscriptionStatus = STATUS_OBSOLETE;
      const entries = exportEntries([active, obsolete]);
      expect(entries.length).assertEqual(1);
      expect(entries[0].server).assertEqual('a.example');
    });

    it('U04#exportReturnsNullForNullList', 0, () => {
      expect(exportProfiles(null)).assertEqual(null);
      expect(exportProfiles(null, true)).assertEqual(null);
      expect(exportProfiles([])).assertEqual('[]');
    });

    it('U04#clipboardTextJoinsUrlsWithNewlines', 0, () => {
      const first = profile('a.example', 8388, 'First');
      const second = profile('b.example', 443, 'Second');
      const obsolete = profile('c.example', 1080, 'Old');
      obsolete.subscriptionStatus = STATUS_OBSOLETE;
      const text = exportProfileUrls([first, obsolete, second]);
      expect(text).assertEqual(`${first.toUri()}\n${second.toUri()}`);
      expect(text.split('\n').length).assertEqual(2);
    });

    it('U04#clipboardTextOfOneProfileHasNoNewline', 0, () => {
      const one = profile('a.example', 8388, 'One');
      const text = exportProfileUrls([one]);
      expect(text).assertEqual(one.toUri());
      expect(text.indexOf('\n')).assertEqual(-1);
    });

    it('U04#malformedJsonDocumentThrows', 0, () => {
      let objectThrew = false;
      try {
        parseProfileDocument('{"server":"a.example",', null);
      } catch (e) {
        objectThrew = true;
      }
      expect(objectThrew).assertTrue();

      let arrayThrew = false;
      try {
        parseProfileDocument('[{"server":"a.example" "server_port":8388}]', null);
      } catch (e) {
        arrayThrew = true;
      }
      expect(arrayThrew).assertTrue();
    });

    it('U04#collectKeepsProfilesBeforeBadDocument', 0, () => {
      const goodJson = serverEntry('');
      const urlText = profile('c.example', 443, 'Third').toUri();
      const batch = collectProfiles([goodJson, '{"server":', urlText], null);
      expect(batch.profiles.length).assertEqual(2);
      expect(batch.profiles[0].host).assertEqual('a.example');
      expect(batch.profiles[1].host).assertEqual('c.example');
      expect(batch.error.length > 0).assertTrue();

      // a document with no profile is not an error
      const quiet = collectProfiles([goodJson, 'not a profile'], null);
      expect(quiet.profiles.length).assertEqual(1);
      expect(quiet.error).assertEqual('');
    });

    it('U04#collectKeepsFirstError', 0, () => {
      const firstBad = '{"server":';
      const secondBad = '[1,';
      let firstMessage = '';
      try {
        JSON.parse(firstBad);
      } catch (e) {
        firstMessage = (e as Error).message;
      }
      const batch = collectProfiles([firstBad, secondBad], null);
      expect(batch.profiles.length).assertEqual(0);
      expect(batch.error.length > 0).assertTrue();
      expect(batch.error).assertEqual(firstMessage);
    });

    it('U04#replaceWithNoProfilesKeepsList', 0, () => {
      const first = profile('a.example', 8388, 'First');
      first.id = 'first';
      first.userOrder = 1;
      const second = profile('b.example', 443, 'Second');
      second.id = 'second';
      second.userOrder = 2;
      const existing = [first, second];

      const result = applyImport(existing, [], true);
      expect(result.length).assertEqual(2);
      expect(result[0]).assertEqual(first);
      expect(result[1]).assertEqual(second);
      expect(existing.length).assertEqual(2);

      const appended = applyImport(existing, [], false);
      expect(appended.length).assertEqual(2);
    });

    it('U04#replaceKeepsCountersForSameAddress', 0, () => {
      const stored = profile('a.example', 8388, 'Mine');
      stored.id = 'kept';
      stored.password = 'old-pw';
      stored.tx = 1000;
      stored.rx = 2048;
      stored.userOrder = 7;
      const gone = profile('b.example', 443, 'Gone');
      gone.id = 'gone';
      gone.userOrder = 8;
      const replacement = profile('a.example', 8388, 'Imported name');

      const result = applyImport([stored, gone], [replacement], true);
      expect(result.length).assertEqual(1);
      expect(result[0].id).assertEqual('kept');
      expect(result[0].tx).assertEqual(1000);
      expect(result[0].rx).assertEqual(2048);
      // the name the user gave the row stays
      expect(result[0].name).assertEqual('Mine');
      expect(result[0].userOrder).assertEqual(1);
      // the transport fields come from the import
      expect(result[0].password).assertEqual('pw');

      // an address that is not stored keeps its own identity
      const added = applyImport([stored], [profile('c.example', 443, 'New')], true);
      expect(added.length).assertEqual(1);
      expect(added[0].host).assertEqual('c.example');
      expect(added[0].id === 'kept').assertFalse();
    });

    it('U04#clipboardTextWithoutUrlsYieldsNoProfiles', 0, () => {
      expect(parseProfilesText('', null).length).assertEqual(0);
      expect(parseProfilesText('not a profile at all', null).length).assertEqual(0);
      expect(parseProfilesText('{"hello":"world"}', null).length).assertEqual(0);
      expect(parseProfilesText('https://example.com/subscription', null).length).assertEqual(0);
    });

    it('U04#clipboardTextKeepsValidUrlBesideBadOne', 0, () => {
      const good = profile('a.example', 8388, 'Good').toUri();
      const parsed = parseProfilesText(`ss://bad%%%\n${good}\nss://`, null);
      expect(parsed.length).assertEqual(1);
      expect(parsed[0].host).assertEqual('a.example');
      expect(parsed[0].name).assertEqual('Good');
    });

    it('U04#jsonArrayOfNumbersYieldsNoProfiles', 0, () => {
      expect(parseProfileDocument('[1,2,3]', null).length).assertEqual(0);
      expect(parseProfileDocument('[]', null).length).assertEqual(0);
      expect(parseProfileDocument('{"hello":"world"}', null).length).assertEqual(0);
      expect(parseProfilesText('[1,2,3]', null).length).assertEqual(0);
    });

    it('U04#manualSeedCopiesFeatureSettings', 0, () => {
      const feature = featureProfile();
      const manual = newManualProfile(feature);
      expect(manual.host).assertEqual('example.shadowsocks.org');
      expect(manual.remotePort).assertEqual(8388);
      expect(manual.method).assertEqual('aes-256-gcm');
      expect(manual.password).assertEqual('u1rRWTssNv0p');
      expect(manual.name).assertEqual('');
      expect(manual.id.length > 0).assertTrue();
      expect(manual.route).assertEqual(ROUTE_BYPASS_CHINA);
      expect(manual.ipv6).assertTrue();
      expect(manual.metered).assertTrue();
      expect(manual.udpdns).assertTrue();
      expect(manual.proxyAppsEnabled).assertTrue();
      expect(manual.proxyAppsBypass).assertTrue();
      expect(manual.proxyAppsList).assertEqual('com.example.one\ncom.example.two');

      const plain = newManualProfile(null);
      expect(plain.route).assertEqual(ROUTE_ALL);
      expect(plain.ipv6).assertFalse();
      expect(plain.metered).assertFalse();
      expect(plain.udpdns).assertFalse();
      expect(plain.proxyAppsEnabled).assertFalse();
      expect(plain.proxyAppsBypass).assertFalse();
      expect(plain.proxyAppsList).assertEqual('');

      // a null feature leaves the target as it is
      const target = new Profile();
      target.route = ROUTE_GFWLIST;
      target.ipv6 = true;
      copyFeatureSettings(null, target);
      expect(target.route).assertEqual(ROUTE_GFWLIST);
      expect(target.ipv6).assertTrue();
    });

    it('U04#urlImportCopiesFeatureSettings', 0, () => {
      const feature = featureProfile();
      const named = profile('a.example', 8388, 'Named');
      named.plugin = 'v2ray-plugin';
      named.pluginOpts = 'mode=websocket';

      const imported = parsedUrl(named.toUri(), feature);
      expect(imported.route).assertEqual(ROUTE_BYPASS_CHINA);
      expect(imported.ipv6).assertTrue();
      expect(imported.metered).assertTrue();
      expect(imported.udpdns).assertTrue();
      expect(imported.proxyAppsEnabled).assertTrue();
      expect(imported.proxyAppsBypass).assertTrue();
      expect(imported.proxyAppsList).assertEqual('com.example.one\ncom.example.two');
      // the URL owns the transport fields, the plugin and the name
      expect(imported.host).assertEqual('a.example');
      expect(imported.remotePort).assertEqual(8388);
      expect(imported.password).assertEqual('pw');
      expect(imported.method).assertEqual('aes-256-gcm');
      expect(imported.plugin).assertEqual('v2ray-plugin');
      expect(imported.pluginOpts).assertEqual('mode=websocket');
      expect(imported.name).assertEqual('Named');

      // a URL without a name takes its host and not the selected name
      const bare = parsedUrl(profile('b.example', 443, '').toUri(), feature);
      expect(bare.name).assertEqual('b.example');

      // the import path applies the same copy
      const fromText = parseProfilesText(named.toUri(), feature);
      expect(fromText.length).assertEqual(1);
      expect(fromText[0].route).assertEqual(ROUTE_BYPASS_CHINA);
      expect(fromText[0].ipv6).assertTrue();
    });

    it('U04#lenientParseKeepsSubscriptionBehavior', 0, () => {
      // malformed JSON: the lenient parser still finds the URL in it
      const broken = '{"servers": [\nss://YWVzLTI1Ni1nY206cHc@a.example:8388#A\n}';
      const fromBroken = parseProfilesText(broken, null);
      expect(fromBroken.length).assertEqual(1);
      expect(fromBroken[0].host).assertEqual('a.example');
      // the strict parser reports the same text as a syntax error
      let threw = false;
      try {
        parseProfileDocument(broken, null);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();

      const sip008 = '{"servers":[{"server":"b.example","server_port":443,' +
        '"password":"pw","method":"chacha20-ietf-poly1305","remarks":"B"}]}';
      const fromJson = parseProfilesText(sip008, null);
      expect(fromJson.length).assertEqual(1);
      expect(fromJson[0].name).assertEqual('B');

      const encoded = Profile.encodeBase64(
        Profile.encodeUtf8('ss://YWVzLTI1Ni1nY206cHc@c.example:8388#C'), false, true);
      const fromBase64 = parseProfilesText(encoded, null);
      expect(fromBase64.length).assertEqual(1);
      expect(fromBase64[0].host).assertEqual('c.example');

      expect(parseProfilesText('{"server":', null).length).assertEqual(0);
      expect(parseProfilesText('', null).length).assertEqual(0);
    });

    it('U04#jsonImportSkipsBadPort', 0, () => {
      const text = '[' +
        '{"server":"zero.example","server_port":0,"password":"pw",' +
        '"method":"aes-256-gcm"},' +
        '{"server":"high.example","server_port":65536,"password":"pw",' +
        '"method":"aes-256-gcm"},' +
        '{"server":"negative.example","server_port":-1,"password":"pw",' +
        '"method":"aes-256-gcm"},' +
        '{"server":"text.example","server_port":"abc","password":"pw",' +
        '"method":"aes-256-gcm"},' +
        '{"server":"fraction.example","server_port":8388.5,"password":"pw",' +
        '"method":"aes-256-gcm"},' +
        '{"server":"string.example","server_port":"8388","password":"pw",' +
        '"method":"aes-256-gcm"},' +
        '{"server":"number.example","server_port":443,"password":"pw",' +
        '"method":"aes-256-gcm"}' +
        ']';
      const parsed = parseProfileDocument(text, null);
      expect(parsed.length).assertEqual(2);
      expect(parsed[0].host).assertEqual('string.example');
      expect(parsed[0].remotePort).assertEqual(8388);
      expect(parsed[1].host).assertEqual('number.example');
      expect(parsed[1].remotePort).assertEqual(443);

      // an entry that misses a required field is skipped too
      const incomplete = parseProfileDocument(
        '[{"server":"a.example","server_port":8388,"password":"",' +
          '"method":"aes-256-gcm"}]', null);
      expect(incomplete.length).assertEqual(0);
    });

    it('U04#storeReadsNewFieldsWithDefaults', 0, () => {
      const before = ProfileStore.fromJson(
        JSON.parse('{"id":"old","host":"a.example"}') as Profile);
      expect(before.metered).assertFalse();
      expect(before.proxyAppsEnabled).assertFalse();
      expect(before.proxyAppsBypass).assertFalse();
      expect(before.proxyAppsList).assertEqual('');

      const storedText = '{"id":"new","host":"b.example","metered":true,' +
        '"proxyAppsEnabled":true,"proxyAppsBypass":true,' +
        '"proxyAppsList":"com.a\\ncom.b"}';
      const stored = ProfileStore.fromJson(JSON.parse(storedText) as Profile);
      expect(stored.metered).assertTrue();
      expect(stored.proxyAppsEnabled).assertTrue();
      expect(stored.proxyAppsBypass).assertTrue();
      expect(stored.proxyAppsList).assertEqual('com.a\ncom.b');

      // a null value takes the default
      const nulled = ProfileStore.fromJson(
        JSON.parse('{"metered":null,"proxyAppsList":null}') as Profile);
      expect(nulled.metered).assertFalse();
      expect(nulled.proxyAppsList).assertEqual('');
    });
  });
}
