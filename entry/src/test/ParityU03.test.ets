import { describe, expect, it } from '@ohos/hypium';
import { MODE_PROXY, MODE_VPN, ipv6SwitchEnabled } from '../main/ets/model/Diagnostics';
import {
  DEFAULT_REMOTE_DNS, Profile, STATUS_ACTIVE, STATUS_OBSOLETE, STATUS_USER_CONFIGURED,
  isSubscriptionLocked, newManualProfile, normalizeRemotePort,
} from '../main/ets/model/Profile';
import { ROUTE_ALL, ROUTE_GFWLIST } from '../main/ets/model/Routes';
import {
  decodeFallbackChoice, eligibleFallbacks, encodeFallbackChoice, fallbackDisplayName,
  fallbackRowIndex, fallbackSummary,
} from '../main/ets/model/UdpFallback';

/** The manual profile defaults, as the LLD fixes them. */
const MANUAL_HOST: string = 'example.shadowsocks.org';
const MANUAL_PASSWORD: string = 'u1rRWTssNv0p';
const MANUAL_METHOD: string = 'aes-256-gcm';

/** A stored profile with the fields the fallback rules read. */
function storedProfile(id: string, name: string, host: string, port: number): Profile {
  const profile = new Profile();
  profile.id = id;
  profile.name = name;
  profile.host = host;
  profile.remotePort = port;
  return profile;
}

