import { describe, expect, it } from '@ohos/hypium';
import {
  ABOUT_LICENCE_URLS, ABOUT_LINK_EMAIL, ABOUT_LINK_OSS, ABOUT_LINK_WEB, ABOUT_MAIL_MAX_LV,
  ABOUT_MAIL_MYGOD, ABOUT_URL_SHADOWSOCKS, aboutTitle, classifyAboutLink, splitAboutBody,
} from '../main/ets/model/AboutLinks';
import { Profile } from '../main/ets/model/Profile';
import { profilesFromScan, profilesFromScanTexts } from '../main/ets/model/QrImport';
import { ROUTE_BYPASS_LAN } from '../main/ets/model/Routes';

/** The password of every helper URL. The parser drops a URL without a password. */
const TEST_PASSWORD: string = 'test-password';

/**
 * An `ss://` URL for a profile with this host and name.
 *
 * An empty name leaves the fragment out, and the parser then uses the host as
 * the name.
 */
function urlFor(host: string, name: string): string {
  const profile = new Profile();
  profile.host = host;
  profile.name = name;
  profile.password = TEST_PASSWORD;
  return profile.toUri();
}

export default function parityU10Test() {
  describe('U10', () => {
    it('U10#scanCreatesProfilesInTextOrder', 0, () => {
      const text = `${urlFor('one.example', 'One')}\n${urlFor('two.example', 'Two')}`;
      const scanned = profilesFromScan(text, null);
      expect(scanned.length).assertEqual(2);
      expect(scanned[0].host).assertEqual('one.example');
      expect(scanned[0].name).assertEqual('One');
      expect(scanned[1].host).assertEqual('two.example');
      expect(scanned[1].name).assertEqual('Two');
    });

    it('U10#scanCreatesProfilePerOccurrence', 0, () => {
      const url = urlFor('same.example', 'Same');
      const scanned = profilesFromScan(`${url} ${url}`, null);
      expect(scanned.length).assertEqual(2);
      expect(scanned[0].host).assertEqual('same.example');
      expect(scanned[1].host).assertEqual('same.example');
      expect(scanned[0].name).assertEqual('Same');
      expect(scanned[1].name).assertEqual('Same');
      // A scan appends. The two entries are separate profiles.
      expect(scanned[0] === scanned[1]).assertFalse();
    });

    it('U10#scanSkipsMalformedUrl', 0, () => {
      // The user information of the first URL is not base64, so the parser
      // drops it and the second URL still imports.
      const text = `ss://%%%@bad.example:8388\n${urlFor('good.example', 'Good')}`;
      const scanned = profilesFromScan(text, null);
      expect(scanned.length).assertEqual(1);
      expect(scanned[0].host).assertEqual('good.example');
      expect(scanned[0].name).assertEqual('Good');
    });

    it('U10#scanReturnsNothingForPlainText', 0, () => {
      expect(profilesFromScan('hello world', null).length).assertEqual(0);
    });

    it('U10#scanCopiesFeatureSettings', 0, () => {
      const current = new Profile();
      current.host = 'current.example';
      current.name = 'Current';
      current.password = 'current-password';
      current.route = ROUTE_BYPASS_LAN;
      current.ipv6 = true;
      current.udpdns = true;
      current.remoteDns = 'dns.example';

      const scanned = profilesFromScan(urlFor('scan.example', 'Scanned'), current);
      expect(scanned.length).assertEqual(1);
      const profile = scanned[0];
      expect(profile.route).assertEqual(ROUTE_BYPASS_LAN);
      expect(profile.ipv6).assertTrue();
      expect(profile.udpdns).assertTrue();
      expect(profile.remoteDns).assertEqual('dns.example');
      // The scan keeps the server fields of its own URL.
      expect(profile.host).assertEqual('scan.example');
      expect(profile.name).assertEqual('Scanned');
      expect(profile.password).assertEqual(TEST_PASSWORD);
    });

    it('U10#scanKeepsScannedHostAndName', 0, () => {
      const current = new Profile();
      current.host = 'other.example';
      current.name = 'Other';
      current.password = 'other-password';

      const text = `${urlFor('scan.example', 'Scanned')} ${urlFor('nofrag.example', '')}`;
      const scanned = profilesFromScan(text, current);
      expect(scanned.length).assertEqual(2);
      // The scanned host and name win over the current profile.
      expect(scanned[0].host).assertEqual('scan.example');
      expect(scanned[0].name).assertEqual('Scanned');
      // A URL without a fragment takes its host as the name.
      expect(scanned[1].host).assertEqual('nofrag.example');
      expect(scanned[1].name).assertEqual('nofrag.example');
    });

    it('U10#scanKeepsScannedPlugin', 0, () => {
      const source = new Profile();
      source.host = 'plugin.example';
      source.name = 'Plugin';
      source.password = TEST_PASSWORD;
      source.plugin = 'v2ray-plugin';
      source.pluginOpts = 'mode=websocket';
      const url = source.toUri();
      expect(url.indexOf('?plugin=v2ray-plugin%3Bmode%3Dwebsocket') >= 0).assertTrue();

      // The current profile carries another plugin. The copy must not touch it.
      const current = new Profile();
      current.host = 'other.example';
      current.password = 'other-password';
      current.plugin = 'obfs-local';
      current.pluginOpts = 'obfs=tls';

      const scanned = profilesFromScan(url, current);
      expect(scanned.length).assertEqual(1);
      expect(scanned[0].plugin).assertEqual('v2ray-plugin');
      expect(scanned[0].pluginOpts).assertEqual('mode=websocket');
    });

    it('U10#scanWithoutCurrentKeepsDefaults', 0, () => {
      const defaults = new Profile();
      const scanned = profilesFromScan(urlFor('default.example', 'Default'), null);
      expect(scanned.length).assertEqual(1);
      const profile = scanned[0];
      // The four copied settings stay at their defaults without a current profile.
      expect(profile.route).assertEqual(defaults.route);
      expect(profile.ipv6).assertEqual(defaults.ipv6);
      expect(profile.udpdns).assertEqual(defaults.udpdns);
      expect(profile.remoteDns).assertEqual(defaults.remoteDns);
      // The other device settings stay at their defaults too.
      expect(profile.metered).assertEqual(defaults.metered);
      expect(profile.proxyAppsEnabled).assertEqual(defaults.proxyAppsEnabled);
      expect(profile.proxyAppsBypass).assertEqual(defaults.proxyAppsBypass);
      expect(profile.proxyAppsList).assertEqual(defaults.proxyAppsList);
    });

    it('U10#batchImportsEveryDecodedImage', 0, () => {
      const first = `${urlFor('a.example', 'A')} ${urlFor('b.example', 'B')}`;
      const profiles = profilesFromScanTexts([first, 'plain text with no url'], null);
      expect(profiles.length).assertEqual(2);
      expect(profiles[0].host).assertEqual('a.example');
      expect(profiles[0].name).assertEqual('A');
      expect(profiles[1].host).assertEqual('b.example');
      expect(profiles[1].name).assertEqual('B');
    });

    it('U10#batchReturnsNothingWithoutUrls', 0, () => {
      expect(profilesFromScanTexts(['hello world', 'still no url here'], null).length)
        .assertEqual(0);
    });

    it('U10#aboutTitleJoinsNameAndVersion', 0, () => {
      expect(aboutTitle('Shadowsocks', '5.3.5')).assertEqual('Shadowsocks 5.3.5');
    });

    it('U10#aboutTitleOmitsMissingVersion', 0, () => {
      expect(aboutTitle('Shadowsocks', '')).assertEqual('Shadowsocks');
      // An empty version leaves no trailing space behind.
      expect(aboutTitle('Shadowsocks', '').length).assertEqual(11);
    });

    it('U10#classifiesWebLink', 0, () => {
      expect(classifyAboutLink(ABOUT_URL_SHADOWSOCKS)).assertEqual(ABOUT_LINK_WEB);
      expect(classifyAboutLink('https://github.com/shadowsocks/shadowsocks-android'))
        .assertEqual(ABOUT_LINK_WEB);
    });

    it('U10#classifiesMailtoLink', 0, () => {
      expect(classifyAboutLink(ABOUT_MAIL_MAX_LV)).assertEqual(ABOUT_LINK_EMAIL);
      expect(classifyAboutLink(ABOUT_MAIL_MYGOD)).assertEqual(ABOUT_LINK_EMAIL);
      expect(classifyAboutLink('mailto:someone@example.com')).assertEqual(ABOUT_LINK_EMAIL);
    });

    it('U10#classifiesOssLink', 0, () => {
      expect(classifyAboutLink('#other-licenses')).assertEqual(ABOUT_LINK_OSS);
      expect(classifyAboutLink('#')).assertEqual(ABOUT_LINK_OSS);
    });

    it('U10#splitsAboutBodyIntoParagraphs', 0, () => {
      const text = '  First paragraph.  \n\n' +
        'Second line one.\nSecond line two.\n\n\n  Third paragraph.\n';
      const paragraphs = splitAboutBody(text);
      expect(paragraphs.length).assertEqual(3);
      expect(paragraphs[0]).assertEqual('First paragraph.');
      // One newline inside a block does not split it.
      expect(paragraphs[1]).assertEqual('Second line one.\nSecond line two.');
      expect(paragraphs[2]).assertEqual('Third paragraph.');
    });

    it('U10#dropsEmptyAboutBody', 0, () => {
      expect(splitAboutBody('').length).assertEqual(0);
      expect(splitAboutBody('\n\n').length).assertEqual(0);
      expect(splitAboutBody('   \n\n \t \n').length).assertEqual(0);
    });

    it('U10#licenceLinksFollowAboutHtml', 0, () => {
      expect(ABOUT_LICENCE_URLS.length).assertEqual(7);
      expect(ABOUT_LICENCE_URLS[6]).assertEqual('#other-licenses');
      expect(ABOUT_LICENCE_URLS[5].indexOf('license-openssl-ssleay.txt') >= 0).assertTrue();
      expect(ABOUT_LICENCE_URLS[0].indexOf('redsocks') >= 0).assertTrue();
      expect(ABOUT_LICENCE_URLS[3].indexOf('shadowsocks-rust') >= 0).assertTrue();
      // The six web links open in a browser. The anchor reports unavailable.
      expect(classifyAboutLink(ABOUT_LICENCE_URLS[0])).assertEqual(ABOUT_LINK_WEB);
      expect(classifyAboutLink(ABOUT_LICENCE_URLS[5])).assertEqual(ABOUT_LINK_WEB);
      expect(classifyAboutLink(ABOUT_LICENCE_URLS[6])).assertEqual(ABOUT_LINK_OSS);
    });
  });
}
