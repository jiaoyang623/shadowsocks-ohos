import { describe, expect, it } from '@ohos/hypium';
import { AclDocument, flattenAcl, importUrls, parseAcl, serializeAcl } from '../main/ets/model/Acl';

/** A fetcher that serves the lists a test names, and fails for anything else. */
function fetcherFor(lists: Map<string, string>): (url: string) => Promise<string> {
  return (url: string): Promise<string> => {
    const body = lists.get(url);
    if (body === undefined) {
      return Promise.reject(new Error(`no such list: ${url}`));
    }
    return Promise.resolve(body);
  };
}

export default function aclTest() {
  describe('AclTest', () => {
    it('reads the sections and the default', 0, () => {
      const doc = parseAcl('[bypass_all]\n\n[proxy_list]\nexample.com\n1.2.3.0/24\n\n' +
        '[bypass_list]\nlocal.test\n');
      expect(doc.bypass).assertTrue();
      expect(doc.proxyEntries.length).assertEqual(2);
      expect(doc.proxyEntries[0]).assertEqual('example.com');
      expect(doc.bypassEntries.length).assertEqual(1);
      expect(doc.bypassEntries[0]).assertEqual('local.test');
    });

    it('takes the android section spellings too', 0, () => {
      const doc = parseAcl('[reject_all]\n[white_list]\nproxied.test\n[black_list]\ndirect.test\n');
      expect(doc.bypass).assertTrue();
      expect(doc.proxyEntries[0]).assertEqual('proxied.test');
      expect(doc.bypassEntries[0]).assertEqual('direct.test');
    });

    it('skips the sections it does not act on, and keeps going', 0, () => {
      const doc = parseAcl('[outbound_block_list]\n10.0.0.0/8\n\n[proxy_list]\nexample.com\n');
      expect(doc.proxyEntries.length).assertEqual(1);
      expect(doc.bypassEntries.length).assertEqual(0);
    });

    it('collects the lists to import, once each', 0, () => {
      const urls = importUrls('#IMPORT_URL <https://a.example/list>\n' +
        '[proxy_all]\n#IMPORT_URL<https://b.example/list>\n#IMPORT_URL <https://a.example/list>\n');
      expect(urls.length).assertEqual(2);
      expect(urls[0]).assertEqual('https://a.example/list');
      expect(urls[1]).assertEqual('https://b.example/list');
    });

    it('writes back what it read', 0, () => {
      const doc: AclDocument = {
        bypass: true,
        bypassEntries: ['direct.test'],
        proxyEntries: ['proxied.test', '1.2.3.0/24'],
        urls: ['https://a.example/list'],
      };
      const text = serializeAcl(doc);
      expect(text.startsWith('[bypass_all]\n')).assertTrue();
      expect(text.includes('[bypass_list]\ndirect.test\n')).assertTrue();
      expect(text.includes('[proxy_list]\nproxied.test\n1.2.3.0/24\n')).assertTrue();
      expect(text.includes('#IMPORT_URL <https://a.example/list>')).assertTrue();

      const again = parseAcl(text);
      expect(again.bypass).assertTrue();
      expect(again.bypassEntries.length).assertEqual(1);
      expect(again.proxyEntries.length).assertEqual(2);
      expect(again.urls.length).assertEqual(1);
    });

    it('folds an imported list into the sections it belongs to', 0, async () => {
      const lists = new Map<string, string>();
      lists.set('https://a.example/list', '[proxy_all]\n\n[proxy_list]\nremote.test\n10.0.0.0/8\n');
      const text = '[bypass_all]\n\n[bypass_list]\ndirect.test\n\n#IMPORT_URL <https://a.example/list>\n';

      const flat = await flattenAcl(text, 1, fetcherFor(lists));
      const doc = parseAcl(flat);
      // the default is the importer's, and the imported entries went to the
      // list their own section named
      expect(doc.bypass).assertTrue();
      expect(doc.bypassEntries[0]).assertEqual('direct.test');
      expect(doc.proxyEntries.length).assertEqual(2);
      expect(doc.proxyEntries[0]).assertEqual('remote.test');
      // the import line is kept, so a later run can refresh it
      expect(doc.urls.length).assertEqual(1);
    });

    it('follows an import inside an imported list', 0, async () => {
      const lists = new Map<string, string>();
      lists.set('https://a.example/list', '[proxy_all]\n#IMPORT_URL <https://b.example/list>\n');
      lists.set('https://b.example/list', '[proxy_all]\n\n[proxy_list]\nsecond.test\n');

      const oneDeep = parseAcl(await flattenAcl('[proxy_all]\n#IMPORT_URL <https://a.example/list>\n',
        1, fetcherFor(lists)));
      expect(oneDeep.proxyEntries.length).assertEqual(0);

      const twoDeep = parseAcl(await flattenAcl('[proxy_all]\n#IMPORT_URL <https://a.example/list>\n',
        2, fetcherFor(lists)));
      expect(twoDeep.proxyEntries.length).assertEqual(1);
      expect(twoDeep.proxyEntries[0]).assertEqual('second.test');
    });

    it('reads entries before a section as bypass rules, like the core', 0, async () => {
      // A default line sets the mode and leaves the current list alone, in the
      // core's parser and in Android's alike, so entries under `[proxy_all]`
      // with no section of their own are bypass rules. Reading them any other
      // way would change what the file means once it is flattened.
      const lists = new Map<string, string>();
      lists.set('https://a.example/list', '[proxy_all]\nbare.test\n');
      const flat = await flattenAcl('[proxy_all]\n\n#IMPORT_URL <https://a.example/list>\n',
        1, fetcherFor(lists));
      const doc = parseAcl(flat);
      expect(doc.bypassEntries.length).assertEqual(1);
      expect(doc.bypassEntries[0]).assertEqual('bare.test');
      expect(doc.proxyEntries.length).assertEqual(0);
    });

    it('leaves the file alone when a list cannot be fetched', 0, async () => {
      const text = '[proxy_all]\n\n[proxy_list]\nmine.test\n\n#IMPORT_URL <https://gone.example/list>\n';
      const flat = await flattenAcl(text, 1, fetcherFor(new Map<string, string>()));
      expect(parseAcl(flat).proxyEntries.length).assertEqual(1);
      expect(parseAcl(flat).proxyEntries[0]).assertEqual('mine.test');
    });

    it('does nothing when there is nothing to import', 0, async () => {
      const text = '[proxy_all]\n\n[proxy_list]\nmine.test\n';
      expect(await flattenAcl(text, 1, fetcherFor(new Map<string, string>()))).assertEqual(text);
    });
  });
}
