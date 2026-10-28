import { describe, expect, it } from '@ohos/hypium';
import { flattenAcl, parseAcl } from '../main/ets/model/Acl';
import { MAX_ACL_DEPTH } from '../main/ets/model/AclSync';
import {
  RULE_ERROR_DOMAIN, RULE_ERROR_PATTERN, RULE_ERROR_URL, RULE_KIND_DOMAIN, RULE_KIND_GENERIC,
  RULE_KIND_SUBNET, RULE_KIND_URL, RULE_WARNING_CLEARTEXT, TEMPLATE_ORDER, RuleRow,
  aclTextForRules, addRule, addRulesFromText, canSwipe, checkRule, composeCustomRules,
  domainFromRule, domainRule, isSubnet, isUrlRule, joinRemovals, removeRules, restoreRules,
  ruleEditorText, ruleRows, ruleTemplateFor, setRule, showRemove, storedRule, swipeBlocked,
  toAsciiDomain, toUnicodeDomain, toggleSelected,
} from '../main/ets/model/CustomRules';
import {
  VPN_STATE_FAILED, VPN_STATE_RUNNING, VPN_STATE_STARTING, VPN_STATE_STOPPED,
} from '../main/ets/model/Diagnostics';
import {
  ROUTE_ALL, ROUTE_BYPASS_CHINA, ROUTE_BYPASS_LAN, ROUTE_BYPASS_LAN_CHINA, ROUTE_CHINA_LIST,
  ROUTE_CUSTOM_RULES, ROUTE_GFWLIST, aclFileForRoute, isValidRoute,
} from '../main/ets/model/Routes';

/** The planned user text: a proxy list with a subnet, a bypass hostname, and an import. */
const USER_TEXT: string =
  '[bypass_all]\n\n[bypass_list]\ndirect.test\n\n[proxy_list]\nproxied.test\n10.0.0.0/8\n\n' +
  '#IMPORT_URL <https://a.example/list>\n';
/** A clipboard text with the proxy default and one subnet. */
const PROXY_ALL_SUBNET: string = '[proxy_all]\n\n[proxy_list]\n10.9.0.0/16\n';
/** A clipboard text with the proxy default, one hostname, and one subnet. */
const PROXY_ALL_MIXED: string = '[proxy_all]\n\n[proxy_list]\nmixed.test\n10.9.0.0/16\n';
/** A gfwlist text: bypass default, a bare IP, a hostname, and an import URL. */
const GFW_TEXT: string =
  '[bypass_all]\n\n[proxy_list]\n14.102.250.18\nlisted.test\n\n#IMPORT_URL <https://a.example/gfw>\n';

