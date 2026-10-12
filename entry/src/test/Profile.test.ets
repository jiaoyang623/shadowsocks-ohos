import { describe, expect, it } from '@ohos/hypium';
import { Profile } from '../main/ets/model/Profile';

export default function profileTest() {
  describe('ProfileTest', () => {
    it('parses SIP002 ss urls', 0, () => {
      // base64("aes-256-gcm:test-password") = YWVzLTI1Ni1nY206dGVzdC1wYXNzd29yZA
      const profile = Profile.parseUrl(
        'ss://YWVzLTI1Ni1nY206dGVzdC1wYXNzd29yZA@example.com:8388#My%20Server');
      expect(profile !== null).assertTrue();
      expect(profile!.host).assertEqual('example.com');
      expect(profile!.remotePort).assertEqual(8388);
      expect(profile!.method).assertEqual('aes-256-gcm');
      expect(profile!.password).assertEqual('test-password');
      expect(profile!.name).assertEqual('My Server');
    });

    it('parses legacy ss urls', 0, () => {
      // base64("aes-256-gcm:test-password@example.com:8388")
      const profile = Profile.parseUrl(
        'ss://YWVzLTI1Ni1nY206dGVzdC1wYXNzd29yZEBleGFtcGxlLmNvbTo4Mzg4');
      expect(profile !== null).assertTrue();
      expect(profile!.host).assertEqual('example.com');
      expect(profile!.remotePort).assertEqual(8388);
      expect(profile!.method).assertEqual('aes-256-gcm');
      expect(profile!.password).assertEqual('test-password');
    });

    it('parses ss urls with a SIP003 plugin', 0, () => {
      // base64("aes-256-gcm:test-password") = YWVzLTI1Ni1nY206dGVzdC1wYXNzd29yZA
      // plugin query value is percent-encoded "v2ray-plugin;mode=websocket;tls;host=cdn.example.com;path=/ws"
      const profile = Profile.parseUrl(
        'ss://YWVzLTI1Ni1nY206dGVzdC1wYXNzd29yZA@example.com:443' +
        '?plugin=v2ray-plugin%3Bmode%3Dwebsocket%3Btls%3Bhost%3Dcdn.example.com%3Bpath%3D%2Fws#Plugin%20Server');
      expect(profile !== null).assertTrue();
      expect(profile!.host).assertEqual('example.com');
      expect(profile!.remotePort).assertEqual(443);
      expect(profile!.plugin).assertEqual('v2ray-plugin');
      expect(profile!.pluginOpts).assertEqual('mode=websocket;tls;host=cdn.example.com;path=/ws');
      expect(profile!.name).assertEqual('Plugin Server');
    });

    it('parses plugin without opts and defaults to no plugin', 0, () => {
      // base64("aes-256-gcm:test-password") = YWVzLTI1Ni1nY206dGVzdC1wYXNzd29yZA
      const bare = Profile.parseUrl(
        'ss://YWVzLTI1Ni1nY206dGVzdC1wYXNzd29yZA@example.com:8388?plugin=obfs-local');
      expect(bare !== null).assertTrue();
      expect(bare!.plugin).assertEqual('obfs-local');
      expect(bare!.pluginOpts).assertEqual('');
      const plain = Profile.parseUrl(
        'ss://YWVzLTI1Ni1nY206dGVzdC1wYXNzd29yZA@example.com:8388');
      expect(plain !== null).assertTrue();
      expect(plain!.plugin).assertEqual('');
      expect(plain!.pluginOpts).assertEqual('');
    });

    it('serializes plugin into sslocal config json', 0, () => {
      const profile = new Profile();
      profile.host = 'example.com';
      profile.remotePort = 8388;
      profile.password = 'pw';
      profile.method = 'aes-256-gcm';
      profile.plugin = 'obfs-local';
      profile.pluginOpts = 'obfs=tls;obfs-host=www.example.com';
      const socks: object = JSON.parse(profile.toLocalConfig()) as object;
      expect(socks['plugin']).assertEqual('obfs-local');
      expect(socks['plugin_opts']).assertEqual('obfs=tls;obfs-host=www.example.com');
      const tun: object = JSON.parse(profile.toTunConfig()) as object;
      expect(tun['plugin']).assertEqual('obfs-local');
      expect(tun['plugin_opts']).assertEqual('obfs=tls;obfs-host=www.example.com');
      // no plugin configured -> keys absent
      profile.plugin = '';
      const plain: object = JSON.parse(profile.toTunConfig()) as object;
      expect(plain['plugin'] === undefined).assertTrue();
      expect(plain['plugin_opts'] === undefined).assertTrue();
    });

    it('tolerates malformed percent escapes', 0, () => {
      // a broken escape in the fragment or the plugin query must not throw
      // out of parseUrl — one bad entry would abort a whole subscription body
      const named = Profile.parseUrl(
        'ss://YWVzLTI1Ni1nY206dGVzdC1wYXNzd29yZA@example.com:8388#Bad%ZZName');
      expect(named !== null).assertTrue();
      expect(named!.host).assertEqual('example.com');
      expect(named!.name).assertEqual('Bad%ZZName');
      const plugged = Profile.parseUrl(
        'ss://YWVzLTI1Ni1nY206dGVzdC1wYXNzd29yZA@example.com:8388?plugin=obfs-local%3Bobfs%3Dhttp%');
      expect(plugged !== null).assertTrue();
      expect(plugged!.plugin).assertEqual('obfs-local%3Bobfs%3Dhttp%');
    });

    it('rejects invalid urls', 0, () => {
      expect(Profile.parseUrl('') === null).assertTrue();
      expect(Profile.parseUrl('http://example.com') === null).assertTrue();
      expect(Profile.parseUrl('ss://%%%') === null).assertTrue();
      expect(Profile.parseUrl('ss://YWJj@host:notaport') === null).assertTrue();
    });

    it('serializes sslocal config json', 0, () => {
      const profile = new Profile();
      profile.host = 'example.com';
      profile.remotePort = 8388;
      profile.password = 'pw';
      profile.method = 'aes-256-gcm';
      const config: object = JSON.parse(profile.toLocalConfig()) as object;
      expect(config['server']).assertEqual('example.com');
      expect(config['server_port']).assertEqual(8388);
      expect(config['locals'][0]['protocol']).assertEqual('socks');
      expect(config['locals'][0]['local_port']).assertEqual(1080);
    });

    it('serializes tun config json', 0, () => {
      const profile = new Profile();
      profile.host = 'example.com';
      profile.remotePort = 8388;
      profile.password = 'pw';
      profile.method = 'aes-256-gcm';
      const config: object = JSON.parse(profile.toTunConfig()) as object;
      expect(config['server']).assertEqual('example.com');
      expect(config['locals'][0]['protocol']).assertEqual('tun');
      // both TCP and UDP must route through the tunnel
      expect(config['mode']).assertEqual('tcp_and_udp');
      // route `all` never injects an ACL
      expect(config['acl'] === undefined).assertTrue();
    });

    it('hands the core a DNS gateway inside the tun', 0, () => {
      const profile = new Profile();
      profile.host = 'example.com';
      profile.remotePort = 8388;
      profile.password = 'pw';
      profile.method = 'aes-256-gcm';
      const config: object =
        JSON.parse(profile.toTunConfig('', '172.19.0.1/30')) as object;

      // the tun answers queries itself, through the resolver it is given
      expect(config['locals'][0]['tun_interface_address']).assertEqual('172.19.0.1/30');
      expect(config['locals'][0]['dns_gateway']).assertEqual('127.0.0.1:5453');

      // that resolver is a loopback listener, and resolves through the proxy
      // over TCP only: the server does not relay UDP, so racing a UDP query
      // against it would cost every lookup the fallback wait for nothing
      const dns: object = config['locals'][1];
      expect(dns['protocol']).assertEqual('dns');
      expect(dns['local_address']).assertEqual('127.0.0.1');
      expect(dns['local_port']).assertEqual(5453);
      expect(dns['local_dns_address']).assertEqual('1.1.1.1');
      // the profile's own resolver, which defaults to the same one
      // shadowsocks-android uses
      expect(dns['remote_dns_address']).assertEqual('dns.google');
      expect(dns['remote_dns_port']).assertEqual(53);
      expect(dns['remote_dns_protocol']).assertEqual('tcp_only');

      // without an interface address the tun is never started, so it is given
      // no gateway and nothing is intercepted
      const plain: object = JSON.parse(profile.toTunConfig()) as object;
      expect(plain['locals'][0]['dns_gateway'] === undefined).assertTrue();
      expect(plain['locals'][1] === undefined).assertTrue();
    });

    it('resolves through the resolver the profile names', 0, () => {
      const profile = new Profile();
      profile.host = 'example.com';
      profile.password = 'pw';
      profile.remoteDns = 'dns://9.9.9.9:5353';

      const config: object = JSON.parse(profile.toTunConfig('', '172.19.0.1/30')) as object;
      expect(config['locals'][1]['remote_dns_address']).assertEqual('9.9.9.9');
      expect(config['locals'][1]['remote_dns_port']).assertEqual(5353);
    });

    it('splits the resolver address shapes android accepts', 0, () => {
      // the shapes shadowsocks-android's URI("dns://$remoteDns") accepts, each
      // defaulting the port to 53, plus an IPv6 literal in brackets
      const inputs: string[] = [
        'dns.google', '8.8.4.4:5353', 'dns://1.1.1.1', 'dns://1.1.1.1:53', '[2001:db8::1]:5353',
      ];
      const hosts: string[] = ['dns.google', '8.8.4.4', '1.1.1.1', '1.1.1.1', '2001:db8::1'];
      const ports: number[] = [53, 5353, 53, 53, 5353];
      for (let i = 0; i < inputs.length; i++) {
        const parsed = Profile.parseDnsAddress(inputs[i]);
        expect(parsed.host).assertEqual(hosts[i]);
        expect(parsed.port).assertEqual(ports[i]);
      }
      // surrounding space is trimmed rather than becoming part of the host
      expect(Profile.parseDnsAddress('  dns.google  ').host).assertEqual('dns.google');
    });

    it('resolves direct names with the resolver the network gave', 0, () => {
      const profile = new Profile();
      profile.host = 'example.com';
      profile.password = 'pw';

      const config: object = JSON.parse(profile.toTunConfig('', '172.19.0.1/30', '192.168.1.1')) as object;
      expect(config['locals'][1]['local_dns_address']).assertEqual('192.168.1.1');

      // with nothing from the platform it falls back to a public resolver,
      // which is what an ACL-less route uses anyway
      const fallback: object = JSON.parse(profile.toTunConfig('', '172.19.0.1/30')) as object;
      expect(fallback['locals'][1]['local_dns_address']).assertEqual('1.1.1.1');
    });

    it('builds a proxy config that binds where it was told', 0, () => {
      const profile = new Profile();
      profile.host = 'example.com';
      profile.password = 'pw';

      const local: object = JSON.parse(profile.toLocalConfig(1081, false)) as object;
      expect(local['locals'][0]['protocol']).assertEqual('socks');
      expect(local['locals'][0]['local_address']).assertEqual('127.0.0.1');
      expect(local['locals'][0]['local_port']).assertEqual(1081);
      // the sandbox cannot read /etc/resolv.conf, so the resolver is named
      expect(local['dns']).assertEqual('google');

      // sharing binds every interface, which is the point of it
      const shared: object = JSON.parse(profile.toLocalConfig(1081, true)) as object;
      expect(shared['locals'][0]['local_address']).assertEqual('0.0.0.0');
    });

    it('injects acl path for bypass routes', 0, () => {
      const profile = new Profile();
      profile.host = 'example.com';
      profile.remotePort = 8388;
      profile.password = 'pw';
      profile.method = 'aes-256-gcm';
      profile.route = 'bypass-lan-china';
      const config: object =
        JSON.parse(profile.toTunConfig('/data/acl/bypass-lan-china.acl')) as object;
      expect(config['acl']).assertEqual('/data/acl/bypass-lan-china.acl');
      // an acl path without a bypass route is ignored
      profile.route = 'all';
      const plain: object =
        JSON.parse(profile.toTunConfig('/data/acl/bypass-lan-china.acl')) as object;
      expect(plain['acl'] === undefined).assertTrue();
    });
  });
}
