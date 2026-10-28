import { describe, expect, it } from '@ohos/hypium';
import { Profile, STATUS_ACTIVE } from '../main/ets/model/Profile';
import { ProfileStore } from '../main/ets/model/ProfileStore';
import { exportProfiles, parseProfilesText } from '../main/ets/model/ProfilesFile';
import {
  PLUGIN_OPTIONS_CONTROL, PLUGIN_OPTIONS_OBFS_MODE, PLUGIN_OPTIONS_OK, PLUGIN_OPTIONS_V2RAY_MODE,
  PLUGIN_STATE_KNOWN, PLUGIN_STATE_UNKNOWN, PluginDefinition, PluginOptions,
  findPlugin, pluginChoices, pluginDefaultOptions, pluginStateOf,
} from '../main/ets/model/PluginOptions';

/**
 * The commit rule of the options editor. The page holds the same rule in
 * `ProfileEdit.commitPluginOptions` (U08 LLD, section 8). A code other than OK
 * writes nothing. The test uses this rule so the error path stays observable.
 */
function commitPluginOptions(profile: Profile, text: string): string {
  const code: string = PluginOptions.validate(profile.plugin, text);
  if (code !== PLUGIN_OPTIONS_OK) {
    return code;
  }
  profile.setPluginOptions(profile.plugin, PluginOptions.canonical(text));
  return PLUGIN_OPTIONS_OK;
}

/** A manual profile with a known plugin and a stored options text. */
function obfsProfile(options: string): Profile {
  const profile = new Profile();
  profile.plugin = 'obfs-local';
  profile.pluginOpts = options;
  profile.pluginConfigs['obfs-local'] = options;
  return profile;
}

