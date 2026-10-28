import { describe, expect, it } from '@ohos/hypium';
import { Profile } from '../main/ets/model/Profile';
import { ProfileStore } from '../main/ets/model/ProfileStore';
import {
  ProfileJson, ProxyAppsJson, exportProfiles, profileFromJson,
} from '../main/ets/model/ProfilesFile';
import {
  APP_MODE_BYPASS, APP_MODE_OFF, APP_MODE_ON, AppEntry, MAX_APP_LIST, PerAppDraft, PerAppState,
  applyToAll, appMode, exportText, isValidBundleName, joinNames, matchesQuery, namesOf,
  parseImportText, selectionCap, sortEntries, toggleName, visibleEntries, vpnApplicationLists,
} from '../main/ets/model/PerApp';

/** The bundle name of the client under test. */
const CLIENT = 'com.xbt.project';

/** An app row whose label is the bundle name, as the picker shows it. */
function row(bundleName: string): AppEntry {
  return { bundleName: bundleName, label: bundleName };
}

/** A profile with the fields an export needs. */
function serverProfile(host: string): Profile {
  const profile = new Profile();
  profile.host = host;
  profile.password = 'pw';
  profile.method = 'aes-256-gcm';
  return profile;
}

/** The state an import text gives. The helper throws for an empty text. */
function importState(text: string): PerAppState {
  const state = parseImportText(text);
  if (state === null) {
    throw new Error(`expected an import state for ${JSON.stringify(text)}`);
  }
  return state;
}

/** The exported entries. The helper throws when the export returns no text. */
function exportedEntries(profiles: Profile[], sip008: boolean = false): ProfileJson[] {
  const text = exportProfiles(profiles, sip008);
  if (text === null) {
    throw new Error('the export returned no text');
  }
  return JSON.parse(text) as ProfileJson[];
}

/** The profile a JSON record gives. The helper throws for a rejected record. */
function parsedProfile(json: string): Profile {
  const record = JSON.parse(json) as Record<string, Object>;
  const profile = profileFromJson(record, null);
  if (profile === null) {
    throw new Error('the record did not parse as a profile');
  }
  return profile;
}

