import { common, wantAgent, WantAgent, Want } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'LongTermTask';

export class LongTermTaskModel {
  private isStart: boolean = false;

  startLongTask(currentContext: common.UIAbilityContext): void {
    if (this.isStart) {
      return;
    }
    let want: Want = {
      bundleName: 'com.xii.v2rayh',
      abilityName: 'EntryAbility'
    };
    let wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [want],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    try {
      wantAgent.getWantAgent(wantAgentInfo).then((wantAgentObj: WantAgent) => {
        backgroundTaskManager.startBackgroundRunning(currentContext, backgroundTaskManager.BackgroundMode.DATA_TRANSFER, wantAgentObj)
          .then(() => {
            this.isStart = true;
            hilog.info(DOMAIN, TAG, 'startBackgroundRunning succeeded');
          })
          .catch((error: BusinessError) => {
            hilog.error(DOMAIN, TAG, 'startBackgroundRunning failed: %{public}s', JSON.stringify(error));
          });
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'getWantAgent failed: %{public}s', JSON.stringify(error));
    }
  }

  stopLongTask(currentContext: common.UIAbilityContext): void {
    if (!this.isStart) {
      return;
    }
    backgroundTaskManager.stopBackgroundRunning(currentContext).then(() => {
      this.isStart = false;
      hilog.info(DOMAIN, TAG, 'stopBackgroundRunning succeeded');
    }).catch((error: BusinessError) => {
      hilog.error(DOMAIN, TAG, 'stopBackgroundRunning failed: %{public}s', JSON.stringify(error));
    });
  }
}