export default function parityU03Test() {
  describe('U03', () => {
    it('U03#portOutsideRangeFallsBack', 0, () => {
      // A value below the range, above the range, or not a number takes 8388.
      expect(normalizeRemotePort('0')).assertEqual(8388);
      expect(normalizeRemotePort('65536')).assertEqual(8388);
      expect(normalizeRemotePort('70000')).assertEqual(8388);
      expect(normalizeRemotePort('-1')).assertEqual(8388);
      expect(normalizeRemotePort('abc')).assertEqual(8388);
      expect(normalizeRemotePort('')).assertEqual(8388);
    });

    it('U03#portInsideRangeIsKept', 0, () => {
      // The two range ends and two values inside the range keep their value.
      expect(normalizeRemotePort('1')).assertEqual(1);
      expect(normalizeRemotePort('65535')).assertEqual(65535);
      expect(normalizeRemotePort('8388')).assertEqual(8388);
      expect(normalizeRemotePort('12345')).assertEqual(12345);
    });

    it('U03#manualProfileUsesDefaults', 0, () => {
      const profile = newManualProfile(null);
      expect(profile.host).assertEqual(MANUAL_HOST);
      expect(profile.name).assertEqual('');
      expect(profile.remotePort).assertEqual(8388);
      expect(profile.password).assertEqual(MANUAL_PASSWORD);
      expect(profile.method).assertEqual(MANUAL_METHOD);
      expect(profile.route).assertEqual(ROUTE_ALL);
      expect(profile.ipv6).assertFalse();
      expect(profile.udpFallbackId).assertEqual('');
      // The row needs an id before the editor opens.
      expect(profile.id.length > 0).assertTrue();
    });

    it('U03#manualProfileCopiesFeatures', 0, () => {
      const current = new Profile();
      current.route = ROUTE_GFWLIST;
      current.ipv6 = true;
      current.udpdns = true;
      // Server identity and the fallback stay with the current profile.
      current.host = 'current.example';
      current.remotePort = 9000;
      current.name = 'Current';
      current.password = 'current-password';
      current.method = 'aes-128-gcm';
      current.remoteDns = 'dns.example';
      current.udpFallbackId = 'fallback-id';

      const profile = newManualProfile(current);
      expect(profile.route).assertEqual(ROUTE_GFWLIST);
      expect(profile.ipv6).assertTrue();
      expect(profile.udpdns).assertTrue();
      expect(profile.host).assertEqual(MANUAL_HOST);
      expect(profile.name).assertEqual('');
      expect(profile.remotePort).assertEqual(8388);
      expect(profile.password).assertEqual(MANUAL_PASSWORD);
      expect(profile.method).assertEqual(MANUAL_METHOD);
      expect(profile.remoteDns).assertEqual(DEFAULT_REMOTE_DNS);
      expect(profile.udpFallbackId).assertEqual('');
      expect(profile.id.length > 0).assertTrue();
    });

    it('U03#activeSubscriptionLocksEdits', 0, () => {
      const profile = new Profile();
      profile.subscriptionStatus = STATUS_ACTIVE;
      expect(isSubscriptionLocked(profile)).assertTrue();
      profile.subscriptionStatus = STATUS_USER_CONFIGURED;
      expect(isSubscriptionLocked(profile)).assertFalse();
      profile.subscriptionStatus = STATUS_OBSOLETE;
      expect(isSubscriptionLocked(profile)).assertFalse();
    });

    it('U03#ipv6SwitchNeedsVpnMode', 0, () => {
      expect(ipv6SwitchEnabled(MODE_VPN)).assertTrue();
      expect(ipv6SwitchEnabled(MODE_PROXY)).assertFalse();
    });

    it('U03#fallbackKeepsOtherProfiles', 0, () => {
      const edited = storedProfile('edited', 'Edited', 'edited.example', 8388);
      const other = storedProfile('other', 'Other', 'other.example', 8388);
      const eligible = eligibleFallbacks([edited, other], edited.id);
      expect(eligible.length).assertEqual(1);
      expect(eligible[0].id).assertEqual('other');
    });

    it('U03#fallbackOmitsEditedProfile', 0, () => {
      const edited = storedProfile('edited', 'Edited', 'edited.example', 8388);
      const profiles = [edited, storedProfile('other', 'Other', 'other.example', 8388)];
      const eligible = eligibleFallbacks(profiles, edited.id);
      // The input order is kept and the edited profile is absent.
      expect(eligible.length).assertEqual(1);
      expect(eligible[0].id).assertEqual('other');
      expect(eligibleFallbacks([edited], edited.id).length).assertEqual(0);
    });

    it('U03#fallbackOmitsPluginProfiles', 0, () => {
      const edited = storedProfile('edited', 'Edited', 'edited.example', 8388);
      const plain = storedProfile('plain', 'Plain', 'plain.example', 8388);
      const plugin = storedProfile('plugin', 'Plugin', 'plugin.example', 8388);
      plugin.plugin = 'obfs-local';
      const eligible = eligibleFallbacks([plain, plugin], edited.id);
      expect(eligible.length).assertEqual(1);
      expect(eligible[0].id).assertEqual('plain');
    });

    it('U03#fallbackOmitsObsoleteProfiles', 0, () => {
      const edited = storedProfile('edited', 'Edited', 'edited.example', 8388);
      const active = storedProfile('active', 'Active', 'active.example', 8388);
      const obsolete = storedProfile('obsolete', 'Obsolete', 'obsolete.example', 8388);
      obsolete.subscriptionStatus = STATUS_OBSOLETE;
      const eligible = eligibleFallbacks([active, obsolete], edited.id);
      expect(eligible.length).assertEqual(1);
      expect(eligible[0].id).assertEqual('active');
    });

    it('U03#fallbackNameUsesName', 0, () => {
      const profile = storedProfile('backup', 'Backup', 'backup.example', 8388);
      expect(fallbackDisplayName(profile)).assertEqual('Backup');
    });

    it('U03#fallbackNameUsesAddress', 0, () => {
      // An empty name shows the address, and an IPv6 host takes brackets.
      const ipv4 = storedProfile('backup', '', 'backup.example', 8388);
      expect(fallbackDisplayName(ipv4)).assertEqual('backup.example:8388');
      const ipv6 = storedProfile('backup6', '', '2001:db8::1', 8388);
      expect(fallbackDisplayName(ipv6)).assertEqual('[2001:db8::1]:8388');
    });

    it('U03#fallbackSummaryHidesMissingProfile', 0, () => {
      const profile = storedProfile('backup', 'Backup', 'backup.example', 8388);
      const profiles = [profile];
      // An empty id and an id that names no profile both show Disabled.
      expect(fallbackSummary(profiles, '')).assertEqual('');
      expect(fallbackSummary(profiles, 'missing')).assertEqual('');
      expect(fallbackSummary(profiles, 'backup')).assertEqual('Backup');
    });

    it('U03#fallbackRowIndexSkipsDisabledRow', 0, () => {
      const first = storedProfile('first', 'First', 'first.example', 8388);
      const second = storedProfile('second', 'Second', 'second.example', 8388);
      const profiles = [first, second];
      // Row 0 is Disabled, so the first profile sits at row 1.
      expect(fallbackRowIndex(profiles, 'first')).assertEqual(1);
      expect(fallbackRowIndex(profiles, 'second')).assertEqual(2);
      expect(fallbackRowIndex(profiles, 'missing')).assertEqual(0);
    });

    it('U03#fallbackChoiceReachesItsEditor', 0, () => {
      const chosen = encodeFallbackChoice('profile-a', '7');
      expect(decodeFallbackChoice('profile-a', chosen)).assertEqual('7');
      // An empty id means Disabled, and it is a choice, not a missing value.
      const disabled = encodeFallbackChoice('profile-a', '');
      expect(decodeFallbackChoice('profile-a', disabled)).assertEqual('');
    });

    it('U03#fallbackChoiceIgnoresOtherProfiles', 0, () => {
      const other = encodeFallbackChoice('profile-a', '7');
      expect(decodeFallbackChoice('profile-b', other)).assertEqual(null);
      // A value that is not JSON, and an empty value, yield no choice.
      expect(decodeFallbackChoice('profile-a', 'not json')).assertEqual(null);
      expect(decodeFallbackChoice('profile-a', '')).assertEqual(null);
    });
  });
}
