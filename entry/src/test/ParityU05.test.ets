import { describe, expect, it } from '@ohos/hypium';
import {
  DEFAULT_REMOTE_DNS, Profile, STATUS_ACTIVE, STATUS_OBSOLETE, STATUS_USER_CONFIGURED,
} from '../main/ets/model/Profile';
import {
  Subscription, SubscriptionEditResult, SubscriptionParseError, SubscriptionStore,
  addSubscriptionUrl, compareSubscriptionUrls, editResult, findSubscriptionByUrl,
  mergeSubscriptionRun, parseSubscriptionBody, parseSubscriptionUrl, replaceSubscriptionUrl,
  restoreSubscriptions, sortSubscriptions, validateSubscriptionUrl,
} from '../main/ets/model/Subscription';
import { SubscriptionRefreshRun } from '../main/ets/model/SubscriptionRefresh';
import { ROUTE_CHINA_LIST, ROUTE_GFWLIST } from '../main/ets/model/Routes';

/** The owning subscription of every helper profile unless a test says otherwise. */
const SUB: string = 'sub-1';

/** A stored subscription record with this URL. */
function record(url: string, id: string = '', updatedAt: number = 0): Subscription {
  const subscription = new Subscription();
  subscription.id = id;
  subscription.url = url;
  subscription.updatedAt = updatedAt;
  return subscription;
}

/** The URLs of a subscription list, in list order. */
function urlsOf(list: Subscription[]): string[] {
  return list.map((subscription: Subscription): string => subscription.url);
}

/** A stored profile with this name, address and subscription state. */
function stored(name: string, host: string, port: number, status: number,
  subscriptionId: string = SUB): Profile {
  const profile = new Profile();
  profile.id = `${host}-${port}`;
  profile.name = name;
  profile.host = host;
  profile.remotePort = port;
  profile.password = 'old-password';
  profile.method = 'aes-256-gcm';
  profile.subscriptionId = subscriptionId;
  profile.subscriptionStatus = status;
  return profile;
}

/** An incoming profile as a body parser builds it. */
function incoming(name: string, host: string, port: number,
  subscriptionId: string = SUB): Profile {
  const profile = new Profile();
  profile.id = `${host}-${port}`;
  profile.name = name;
  profile.host = host;
  profile.remotePort = port;
  profile.password = 'new-password';
  profile.method = 'chacha20-ietf-poly1305';
  profile.subscriptionId = subscriptionId;
  return profile;
}

/** A SIP002 `ss://` URL with this transport and name. */
function ssUrl(host: string, port: number, method: string, password: string,
  name: string): string {
  const userInfo = Profile.encodeBase64(Profile.encodeUtf8(`${method}:${password}`), true, false);
  return `ss://${userInfo}@${host}:${port}#${Profile.percentEncode(name)}`;
}

/** A JSON server entry with the four fields that make one. */
function jsonEntry(host: string, port: number, extra: string = ''): string {
  return `{"server":"${host}","server_port":${port},"password":"pw",` +
    `"method":"aes-256-gcm"${extra}}`;
}

