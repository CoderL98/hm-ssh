import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { HostStore } from '../services/HostStore';
import { ThemeStore } from '../services/ThemeStore';
import { AuthStore } from '../services/AuthService';
import { CloudSyncServiceFactory } from '../services/CloudSyncService';
import { AppSettings } from '../services/AppSettings';
import { HuksCrypto } from '../services/HuksCrypto';

const DOMAIN = 0x0000;
const TAG = 'HmSSH';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      AppStorage.setOrCreate('themeRev', 0);
      AppStorage.setOrCreate('authRev', 0);
      AppStorage.setOrCreate('appSettingsRev', 0);
    } catch (_e) {
      // ignore
    }
    // 默认跟随系统；ThemeStore.init 会按用户偏好覆盖
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (_e) {
      // ignore on older runtimes
    }
    hilog.info(DOMAIN, TAG, 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'Ability onWindowStageCreate');
    Promise.all([
      AppSettings.getInstance().init(this.context),
      HuksCrypto.getInstance().init().catch((e: Error) => {
        hilog.error(DOMAIN, TAG, 'HUKS init failed %{public}s', e.message ?? `${e}`);
      }),
      ThemeStore.getInstance().init(this.context),
      AuthStore.getInstance().init(this.context),
      CloudSyncServiceFactory.init(this.context)
    ]).then(async () => {
      // HostStore after HUKS/AppSettings so migration can encrypt
      await HostStore.getInstance().init(this.context);
      hilog.info(DOMAIN, TAG, 'Stores + HUKS + AppSettings ready');
    }).catch((err: Error) => {
      hilog.error(DOMAIN, TAG, 'Store init failed %{public}s', JSON.stringify(err));
    });

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'loadContent success');
    });
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    hilog.info(DOMAIN, TAG, 'onConfigurationUpdate');
    ThemeStore.getInstance().onConfigurationChanged(this.context);
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onBackground');
  }
}