export default function parityU07Test() {
  describe('ParityU07Test', () => {
    it('U07#opening-forces-mode-on', 0, () => {
      // A profile with Apps VPN mode off opens, and the page turns the mode on.
      const off = new Profile();
      off.proxyAppsEnabled = false;
      off.proxyAppsList = '';
      PerAppDraft.open(off);
      expect(PerAppDraft.dirty).assertFalse();
      PerAppDraft.ensureEnabled();
      expect(PerAppDraft.enabled).assertTrue();
      expect(PerAppDraft.dirty).assertTrue();
      expect(appMode(PerAppDraft.enabled, PerAppDraft.bypass)).assertEqual(APP_MODE_ON);

      // A profile with the mode on keeps its flags and stays clean.
      const on = new Profile();
      on.proxyAppsEnabled = true;
      on.proxyAppsBypass = true;
      on.proxyAppsList = 'com.example.a';
      PerAppDraft.open(on);
      PerAppDraft.ensureEnabled();
      expect(PerAppDraft.enabled).assertTrue();
      expect(PerAppDraft.bypass).assertTrue();
      expect(PerAppDraft.dirty).assertFalse();
      expect(appMode(PerAppDraft.enabled, PerAppDraft.bypass)).assertEqual(APP_MODE_BYPASS);
    });

    it('U07#mode-group-exclusive', 0, () => {
      const stored = new Profile();
      stored.proxyAppsEnabled = true;
      stored.proxyAppsBypass = true;
      stored.proxyAppsList = 'com.example.a\ncom.example.b';
      PerAppDraft.open(stored);

      PerAppDraft.setMode(APP_MODE_ON);
      expect(PerAppDraft.enabled).assertTrue();
      expect(PerAppDraft.bypass).assertFalse();
      expect(PerAppDraft.list).assertEqual('com.example.a\ncom.example.b');

      PerAppDraft.setMode(APP_MODE_BYPASS);
      expect(PerAppDraft.enabled).assertTrue();
      expect(PerAppDraft.bypass).assertTrue();
      expect(PerAppDraft.list).assertEqual('com.example.a\ncom.example.b');

      PerAppDraft.setMode(APP_MODE_ON);
      expect(PerAppDraft.enabled).assertTrue();
      expect(PerAppDraft.bypass).assertFalse();
      expect(PerAppDraft.list).assertEqual('com.example.a\ncom.example.b');

      // A mode the group does not offer changes nothing.
      PerAppDraft.setMode('unknown');
      expect(PerAppDraft.enabled).assertTrue();
      expect(PerAppDraft.bypass).assertFalse();
    });

    it('U07#mode-off-keeps-bypass-and-list', 0, () => {
      const stored = new Profile();
      stored.proxyAppsEnabled = true;
      stored.proxyAppsBypass = true;
      stored.proxyAppsList = 'com.example.a\ncom.example.b';
      PerAppDraft.open(stored);

      PerAppDraft.setMode(APP_MODE_OFF);
      const state = PerAppDraft.state();
      expect(state.enabled).assertFalse();
      expect(state.bypass).assertTrue();
      expect(state.list).assertEqual('com.example.a\ncom.example.b');
      expect(appMode(state.enabled, state.bypass)).assertEqual(APP_MODE_OFF);
    });

    it('U07#mode-start-from-stored-flags', 0, () => {
      const pairs: boolean[][] = [[false, false], [false, true], [true, false], [true, true]];
      const expected: string[] = [APP_MODE_OFF, APP_MODE_OFF, APP_MODE_ON, APP_MODE_BYPASS];
      for (let i = 0; i < pairs.length; i++) {
        const stored = new Profile();
        stored.proxyAppsEnabled = pairs[i][0];
        stored.proxyAppsBypass = pairs[i][1];
        PerAppDraft.open(stored);
        expect(PerAppDraft.dirty).assertFalse();
        expect(appMode(PerAppDraft.enabled, PerAppDraft.bypass)).assertEqual(expected[i]);
      }
    });

    it('U07#toggle-adds-and-removes-name', 0, () => {
      let list = '';
      list = toggleName(list, 'com.example.a');
      expect(list).assertEqual('com.example.a');
      list = toggleName(list, 'com.example.b');
      expect(list).assertEqual('com.example.a\ncom.example.b');
      // A second tap on the same name removes it.
      list = toggleName(list, 'com.example.a');
      expect(list).assertEqual('com.example.b');
    });

    it('U07#list-round-trips-newline-joined', 0, () => {
      expect(namesOf('com.example.a\n\n com.example.b \ncom.example.a'))
        .assertEqual(['com.example.a', 'com.example.b']);
      expect(joinNames(['com.example.a', 'com.example.b']))
        .assertEqual('com.example.a\ncom.example.b');
      expect(namesOf('')).assertEqual([]);
      expect(joinNames([])).assertEqual('');
      expect(joinNames(namesOf(''))).assertEqual('');
    });

    it('U07#search-matches-label-and-bundle', 0, () => {
      const camera: AppEntry = { bundleName: 'com.example.camera', label: 'Camera' };
      const mail: AppEntry = { bundleName: 'com.example.mail', label: 'Mail' };
      // The query matches the label and the bundle name, and ignores case.
      expect(matchesQuery(camera, 'Cam')).assertTrue();
      expect(matchesQuery(camera, 'cam')).assertTrue();
      expect(matchesQuery(camera, 'com.example.camera')).assertTrue();
      expect(matchesQuery(camera, 'mail')).assertFalse();
      expect(visibleEntries([camera, mail], 'cam')).assertEqual([camera]);
      expect(visibleEntries([camera, mail], 'example')).assertEqual([camera, mail]);
    });

    it('U07#search-empty-lists-every-entry', 0, () => {
      const entries: AppEntry[] = [
        row('com.example.a'), row('com.example.b'), row('com.example.c'),
      ];
      expect(visibleEntries(entries, '')).assertEqual(entries);
      expect(visibleEntries(entries, '   ')).assertEqual(entries);
    });

    it('U07#sort-selected-first-then-label', 0, () => {
      const alpha = row('com.example.alpha');
      const mail = row('com.example.mail');
      const zebra = row('com.example.zebra');
      const input: AppEntry[] = [alpha, mail, zebra];

      const sorted = sortEntries(input, 'com.example.zebra');
      expect(sorted.map((item: AppEntry) => item.bundleName))
        .assertEqual(['com.example.zebra', 'com.example.alpha', 'com.example.mail']);
      // The stored order and the input array do not change.
      expect(input.map((item: AppEntry) => item.bundleName))
        .assertEqual(['com.example.alpha', 'com.example.mail', 'com.example.zebra']);
    });

    it('U07#toggle-keeps-visible-order', 0, () => {
      const camera = row('com.example.camera');
      const mail = row('com.example.mail');
      const zebra = row('com.example.zebra');
      const entries: AppEntry[] = sortEntries([camera, mail, zebra], 'com.example.zebra');
      expect(entries.map((item: AppEntry) => item.bundleName))
        .assertEqual(['com.example.zebra', 'com.example.camera', 'com.example.mail']);

      // A row tap appends the name to the stored list and does not re-sort.
      const next = toggleName('com.example.zebra', 'com.example.camera');
      expect(next).assertEqual('com.example.zebra\ncom.example.camera');
      expect(namesOf(next).indexOf('com.example.camera') >= 0).assertTrue();
      expect(namesOf(next).indexOf('com.example.zebra') >= 0).assertTrue();
      // The visible array keeps the order it had. Only the selected set changes.
      expect(visibleEntries(entries, '').map((item: AppEntry) => item.bundleName))
        .assertEqual(['com.example.zebra', 'com.example.camera', 'com.example.mail']);
      // A second tap removes the name and keeps the others in order.
      expect(toggleName(next, 'com.example.zebra')).assertEqual('com.example.camera');
    });

    it('U07#export-flag-and-list', 0, () => {
      expect(exportText(true, 'com.example.a\ncom.example.b'))
        .assertEqual('true\ncom.example.a\ncom.example.b');
      expect(exportText(false, '')).assertEqual('false\n');
    });

    it('U07#import-splits-flag-and-names', 0, () => {
      const bypass = importState('true\ncom.example.a\ncom.example.b');
      expect(bypass.enabled).assertTrue();
      expect(bypass.bypass).assertTrue();
      expect(bypass.list).assertEqual('com.example.a\ncom.example.b');

      const on = importState('false\ncom.example.a');
      expect(on.enabled).assertTrue();
      expect(on.bypass).assertFalse();
      expect(on.list).assertEqual('com.example.a');

      // The flag letter case does not matter.
      expect(importState('TRUE\ncom.example.a').bypass).assertTrue();
    });

    it('U07#import-without-newline-clears-list', 0, () => {
      const bypass = importState('true');
      expect(bypass.bypass).assertTrue();
      expect(bypass.list).assertEqual('');
      const on = importState('false');
      expect(on.bypass).assertFalse();
      expect(on.list).assertEqual('');
    });

    it('U07#import-empty-changes-nothing', 0, () => {
      expect(parseImportText('')).assertEqual(null);
    });

    it('U07#import-dedupes-and-trims', 0, () => {
      const state = importState(
        'true\n com.example.a \n\n com.example.a \ncom.example.b');
      expect(state.bypass).assertTrue();
      expect(state.list).assertEqual('com.example.a\ncom.example.b');
    });

    it('U07#draft-survives-until-save', 0, () => {
      const stored = new Profile();
      stored.proxyAppsEnabled = false;
      stored.proxyAppsList = '';

      PerAppDraft.open(stored);
      PerAppDraft.ensureEnabled();
      PerAppDraft.setList('com.example.a');
      expect(PerAppDraft.dirty).assertTrue();
      expect(PerAppDraft.snapshot()).assertEqual('1|0|com.example.a');

      // A discard clears the draft. The stored profile did not change.
      PerAppDraft.clear();
      PerAppDraft.open(stored);
      expect(PerAppDraft.enabled).assertFalse();
      expect(PerAppDraft.list).assertEqual('');
      expect(PerAppDraft.dirty).assertFalse();

      // A save copies the draft to the profile and then clears the draft.
      PerAppDraft.ensureEnabled();
      PerAppDraft.setList('com.example.a');
      stored.proxyAppsEnabled = PerAppDraft.enabled;
      stored.proxyAppsBypass = PerAppDraft.bypass;
      stored.proxyAppsList = PerAppDraft.list;
      PerAppDraft.clear();
      PerAppDraft.open(stored);
      expect(PerAppDraft.enabled).assertTrue();
      expect(PerAppDraft.list).assertEqual('com.example.a');
      expect(PerAppDraft.dirty).assertFalse();
    });

    it('U07#apply-to-all-copies-and-keeps-enabled', 0, () => {
      const on = new Profile();
      on.proxyAppsEnabled = true;
      on.proxyAppsBypass = false;
      on.proxyAppsList = 'com.example.old';
      const off = new Profile();
      off.proxyAppsEnabled = false;
      off.proxyAppsBypass = false;
      off.proxyAppsList = '';
      const profiles: Profile[] = [on, off];

      const result = applyToAll(profiles, true, 'com.example.a\ncom.example.b');
      // The action returns the same array. The caller saves it.
      expect(result === profiles).assertTrue();
      expect(result[0].proxyAppsEnabled).assertTrue();
      expect(result[0].proxyAppsBypass).assertTrue();
      expect(result[0].proxyAppsList).assertEqual('com.example.a\ncom.example.b');
      // The enabled flag does not change.
      expect(result[1].proxyAppsEnabled).assertFalse();
      expect(result[1].proxyAppsBypass).assertTrue();
      expect(result[1].proxyAppsList).assertEqual('com.example.a\ncom.example.b');

      // The list takes the normalized form before the copy.
      applyToAll(profiles, false, ' com.example.a \n\n com.example.a \ncom.example.b');
      expect(result[1].proxyAppsBypass).assertFalse();
      expect(result[1].proxyAppsList).assertEqual('com.example.a\ncom.example.b');
    });

    it('U07#vpn-lists-mode-off-empty', 0, () => {
      const lists = vpnApplicationLists(false, false, 'com.example.a', CLIENT);
      expect(lists.trusted.length).assertEqual(0);
      expect(lists.blocked.length).assertEqual(0);
      // The bypass flag does not matter when the mode is off.
      const bypass = vpnApplicationLists(false, true, 'com.example.a', CLIENT);
      expect(bypass.trusted.length).assertEqual(0);
      expect(bypass.blocked.length).assertEqual(0);
    });

    it('U07#vpn-lists-on-trusted', 0, () => {
      const lists = vpnApplicationLists(true, false, 'com.example.a\ncom.example.b', CLIENT);
      expect(lists.trusted).assertEqual(['com.example.a', 'com.example.b']);
      expect(lists.blocked.length).assertEqual(0);
      // The client bundle never enters the trusted list.
      const withClient = vpnApplicationLists(true, false, `${CLIENT}\ncom.example.a`, CLIENT);
      expect(withClient.trusted).assertEqual(['com.example.a']);
      expect(withClient.blocked.length).assertEqual(0);
    });

    it('U07#vpn-lists-on-empty-adds-none', 0, () => {
      const lists = vpnApplicationLists(true, false, '', CLIENT);
      expect(lists.trusted.length).assertEqual(0);
      expect(lists.blocked.length).assertEqual(0);
    });

    it('U07#vpn-lists-bypass-blocks-list-and-client', 0, () => {
      const lists = vpnApplicationLists(true, true, 'com.example.a', CLIENT);
      expect(lists.trusted.length).assertEqual(0);
      expect(lists.blocked).assertEqual([CLIENT, 'com.example.a']);
      // A stored client name is not repeated.
      const repeated = vpnApplicationLists(true, true, `${CLIENT}\ncom.example.a`, CLIENT);
      expect(repeated.blocked).assertEqual([CLIENT, 'com.example.a']);
    });

    it('U07#vpn-lists-bypass-empty-blocks-client', 0, () => {
      const lists = vpnApplicationLists(true, true, '', CLIENT);
      expect(lists.trusted.length).assertEqual(0);
      expect(lists.blocked).assertEqual([CLIENT]);
      // With no client name there is no blocked entry, and every app uses the VPN.
      const anonymous = vpnApplicationLists(true, true, '', '');
      expect(anonymous.blocked.length).assertEqual(0);
    });

    it('U07#vpn-lists-cap-at-64', 0, () => {
      const names: string[] = [];
      for (let i = 0; i < 70; i++) {
        names.push(`com.example.app${i}`);
      }
      const list = names.join('\n');
      expect(MAX_APP_LIST).assertEqual(64);

      const on = vpnApplicationLists(true, false, list, CLIENT);
      expect(on.trusted.length).assertEqual(64);
      expect(on.trusted[0]).assertEqual('com.example.app0');
      expect(on.trusted[63]).assertEqual('com.example.app63');
      expect(on.blocked.length).assertEqual(0);

      // Bypass blocks the client first, so 63 names fit beside it.
      const bypass = vpnApplicationLists(true, true, list, CLIENT);
      expect(bypass.trusted.length).assertEqual(0);
      expect(bypass.blocked.length).assertEqual(64);
      expect(bypass.blocked[0]).assertEqual(CLIENT);
      expect(bypass.blocked[1]).assertEqual('com.example.app0');
      expect(bypass.blocked[63]).assertEqual('com.example.app62');

      expect(selectionCap(false)).assertEqual(64);
      expect(selectionCap(true)).assertEqual(63);
    });

    it('U07#proxy-apps-json-on-export', 0, () => {
      const enabled = serverProfile('a.example');
      enabled.proxyAppsEnabled = true;
      enabled.proxyAppsBypass = true;
      enabled.proxyAppsList = 'com.example.a';

      // The disabled profile carries values, but the export must not write them.
      const disabled = serverProfile('b.example');
      disabled.proxyAppsEnabled = false;
      disabled.proxyAppsBypass = true;
      disabled.proxyAppsList = 'com.example.b';

      const entries = exportedEntries([enabled, disabled]);
      expect(entries.length).assertEqual(2);

      const first = entries[0].proxy_apps as ProxyAppsJson;
      expect(first.enabled).assertTrue();
      expect(first.bypass).assertTrue();
      expect(first.android_list).assertEqual(['com.example.a']);

      const second = entries[1].proxy_apps as ProxyAppsJson;
      expect(second.enabled).assertFalse();
      expect(second.bypass === undefined).assertTrue();
      expect(second.android_list === undefined).assertTrue();
      expect(JSON.stringify(second)).assertEqual('{"enabled":false}');

      // The SIP008 export defines four fields only, so it carries no block.
      const sip008 = exportedEntries([enabled], true);
      expect(sip008[0].proxy_apps === undefined).assertTrue();
    });

    it('U07#proxy-apps-json-on-import', 0, () => {
      const enabled = parsedProfile('{"server":"a.example","server_port":8388,' +
        '"password":"pw","method":"aes-256-gcm","proxy_apps":{"enabled":true,' +
        '"bypass":true,"android_list":["com.example.a","com.example.b"]}}');
      expect(enabled.proxyAppsEnabled).assertTrue();
      expect(enabled.proxyAppsBypass).assertTrue();
      expect(enabled.proxyAppsList).assertEqual('com.example.a\ncom.example.b');

      // A disabled block ignores the names.
      const disabled = parsedProfile('{"server":"b.example","server_port":8388,' +
        '"password":"pw","method":"aes-256-gcm","proxy_apps":{"enabled":false,' +
        '"android_list":["com.example.c"]}}');
      expect(disabled.proxyAppsEnabled).assertFalse();
      expect(disabled.proxyAppsList).assertEqual('');

      // An absent block leaves the defaults.
      const absent = parsedProfile('{"server":"c.example","server_port":8388,' +
        '"password":"pw","method":"aes-256-gcm"}');
      expect(absent.proxyAppsEnabled).assertFalse();
      expect(absent.proxyAppsBypass).assertFalse();
      expect(absent.proxyAppsList).assertEqual('');
    });

    it('U07#bundle-name-validation', 0, () => {
      expect(isValidBundleName('com.example.a')).assertTrue();
      expect(isValidBundleName('')).assertFalse();
      expect(isValidBundleName('com example')).assertFalse();
      expect(isValidBundleName('com')).assertFalse();
      expect(isValidBundleName('.a')).assertFalse();
      expect(isValidBundleName('a..b')).assertFalse();
      // A segment starts with a letter. Digits and underscores follow it.
      expect(isValidBundleName('a.b_1')).assertTrue();
      expect(isValidBundleName('1a.b')).assertFalse();
      expect(isValidBundleName('a.1b')).assertFalse();
      // The total length stops at 128.
      const longName = `a.${'b'.repeat(126)}`;
      expect(longName.length).assertEqual(128);
      expect(isValidBundleName(longName)).assertTrue();
      expect(isValidBundleName(`${longName}b`)).assertFalse();
    });

    it('U07#profile-store-round-trips-per-app-fields', 0, () => {
      const stored = new Profile();
      stored.id = 'kept';
      stored.proxyAppsEnabled = true;
      stored.proxyAppsBypass = true;
      stored.proxyAppsList = 'com.example.a\ncom.example.b';

      const loaded = ProfileStore.fromJson(stored);
      expect(loaded.proxyAppsEnabled).assertTrue();
      expect(loaded.proxyAppsBypass).assertTrue();
      expect(loaded.proxyAppsList).assertEqual('com.example.a\ncom.example.b');

      // A record written before the fields existed takes the defaults.
      const legacy = ProfileStore.fromJson(JSON.parse('{"id":"old","name":"Old",' +
        '"host":"example.com","remotePort":8388,"password":"pw",' +
        '"method":"aes-256-gcm"}') as Profile);
      expect(legacy.proxyAppsEnabled).assertFalse();
      expect(legacy.proxyAppsBypass).assertFalse();
      expect(legacy.proxyAppsList).assertEqual('');
    });
  });
}