export default function parityU06Test() {
  describe('ParityU06Test', () => {
    it('U06#add-rule-and-row-order', 0, () => {
      const rows = ruleRows(USER_TEXT);
      const values = rows.map((row: RuleRow) => row.value);
      expect(rows.length).assertEqual(3);
      expect(values[0]).assertEqual('10.0.0.0/8');
      expect(rows[0].kind).assertEqual(RULE_KIND_SUBNET);
      expect(values[1]).assertEqual('proxied.test');
      expect(rows[1].kind).assertEqual(RULE_KIND_GENERIC);
      expect(values[2]).assertEqual('https://a.example/list');
      expect(rows[2].kind).assertEqual(RULE_KIND_URL);
      // A bypass entry stays in the file and does not become a row.
      expect(values.indexOf('direct.test')).assertEqual(-1);

      const added = addRule(USER_TEXT, RULE_KIND_SUBNET, '14.102.250.18');
      const after = ruleRows(added).map((row: RuleRow) => row.value);
      expect(after.length).assertEqual(4);
      // The file order holds inside the subnet group.
      expect(after[0]).assertEqual('10.0.0.0/8');
      expect(after[1]).assertEqual('14.102.250.18');
      expect(after[2]).assertEqual('proxied.test');
      expect(after[3]).assertEqual('https://a.example/list');

      // A duplicate is not added twice.
      expect(ruleRows(addRule(added, RULE_KIND_SUBNET, '14.102.250.18')).length).assertEqual(4);

      // A Domain rule is stored as its anchored pattern and sorts with the hostnames.
      const domainRows = ruleRows(addRule(USER_TEXT, RULE_KIND_DOMAIN, 'example.com'));
      expect(domainRows.length).assertEqual(4);
      expect(domainRows[2].value).assertEqual(domainRule('example.com'));
      expect(domainRows[2].kind).assertEqual(RULE_KIND_DOMAIN);
    });

    it('U06#generic-pattern-validation', 0, () => {
      expect(checkRule(RULE_KIND_GENERIC, '10.0.0.0/8').valid).assertTrue();
      expect(checkRule(RULE_KIND_GENERIC, '').valid).assertTrue();
      expect(checkRule(RULE_KIND_GENERIC, '^example\\.com$').valid).assertTrue();
      const bad = checkRule(RULE_KIND_GENERIC, '[');
      expect(bad.valid).assertFalse();
      expect(bad.error).assertEqual(RULE_ERROR_PATTERN);
      expect(bad.detail.length > 0).assertTrue();

      expect(isSubnet('14.102.250.18')).assertTrue();
      expect(isSubnet('10.0.0.0/8')).assertTrue();
      expect(isSubnet('::1')).assertTrue();
      expect(isSubnet('::1/128')).assertTrue();
      expect(isSubnet('999.1.1.1')).assertFalse();
      expect(isSubnet('10.0.0.0/33')).assertFalse();
      expect(isSubnet('::1/129')).assertFalse();
      expect(isSubnet('a.test')).assertFalse();
      expect(isSubnet('')).assertFalse();
    });

    it('U06#domain-rule-anchor', 0, () => {
      const rule = domainRule('example.com');
      expect(rule).assertEqual('(?:^|\\.)example\\.com$');
      const matches = new RegExp(rule);
      expect(matches.test('example.com')).assertTrue();
      expect(matches.test('a.example.com')).assertTrue();
      // The trailing $ keeps the rule off a longer suffix.
      expect(matches.test('example.com.evil.com')).assertFalse();
      expect(matches.test('example.com.cn')).assertFalse();
      expect(matches.test('notexample.com')).assertFalse();
      expect(domainFromRule(rule)).assertEqual('example.com');
      expect(domainFromRule('example.com')).assertEqual(null);
    });

    it('U06#domain-idn-punycode', 0, () => {
      expect(toAsciiDomain('münchen.example')).assertEqual('xn--mnchen-3ya.example');
      expect(toAsciiDomain('例子.测试')).assertEqual('xn--fsqu00a.xn--0zwm56d');
      expect(toUnicodeDomain('xn--mnchen-3ya.example')).assertEqual('münchen.example');
      expect(toUnicodeDomain('xn--fsqu00a.xn--0zwm56d')).assertEqual('例子.测试');
      expect(domainRule('münchen.example'))
        .assertEqual('(?:^|\\.)xn--mnchen-3ya\\.example$');
      expect(ruleEditorText(domainRule('münchen.example'))).assertEqual('münchen.example');
      expect(checkRule(RULE_KIND_DOMAIN, '例子.测试').valid).assertTrue();
    });

    it('U06#domain-rejects-empty-label', 0, () => {
      const bad = checkRule(RULE_KIND_DOMAIN, 'a..b');
      expect(bad.valid).assertFalse();
      expect(bad.error).assertEqual(RULE_ERROR_DOMAIN);
      expect(toAsciiDomain('a..b')).assertEqual(null);
      expect(toAsciiDomain('-a.example')).assertEqual(null);
      expect(toAsciiDomain('a-.example')).assertEqual(null);
      expect(toAsciiDomain('a_b.example')).assertEqual(null);
      expect(toAsciiDomain('a b.example')).assertEqual(null);
      // An empty text is valid and stores an anchored empty domain.
      expect(checkRule(RULE_KIND_DOMAIN, '').valid).assertTrue();
      expect(toAsciiDomain('')).assertEqual('');
      expect(domainRule('')).assertEqual('(?:^|\\.)$');
    });

    it('U06#url-rule-cleartext-warning', 0, () => {
      const cleartext = checkRule(RULE_KIND_URL, 'http://a.example/list');
      expect(cleartext.valid).assertTrue();
      expect(cleartext.warning).assertEqual(RULE_WARNING_CLEARTEXT);
      expect(cleartext.error).assertEqual('');
      const secure = checkRule(RULE_KIND_URL, 'https://a.example/list');
      expect(secure.valid).assertTrue();
      expect(secure.warning).assertEqual('');
      const missing = checkRule(RULE_KIND_URL, 'a.example');
      expect(missing.valid).assertFalse();
      expect(missing.error).assertEqual(RULE_ERROR_URL);
      expect(checkRule(RULE_KIND_URL, 'ftp://a.example').valid).assertFalse();
      expect(checkRule(RULE_KIND_URL, 'http://').valid).assertFalse();
      expect(checkRule(RULE_KIND_URL, 'http://a.example/a b').valid).assertFalse();
      expect(isUrlRule('https://a.example/list')).assertTrue();
      expect(isUrlRule('a.example')).assertFalse();
    });

    it('U06#template-read-back', 0, () => {
      expect(TEMPLATE_ORDER.length).assertEqual(3);
      expect(TEMPLATE_ORDER[0]).assertEqual(RULE_KIND_GENERIC);
      expect(TEMPLATE_ORDER[1]).assertEqual(RULE_KIND_DOMAIN);
      expect(TEMPLATE_ORDER[2]).assertEqual(RULE_KIND_URL);
      expect(ruleTemplateFor('https://a.example/list')).assertEqual(RULE_KIND_URL);
      expect(ruleTemplateFor(domainRule('example.com'))).assertEqual(RULE_KIND_DOMAIN);
      expect(ruleTemplateFor('example.com')).assertEqual(RULE_KIND_GENERIC);
      expect(ruleTemplateFor('10.0.0.0/8')).assertEqual(RULE_KIND_GENERIC);
      expect(ruleEditorText('https://a.example/list')).assertEqual('https://a.example/list');
      expect(ruleEditorText(domainRule('example.com'))).assertEqual('example.com');
      expect(ruleEditorText(domainRule('münchen.example'))).assertEqual('münchen.example');
      expect(ruleEditorText('example.com')).assertEqual('example.com');
    });

    it('U06#empty-generic-rule', 0, () => {
      expect(checkRule(RULE_KIND_GENERIC, '').valid).assertTrue();
      expect(storedRule(RULE_KIND_GENERIC, '')).assertEqual('');
      const single = addRule('', RULE_KIND_GENERIC, '');
      expect(single.startsWith('[bypass_all]')).assertTrue();
      expect(single.startsWith('[bypass_all]\n\n[proxy_list]\n')).assertTrue();
      // An empty rule is a row for this session only. A reload drops it.
      expect(ruleRows(single).length).assertEqual(0);
      const text = addRule(USER_TEXT, RULE_KIND_GENERIC, '');
      expect(text.includes('10.0.0.0/8\n\n\n#IMPORT_URL')).assertTrue();
      expect(parseAcl(text).proxyEntries.length).assertEqual(2);
      expect(ruleRows(text).length).assertEqual(3);
    });

    it('U06#edit-replaces-rule', 0, () => {
      const oldValue = storedRule(RULE_KIND_DOMAIN, 'a.example');
      expect(oldValue).assertEqual('(?:^|\\.)a\\.example$');
      let text = addRule('', RULE_KIND_DOMAIN, 'a.example');
      text = addRule(text, RULE_KIND_URL, 'https://a.example/list');
      const next = setRule(text, oldValue, RULE_KIND_DOMAIN, 'b.example');
      const doc = parseAcl(next);
      expect(doc.proxyEntries.indexOf(oldValue)).assertEqual(-1);
      expect(doc.proxyEntries[0]).assertEqual(domainRule('b.example'));
      expect(doc.urls.length).assertEqual(1);
      // An edit of a new rule only adds the new rule.
      const added = setRule('', '', RULE_KIND_GENERIC, 'new.test');
      expect(parseAcl(added).proxyEntries[0]).assertEqual('new.test');
      // An invalid new rule removes the old rule and adds nothing.
      const invalid = setRule(text, oldValue, RULE_KIND_DOMAIN, 'a..b');
      expect(parseAcl(invalid).proxyEntries.length).assertEqual(0);
    });

    it('U06#remove-and-undo', 0, () => {
      const removedText = removeRules(USER_TEXT, ['10.0.0.0/8', 'https://a.example/list']);
      const left = parseAcl(removedText);
      expect(left.proxyEntries.length).assertEqual(1);
      expect(left.proxyEntries[0]).assertEqual('proxied.test');
      expect(left.urls.length).assertEqual(0);
      expect(left.bypassEntries[0]).assertEqual('direct.test');
      const back = parseAcl(restoreRules(removedText, ['https://a.example/list', '10.0.0.0/8']));
      expect(back.proxyEntries.indexOf('10.0.0.0/8') >= 0).assertTrue();
      expect(back.urls.indexOf('https://a.example/list') >= 0).assertTrue();
      expect(back.bypassEntries[0]).assertEqual('direct.test');
    });

    it('U06#undo-count-accumulates', 0, () => {
      const first = joinRemovals([], ['a.test']);
      expect(first.length).assertEqual(1);
      const second = joinRemovals(first, ['b.test', 'c.test']);
      expect(second.length).assertEqual(3);
      // The newest batch comes first.
      expect(second[0]).assertEqual('b.test');
      expect(second[1]).assertEqual('c.test');
      expect(second[2]).assertEqual('a.test');
      const restored = parseAcl(restoreRules(removeRules(USER_TEXT, ['proxied.test']),
        ['a.test', 'b.test', 'c.test']));
      expect(restored.proxyEntries.indexOf('a.test') >= 0).assertTrue();
      expect(restored.proxyEntries.indexOf('b.test') >= 0).assertTrue();
      expect(restored.proxyEntries.indexOf('c.test') >= 0).assertTrue();
    });

    it('U06#undo-dismissal-keeps-removal', 0, () => {
      const removedText = removeRules(USER_TEXT, ['proxied.test']);
      const bin = joinRemovals([], ['proxied.test']);
      expect(parseAcl(removedText).proxyEntries.indexOf('proxied.test')).assertEqual(-1);
      // A dismissal drops the bin and restores nothing.
      const dismissed = restoreRules(removedText, []);
      expect(parseAcl(dismissed).proxyEntries.indexOf('proxied.test')).assertEqual(-1);
      expect(bin.length).assertEqual(1);
    });

    it('U06#copy-selection-as-acl', 0, () => {
      const text = aclTextForRules(['example.com', '10.0.0.0/8', 'https://a.example/list']);
      expect(text.startsWith('[bypass_all]')).assertTrue();
      const doc = parseAcl(text);
      expect(doc.bypass).assertTrue();
      expect(doc.proxyEntries.length).assertEqual(2);
      expect(doc.proxyEntries[0]).assertEqual('example.com');
      expect(doc.proxyEntries[1]).assertEqual('10.0.0.0/8');
      expect(doc.urls.length).assertEqual(1);
      expect(doc.urls[0]).assertEqual('https://a.example/list');
      const pattern = domainRule('example.com');
      expect(parseAcl(aclTextForRules([pattern])).proxyEntries[0]).assertEqual(pattern);
    });

    it('U06#import-clipboard-and-subnet-filter', 0, () => {
      // A proxy-default list with only a subnet adds nothing.
      const onlySubnet = addRulesFromText('', PROXY_ALL_SUBNET);
      expect(parseAcl(onlySubnet).proxyEntries.length).assertEqual(0);
      expect(ruleRows(onlySubnet).length).assertEqual(0);
      // A proxy-default list keeps its hostnames and drops its subnets.
      const mixed = parseAcl(addRulesFromText('', PROXY_ALL_MIXED));
      expect(mixed.proxyEntries.length).assertEqual(1);
      expect(mixed.proxyEntries[0]).assertEqual('mixed.test');
      // A bypass-default list keeps its subnets.
      const kept = parseAcl(addRulesFromText('', GFW_TEXT));
      expect(kept.proxyEntries.indexOf('14.102.250.18') >= 0).assertTrue();
      expect(kept.proxyEntries.indexOf('listed.test') >= 0).assertTrue();
      expect(kept.urls.length).assertEqual(1);
      // A bypass entry describes the route the list came from and is dropped.
      const bypassOnly = addRulesFromText('', '[bypass_all]\n\n[bypass_list]\ndirect.test\n');
      expect(parseAcl(bypassOnly).proxyEntries.length).assertEqual(0);
      expect(parseAcl(bypassOnly).bypassEntries.length).assertEqual(0);
      // A duplicate check uses the target list only.
      const once = addRule('', RULE_KIND_GENERIC, 'dup.test');
      const twice = addRulesFromText(once, '[bypass_all]\n\n[proxy_list]\ndup.test\n');
      expect(parseAcl(twice).proxyEntries.length).assertEqual(1);
      // Nothing to add leaves the list empty, which the page reports.
      expect(ruleRows(addRulesFromText('', '# nothing here\n')).length).assertEqual(0);
    });

    it('U06#gfwlist-import', 0, () => {
      const imported = addRulesFromText('', GFW_TEXT);
      const doc = parseAcl(imported);
      expect(doc.bypass).assertTrue();
      expect(doc.proxyEntries.indexOf('14.102.250.18') >= 0).assertTrue();
      expect(doc.proxyEntries.indexOf('listed.test') >= 0).assertTrue();
      expect(doc.urls.length).assertEqual(1);
      expect(doc.urls[0]).assertEqual('https://a.example/gfw');
      expect(ruleRows(imported).length).assertEqual(3);
      // A gfwlist file with the proxy default adds no subnets.
      const proxyFile = parseAcl(addRulesFromText('',
        '[proxy_all]\n\n[proxy_list]\n10.1.2.0/24\nonly.test\n'));
      expect(proxyFile.proxyEntries.indexOf('10.1.2.0/24')).assertEqual(-1);
      expect(proxyFile.proxyEntries.indexOf('only.test') >= 0).assertTrue();
    });

    it('U06#swipe-gate', 0, () => {
      expect(swipeBlocked(ROUTE_CUSTOM_RULES, VPN_STATE_STARTING)).assertTrue();
      expect(swipeBlocked(ROUTE_CUSTOM_RULES, VPN_STATE_RUNNING)).assertTrue();
      expect(swipeBlocked(ROUTE_CUSTOM_RULES, VPN_STATE_FAILED)).assertFalse();
      expect(swipeBlocked(ROUTE_CUSTOM_RULES, VPN_STATE_STOPPED)).assertFalse();
      // Another route leaves the gate open.
      expect(swipeBlocked(ROUTE_ALL, VPN_STATE_RUNNING)).assertFalse();
      expect(swipeBlocked(ROUTE_GFWLIST, VPN_STATE_RUNNING)).assertFalse();
      expect(canSwipe(0, false)).assertTrue();
      expect(canSwipe(1, false)).assertFalse();
      expect(canSwipe(0, true)).assertFalse();
      expect(canSwipe(2, true)).assertFalse();
    });

    it('U06#selection-toggle', 0, () => {
      const none: string[] = [];
      const one = toggleSelected(none, 'a.test');
      expect(none.length).assertEqual(0);
      expect(one.length).assertEqual(1);
      expect(one[0]).assertEqual('a.test');
      const two = toggleSelected(one, 'b.test');
      expect(two.length).assertEqual(2);
      expect(two[1]).assertEqual('b.test');
      const back = toggleSelected(two, 'a.test');
      expect(back.length).assertEqual(1);
      expect(back[0]).assertEqual('b.test');
      // The earlier array is untouched.
      expect(one.length).assertEqual(1);
    });

    it('U06#compose-forced-bypass', 0, () => {
      const proxyDefault = '[proxy_all]\n\n[bypass_list]\ndirect.test\n10.5.0.0/16\n\n' +
        '[proxy_list]\nproxied.test\n10.0.0.0/8\n\n#IMPORT_URL <https://a.example/list>\n';
      const doc = parseAcl(composeCustomRules(proxyDefault));
      expect(doc.bypass).assertTrue();
      // The bypass hostname stays and the bypass subnet is dropped.
      expect(doc.bypassEntries.length).assertEqual(1);
      expect(doc.bypassEntries[0]).assertEqual('direct.test');
      // The proxy entries stay.
      expect(doc.proxyEntries.indexOf('10.0.0.0/8') >= 0).assertTrue();
      expect(doc.proxyEntries.indexOf('proxied.test') >= 0).assertTrue();
      expect(doc.urls.length).assertEqual(1);
      // Entries before a section belong to the proxy list under a bypass default.
      const bare = parseAcl(composeCustomRules('bare.test\n10.6.0.0/16\n'));
      expect(bare.bypass).assertTrue();
      expect(bare.proxyEntries.length).assertEqual(2);
      expect(bare.bypassEntries.length).assertEqual(0);
      expect(composeCustomRules('').startsWith('[bypass_all]')).assertTrue();
    });

    it('U06#flatten-depth-ten', 0, async () => {
      expect(MAX_ACL_DEPTH).assertEqual(10);
      const lists = new Map<string, string>();
      for (let i = 1; i < MAX_ACL_DEPTH; i++) {
        lists.set(`https://a.example/l${i}`,
          `[bypass_all]\n#IMPORT_URL <https://a.example/l${i + 1}>\n`);
      }
      lists.set('https://a.example/l10', '[bypass_all]\n\n[proxy_list]\ndeep.test\n');
      const fetch = (url: string): Promise<string> => {
        const body = lists.get(url);
        if (body === undefined) {
          return Promise.reject(new Error(`no such list: ${url}`));
        }
        return Promise.resolve(body);
      };
      const top = '[bypass_all]\n#IMPORT_URL <https://a.example/l1>\n';
      const flat = await flattenAcl(top, MAX_ACL_DEPTH, fetch);
      expect(parseAcl(flat).proxyEntries.indexOf('deep.test') >= 0).assertTrue();
      // One level less does not reach the deepest list.
      const shallow = await flattenAcl(top, MAX_ACL_DEPTH - 1, fetch);
      expect(parseAcl(shallow).proxyEntries.indexOf('deep.test')).assertEqual(-1);

      // A raw child takes the parent default.
      const rawLists = new Map<string, string>();
      rawLists.set('https://a.example/raw', 'raw.test\n');
      const rawFetch = (url: string): Promise<string> => {
        const body = rawLists.get(url);
        if (body === undefined) {
          return Promise.reject(new Error(`no such list: ${url}`));
        }
        return Promise.resolve(body);
      };
      const raw = await flattenAcl('[bypass_all]\n#IMPORT_URL <https://a.example/raw>\n',
        1, rawFetch);
      expect(parseAcl(raw).proxyEntries.indexOf('raw.test') >= 0).assertTrue();
      expect(parseAcl(raw).bypassEntries.indexOf('raw.test')).assertEqual(-1);
    });

    it('U06#remove-button-visibility', 0, () => {
      expect(showRemove('')).assertFalse();
      expect(showRemove('example.com')).assertTrue();
      expect(showRemove(domainRule('example.com'))).assertTrue();
      // An empty Generic rule hides Remove, as a new rule does.
      expect(showRemove(storedRule(RULE_KIND_GENERIC, ''))).assertFalse();
    });

    it('U06#route-acl-file-map', 0, () => {
      expect(aclFileForRoute(ROUTE_ALL)).assertEqual('');
      expect(aclFileForRoute(ROUTE_BYPASS_LAN)).assertEqual('bypass-lan.acl');
      expect(aclFileForRoute(ROUTE_BYPASS_CHINA)).assertEqual('bypass-china.acl');
      expect(aclFileForRoute(ROUTE_BYPASS_LAN_CHINA)).assertEqual('bypass-lan-china.acl');
      expect(aclFileForRoute(ROUTE_GFWLIST)).assertEqual('gfwlist.acl');
      expect(aclFileForRoute(ROUTE_CHINA_LIST)).assertEqual('china-list.acl');
      expect(aclFileForRoute(ROUTE_CUSTOM_RULES)).assertEqual('custom-rules.acl');
      expect(isValidRoute(ROUTE_CUSTOM_RULES)).assertTrue();
      expect(isValidRoute('nope')).assertFalse();
    });
  });
}
