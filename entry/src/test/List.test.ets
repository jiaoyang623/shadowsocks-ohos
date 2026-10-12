import profileTest from './Profile.test';
import subscriptionTest from './Subscription.test';
import diagnosticsTest from './Diagnostics.test';
import settingsTest from './Settings.test';

export default function testsuite() {
  profileTest();
  subscriptionTest();
  diagnosticsTest();
  settingsTest();
}
