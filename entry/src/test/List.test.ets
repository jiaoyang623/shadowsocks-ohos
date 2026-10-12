import profileTest from './Profile.test';
import profileStoreTest from './ProfileStore.test';
import profilesFileTest from './ProfilesFile.test';
import subscriptionMergeTest from './SubscriptionMerge.test';
import aclTest from './Acl.test';
import subscriptionTest from './Subscription.test';
import diagnosticsTest from './Diagnostics.test';
import settingsTest from './Settings.test';

export default function testsuite() {
  profileTest();
  profileStoreTest();
  profilesFileTest();
  subscriptionMergeTest();
  aclTest();
  subscriptionTest();
  diagnosticsTest();
  settingsTest();
}
