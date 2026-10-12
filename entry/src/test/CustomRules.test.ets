import { describe, expect, it } from '@ohos/hypium';
import { parseAcl } from '../main/ets/model/Acl';
import { RULE_KIND_DOMAIN, RULE_KIND_SUBNET, RULE_KIND_URL, addRule, composeCustomRules, removeRule } from '../main/ets/model/CustomRules';

export default function customRulesTest() {
  describe('CustomRulesTest', () => {
    it('turns a list round so that what is listed is proxied', 0, () => {
      // a file that says "proxy everything except these" can only mean the
      // opposite here: the route is a list of what to proxy
      const composed = parseAcl(composeCustomRules('[proxy_all]\n\n[bypass_list]\ndirect.test\n'));
      expect(composed.bypass).assertTrue();
      expect(composed.bypassEntries.length).assertEqual(1);
      expect(composed.bypassEntries[0]).assertEqual('direct.test');
    });

    it('keeps the lists it was given', 0, () => {
      const composed = parseAcl(composeCustomRules('[bypass_all]\n\n[proxy_list]\nproxied.test\n10.0.0.0/8\n'));
      expect(composed.bypass).assertTrue();
      expect(composed.proxyEntries.length).assertEqual(2);
      expect(composed.proxyEntries[1]).assertEqual('10.0.0.0/8');
    });

    it('produces a usable file from nothing at all', 0, () => {
      const composed = parseAcl(composeCustomRules(''));
      expect(composed.bypass).assertTrue();
      expect(composed.proxyEntries.length).assertEqual(0);
    });

    it('adds a domain, a subnet and an import', 0, () => {
      let text = addRule('', RULE_KIND_DOMAIN, 'example.com');
      text = addRule(text, RULE_KIND_SUBNET, '10.0.0.0/8');
      text = addRule(text, RULE_KIND_URL, 'https://a.example/list');

      const doc = parseAcl(text);
      expect(doc.proxyEntries.length).assertEqual(2);
      expect(doc.proxyEntries[0]).assertEqual('example.com');
      expect(doc.proxyEntries[1]).assertEqual('10.0.0.0/8');
      expect(doc.urls.length).assertEqual(1);
      expect(doc.urls[0]).assertEqual('https://a.example/list');
    });

    it('does not add the same rule twice, or an empty one', 0, () => {
      let text = addRule('', RULE_KIND_DOMAIN, 'example.com');
      text = addRule(text, RULE_KIND_DOMAIN, 'example.com');
      text = addRule(text, RULE_KIND_DOMAIN, '   ');
      expect(parseAcl(text).proxyEntries.length).assertEqual(1);
    });

    it('removes a rule from whichever list holds it', 0, () => {
      const text = '# a comment\n[bypass_all]\n\n[proxy_list]\nkeep.test\ndrop.test\n' +
        '\n#IMPORT_URL <https://a.example/list>\n';
      const removed = removeRule(text, 'drop.test');
      expect(parseAcl(removed).proxyEntries.length).assertEqual(1);
      expect(parseAcl(removed).proxyEntries[0]).assertEqual('keep.test');

      const alsoUrl = removeRule(removed, 'https://a.example/list');
      expect(parseAcl(alsoUrl).urls.length).assertEqual(0);
    });
  });
}
