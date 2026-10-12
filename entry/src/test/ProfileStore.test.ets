import { describe, expect, it } from '@ohos/hypium';
import { Profile, STATUS_ACTIVE, STATUS_USER_CONFIGURED, nextUserOrder } from '../main/ets/model/Profile';
import { ProfileStore } from '../main/ets/model/ProfileStore';

export default function profileStoreTest() {
  describe('ProfileStoreTest', () => {
    it('fills in defaults for a profile written before the fields existed', 0, () => {
      // what an older build left on disk: the fields below were not in it
      const legacy = '{"id":"a","name":"Old","host":"example.com","remotePort":8388,' +
        '"password":"pw","method":"aes-256-gcm","route":"all","subscriptionId":"",' +
        '"localAddress":"127.0.0.1","localPort":1080,"plugin":"","pluginOpts":""}';
      const loaded = ProfileStore.fromJson(JSON.parse(legacy) as Profile);
      expect(loaded.remoteDns).assertEqual('dns.google');
      expect(loaded.udpdns).assertFalse();
      expect(loaded.ipv6).assertFalse();
      expect(loaded.udpFallbackId).assertEqual('');
      expect(loaded.subscriptionStatus).assertEqual(STATUS_USER_CONFIGURED);
      expect(loaded.tx).assertEqual(0);
      expect(loaded.rx).assertEqual(0);
      expect(loaded.userOrder).assertEqual(0);
    });

    it('keeps the values a stored profile does carry', 0, () => {
      const stored = new Profile();
      stored.id = 'b';
      stored.remoteDns = '9.9.9.9';
      stored.subscriptionStatus = STATUS_ACTIVE;
      stored.tx = 1024;
      stored.rx = 2048;
      stored.userOrder = 7;

      const loaded = ProfileStore.fromJson(stored);
      expect(loaded.remoteDns).assertEqual('9.9.9.9');
      expect(loaded.subscriptionStatus).assertEqual(STATUS_ACTIVE);
      expect(loaded.tx).assertEqual(1024);
      expect(loaded.rx).assertEqual(2048);
      expect(loaded.userOrder).assertEqual(7);
    });

    it('numbers a new profile after the ones already there', 0, () => {
      const first = new Profile();
      const later = new Profile();
      later.userOrder = 4;
      expect(nextUserOrder([])).assertEqual(1);
      expect(nextUserOrder([first])).assertEqual(1);
      expect(nextUserOrder([first, later])).assertEqual(5);
    });
  });
}
