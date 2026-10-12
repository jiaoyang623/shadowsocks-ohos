import { describe, expect, it } from '@ohos/hypium';
import { Profile } from '../main/ets/model/Profile';
import { ProfileJson, applyImport, exportProfiles, parseProfilesText } from '../main/ets/model/ProfilesFile';

function profile(host: string, port: number, name: string): Profile {
  const profile = new Profile();
  profile.id = `${host}-${port}`;
  profile.host = host;
  profile.remotePort = port;
  profile.password = 'pw';
  profile.method = 'aes-256-gcm';
  profile.name = name;
  return profile;
}

export default function profilesFileTest() {
  describe('ProfilesFileTest', () => {
    it('exports the fields android exports', 0, () => {
      const exported = profile('example.com', 8388, 'Example');
      exported.plugin = 'obfs-local';
      exported.pluginOpts = 'obfs=tls';
      exported.remoteDns = '9.9.9.9';
      exported.userOrder = 3;

      const entries = JSON.parse(exportProfiles([exported])) as ProfileJson[];
      expect(entries.length).assertEqual(1);
      expect(entries[0].server).assertEqual('example.com');
      expect(entries[0].server_port).assertEqual(8388);
      expect(entries[0].password).assertEqual('pw');
      expect(entries[0].method).assertEqual('aes-256-gcm');
      expect(entries[0].plugin).assertEqual('obfs-local');
      expect(entries[0].plugin_opts).assertEqual('obfs=tls');
      expect(entries[0].remarks).assertEqual('Example');
      expect(entries[0].remote_dns).assertEqual('9.9.9.9');
      expect(entries[0].route).assertEqual('all');
      expect(entries[0].ipv6).assertFalse();
      expect(entries[0].udpdns).assertFalse();
    });

    it('writes only the four fields a sip008 document defines', 0, () => {
      const exported = profile('example.com', 8388, 'Example');
      exported.plugin = 'v2ray-plugin';

      const entries = JSON.parse(exportProfiles([exported], true)) as ProfileJson[];
      expect(entries[0].server).assertEqual('example.com');
      expect(entries[0].plugin === undefined).assertTrue();
      expect(entries[0].remarks === undefined).assertTrue();
    });

    it('reads back the file it wrote', 0, () => {
      const original = profile('example.com', 8388, 'Example');
      original.route = 'bypass-china';
      original.remoteDns = '1.1.1.1';
      original.ipv6 = true;

      const parsed = parseProfilesText(exportProfiles([original]));
      expect(parsed.length).assertEqual(1);
      expect(parsed[0].host).assertEqual('example.com');
      expect(parsed[0].remotePort).assertEqual(8388);
      expect(parsed[0].password).assertEqual('pw');
      expect(parsed[0].name).assertEqual('Example');
      expect(parsed[0].route).assertEqual('bypass-china');
      expect(parsed[0].remoteDns).assertEqual('1.1.1.1');
      expect(parsed[0].ipv6).assertTrue();
    });

    it('finds servers nested in a provider document', 0, () => {
      // the shapes providers serve: SIP008 wraps them in `servers`, and some
      // wrap that in an object of their own
      const sip008 = '{"servers":[{"server":"a.example","server_port":8388,' +
        '"password":"pw","method":"aes-256-gcm","remarks":"A"}]}';
      const nested = '{"data":{"configs":[{"server":"b.example","server_port":443,' +
        '"password":"pw","method":"chacha20-ietf-poly1305"}]}}';

      const fromSip008 = parseProfilesText(sip008);
      expect(fromSip008.length).assertEqual(1);
      expect(fromSip008[0].host).assertEqual('a.example');
      expect(fromSip008[0].name).assertEqual('A');

      const fromNested = parseProfilesText(nested);
      expect(fromNested.length).assertEqual(1);
      expect(fromNested[0].host).assertEqual('b.example');
      expect(fromNested[0].remotePort).assertEqual(443);
      // no remarks, so the address is the name rather than nothing
      expect(fromNested[0].name).assertEqual('b.example');
    });

    it('takes a port written as a string', 0, () => {
      const parsed = parseProfilesText('{"server":"a.example","server_port":"8388",' +
        '"password":"pw","method":"aes-256-gcm"}');
      expect(parsed.length).assertEqual(1);
      expect(parsed[0].remotePort).assertEqual(8388);
    });

    it('ignores json that holds no server', 0, () => {
      expect(parseProfilesText('{"hello":"world"}').length).assertEqual(0);
      // a server entry missing its password is not usable and is skipped
      expect(parseProfilesText('{"server":"a.example","server_port":8388}').length).assertEqual(0);
    });

    it('reads a list of urls and a base64 blob of them', 0, () => {
      // base64("aes-256-gcm:pw") = YWVzLTI1Ni1nY206cHc
      const url = 'ss://YWVzLTI1Ni1nY206cHc@a.example:8388#A';
      expect(parseProfilesText(`${url}\n${url}`).length).assertEqual(2);
      expect(parseProfilesText('not a profile at all').length).assertEqual(0);

      const plain = 'ss://YWVzLTI1Ni1nY206cHc@a.example:8388#A';
      const encoded = encodeBase64(`${plain}\n${plain}`);
      expect(parseProfilesText(encoded).length).assertEqual(2);
    });

    it('keeps identity and counters when a replace finds the same server', 0, () => {
      const existing = profile('example.com', 8388, 'Example');
      existing.tx = 1000;
      existing.rx = 2000;
      existing.id = 'kept';
      const other = profile('old.example', 1080, 'Gone');

      const replacement = profile('example.com', 8388, 'Example');
      const result = applyImport([existing, other], [replacement], true);

      expect(result.length).assertEqual(1);
      expect(result[0].id).assertEqual('kept');
      expect(result[0].tx).assertEqual(1000);
      expect(result[0].rx).assertEqual(2000);
      expect(result[0].userOrder).assertEqual(1);
    });

    it('appends on import, and numbers what it appends', 0, () => {
      const existing = profile('example.com', 8388, 'Example');
      existing.userOrder = 1;
      const incoming = profile('new.example', 443, 'New');

      const result = applyImport([existing], [incoming], false);
      expect(result.length).assertEqual(2);
      expect(result[1].host).assertEqual('new.example');
      expect(result[1].userOrder).assertEqual(2);
      expect(result[1].id.length > 0).assertTrue();
      // an imported profile belongs to no subscription, whatever it carried
      expect(result[1].subscriptionId).assertEqual('');
    });
  });
}

/** Local base64 encoder, so the spec does not need the native codec. */
function encodeBase64(text: string): string {
  const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  const bytes: number[] = [];
  for (let i = 0; i < text.length; i++) {
    const code = text.charCodeAt(i);
    if (code < 0x80) {
      bytes.push(code);
    }
  }
  let out = '';
  for (let i = 0; i < bytes.length; i += 3) {
    const b0 = bytes[i];
    const b1 = i + 1 < bytes.length ? bytes[i + 1] : 0;
    const b2 = i + 2 < bytes.length ? bytes[i + 2] : 0;
    out += ALPHABET.charAt(b0 >> 2);
    out += ALPHABET.charAt(((b0 & 3) << 4) | (b1 >> 4));
    out += i + 1 < bytes.length ? ALPHABET.charAt(((b1 & 15) << 2) | (b2 >> 6)) : '=';
    out += i + 2 < bytes.length ? ALPHABET.charAt(b2 & 63) : '=';
  }
  return out;
}
