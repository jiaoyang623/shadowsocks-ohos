import { describe, expect, it } from '@ohos/hypium';
import {
  AppSettings, AppSettingsJson, DEFAULT_PROBE_URL, DEFAULT_SPEED_URL, settingsFromJson,
} from '../main/ets/model/Diagnostics';

export default function settingsTest() {
  describe('SettingsTest', () => {
    it('uses the defaults when nothing has been stored', 0, () => {
      const settings: AppSettings = settingsFromJson(null);
      expect(settings.probeUrl).assertEqual(DEFAULT_PROBE_URL);
      expect(settings.speedTestUrl).assertEqual(DEFAULT_SPEED_URL);
    });

    it('keeps both stored overrides', 0, () => {
      const stored: AppSettingsJson = {
        probeUrl: 'http://example.com/generate_204',
        speedTestUrl: 'https://example.com/10mb.bin',
      };
      const settings = settingsFromJson(stored);
      expect(settings.probeUrl).assertEqual('http://example.com/generate_204');
      expect(settings.speedTestUrl).assertEqual('https://example.com/10mb.bin');
    });

    it('fills in only the field a partial file omits', 0, () => {
      const onlyProbe: AppSettingsJson = { probeUrl: 'http://example.com/generate_204' };
      expect(settingsFromJson(onlyProbe).probeUrl).assertEqual('http://example.com/generate_204');
      expect(settingsFromJson(onlyProbe).speedTestUrl).assertEqual(DEFAULT_SPEED_URL);

      const onlySpeed: AppSettingsJson = { speedTestUrl: 'https://example.com/10mb.bin' };
      expect(settingsFromJson(onlySpeed).probeUrl).assertEqual(DEFAULT_PROBE_URL);
      expect(settingsFromJson(onlySpeed).speedTestUrl).assertEqual('https://example.com/10mb.bin');
    });

    it('rejects blank values instead of accepting an unusable endpoint', 0, () => {
      const blank: AppSettingsJson = { probeUrl: '', speedTestUrl: '' };
      expect(settingsFromJson(blank).probeUrl).assertEqual(DEFAULT_PROBE_URL);
      expect(settingsFromJson(blank).speedTestUrl).assertEqual(DEFAULT_SPEED_URL);
    });
  });
}
