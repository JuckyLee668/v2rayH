export class AppTheme {
  static PRIMARY: string = '#0a59f7';
  static PRIMARY_SOFT: string = '#e8f0ff';
  static DANGER: string = '#e84026';
  static DANGER_SOFT: string = '#fdecea';
  static OK: string = '#34c759';
  static OK_SOFT: string = '#e6f8ec';
  static TEXT: string = '#1c1c1e';
  static TEXT_SUB: string = '#8a8a8e';
  static TEXT_WEAK: string = '#b8b8c0';
  static PAGE_BG: string = '#f2f2f7';
  static CARD_BG: string = '#ffffff';
  static CHIP_BG: string = '#ececf0';
  static DIVIDER: string = '#f0f0f3';

  static readonly CARD_RADIUS: number = 20;
  static readonly PAGE_GAP: number = 16;
  static readonly BAR_RESERVE: number = 74;

  static applyAppearance(dark: boolean, accentIndex: number): void {
    if (dark) {
      AppTheme.PAGE_BG = '#000000';
      AppTheme.CARD_BG = '#1c1c1e';
      AppTheme.TEXT = '#f5f5f7';
      AppTheme.TEXT_SUB = '#98989f';
      AppTheme.TEXT_WEAK = '#6c6c70';
      AppTheme.CHIP_BG = '#2c2c2e';
      AppTheme.DIVIDER = '#2c2c2e';
      AppTheme.DANGER = '#ff453a';
      AppTheme.DANGER_SOFT = '#3a1c1a';
      AppTheme.OK = '#30d158';
      AppTheme.OK_SOFT = '#13301c';
    } else {
      AppTheme.PAGE_BG = '#f2f2f7';
      AppTheme.CARD_BG = '#ffffff';
      AppTheme.TEXT = '#1c1c1e';
      AppTheme.TEXT_SUB = '#8a8a8e';
      AppTheme.TEXT_WEAK = '#b8b8c0';
      AppTheme.CHIP_BG = '#ececf0';
      AppTheme.DIVIDER = '#f0f0f3';
      AppTheme.DANGER = '#e84026';
      AppTheme.DANGER_SOFT = '#fdecea';
      AppTheme.OK = '#34c759';
      AppTheme.OK_SOFT = '#e6f8ec';
    }
    let primary: string = '#0a59f7';
    let softLight: string = '#e8f0ff';
    let softDark: string = '#17263f';
    if (accentIndex === 1) {
      primary = '#34c759';
      softLight = '#e6f8ec';
      softDark = '#14301c';
    } else if (accentIndex === 2) {
      primary = '#7b61ff';
      softLight = '#f0ecff';
      softDark = '#241f3d';
    } else if (accentIndex === 3) {
      primary = '#ff8a00';
      softLight = '#fff1e0';
      softDark = '#3a2614';
    } else if (accentIndex === 4) {
      primary = '#ff3b30';
      softLight = '#ffe9e8';
      softDark = '#3a1c1a';
    }
    AppTheme.PRIMARY = primary;
    AppTheme.PRIMARY_SOFT = dark ? softDark : softLight;
  }
}