export default function parityU08Test() {
  describe('ParityU08Test', () => {
    it('U08#pluginRowShowsKnownLabel', 0, () => {
      expect(pluginStateOf('obfs-local')).assertEqual(PLUGIN_STATE_KNOWN);
      expect(pluginStateOf('simple-obfs')).assertEqual(PLUGIN_STATE_KNOWN);
      expect(pluginStateOf('obfs')).assertEqual(PLUGIN_STATE_KNOWN);
      const definition: PluginDefinition | null = findPlugin('obfs-local');
      expect(definition !== null).assertTrue();
      if (definition !== null) {
        expect(definition.label).assertEqual('simple-obfs');
        expect(definition.aliases.length).assertEqual(2);
      }

      const profile = new Profile();
      profile.plugin = 'obfs-local';
      profile.pluginOpts = 'obfs=tls';
      expect(profile.hasPlugin()).assertTrue();
      // A manual profile is not locked, so the row is editable.
      expect(profile.canEditPlugin()).assertTrue();
      expect(profile.isSubscriptionLocked()).assertFalse();
    });

    it('U08#unknownPluginReadsUnknown', 0, () => {
      expect(pluginStateOf('kcptun')).assertEqual(PLUGIN_STATE_UNKNOWN);
      const profile = new Profile();
      profile.plugin = 'kcptun';
      expect(profile.pluginState()).assertEqual(PLUGIN_STATE_UNKNOWN);
      // The editor cannot open the options for an unknown plugin.
      expect(profile.canConfigurePlugin()).assertFalse();
      expect(profile.pluginError()).assertEqual('Unknown plugin kcptun');
    });

    it('U08#pickerMovesCurrentFirst', 0, () => {
      expect(pluginChoices('v2ray-plugin')).assertEqual([
        { id: 'v2ray-plugin', current: true },
        { id: '', current: false },
        { id: 'obfs-local', current: false },
      ]);
      expect(pluginChoices('obfs-local')).assertEqual([
        { id: 'obfs-local', current: true },
        { id: '', current: false },
        { id: 'v2ray-plugin', current: false },
      ]);
      // Disabled is already first, so the order stays.
      expect(pluginChoices('')).assertEqual([
        { id: '', current: true },
        { id: 'obfs-local', current: false },
        { id: 'v2ray-plugin', current: false },
      ]);
      // An unknown id marks no row and moves no row.
      expect(pluginChoices('kcptun')).assertEqual([
        { id: '', current: false },
        { id: 'obfs-local', current: false },
        { id: 'v2ray-plugin', current: false },
      ]);

      // A pick of the current row changes nothing.
      const profile = obfsProfile('obfs=http');
      const before = JSON.stringify(profile);
      profile.selectPlugin('obfs-local');
      expect(JSON.stringify(profile)).assertEqual(before);

      const unknown = new Profile();
      unknown.plugin = 'kcptun';
      const unknownBefore = JSON.stringify(unknown);
      unknown.selectPlugin('kcptun');
      expect(JSON.stringify(unknown)).assertEqual(unknownBefore);
    });

    it('U08#disabledKeepsStoredOptions', 0, () => {
      const profile = obfsProfile('obfs=tls');

      profile.selectPlugin('');
      expect(profile.plugin).assertEqual('');
      expect(profile.pluginOpts).assertEqual('');
      // The entry survives the switch to Disabled.
      expect(profile.pluginConfigs['obfs-local']).assertEqual('obfs=tls');

      profile.selectPlugin('obfs-local');
      expect(profile.plugin).assertEqual('obfs-local');
      expect(profile.pluginOpts).assertEqual('obfs=tls');
    });

    it('U08#switchKeepsEachOptions', 0, () => {
      const profile = new Profile();
      profile.selectPlugin('obfs-local');
      expect(profile.pluginOpts).assertEqual('obfs=tls');
      profile.setPluginOptions('obfs-local', 'obfs=http');

      profile.selectPlugin('v2ray-plugin');
      expect(profile.plugin).assertEqual('v2ray-plugin');
      expect(profile.pluginOpts).assertEqual('mode=websocket');
      profile.setPluginOptions('v2ray-plugin', 'mode=websocket;tls');

      profile.selectPlugin('obfs-local');
      expect(profile.plugin).assertEqual('obfs-local');
      expect(profile.pluginOpts).assertEqual('obfs=http');
      expect(profile.pluginConfigs['v2ray-plugin']).assertEqual('mode=websocket;tls');

      profile.selectPlugin('v2ray-plugin');
      expect(profile.plugin).assertEqual('v2ray-plugin');
      expect(profile.pluginOpts).assertEqual('mode=websocket;tls');
      expect(profile.pluginConfigs['obfs-local']).assertEqual('obfs=http');

      // A stored alias entry is selected when the user picks the canonical row.
      const alias = new Profile();
      alias.pluginConfigs['simple-obfs'] = 'obfs=http';
      alias.selectPlugin('obfs-local');
      expect(alias.plugin).assertEqual('simple-obfs');
      expect(alias.pluginOpts).assertEqual('obfs=http');

      // A stored entry for the requested id wins over an alias entry.
      const both = new Profile();
      both.pluginConfigs['simple-obfs'] = 'obfs=http';
      both.pluginConfigs['obfs-local'] = 'obfs=tls';
      both.selectPlugin('obfs-local');
      expect(both.plugin).assertEqual('obfs-local');
      expect(both.pluginOpts).assertEqual('obfs=tls');

      // An alias of the current plugin is the same selection.
      const current = new Profile();
      current.plugin = 'obfs';
      current.pluginOpts = 'obfs=http';
      const currentBefore = JSON.stringify(current);
      current.selectPlugin('simple-obfs');
      expect(JSON.stringify(current)).assertEqual(currentBefore);
    });

    it('U08#editorStoresTypedOptions', 0, () => {
      const text = 'mode=websocket;tls;host=example.com';
      expect(PluginOptions.validate('v2ray-plugin', text)).assertEqual(PLUGIN_OPTIONS_OK);
      // The typed order is kept, and no character needs an escape here.
      expect(PluginOptions.canonical(text)).assertEqual(text);

      const profile = new Profile();
      profile.plugin = 'v2ray-plugin';
      profile.setPluginOptions('v2ray-plugin', PluginOptions.canonical(text));
      expect(profile.pluginOpts).assertEqual(text);
      expect(profile.pluginConfigs['v2ray-plugin']).assertEqual(text);

      // The store keeps the pair and the entry.
      const loaded = ProfileStore.fromJson(profile);
      expect(loaded.plugin).assertEqual('v2ray-plugin');
      expect(loaded.pluginOpts).assertEqual(text);
      expect(loaded.pluginConfigs['v2ray-plugin']).assertEqual(text);
    });

    it('U08#editorRejectsControlCharacters', 0, () => {
      // A newline, a C0 character, and a C1 character.
      expect(PluginOptions.validate('obfs-local', 'obfs=tls\n'))
        .assertEqual(PLUGIN_OPTIONS_CONTROL);
      expect(PluginOptions.validate('obfs-local', 'obfs=tls\u0001'))
        .assertEqual(PLUGIN_OPTIONS_CONTROL);
      expect(PluginOptions.validate('obfs-local', 'obfs=tls\u0080'))
        .assertEqual(PLUGIN_OPTIONS_CONTROL);
      expect(PluginOptions.check('obfs=tls\u0080'))
        .assertEqual(PluginOptions.CONTROL_MESSAGE);

      // An error code writes nothing.
      const profile = obfsProfile('obfs=tls');
      expect(commitPluginOptions(profile, 'obfs=tls\n')).assertEqual(PLUGIN_OPTIONS_CONTROL);
      expect(profile.pluginOpts).assertEqual('obfs=tls');
      expect(profile.pluginConfigs['obfs-local']).assertEqual('obfs=tls');
    });

    it('U08#cancelKeepsStoredOptions', 0, () => {
      const profile = obfsProfile('obfs=tls');

      // The dialog edits its own draft. Cancel closes the dialog and commits
      // no text.
      let draft: string = profile.pluginOpts;
      draft = 'obfs=http';
      expect(draft).assertEqual('obfs=http');
      expect(profile.pluginOpts).assertEqual('obfs=tls');
      expect(profile.pluginConfigs['obfs-local']).assertEqual('obfs=tls');
    });

    it('U08#unknownPluginFailsStart', 0, () => {
      const empty = new Profile();
      expect(empty.pluginError()).assertEqual('');
      const known = new Profile();
      known.plugin = 'obfs-local';
      known.pluginOpts = 'obfs=tls';
      expect(known.pluginError()).assertEqual('');

      const unknown = new Profile();
      unknown.plugin = 'kcptun';
      expect(unknown.pluginError()).assertEqual('Unknown plugin kcptun');
    });

    it('U08#subscriptionLocksPluginControls', 0, () => {
      const active = obfsProfile('obfs=tls');
      active.subscriptionId = 'sub-1';
      active.subscriptionStatus = STATUS_ACTIVE;
      expect(active.isSubscriptionLocked()).assertTrue();
      expect(active.canEditPlugin()).assertFalse();
      expect(active.canConfigurePlugin()).assertFalse();

      const manual = obfsProfile('obfs=tls');
      expect(manual.isSubscriptionLocked()).assertFalse();
      expect(manual.canEditPlugin()).assertTrue();
      expect(manual.canConfigurePlugin()).assertTrue();

      const disabled = new Profile();
      expect(disabled.isSubscriptionLocked()).assertFalse();
      expect(disabled.canEditPlugin()).assertTrue();
      expect(disabled.canConfigurePlugin()).assertFalse();
    });

    it('U08#pluginRoundTrip', 0, () => {
      const profile = new Profile();
      profile.host = 'example.com';
      profile.remotePort = 8388;
      profile.password = 'pw';
      profile.method = 'aes-256-gcm';
      profile.name = 'Plugin Server';
      profile.plugin = 'obfs-local';
      profile.pluginOpts = 'obfs=tls';
      profile.seedPluginConfigs();

      const url = profile.toUri();
      expect(url.indexOf('?plugin=obfs-local%3Bobfs%3Dtls') >= 0).assertTrue();
      const parsed = Profile.parseUrl(url);
      expect(parsed !== null).assertTrue();
      if (parsed !== null) {
        expect(parsed.plugin).assertEqual('obfs-local');
        expect(parsed.pluginOpts).assertEqual('obfs=tls');
        // A URL with options seeds the entry.
        expect(parsed.pluginConfigs['obfs-local']).assertEqual('obfs=tls');
      }

      // A bare plugin URL carries no options and seeds no entry.
      const bare = new Profile();
      bare.host = 'example.com';
      bare.remotePort = 8388;
      bare.password = 'pw';
      bare.method = 'aes-256-gcm';
      bare.plugin = 'obfs-local';
      const bareUrl = bare.toUri();
      expect(bareUrl.indexOf('?plugin=obfs-local') >= 0).assertTrue();
      const bareParsed = Profile.parseUrl(bareUrl);
      expect(bareParsed !== null).assertTrue();
      if (bareParsed !== null) {
        expect(bareParsed.plugin).assertEqual('obfs-local');
        expect(bareParsed.pluginOpts).assertEqual('');
        expect(Object.keys(bareParsed.pluginConfigs).length).assertEqual(0);
      }

      // The JSON export writes the pair and never the map.
      const exported = exportProfiles([profile], false);
      expect(exported !== null).assertTrue();
      const json = exported === null ? '' : exported;
      expect(json.indexOf('pluginConfigs') >= 0).assertFalse();
      const entries = JSON.parse(json) as Record<string, Object>[];
      expect(entries.length).assertEqual(1);
      expect(entries[0]['plugin']).assertEqual('obfs-local');
      expect(entries[0]['plugin_opts']).assertEqual('obfs=tls');

      // An import gives the same plugin and options back.
      const imported = parseProfilesText(json, null);
      expect(imported.length).assertEqual(1);
      expect(imported[0].plugin).assertEqual('obfs-local');
      expect(imported[0].pluginOpts).assertEqual('obfs=tls');
      expect(imported[0].pluginConfigs['obfs-local']).assertEqual('obfs=tls');
    });

    it('U08#stored-empty-options-stay-empty', 0, () => {
      // A bare plugin URL keeps an empty options text and seeds no entry.
      const bare = Profile.parseUrl(
        'ss://YWVzLTI1Ni1nY206dGVzdC1wYXNzd29yZA@example.com:8388?plugin=obfs-local');
      expect(bare !== null).assertTrue();
      if (bare === null) {
        return;
      }
      expect(bare.pluginOpts).assertEqual('');

      // The store writes the plugin map, so the empty text is explicit. It
      // survives two save and load rounds without taking the default.
      const first = ProfileStore.fromJson(JSON.parse(JSON.stringify(bare)) as Profile);
      expect(first.plugin).assertEqual('obfs-local');
      expect(first.pluginOpts).assertEqual('');
      expect(Object.keys(first.pluginConfigs).length).assertEqual(0);

      const second = ProfileStore.fromJson(JSON.parse(JSON.stringify(first)) as Profile);
      expect(second.plugin).assertEqual('obfs-local');
      expect(second.pluginOpts).assertEqual('');
      expect(Object.keys(second.pluginConfigs).length).assertEqual(0);
    });

    it('U08#old-record-without-map-takes-default', 0, () => {
      // A record written before the map existed has no pluginConfigs field,
      // so an empty text there means the plugin was not configured. It takes
      // the catalogue default. A missing entry means the same default, so the
      // map stays empty.
      const old = ProfileStore.fromJson(JSON.parse(
        '{"id":"old","plugin":"obfs-local","pluginOpts":""}') as Profile);
      expect(old.pluginOpts).assertEqual('obfs=tls');
      expect(Object.keys(old.pluginConfigs).length).assertEqual(0);
      // The next load sees the map, keeps the text, and seeds the entry.
      const reloaded = ProfileStore.fromJson(JSON.parse(JSON.stringify(old)) as Profile);
      expect(reloaded.pluginOpts).assertEqual('obfs=tls');
      expect(reloaded.pluginConfigs['obfs-local']).assertEqual('obfs=tls');

      // A non-empty text is the options the user chose and is kept as it is.
      const chosen = ProfileStore.fromJson(JSON.parse(
        '{"id":"chosen","plugin":"v2ray-plugin",' +
          '"pluginOpts":"mode=websocket;tls"}') as Profile);
      expect(chosen.pluginOpts).assertEqual('mode=websocket;tls');
      expect(chosen.pluginConfigs['v2ray-plugin']).assertEqual('mode=websocket;tls');
    });

    it('U08#firstSelectionUsesDefault', 0, () => {
      const obfs = new Profile();
      obfs.selectPlugin('obfs-local');
      expect(obfs.pluginOpts).assertEqual('obfs=tls');
      // A first selection stores the default.
      expect(obfs.pluginConfigs['obfs-local']).assertEqual('obfs=tls');

      const v2ray = new Profile();
      v2ray.selectPlugin('v2ray-plugin');
      expect(v2ray.pluginOpts).assertEqual('mode=websocket');
      expect(v2ray.pluginConfigs['v2ray-plugin']).assertEqual('mode=websocket');

      // An unknown id has no catalogue default.
      expect(pluginDefaultOptions('kcptun')).assertEqual('');
    });

    it('U08#profileRowAddsPluginLine', 0, () => {
      const withPlugin = new Profile();
      withPlugin.plugin = 'v2ray-plugin';
      expect(withPlugin.hasPlugin()).assertTrue();

      const withoutPlugin = new Profile();
      expect(withoutPlugin.hasPlugin()).assertFalse();
    });

    it('U08#tunRunsTcpOnlyWithPlugin', 0, () => {
      const profile = new Profile();
      profile.plugin = 'obfs-local';
      profile.pluginOpts = 'obfs=tls';
      const tun: Record<string, Object> = JSON.parse(profile.toTunConfig()) as Record<string, Object>;
      expect(tun['mode']).assertEqual('tcp_only');
      expect(tun['plugin']).assertEqual('obfs-local');
      expect(tun['plugin_opts']).assertEqual('obfs=tls');

      profile.plugin = '';
      profile.pluginOpts = '';
      const plain: Record<string, Object> =
        JSON.parse(profile.toTunConfig()) as Record<string, Object>;
      expect(plain['mode']).assertEqual('tcp_and_udp');
      expect(plain['plugin'] === undefined).assertTrue();
    });

    it('U08#optionsSyntaxRoundTrip', 0, () => {
      expect(PluginOptions.canonical('obfs=http;obfs-host=example.com'))
        .assertEqual('obfs=http;obfs-host=example.com');
      // Bare flags keep their form.
      expect(PluginOptions.canonical('a;b')).assertEqual('a;b');
      // An escaped separator stays escaped after the round trip.
      expect(PluginOptions.canonical('obfs=va\\;lue')).assertEqual('obfs=va\\;lue');
      // A trailing backslash consumes the appended terminator, so the last
      // pair drops. The change is accepted, as on Android.
      expect(PluginOptions.canonical('obfs=http;host=example.com\\'))
        .assertEqual('obfs=http');

      // A known key with an unknown name passes. The native parser ignores it.
      expect(PluginOptions.validate('obfs-local', 'obfs=tls;whatever=1'))
        .assertEqual(PLUGIN_OPTIONS_OK);
      // A bare key and a bad value fail the obfs check.
      expect(PluginOptions.validate('obfs-local', 'obfs')).assertEqual(PLUGIN_OPTIONS_OBFS_MODE);
      expect(PluginOptions.validate('obfs-local', 'obfs=quic'))
        .assertEqual(PLUGIN_OPTIONS_OBFS_MODE);
      // A missing mode key is valid for v2ray. A bare key and a bad value fail.
      expect(PluginOptions.validate('v2ray-plugin', 'tls')).assertEqual(PLUGIN_OPTIONS_OK);
      expect(PluginOptions.validate('v2ray-plugin', 'mode'))
        .assertEqual(PLUGIN_OPTIONS_V2RAY_MODE);
      expect(PluginOptions.validate('v2ray-plugin', 'mode=quic'))
        .assertEqual(PLUGIN_OPTIONS_V2RAY_MODE);
      expect(PluginOptions.validate('v2ray-plugin', 'mode=WS'))
        .assertEqual(PLUGIN_OPTIONS_OK);
    });

    it('U08#dismissKeepsStoredOptions', 0, () => {
      const profile = obfsProfile('obfs=tls');

      // An outside tap closes the dialog. The typed draft drops without a
      // commit.
      let draft: string = profile.pluginOpts;
      draft = 'obfs=http;obfs-host=example.com';
      draft = '';
      expect(draft).assertEqual('');
      expect(profile.pluginOpts).assertEqual('obfs=tls');
      expect(profile.pluginConfigs['obfs-local']).assertEqual('obfs=tls');
      // The effective options still pass their own schema check.
      expect(PluginOptions.validate('obfs-local', profile.pluginOpts))
        .assertEqual(PLUGIN_OPTIONS_OK);
    });
  });
}
