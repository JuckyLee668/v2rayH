import { AppTheme } from '../common/AppTheme';
import { AppState } from '../common/AppState';
import { HomeTab } from '../view/HomeTab';
import { ConfigTab } from '../view/ConfigTab';
import { SettingsTab } from '../view/SettingsTab';

@Entry
@Component
struct Index {
  @State app: AppState = new AppState();
  @State currentIndex: number = 0;
  @State configReset: number = 0;
  @State settingsReset: number = 0;
  @StorageProp('bottomRectHeight') bottomRectPx: number = 0;
  @StorageProp('systemDarkFlag') @Watch('onSystemDark') systemDarkFlag: boolean = false;
  @StorageLink('themeRev') themeRev: number = 0;
  private tabsController: TabsController = new TabsController();

  onSystemDark(): void {
    this.app.setSystemDark(this.systemDarkFlag);
  }

  onTabBarTap(index: number): void {
    if (index !== this.currentIndex) {
      return;
    }
    if (index === 1) {
      this.configReset = this.configReset + 1;
    } else if (index === 2) {
      this.settingsReset = this.settingsReset + 1;
    }
  }

  aboutToAppear(): void {
    let ctx = this.getUIContext().getHostContext();
    if (ctx !== undefined) {
      this.app.init(ctx);
    }
  }

  @Builder
  tabItem(label: string, icon: Resource, idx: number) {
    Column({ space: 2 }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([this.currentIndex === idx ? AppTheme.PRIMARY : AppTheme.TEXT_SUB])
      Text(label)
        .fontSize(10)
        .fontColor(this.currentIndex === idx ? AppTheme.PRIMARY : AppTheme.TEXT_SUB)
        .fontWeight(this.currentIndex === idx ? FontWeight.Medium : FontWeight.Normal)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Tabs({ barPosition: BarPosition.End, controller: this.tabsController }) {
      TabContent() {
        HomeTab({ app: this.app })
      }
      .tabBar(this.tabItem('主页', $r('sys.symbol.house'), 0))

      TabContent() {
        ConfigTab({ app: this.app, resetTick: this.configReset })
      }
      .tabBar(this.tabItem('配置', $r('sys.symbol.slider_horizontal_2'), 1))

      TabContent() {
        SettingsTab({ app: this.app, resetTick: this.settingsReset })
      }
      .tabBar(this.tabItem('设置', $r('sys.symbol.gearshape'), 2))
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.PAGE_BG)
    .barMode(BarMode.Fixed)
    .barHeight(56)
    .barOverlap(true)
    .scrollable(false)
    .animationDuration(0)
    .barBackgroundColor(AppTheme.CARD_BG)
    .barBackgroundBlurStyle(BlurStyle.Thick)
    .padding({ bottom: px2vp(this.bottomRectPx) })
    .onTabBarClick((index: number) => {
      this.onTabBarTap(index);
    })
    .onChange((index: number) => {
      this.currentIndex = index;
    })
  }
}
