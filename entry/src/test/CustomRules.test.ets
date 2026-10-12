import { describe, expect, it } from '@ohos/hypium';
import { parseAcl } from '../main/ets/model/Acl';
import {
  RULE_KIND_DOMAIN, RULE_KIND_SUBNET, RULE_KIND_URL, addRule, addRulesFromText,
  composeCustomRules, removeRule, removeRules,
} from '../main/ets/model/CustomRules';

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
    it('removes a whole selection at once', 0, () => {
      let text = addRule('', RULE_KIND_DOMAIN, 'a.test');
      text = addRule(text, RULE_KIND_DOMAIN, 'b.test');
      text = addRule(text, RULE_KIND_DOMAIN, 'c.test');
      const left = parseAcl(removeRules(text, ['a.test', 'c.test']));
      expect(left.proxyEntries.length).assertEqual(1);
      expect(left.proxyEntries[0]).assertEqual('b.test');
      // and one at a time is the same thing
      expect(parseAcl(removeRule(text, 'b.test')).proxyEntries.length).assertEqual(2);
    });

    it('takes the entries of another list and nothing else', 0, () => {
      const imported = addRulesFromText('',
        '#IMPORT_URL <https://a.example/list>\n' +
        '[bypass_all]\n\n[proxy_list]\nproxied.test\n10.0.0.0/8\n\n[bypass_list]\ndirect.test\n');
      const doc = parseAcl(imported);
      // the entries of the list, not its sections, and not what it bypasses
      expect(doc.proxyEntries.length).assertEqual(2);
      expect(doc.proxyEntries[0]).assertEqual('proxied.test');
      expect(doc.bypassEntries.length).assertEqual(0);
      expect(doc.urls[0]).assertEqual('https://a.example/list');
    });

    it('takes a list with no sections as a list to proxy', 0, () => {
      // the entries of such a text land in the bypass list, since that is the
      // list a file starts with, and a pasted list still means "these"
      const doc = parseAcl(addRulesFromText('', 'a.test\nb.test\n'));
      expect(doc.proxyEntries.length).assertEqual(2);
      expect(doc.proxyEntries[0]).assertEqual('a.test');
    });

    it('does not add a rule it already has', 0, () => {
      // an entry a sectioned list bypasses is not a rule to add
      expect(parseAcl(addRulesFromText('', '[proxy_all]\n\n[bypass_list]\na.test\n'))
        .proxyEntries.length).assertEqual(0);
      const twice = addRulesFromText(addRule('', RULE_KIND_DOMAIN, 'a.test'),
        '[bypass_all]\n\n[proxy_list]\na.test\n');
      expect(parseAcl(twice).proxyEntries.length).assertEqual(1);
    });
  });
}
