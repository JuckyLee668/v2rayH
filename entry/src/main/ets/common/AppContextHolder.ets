import { common } from '@kit.AbilityKit';

/**
 * 持有主 Ability 的 UIAbilityContext，供非 UI 模块（如 AppState）调用
 * 需要 UIAbilityContext 的系统能力（长时任务申请/取消等）。
 */
export class AppContextHolder {
  private static abilityCtx: common.UIAbilityContext | undefined = undefined;

  static set(ctx: common.UIAbilityContext): void {
    AppContextHolder.abilityCtx = ctx;
  }

  static get(): common.UIAbilityContext | undefined {
    return AppContextHolder.abilityCtx;
  }
}
