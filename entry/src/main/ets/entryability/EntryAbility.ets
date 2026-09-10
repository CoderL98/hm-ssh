import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { HostStore } from '../services/HostStore';
import { ThemeStore } from '../services/ThemeStore';
import { AuthStore } from '../services/AuthService';
import { CloudSyncServiceFactory, syncAllCoalesced } from '../services/CloudSyncService';
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
      AppStorage.setOrCreate('hostRev', 0);
      AppStorage.setOrCreate('syncToastMsg', '');
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
    // 先完成 stores，再 loadContent，避免 Index/Account 在 AuthStore/HostStore 未就绪时读空状态
    this.bootstrapStores()
      .catch((err: Error) => {
        hilog.error(DOMAIN, TAG, 'Store init failed %{public}s', JSON.stringify(err));
      })
      .then(() => {
        windowStage.loadContent('pages/Index', (err) => {
          if (err.code) {
            hilog.error(DOMAIN, TAG, 'loadContent failed %{public}s', JSON.stringify(err));
            return;
          }
          hilog.info(DOMAIN, TAG, 'loadContent success');
        });
      });
  }

  private async bootstrapStores(): Promise<void> {
    // HUKS 须先于 AppSettings：保险柜口令密文解密依赖本地 AES 密钥
    try {
      await HuksCrypto.getInstance().init();
    } catch (e) {
      const err = e instanceof Error ? e : new Error(`${e}`);
      hilog.error(DOMAIN, TAG, 'HUKS init failed %{public}s', err.message ?? `${err}`);
    }
    await AppSettings.getInstance().init(this.context);
    await Promise.all([
      ThemeStore.getInstance().init(this.context),
      AuthStore.getInstance().init(this.context),
      CloudSyncServiceFactory.init(this.context)
    ]);
    await HostStore.getInstance().init(this.context);
    hilog.info(DOMAIN, TAG, 'Stores + HUKS + AppSettings ready');

    const auth = AuthStore.getInstance();
    if (auth.isLoggedIn()) {
      // 有会话则后台全量同步；结果写入 syncToastMsg 供 Index toast
      void this.autoSyncOnLaunch();
    }
  }

  private async autoSyncOnLaunch(): Promise<void> {
    try {
      const msg = await syncAllCoalesced();
      HostStore.getInstance().notifyChanged();
      hilog.info(DOMAIN, TAG, 'Launch sync OK: %{public}s', msg);
      try {
        AppStorage.setOrCreate('syncToastMsg', msg);
      } catch (_e) {
        // ignore
      }
    } catch (e) {
      const m = e instanceof Error ? e.message : `${e}`;
      hilog.error(DOMAIN, TAG, 'Launch sync failed %{public}s', m);
      try {
        AppStorage.setOrCreate('syncToastMsg', `启动同步失败：${m}`);
      } catch (_e) {
        // ignore
      }
    }
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
