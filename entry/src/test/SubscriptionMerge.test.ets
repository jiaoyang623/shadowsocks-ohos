import { describe, expect, it } from '@ohos/hypium';
import { Profile, STATUS_ACTIVE, STATUS_OBSOLETE, STATUS_USER_CONFIGURED } from '../main/ets/model/Profile';
import { mergeSubscriptionRun } from '../main/ets/model/Subscription';

const SUB = 'sub-1';

function server(name: string, host: string, port: number, status: number, subscriptionId: string): Profile {
  const profile = new Profile();
  profile.id = `${host}-${port}`;
  profile.name = name;
  profile.host = host;
  profile.remotePort = port;
  profile.password = 'old';
  profile.method = 'aes-256-gcm';
  profile.subscriptionId = subscriptionId;
  profile.subscriptionStatus = status;
  return profile;
}

function fresh(name: string, host: string, port: number): Profile {
  const profile = new Profile();
  profile.name = name;
  profile.host = host;
  profile.remotePort = port;
  profile.password = 'new';
  profile.method = 'chacha20-ietf-poly1305';
  // a body parser sets the owning subscription before the merge
  profile.subscriptionId = SUB;
  return profile;
}

export default function subscriptionMergeTest() {
  describe('SubscriptionMergeTest', () => {
    it('keeps a re-listed profile, and takes the new transport', 0, () => {
      const stored = server('A', 'a.example', 8388, STATUS_ACTIVE, SUB);
      stored.tx = 500;
      stored.userOrder = 2;
      const merged = mergeSubscriptionRun([stored], [fresh('A', 'a.example', 8388)], SUB).profiles;

      expect(merged.length).assertEqual(1);
      expect(merged[0].id).assertEqual('a.example-8388');
      expect(merged[0].tx).assertEqual(500);
      expect(merged[0].userOrder).assertEqual(2);
      expect(merged[0].subscriptionStatus).assertEqual(STATUS_ACTIVE);
      // the password is what an update is for. The resolver is the user's.
      expect(merged[0].password).assertEqual('new');
      expect(merged[0].method).assertEqual('chacha20-ietf-poly1305');
    });

    it('marks what the subscription dropped as obsolete, and keeps it', 0, () => {
      const kept = server('A', 'a.example', 8388, STATUS_ACTIVE, SUB);
      const dropped = server('B', 'b.example', 8388, STATUS_ACTIVE, SUB);

      const merged = mergeSubscriptionRun([kept, dropped], [fresh('A', 'a.example', 8388)], SUB).profiles;
      expect(merged.length).assertEqual(2);
      expect(merged[1].name).assertEqual('B');
      expect(merged[1].subscriptionStatus).assertEqual(STATUS_OBSOLETE);
    });

    it('brings an obsolete profile back rather than duplicating it', 0, () => {
      const gone = server('B', 'b.example', 8388, STATUS_OBSOLETE, SUB);
      gone.id = 'kept-id';

      const merged = mergeSubscriptionRun([gone], [fresh('B', 'b.example', 8388)], SUB).profiles;
      expect(merged.length).assertEqual(1);
      expect(merged[0].id).assertEqual('kept-id');
      expect(merged[0].subscriptionStatus).assertEqual(STATUS_ACTIVE);
      expect(merged[0].password).assertEqual('new');
    });

    it('appends what the subscription added', 0, () => {
      const existing = server('A', 'a.example', 8388, STATUS_ACTIVE, SUB);
      existing.userOrder = 1;

      const merged = mergeSubscriptionRun([existing],
        [fresh('A', 'a.example', 8388), fresh('C', 'c.example', 443)], SUB).profiles;
      expect(merged.length).assertEqual(2);
      expect(merged[1].host).assertEqual('c.example');
      expect(merged[1].subscriptionStatus).assertEqual(STATUS_ACTIVE);
      expect(merged[1].subscriptionId).assertEqual(SUB);
      expect(merged[1].userOrder).assertEqual(2);
      expect(merged[1].id.length > 0).assertTrue();
    });

    it('leaves a hand-made profile alone and retires another subscription', 0, () => {
      const manual = server('Mine', 'mine.example', 8388, STATUS_USER_CONFIGURED, '');
      const other = server('Other', 'other.example', 8388, STATUS_ACTIVE, 'sub-2');
      const mine = server('A', 'a.example', 8388, STATUS_ACTIVE, SUB);

      const merged = mergeSubscriptionRun([manual, other, mine], [fresh('A', 'a.example', 8388)], SUB).profiles;
      expect(merged.length).assertEqual(3);
      expect(merged[0].subscriptionStatus).assertEqual(STATUS_USER_CONFIGURED);
      // a run merges every URL, so a profile that no body lists becomes
      // obsolete even when another subscription owns it
      expect(merged[1].subscriptionStatus).assertEqual(STATUS_OBSOLETE);
      expect(merged[1].subscriptionId).assertEqual('sub-2');
      // the fresh copy of A brings the listed profile back
      expect(merged[2].id).assertEqual('a.example-8388');
      expect(merged[2].subscriptionStatus).assertEqual(STATUS_ACTIVE);
    });

    it('keeps one copy when a subscription lists a server twice', 0, () => {
      const first = server('A', 'a.example', 8388, STATUS_ACTIVE, SUB);
      const second = server('A', 'a.example', 8388, STATUS_ACTIVE, SUB);
      second.id = 'second';

      const merged = mergeSubscriptionRun([first, second], [fresh('A', 'a.example', 8388)], SUB).profiles;
      expect(merged.length).assertEqual(1);
      expect(merged[0].id).assertEqual('a.example-8388');
    });

    it('treats a renamed server as a different profile', 0, () => {
      // Android keys on the name as well as the address, so a rename retires
      // the old entry instead of renaming it
      const before = server('Old name', 'a.example', 8388, STATUS_ACTIVE, SUB);

      const merged = mergeSubscriptionRun([before], [fresh('New name', 'a.example', 8388)], SUB).profiles;
      expect(merged.length).assertEqual(2);
      expect(merged[0].subscriptionStatus).assertEqual(STATUS_OBSOLETE);
      expect(merged[1].name).assertEqual('New name');
      expect(merged[1].subscriptionStatus).assertEqual(STATUS_ACTIVE);
    });
  });
}
