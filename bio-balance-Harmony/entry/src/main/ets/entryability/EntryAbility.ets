import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import hilog from '@ohos.hilog';
import UIAbility from '@ohos.app.ability.UIAbility';
import Want from '@ohos.app.ability.Want';
import window from '@ohos.window';

const DOMAIN: number = 0x0000;
const TAG: string = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'operation=ability_create');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'operation=ability_destroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'operation=window_stage_create');

    const startedAt: number = Date.now();
    windowStage.loadContent('pages/Index', (err) => {
      const durationMs: number = Date.now() - startedAt;
      if (err.code) {
        hilog.error(DOMAIN, TAG,
          'operation=load_content errorCode=%{public}d durationMs=%{public}d', err.code, durationMs);
        return;
      }
      hilog.info(DOMAIN, TAG,
        'operation=load_content errorCode=0 durationMs=%{public}d', durationMs);
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'operation=window_stage_destroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'operation=ability_foreground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'operation=ability_background');
  }
}
