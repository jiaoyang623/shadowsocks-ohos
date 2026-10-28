import { describe, expect, it } from '@ohos/hypium';
import { parseAcl } from '../main/ets/model/Acl';
import {
  RULE_KIND_DOMAIN, RULE_KIND_SUBNET, RULE_KIND_URL, addRule, addRulesFromText,
  composeCustomRules, domainRule, removeRule, removeRules,
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

    it('reads an absent or empty user file as no rules, not as proxy everything', 0, () => {
      // readUserRules returns '' both for a missing file and for an empty one.
      // The composed file must keep that meaning: [bypass_all] with no lists,
      // so no destination is proxied. A torn or truncated read must never turn
      // into a file that proxies every destination.
      const texts: string[] = ['', '\n', '# nothing yet\n'];
      for (const text of texts) {
        const composed = parseAcl(composeCustomRules(text));
        expect(composed.bypass).assertTrue();
        expect(composed.proxyEntries.length).assertEqual(0);
        expect(composed.bypassEntries.length).assertEqual(0);
        expect(composed.urls.length).assertEqual(0);
      }
    });

    it('adds a domain, a subnet and an import', 0, () => {
      let text = addRule('', RULE_KIND_DOMAIN, 'example.com');
      text = addRule(text, RULE_KIND_SUBNET, '10.0.0.0/8');
      text = addRule(text, RULE_KIND_URL, 'https://a.example/list');

      const doc = parseAcl(text);
      expect(doc.proxyEntries.length).assertEqual(2);
      // a Domain rule is stored as its anchored pattern
      expect(doc.proxyEntries[0]).assertEqual(domainRule('example.com'));
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
      // the selection holds the stored forms, which is what the rows show
      const left = parseAcl(removeRules(text, [domainRule('a.test'), domainRule('c.test')]));
      expect(left.proxyEntries.length).assertEqual(1);
      expect(left.proxyEntries[0]).assertEqual(domainRule('b.test'));
      // and one at a time is the same thing
      expect(parseAcl(removeRule(text, domainRule('b.test'))).proxyEntries.length).assertEqual(2);
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
      // a proxy_all list drops its subnets, because their meaning belongs to it
      const fromProxyAll = parseAcl(addRulesFromText('',
        '[proxy_all]\n\n[proxy_list]\n10.7.0.0/16\nkept.test\n'));
      expect(fromProxyAll.proxyEntries.length).assertEqual(1);
      expect(fromProxyAll.proxyEntries[0]).assertEqual('kept.test');
    });

    it('takes a list with no sections as a list to proxy', 0, () => {
      // the entries of such a text land in the proxy list, since the import
      // reads it with a bypass default, and a pasted list still means "these"
      const doc = parseAcl(addRulesFromText('', 'a.test\nb.test\n10.7.0.0/16\n'));
      expect(doc.proxyEntries.length).assertEqual(3);
      expect(doc.proxyEntries[0]).assertEqual('a.test');
      // a plain list keeps its subnets
      expect(doc.proxyEntries[2]).assertEqual('10.7.0.0/16');
    });

    it('does not add a rule it already has', 0, () => {
      // an entry a sectioned list bypasses is not a rule to add
      expect(parseAcl(addRulesFromText('', '[proxy_all]\n\n[bypass_list]\na.test\n'))
        .proxyEntries.length).assertEqual(0);
      // the target list holds the stored form, so the same form is a duplicate
      const twice = addRulesFromText(addRule('', RULE_KIND_DOMAIN, 'a.test'),
        `[bypass_all]\n\n[proxy_list]\n${domainRule('a.test')}\n`);
      expect(parseAcl(twice).proxyEntries.length).assertEqual(1);
    });
  });
}