export default function parityU05Test() {
  describe('ParityU05Test', () => {
    it('U05#url-validation-states', 0, () => {
      const refuse = (link: string): boolean => false;

      // Empty text and text without a scheme report the no-protocol state.
      const empty = validateSubscriptionUrl('', refuse);
      expect(empty.valid).assertFalse();
      expect(empty.cleartext).assertFalse();
      expect(empty.scheme).assertEqual('');
      expect(empty.error).assertEqual('no_protocol');

      const blank = validateSubscriptionUrl('   ', refuse);
      expect(blank.valid).assertFalse();
      expect(blank.error).assertEqual('no_protocol');

      const bare = validateSubscriptionUrl('example.com/sub', refuse);
      expect(bare.valid).assertFalse();
      expect(bare.scheme).assertEqual('');
      expect(bare.error).assertEqual('no_protocol');

      // Built-in schemes are valid. The text is trimmed first.
      const https = validateSubscriptionUrl('  https://example.com/sub  ', refuse);
      expect(https.valid).assertTrue();
      expect(https.cleartext).assertFalse();
      expect(https.scheme).assertEqual('https');
      expect(https.error).assertEqual('');

      const upper = validateSubscriptionUrl('HTTPS://EXAMPLE.COM/sub', refuse);
      expect(upper.valid).assertTrue();
      expect(upper.cleartext).assertFalse();
      expect(upper.scheme).assertEqual('https');

      // An empty host after the scheme is valid, as java.net.URL accepts it.
      const hostOnly = validateSubscriptionUrl('http://', refuse);
      expect(hostOnly.valid).assertTrue();
      expect(hostOnly.cleartext).assertTrue();
      expect(hostOnly.scheme).assertEqual('http');
      expect(hostOnly.error).assertEqual('');
    });

    it('U05#cleartext-http-warns-and-passes', 0, () => {
      const refuse = (link: string): boolean => false;
      const http = validateSubscriptionUrl('http://example.com/sub', refuse);
      expect(http.valid).assertTrue();
      expect(http.cleartext).assertTrue();
      expect(http.scheme).assertEqual('http');
      expect(http.error).assertEqual('');

      // The scheme is lower-case, so the warning also applies to upper-case text.
      const upper = validateSubscriptionUrl('HTTP://example.com/sub', refuse);
      expect(upper.valid).assertTrue();
      expect(upper.cleartext).assertTrue();
      expect(upper.scheme).assertEqual('http');

      // Every other built-in scheme is not cleartext.
      const https = validateSubscriptionUrl('https://example.com/sub', refuse);
      expect(https.valid).assertTrue();
      expect(https.cleartext).assertFalse();
      const ftp = validateSubscriptionUrl('ftp://example.com/list', refuse);
      expect(ftp.valid).assertTrue();
      expect(ftp.cleartext).assertFalse();
      const file = validateSubscriptionUrl('file:///sdcard/subscription.json', refuse);
      expect(file.valid).assertTrue();
      expect(file.cleartext).assertFalse();

      // An invalid text carries no cleartext warning.
      const invalid = validateSubscriptionUrl('example.com/sub', refuse);
      expect(invalid.valid).assertFalse();
      expect(invalid.cleartext).assertFalse();
    });

    it('U05#url-scheme-rules', 0, () => {
      // The built-in set answers without a handler query.
      let builtInCalls = 0;
      const refuse = (link: string): boolean => {
        builtInCalls++;
        return false;
      };
      const ftp = validateSubscriptionUrl('ftp://example.com/list', refuse);
      expect(ftp.valid).assertTrue();
      expect(ftp.scheme).assertEqual('ftp');
      const file = validateSubscriptionUrl('file:///sdcard/subscription.json', refuse);
      expect(file.valid).assertTrue();
      expect(file.scheme).assertEqual('file');
      expect(builtInCalls).assertEqual(0);

      // An unknown scheme asks the handler query.
      const foo = validateSubscriptionUrl('foo://example.com', refuse);
      expect(foo.valid).assertFalse();
      expect(foo.scheme).assertEqual('foo');
      expect(foo.error).assertEqual('unknown_protocol');
      expect(builtInCalls).assertEqual(1);

      // A handled scheme passes when the query accepts it.
      let handledCalls = 0;
      const accept = (link: string): boolean => {
        handledCalls++;
        return true;
      };
      const custom = validateSubscriptionUrl('custom://host/path', accept);
      expect(custom.valid).assertTrue();
      expect(custom.cleartext).assertFalse();
      expect(custom.scheme).assertEqual('custom');
      expect(custom.error).assertEqual('');
      expect(handledCalls).assertEqual(1);

      // A throwing handler query reports the unknown protocol.
      const throwing = (link: string): boolean => {
        throw new Error('no handler');
      };
      const thrown = validateSubscriptionUrl('foo://example.com', throwing);
      expect(thrown.valid).assertFalse();
      expect(thrown.error).assertEqual('unknown_protocol');
    });

    it('U05#remove-appears-only-for-a-stored-url', 0, () => {
      // Add mode has no stored URL, so Remove returns no action.
      const onAdd = editResult('remove', 'https://a.example/sub', '');
      expect(onAdd === null).assertTrue();

      // Edit mode returns the stored URL as the record to drop.
      const onEdit = editResult('remove', 'https://a.example/sub', 'https://stored.example/sub');
      expect(onEdit === null).assertFalse();
      if (onEdit !== null) {
        expect(onEdit.edited === null).assertTrue();
        expect(onEdit.replacing).assertEqual('https://stored.example/sub');
      }

      // OK reports the text and the stored URL under edit.
      const okAdd = editResult('ok', ' https://new.example/sub ', '');
      expect(okAdd === null).assertFalse();
      if (okAdd !== null) {
        expect(okAdd.edited).assertEqual(' https://new.example/sub ');
        expect(okAdd.replacing === null).assertTrue();
      }
      const okEdit = editResult('ok', 'https://new.example/sub', 'https://old.example/sub');
      if (okEdit !== null) {
        expect(okEdit.edited).assertEqual('https://new.example/sub');
        expect(okEdit.replacing).assertEqual('https://old.example/sub');
      }
    });

    it('U05#edit-replaces-the-old-url', 0, () => {
      const oldUrl = 'https://old.example/sub';
      const original = record(oldUrl, 'a-id');
      const list = [record('https://b.example/sub', 'b-id'), original];
      const replacement = record('https://new.example/sub', 'a-id');

      const result = replaceSubscriptionUrl(list, oldUrl, replacement);
      expect(result.length).assertEqual(2);
      expect(urlsOf(result)).assertEqual([
        'https://b.example/sub', 'https://new.example/sub',
      ]);
      expect(findSubscriptionByUrl(result, oldUrl) === null).assertTrue();
      expect(findSubscriptionByUrl(result, 'https://new.example/sub')).assertEqual(replacement);

      // The input list is unchanged.
      expect(list.length).assertEqual(2);
      expect(findSubscriptionByUrl(list, oldUrl) !== null).assertTrue();

      // A missing old URL adds the new record.
      const grown = replaceSubscriptionUrl(
        [record('https://a.example/sub', 'a-id')], 'https://missing.example/sub',
        record('https://c.example/sub', 'c-id'));
      expect(grown.length).assertEqual(2);
      expect(findSubscriptionByUrl(grown, 'https://c.example/sub') !== null).assertTrue();
    });

    it('U05#edit-to-an-existing-url-leaves-one-row', 0, () => {
      const kept = record('https://b.example/sub', 'b-id');
      const list = [record('https://a.example/sub', 'a-id'), kept];
      const duplicate = record('https://b.example/sub', 'new-id');

      const result = replaceSubscriptionUrl(list, 'https://a.example/sub', duplicate);
      // The old row is dropped, the existing equal row stays, and the new
      // record is not added a second time.
      expect(result.length).assertEqual(1);
      expect(result[0].id).assertEqual('b-id');
      expect(result[0].url).assertEqual('https://b.example/sub');
    });

    it('U05#remove-result-carries-the-removed-url', 0, () => {
      const storedRecord = record('https://a.example/sub', 'a-id', 42);
      const list = [storedRecord, record('https://b.example/sub', 'b-id')];

      // The dialog text is ignored. The stored URL names the record to drop.
      const answer: SubscriptionEditResult | null =
        editResult('remove', 'https://changed.example/sub', storedRecord.url);
      expect(answer === null).assertFalse();
      if (answer !== null && answer.replacing !== null) {
        expect(answer.edited === null).assertTrue();
        expect(answer.replacing).assertEqual('https://a.example/sub');
        const found = findSubscriptionByUrl(list, answer.replacing);
        expect(found !== null).assertTrue();
        if (found !== null) {
          // The page pushes this record onto the undo window.
          const removed: Subscription[] = [found];
          expect(removed.length).assertEqual(1);
          expect(removed[0].id).assertEqual('a-id');
          expect(removed[0].updatedAt).assertEqual(42);
        }
      }
    });

    it('U05#undo-restores-every-removed-url', 0, () => {
      const a = record('https://a.example/sub', 'a-id');
      const b = record('https://b.example/sub', 'b-id');
      const c = record('https://c.example/sub', 'c-id');

      // Two removals in one window: every URL returns, sorted.
      const restored = restoreSubscriptions([a], [c, b]);
      expect(restored.length).assertEqual(3);
      expect(urlsOf(restored)).assertEqual([
        'https://a.example/sub', 'https://b.example/sub', 'https://c.example/sub',
      ]);

      // A restored record wins over an equal record in the list.
      const stale = record('https://b.example/sub', 'stale-id');
      const winner = record('https://b.example/sub', 'b-id');
      const replaced = restoreSubscriptions([stale, a], [winner]);
      expect(replaced.length).assertEqual(2);
      const found = findSubscriptionByUrl(replaced, 'https://b.example/sub');
      expect(found).assertEqual(winner);
      if (found !== null) {
        expect(found.id).assertEqual('b-id');
      }
    });

    it('U05#stored-list-round-trips-in-url-order', 0, () => {
      const first = record('https://b.example/sub', 'b-id', 2);
      const second = record('ftp://a.example/x', 'a-id', 3);
      const third = record('http://a.example/x?z=1', 'q-id', 4);
      const duplicate = record('https://b.example/sub', 'b2-id', 5);

      // saveAll sorts before the write.
      const written = JSON.stringify(sortSubscriptions([first, second, third, duplicate]));
      const saved = JSON.parse(written) as Subscription[];
      expect(urlsOf(saved)).assertEqual([
        'ftp://a.example/x', 'http://a.example/x?z=1',
        'https://b.example/sub', 'https://b.example/sub',
      ]);

      // The read revives, drops the duplicate and sorts. The last record wins.
      const normalized = SubscriptionStore.normalize(
        saved.map((item: Subscription): Subscription => SubscriptionStore.fromJson(item)));
      expect(normalized.length).assertEqual(3);
      expect(urlsOf(normalized)).assertEqual([
        'ftp://a.example/x', 'http://a.example/x?z=1', 'https://b.example/sub',
      ]);
      expect(normalized[0].id).assertEqual('a-id');
      expect(normalized[0].updatedAt).assertEqual(3);
      expect(normalized[2].id).assertEqual('b2-id');
      expect(normalized[2].updatedAt).assertEqual(5);
    });

    it('U05#stored-unparseable-urls-are-dropped', 0, () => {
      const kept = record('https://a.example/sub', 'a-id', 1);
      const empty = record('', 'empty-id');
      const bare = record('example.com/sub', 'bare-id');

      const normalized = SubscriptionStore.normalize([empty, kept, bare]);
      expect(normalized.length).assertEqual(1);
      expect(normalized[0].url).assertEqual('https://a.example/sub');
      expect(normalized[0].id).assertEqual('a-id');

      // The filter uses the same rule as the URL parser.
      expect(parseSubscriptionUrl('example.com/sub') === null).assertTrue();
      expect(parseSubscriptionUrl('') === null).assertTrue();
      expect(parseSubscriptionUrl('https://a.example/sub') !== null).assertTrue();
    });

    it('U05#rows-sort-by-host-port-file-protocol', 0, () => {
      const list = [
        record('https://b.example/x'),
        record('https://a.example:443/x'),
        record('https://a.example:80/x'),
        record('https://a.example:80/a'),
        record('https://a.example:80/a?b=2'),
        record('https://a.example:80/a?b=1'),
        record('ftp://a.example:80/a?b=1'),
        record('http://a.example:80/a?b=1'),
      ];
      expect(urlsOf(sortSubscriptions(list))).assertEqual([
        'https://a.example:80/a',
        'ftp://a.example:80/a?b=1',
        'http://a.example:80/a?b=1',
        'https://a.example:80/a?b=1',
        'https://a.example:80/a?b=2',
        'https://a.example:80/x',
        'https://a.example:443/x',
        'https://b.example/x',
      ]);

      // Equal URLs keep their input order.
      const stable = sortSubscriptions([
        record('https://c.example/x', 'first-id', 1),
        record('https://c.example/x', 'second-id', 2),
      ]);
      expect(stable[0].id).assertEqual('first-id');
      expect(stable[1].id).assertEqual('second-id');

      // An unparseable URL compares by its raw text.
      expect(compareSubscriptionUrls('zzz', 'aaa') > 0).assertTrue();
      expect(compareSubscriptionUrls('aaa', 'aaa')).assertEqual(0);

      // The parser splits the parts that the order uses.
      const parsed = parseSubscriptionUrl('HTTPS://User@Example.COM:8443/sub?x=1#frag');
      expect(parsed !== null).assertTrue();
      if (parsed !== null) {
        expect(parsed.protocol).assertEqual('https');
        expect(parsed.host).assertEqual('Example.COM');
        expect(parsed.port).assertEqual(8443);
        expect(parsed.file).assertEqual('/sub?x=1');
      }
    });

    it('U05#adding-an-equal-url-changes-nothing', 0, () => {
      const existing = record('https://a.example/sub', 'a-id');
      const list = [existing];

      const added = addSubscriptionUrl(list, record('https://a.example/sub', 'other-id'));
      expect(added.changed).assertFalse();
      expect(added.list.length).assertEqual(1);
      expect(added.list[0].id).assertEqual('a-id');

      // A new URL is appended and sorted.
      const grown = addSubscriptionUrl(list, record('https://b.example/sub', 'b-id'));
      expect(grown.changed).assertTrue();
      expect(urlsOf(grown.list)).assertEqual([
        'https://a.example/sub', 'https://b.example/sub',
      ]);
      expect(list.length).assertEqual(1);
    });

    it('U05#progress-counts-finished-downloads', 0, () => {
      const run = new SubscriptionRefreshRun([
        record('https://a.example/sub', 'a-id'),
        record('https://b.example/sub', 'b-id'),
      ]);
      expect(run.done).assertEqual(0);
      expect(run.outcomes.length).assertEqual(0);
      expect(run.urls.length).assertEqual(2);

      run.recordFetch({ id: 'a-id', body: 'body-a', error: '' });
      expect(run.done).assertEqual(1);
      run.recordFetch({ id: 'b-id', body: '', error: 'network down' });
      expect(run.done).assertEqual(2);
      expect(run.outcomes.length).assertEqual(2);
      expect(run.succeededIds()).assertEqual(['a-id']);
      expect(run.failureCount()).assertEqual(1);

      // A call after the last URL is ignored.
      run.recordFetch({ id: 'c-id', body: 'extra', error: '' });
      expect(run.done).assertEqual(2);
      expect(run.outcomes.length).assertEqual(2);

      run.markFinishing();
      expect(run.finishing).assertTrue();
    });

    it('U05#cancel-before-merge-writes-nothing', 0, () => {
      const run = new SubscriptionRefreshRun([record('https://a.example/sub', 'a-id')]);
      run.requestCancel();
      expect(run.cancelled).assertTrue();
      expect(run.beginMerge()).assertFalse();
      expect(run.merging).assertFalse();
      expect(run.shouldCommit()).assertFalse();
    });

    it('U05#cancel-after-merge-start-does-not-stop-the-write', 0, () => {
      const run = new SubscriptionRefreshRun([record('https://a.example/sub', 'a-id')]);
      expect(run.beginMerge()).assertTrue();
      expect(run.shouldCommit()).assertTrue();

      run.requestCancel();
      expect(run.cancelled).assertTrue();
      expect(run.merging).assertTrue();
      expect(run.shouldCommit()).assertTrue();
    });

    it('U05#failed-download-is-skipped-and-reported', 0, () => {
      const bodyA = ssUrl('a.example', 8388, 'aes-256-gcm', 'pw', 'A');
      const run = new SubscriptionRefreshRun([
        record('https://a.example/sub', 'a-id'),
        record('https://b.example/sub', 'b-id'),
      ]);
      run.recordFetch({ id: 'a-id', body: bodyA, error: '' });
      run.recordFetch({ id: 'b-id', body: '', error: 'HTTP 503' });

      expect(run.failureCount()).assertEqual(1);
      expect(run.succeededIds()).assertEqual(['a-id']);
      expect(run.outcomes[1].error).assertEqual('HTTP 503');

      // Only the succeeded body yields fresh profiles.
      const fresh: Profile[] = [];
      for (const outcome of run.outcomes) {
        if (outcome.error.length === 0) {
          for (const profile of parseSubscriptionBody(outcome.body, outcome.id)) {
            fresh.push(profile);
          }
        }
      }
      expect(fresh.length).assertEqual(1);

      // The failing URL's stored profiles become obsolete.
      const merged = mergeSubscriptionRun([
        stored('A', 'a.example', 8388, STATUS_ACTIVE, 'a-id'),
        stored('B', 'b.example', 8388, STATUS_ACTIVE, 'b-id'),
      ], fresh, '');
      expect(merged.profiles.length).assertEqual(2);
      expect(merged.profiles[0].subscriptionStatus).assertEqual(STATUS_ACTIVE);
      expect(merged.profiles[1].subscriptionStatus).assertEqual(STATUS_OBSOLETE);
    });

    it('U05#json-parse-error-is-reported-and-skipped', 0, () => {
      // The host shim has no assertThrow, so a flag records the throw.
      let raised = false;
      try {
        parseSubscriptionBody('{invalid json', 'broken');
      } catch (e) {
        raised = true;
        expect(e instanceof SubscriptionParseError).assertTrue();
      }
      expect(raised).assertTrue();

      let truncatedRaised = false;
      try {
        parseSubscriptionBody('[{"server":', 'broken');
      } catch (e) {
        truncatedRaised = true;
      }
      expect(truncatedRaised).assertTrue();

      // The bad body adds no profile. The merge still runs and retires the
      // stored profiles of that URL.
      const merged = mergeSubscriptionRun(
        [stored('Broken', 'broken.example', 8388, STATUS_ACTIVE, 'broken')], [], '');
      expect(merged.profiles.length).assertEqual(1);
      expect(merged.profiles[0].subscriptionStatus).assertEqual(STATUS_OBSOLETE);
    });

    it('U05#bare-literals-add-nothing-and-do-not-raise', 0, () => {
      // The calls return. A throw fails the test.
      expect(parseSubscriptionBody('Not Found', 's').length).assertEqual(0);
      expect(parseSubscriptionBody('', 's').length).assertEqual(0);
      expect(parseSubscriptionBody('{}', 's').length).assertEqual(0);
      expect(parseSubscriptionBody('[]', 's').length).assertEqual(0);

      // A body that decodes but has no ss:// line adds nothing.
      const encoded = Profile.encodeBase64(
        Profile.encodeUtf8('hello world\nno links here'), true, false);
      expect(parseSubscriptionBody(encoded, 's').length).assertEqual(0);
    });

    it('U05#single-json-object-parses', 0, () => {
      const body = '{"server":"A.EXAMPLE.COM","server_port":"8388","password":"pw",' +
        '"method":"aes-256-gcm","remarks":"Node One"}';
      const profiles = parseSubscriptionBody(body, 'sub-json');
      expect(profiles.length).assertEqual(1);
      expect(profiles[0].host).assertEqual('A.EXAMPLE.COM');
      expect(profiles[0].remotePort).assertEqual(8388);
      expect(profiles[0].password).assertEqual('pw');
      expect(profiles[0].method).assertEqual('aes-256-gcm');
      expect(profiles[0].name).assertEqual('Node One');
      expect(profiles[0].subscriptionId).assertEqual('sub-json');
      expect(profiles[0].id.length > 0).assertTrue();

      // Without remarks the host becomes the name.
      const unnamed = parseSubscriptionBody(jsonEntry('b.example', 8389), 'sub-json');
      expect(unnamed.length).assertEqual(1);
      expect(unnamed[0].name).assertEqual('b.example');
    });

    it('U05#surviving-active-profiles-become-obsolete', 0, () => {
      const merged = mergeSubscriptionRun([
        stored('A', 'a.example', 8388, STATUS_ACTIVE),
        stored('B', 'b.example', 8388, STATUS_ACTIVE),
        stored('Mine', 'mine.example', 8388, STATUS_USER_CONFIGURED, ''),
      ], [], '');
      expect(merged.profiles.length).assertEqual(3);
      expect(merged.profiles[0].subscriptionStatus).assertEqual(STATUS_OBSOLETE);
      expect(merged.profiles[1].subscriptionStatus).assertEqual(STATUS_OBSOLETE);
      expect(merged.profiles[2].subscriptionStatus).assertEqual(STATUS_USER_CONFIGURED);

      // A body that still lists A keeps it active.
      const listed = mergeSubscriptionRun(
        [stored('A', 'a.example', 8388, STATUS_ACTIVE)], [incoming('A', 'a.example', 8388)], '');
      expect(listed.profiles.length).assertEqual(1);
      expect(listed.profiles[0].subscriptionStatus).assertEqual(STATUS_ACTIVE);
    });

    it('U05#relisted-obsolete-keeps-id-and-takes-transport', 0, () => {
      const saved = stored('A', 'a.example', 8388, STATUS_OBSOLETE, 'sub-old');
      saved.id = 'kept-id';
      saved.route = ROUTE_GFWLIST;
      saved.remoteDns = '9.9.9.9';
      saved.tx = 11;
      saved.rx = 22;
      saved.userOrder = 5;

      const listed = incoming('A', 'a.example', 8388, 'sub-new');
      listed.plugin = 'v2ray-plugin';
      listed.pluginOpts = 'mode=websocket';
      listed.udpFallbackId = 'fallback-id';

      const merged = mergeSubscriptionRun([saved], [listed], '');
      expect(merged.profiles.length).assertEqual(1);
      const result = merged.profiles[0];
      // The stored identity and place stay.
      expect(result.id).assertEqual('kept-id');
      expect(result.name).assertEqual('A');
      expect(result.host).assertEqual('a.example');
      expect(result.remotePort).assertEqual(8388);
      expect(result.userOrder).assertEqual(5);
      expect(result.tx).assertEqual(11);
      expect(result.rx).assertEqual(22);
      // The route and the resolver belong to the user.
      expect(result.route).assertEqual(ROUTE_GFWLIST);
      expect(result.remoteDns).assertEqual('9.9.9.9');
      // The transport comes from the new copy.
      expect(result.password).assertEqual('new-password');
      expect(result.method).assertEqual('chacha20-ietf-poly1305');
      expect(result.plugin).assertEqual('v2ray-plugin');
      expect(result.pluginOpts).assertEqual('mode=websocket');
      expect(result.udpFallbackId).assertEqual('fallback-id');
      expect(result.subscriptionStatus).assertEqual(STATUS_ACTIVE);
      expect(result.subscriptionId).assertEqual('sub-new');
    });

    it('U05#new-profile-copies-feature-settings', 0, () => {
      const feature = new Profile();
      feature.name = 'Feature';
      feature.host = 'feature.example';
      feature.remotePort = 1234;
      feature.password = 'feature-password';
      feature.method = 'chacha20-ietf-poly1305';
      feature.route = ROUTE_GFWLIST;
      feature.ipv6 = true;
      feature.udpdns = true;
      feature.remoteDns = '9.9.9.9';
      feature.plugin = 'obfs-local';
      feature.pluginOpts = 'obfs=tls';

      const profiles = parseSubscriptionBody(
        ssUrl('node.example', 8388, 'aes-256-gcm', 'body-password', 'Node'), 'sub-1', feature);
      expect(profiles.length).assertEqual(1);
      const node = profiles[0];
      // The feature settings describe how this device uses the server.
      expect(node.route).assertEqual(ROUTE_GFWLIST);
      expect(node.ipv6).assertTrue();
      expect(node.udpdns).assertTrue();
      // The transport, the plugin and the resolver do not come from the feature.
      expect(node.password).assertEqual('body-password');
      expect(node.method).assertEqual('aes-256-gcm');
      expect(node.plugin).assertEqual('');
      expect(node.remoteDns).assertEqual(DEFAULT_REMOTE_DNS);
      expect(node.host).assertEqual('node.example');
      expect(node.name).assertEqual('Node');

      // The JSON branch copies the same set.
      const listed = parseSubscriptionBody(jsonEntry('j.example', 443), 'sub-1', feature);
      expect(listed.length).assertEqual(1);
      expect(listed[0].route).assertEqual(ROUTE_GFWLIST);
      expect(listed[0].ipv6).assertTrue();
      expect(listed[0].udpdns).assertTrue();
      expect(listed[0].plugin).assertEqual('');
      expect(listed[0].remoteDns).assertEqual(DEFAULT_REMOTE_DNS);
    });

    it('U05#body-keys-override-feature-settings', 0, () => {
      const feature = new Profile();
      feature.route = ROUTE_GFWLIST;
      feature.ipv6 = true;
      feature.udpdns = true;

      const body = jsonEntry('a.example', 8388,
        ',"route":"china-list","ipv6":false,"udpdns":false,' +
        '"plugin":"v2ray-plugin","plugin_opts":"mode=websocket"');
      const profiles = parseSubscriptionBody(body, 'sub-1', feature);
      expect(profiles.length).assertEqual(1);
      expect(profiles[0].route).assertEqual(ROUTE_CHINA_LIST);
      expect(profiles[0].ipv6).assertFalse();
      expect(profiles[0].udpdns).assertFalse();
      expect(profiles[0].plugin).assertEqual('v2ray-plugin');
      expect(profiles[0].pluginOpts).assertEqual('mode=websocket');

      // An unknown route and a non-boolean flag keep the copied values.
      const kept = parseSubscriptionBody(jsonEntry('b.example', 8389,
        ',"route":"not-a-route","ipv6":"yes"'), 'sub-1', feature);
      expect(kept.length).assertEqual(1);
      expect(kept[0].route).assertEqual(ROUTE_GFWLIST);
      expect(kept[0].ipv6).assertTrue();
      expect(kept[0].udpdns).assertTrue();
    });

    it('U05#remote-dns-is-body-or-default', 0, () => {
      const feature = new Profile();
      feature.remoteDns = '9.9.9.9';

      // The body does not carry the feature resolver.
      const none = parseSubscriptionBody(jsonEntry('a.example', 8388), 'sub-1', feature);
      expect(none[0].remoteDns).assertEqual(DEFAULT_REMOTE_DNS);

      const given = parseSubscriptionBody(jsonEntry('b.example', 8389,
        ',"remote_dns":"1.1.1.1:5353"'), 'sub-1', feature);
      expect(given[0].remoteDns).assertEqual('1.1.1.1:5353');

      // An empty or non-string value takes the default.
      const empty = parseSubscriptionBody(jsonEntry('c.example', 8390,
        ',"remote_dns":""'), 'sub-1', feature);
      expect(empty[0].remoteDns).assertEqual(DEFAULT_REMOTE_DNS);
      const wrongType = parseSubscriptionBody(jsonEntry('d.example', 8391,
        ',"remote_dns":7'), 'sub-1', feature);
      expect(wrongType[0].remoteDns).assertEqual(DEFAULT_REMOTE_DNS);

      // The ss:// branch always takes the default.
      const linked = parseSubscriptionBody(
        ssUrl('e.example', 8392, 'aes-256-gcm', 'pw', 'E'), 'sub-1', feature);
      expect(linked[0].remoteDns).assertEqual(DEFAULT_REMOTE_DNS);
    });

    it('U05#stored-duplicate-is-deleted', 0, () => {
      const first = stored('A', 'a.example', 8388, STATUS_ACTIVE);
      first.id = 'first-id';
      const second = stored('A', 'a.example', 8388, STATUS_ACTIVE);
      second.id = 'second-id';

      const merged = mergeSubscriptionRun(
        [first, second], [incoming('A', 'a.example', 8388)], '');
      expect(merged.deleted).assertEqual(1);
      expect(merged.profiles.length).assertEqual(1);
      expect(merged.profiles[0].id).assertEqual('first-id');
      expect(merged.profiles[0].subscriptionStatus).assertEqual(STATUS_ACTIVE);

      // The same cleanup runs with no body at all.
      const firstAgain = stored('A', 'a.example', 8388, STATUS_ACTIVE);
      firstAgain.id = 'first-id';
      const secondAgain = stored('A', 'a.example', 8388, STATUS_ACTIVE);
      secondAgain.id = 'second-id';
      const empty = mergeSubscriptionRun([firstAgain, secondAgain], [], '');
      expect(empty.deleted).assertEqual(1);
      expect(empty.profiles.length).assertEqual(1);
      expect(empty.profiles[0].subscriptionStatus).assertEqual(STATUS_OBSOLETE);
    });

    it('U05#deleting-the-current-duplicate-resets-the-selection', 0, () => {
      const first = stored('A', 'a.example', 8388, STATUS_ACTIVE);
      first.id = 'first-id';
      const second = stored('A', 'a.example', 8388, STATUS_ACTIVE);
      second.id = 'second-id';

      // The deleted record is the current profile, so the selection clears.
      const deleted = mergeSubscriptionRun([first, second], [], 'second-id');
      expect(deleted.deleted).assertEqual(1);
      expect(deleted.currentId).assertEqual('');

      // The kept record keeps the selection.
      const keptFirst = stored('A', 'a.example', 8388, STATUS_ACTIVE);
      keptFirst.id = 'first-id';
      const keptSecond = stored('A', 'a.example', 8388, STATUS_ACTIVE);
      keptSecond.id = 'second-id';
      const kept = mergeSubscriptionRun([keptFirst, keptSecond], [], 'first-id');
      expect(kept.currentId).assertEqual('first-id');

      // An unrelated selection also stays.
      const otherFirst = stored('A', 'a.example', 8388, STATUS_ACTIVE);
      otherFirst.id = 'first-id';
      const otherSecond = stored('A', 'a.example', 8388, STATUS_ACTIVE);
      otherSecond.id = 'second-id';
      const other = mergeSubscriptionRun([otherFirst, otherSecond], [], 'other-id');
      expect(other.currentId).assertEqual('other-id');
    });

    it('U05#user-configured-profile-is-never-deleted', 0, () => {
      const mine = stored('Mine', 'mine.example', 8388, STATUS_USER_CONFIGURED, '');
      const other = stored('Mine', 'mine.example', 8388, STATUS_USER_CONFIGURED, '');
      other.id = 'other-id';

      // Equal name and address do not make a user profile a duplicate.
      const merged = mergeSubscriptionRun([mine, other], [], '');
      expect(merged.deleted).assertEqual(0);
      expect(merged.profiles.length).assertEqual(2);
      expect(merged.profiles[0].subscriptionStatus).assertEqual(STATUS_USER_CONFIGURED);
      expect(merged.profiles[1].subscriptionStatus).assertEqual(STATUS_USER_CONFIGURED);

      // A subscription server with the same name and address becomes a new
      // active profile. The user profile stays untouched.
      const listed = mergeSubscriptionRun(
        [stored('Mine', 'mine.example', 8388, STATUS_USER_CONFIGURED, '')],
        [incoming('Mine', 'mine.example', 8388)], '');
      expect(listed.deleted).assertEqual(0);
      expect(listed.profiles.length).assertEqual(2);
      expect(listed.profiles[0].subscriptionStatus).assertEqual(STATUS_USER_CONFIGURED);
      expect(listed.profiles[0].password).assertEqual('old-password');
      expect(listed.profiles[1].subscriptionStatus).assertEqual(STATUS_ACTIVE);
    });

    it('U05#active-incoming-duplicate-is-ignored', 0, () => {
      const one = incoming('A', 'a.example', 8388);
      one.password = 'first-password';
      const two = incoming('A', 'a.example', 8388);
      two.password = 'second-password';

      // The first copy creates the profile. The second copy is ignored.
      const merged = mergeSubscriptionRun([], [one, two], '');
      expect(merged.profiles.length).assertEqual(1);
      expect(merged.profiles[0].password).assertEqual('first-password');
      expect(merged.profiles[0].subscriptionStatus).assertEqual(STATUS_ACTIVE);

      // A revived profile also takes the first copy only.
      const stale = stored('B', 'b.example', 8388, STATUS_OBSOLETE);
      stale.id = 'kept-b';
      const firstCopy = incoming('B', 'b.example', 8388);
      firstCopy.password = 'first-password';
      const secondCopy = incoming('B', 'b.example', 8388);
      secondCopy.password = 'second-password';
      const revived = mergeSubscriptionRun([stale], [firstCopy, secondCopy], '');
      expect(revived.profiles.length).assertEqual(1);
      expect(revived.profiles[0].id).assertEqual('kept-b');
      expect(revived.profiles[0].password).assertEqual('first-password');
    });

    it('U05#cancel-result-changes-nothing', 0, () => {
      const list = [record('https://a.example/sub', 'a-id')];

      // Cancel returns no action, so the page applies no list change.
      const answer = editResult('cancel', 'https://b.example/sub', 'https://a.example/sub');
      expect(answer === null).assertTrue();
      expect(editResult('cancel', '', '') === null).assertTrue();
      expect(list.length).assertEqual(1);
      expect(list[0].url).assertEqual('https://a.example/sub');
    });

    it('U05#empty-run-still-obsoletes-profiles', 0, () => {
      // No stored URL: the run goes from fetching to finishing, and the merge
      // with an empty list retires every active non-user profile.
      const emptyRun = new SubscriptionRefreshRun([]);
      expect(emptyRun.urls.length).assertEqual(0);
      emptyRun.markFinishing();
      expect(emptyRun.beginMerge()).assertTrue();
      expect(emptyRun.shouldCommit()).assertTrue();
      expect(emptyRun.succeededIds().length).assertEqual(0);

      const fresh: Profile[] = [];
      for (const outcome of emptyRun.outcomes) {
        if (outcome.error.length === 0) {
          for (const profile of parseSubscriptionBody(outcome.body, outcome.id)) {
            fresh.push(profile);
          }
        }
      }
      const merged = mergeSubscriptionRun([
        stored('A', 'a.example', 8388, STATUS_ACTIVE),
        stored('B', 'b.example', 8388, STATUS_ACTIVE),
        stored('Mine', 'mine.example', 8388, STATUS_USER_CONFIGURED, ''),
      ], fresh, '');
      expect(merged.profiles.length).assertEqual(3);
      expect(merged.profiles[0].subscriptionStatus).assertEqual(STATUS_OBSOLETE);
      expect(merged.profiles[1].subscriptionStatus).assertEqual(STATUS_OBSOLETE);
      expect(merged.profiles[2].subscriptionStatus).assertEqual(STATUS_USER_CONFIGURED);

      // Every download fails: the same result.
      const failedRun = new SubscriptionRefreshRun([record('https://a.example/sub', 'a-id')]);
      failedRun.recordFetch({ id: 'a-id', body: '', error: 'network down' });
      expect(failedRun.succeededIds().length).assertEqual(0);
      expect(failedRun.failureCount()).assertEqual(1);
      failedRun.markFinishing();
      expect(failedRun.beginMerge()).assertTrue();

      const failedFresh: Profile[] = [];
      for (const outcome of failedRun.outcomes) {
        if (outcome.error.length === 0) {
          for (const profile of parseSubscriptionBody(outcome.body, outcome.id)) {
            failedFresh.push(profile);
          }
        }
      }
      expect(failedFresh.length).assertEqual(0);
      const failedMerged = mergeSubscriptionRun(
        [stored('A', 'a.example', 8388, STATUS_ACTIVE)], failedFresh, '');
      expect(failedMerged.profiles.length).assertEqual(1);
      expect(failedMerged.profiles[0].subscriptionStatus).assertEqual(STATUS_OBSOLETE);
    });

    it('U05#run-snapshots-the-url-list-once', 0, () => {
      const first = record('https://a.example/sub', 'a-id');
      const second = record('https://b.example/sub', 'b-id');
      const source = [first, second];
      const run = new SubscriptionRefreshRun(source);
      expect(run.urls.length).assertEqual(2);
      expect(run.urls[0].url).assertEqual('https://a.example/sub');
      expect(run.urls[1].url).assertEqual('https://b.example/sub');
      expect(run.urls[1].id).assertEqual('b-id');

      // The page changes its list after the run starts.
      first.url = 'https://changed.example/sub';
      second.id = 'changed-id';
      source.push(record('https://c.example/sub', 'c-id'));
      source.splice(1, 1);

      // The run keeps the old URLs and the old ids.
      expect(run.urls.length).assertEqual(2);
      expect(run.urls[0].url).assertEqual('https://a.example/sub');
      expect(run.urls[0].id).assertEqual('a-id');
      expect(run.urls[1].url).assertEqual('https://b.example/sub');
      expect(run.urls[1].id).assertEqual('b-id');
    });
  });
}
