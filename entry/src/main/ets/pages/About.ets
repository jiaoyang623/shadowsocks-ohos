/*******************************************************************************
 *                                                                             *
 *  Copyright (C) 2026 by Max Lv <max.c.lv@gmail.com>                          *
 *                                                                             *
 *  This program is free software: you can redistribute it and/or modify       *
 *  it under the terms of the GNU General Public License as published by       *
 *  the Free Software Foundation, either version 3 of the License, or          *
 *  (at your option) any later version.                                        *
 *                                                                             *
 *  This program is distributed in the hope that it will be useful,            *
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of             *
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the              *
 *  GNU General Public License for more details.                               *
 *                                                                             *
 *  You should have received a copy of the GNU General Public License          *
 *  along with this program. If not, see <http://www.gnu.org/licenses/>.       *
 *                                                                             *
 *******************************************************************************/

import { promptAction, router } from '@kit.ArkUI';
import { bundleManager } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import sslocal from 'libsslocal.so';
import { abilityContext } from '../model/AppContext';
import {
  ABOUT_LICENCE_URLS, ABOUT_MAIL_MAX_LV, ABOUT_MAIL_MYGOD, ABOUT_URL_GNU,
  ABOUT_URL_SHADOWSOCKS, aboutTitle, splitAboutBody,
} from '../model/AboutLinks';
import { ABOUT_NO_HANDLER, ABOUT_UNSUPPORTED, openAboutLink } from '../model/AboutOpener';

const TAG = 'About';

/** What the page shows when the bundle will not say. */
interface Versions {
  app: string;
  core: string;
}

/** One tappable row: the text the user reads and the URL it opens. */
interface AboutRow {
  label: ResourceStr;
  url: string;
}

/** The project and author links, in the order the Android page lists them. */
const ABOUT_LINKS: AboutRow[] = [
  { label: $r('app.string.about_link_shadowsocks'), url: ABOUT_URL_SHADOWSOCKS },
  { label: $r('app.string.about_link_max_lv'), url: ABOUT_MAIL_MAX_LV },
  { label: $r('app.string.about_link_mygod'), url: ABOUT_MAIL_MYGOD },
  { label: $r('app.string.about_link_gnu'), url: ABOUT_URL_GNU },
];

/** The seven library licences, in the order of the Android `about.html`. */
const ABOUT_LICENCES: AboutRow[] = [
  { label: $r('app.string.about_link_redsocks'), url: ABOUT_LICENCE_URLS[0] },
  { label: $r('app.string.about_link_libevent'), url: ABOUT_LICENCE_URLS[1] },
  { label: $r('app.string.about_link_tun2socks'), url: ABOUT_LICENCE_URLS[2] },
  { label: $r('app.string.about_link_shadowsocks_rust'), url: ABOUT_LICENCE_URLS[3] },
  { label: $r('app.string.about_link_libsodium'), url: ABOUT_LICENCE_URLS[4] },
  { label: $r('app.string.about_link_openssl'), url: ABOUT_LICENCE_URLS[5] },
  { label: $r('app.string.about_link_other'), url: ABOUT_LICENCE_URLS[6] },
];

/**
 * Version, licence and links: the things a user is told when they ask what
 * they are running. shadowsocks-android has the same screen. The version
 * numbers are shown separately here because the native core is patched, so it
 * can differ from any released shadowsocks-rust build.
 *
 * The title carries the version, as the Android toolbar title does. The body
 * and the licence rows scroll, because the text is longer than the screen.
 */
@Entry
@Component
struct AboutPage {
  @State versions: Versions = { app: '', core: '' };
  @State paragraphs: string[] = [];

  aboutToAppear(): void {
    this.versions = AboutPage.read();
    const body: string = this.text($r('app.string.about_about_text')) + '\n\n' +
      this.text($r('app.string.about_body_notice'));
    this.paragraphs = splitAboutBody(body);
  }

  private static read(): Versions {
    let app = '';
    try {
      app = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT).versionName;
    } catch (e) {
      hilog.warn(0x0000, TAG, 'could not read the bundle version');
    }
    let core = '';
    try {
      core = sslocal.version();
    } catch (e) {
      hilog.warn(0x0000, TAG, 'could not read the core version');
    }
    return { app: app, core: core };
  }

  /**
   * A resource as the text it stands for. The title and the body are put
   * together in code, and a template literal cannot take a Resource.
   */
  private text(value: ResourceStr): string {
    return typeof value === 'string'
      ? value
      : abilityContext().resourceManager.getStringSync(value.id);
  }

  /** The toolbar title: the app name, with the version when the bundle says. */
  private title(): string {
    return aboutTitle(this.text($r('app.string.app_name')), this.versions.app);
  }

  /**
   * Opens one link. A link with no handler shows the raw URL, which is the
   * fallback the Android page uses. The in-page licence anchor has no target
   * on this device, so it shows a message.
   */
  private async follow(url: string): Promise<void> {
    const outcome: string = await openAboutLink(abilityContext(), url);
    if (outcome === ABOUT_NO_HANDLER) {
      promptAction.showToast({ message: url });
    } else if (outcome === ABOUT_UNSUPPORTED) {
      promptAction.showToast({ message: $r('app.string.about_other_licences_unavailable') });
    }
  }

  @Builder
  Line(label: ResourceStr, value: ResourceStr) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor($r('app.color.text_body'))
        .layoutWeight(1)
      Text(value)
        .fontSize(14)
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
  }

  @Builder
  LinkRow(label: ResourceStr, url: string) {
    Text(label)
      .fontSize(14)
      .fontColor($r('app.color.accent'))
      .width('100%')
      .padding({ top: 4, bottom: 4 })
      .copyOption(CopyOptions.LocalDevice)
      .onClick(() => this.follow(url))
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Text($r('app.string.common_back'))
          .fontSize(16)
          .fontColor($r('app.color.accent'))
          .onClick(() => router.back())
        Text(this.title())
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        // holds the title centred against the back button
        Text(' ')
          .fontSize(16)
      }
      .width('100%')
      .padding({ top: 8, bottom: 8 })

      Column() {
        this.Line($r('app.string.about_app_version'), this.versions.app)
        this.Line($r('app.string.about_native_core'), this.versions.core)
        this.Line($r('app.string.about_licence'), $r('app.string.about_licence_value'))
      }
      .width('100%')
      .padding(12)
      .borderRadius(8)
      .backgroundColor($r('app.color.surface'))

      Scroll() {
        Column({ space: 12 }) {
          if (this.paragraphs.length > 0) {
            Column({ space: 12 }) {
              ForEach(this.paragraphs, (paragraph: string) => {
                Text(paragraph)
                  .fontSize(13)
                  .fontColor($r('app.color.text_body'))
                  .copyOption(CopyOptions.LocalDevice)
              }, (paragraph: string, index: number) => `${index}`)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }

          Column() {
            ForEach(ABOUT_LINKS, (row: AboutRow) => {
              this.LinkRow(row.label, row.url)
            }, (row: AboutRow) => row.url)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Text($r('app.string.about_heading_licences'))
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_body'))
            .width('100%')

          Column() {
            ForEach(ABOUT_LICENCES, (row: AboutRow) => {
              this.LinkRow(row.label, row.url)
            }, (row: AboutRow) => row.url)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        // clear the navigation bar, so the last line stays readable
        .padding({ bottom: 16 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor($r('app.color.background'))
  }
}
