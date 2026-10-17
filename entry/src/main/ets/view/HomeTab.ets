import { AppState } from '../common/AppState';
import { AppTheme } from '../common/AppTheme';
import { ServerConfig } from '../model/ServerConfig';

@Component
export struct HomeTab {
  @ObjectLink app: AppState;
  @StorageProp('themeRev') themeRev: number = 0;
  @StorageProp('topRectHeight') topRectPx: number = 0;
  @StorageProp('bottomRectHeight') bottomRectPx: number = 0;

  private ipLabel(): string {
    if (!this.app.connected && !this.app.ipBusy) {
      return '';
    }
    if (this.app.exitIp.length > 0) {
      return this.app.exitIp;
    }
    if (this.app.ipBusy) {
      return 'IP 获取中...';
    }
    return 'IP 未获取';
  }

  @Builder
  header() {
    Row() {
      Column() {
        Text('v2rayH')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.TEXT)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Circle()
            .width(8)
            .height(8)
            .fill(this.app.connected ? AppTheme.OK : AppTheme.TEXT_WEAK)
          Text(this.app.connected ? '已连接' : '未连接')
            .fontSize(12)
            .fontColor(this.app.connected ? AppTheme.OK : AppTheme.TEXT_SUB)
            .fontWeight(FontWeight.Medium)
        }
        .padding({ left: 10, right: 12, top: 6, bottom: 6 })
        .backgroundColor(this.app.connected ? AppTheme.OK_SOFT : AppTheme.CHIP_BG)
        .borderRadius(100)

        Text(this.ipLabel())
          .fontSize(11)
          .fontColor(this.app.exitIp.length > 0 ? AppTheme.PRIMARY : AppTheme.TEXT_WEAK)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .height(14)
      }
      .width(104)
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  private groupOptions(): SelectOption[] {
    let out: SelectOption[] = [];
    for (let i = 0; i < this.app.groups.length; i++) {
      out.push({ value: this.app.groups[i].name });
    }
    return out;
  }

  @Builder
  groupSelector() {
    Row() {
      if (this.app.groups.length > 0) {
        Select(this.groupOptions())
          .selected(this.app.activeGroup)
          .value(this.app.activeGroupName())
          .font({ size: 13, weight: FontWeight.Medium })
          .fontColor(AppTheme.TEXT)
          .optionFont({ size: 13 })
          .selectedOptionFont({ size: 13 })
          .backgroundColor(AppTheme.CARD_BG)
          .borderRadius(10)
          .constraintSize({ maxWidth: '60%' })
          .onSelect((index: number, value: string) => {
            this.app.selectGroup(index);
          })
      } else {
        Text('订阅节点')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_SUB)
      }

      Blank()

      Text(this.app.servers.length.toString() + ' 个节点')
        .fontSize(11)
        .fontColor(AppTheme.TEXT_WEAK)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .margin({ top: 16, bottom: 8 })
  }

  @Builder
  nodeRow(item: ServerConfig, idx: number) {
    Row() {
      Column() {
        Text(item.name)
          .fontSize(15)
          .fontWeight(this.app.selected === idx ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.app.selected === idx ? AppTheme.PRIMARY : AppTheme.TEXT)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(item.protocol + ' · ' + item.address + ':' + item.port.toString())
          .fontSize(11)
          .fontColor(AppTheme.TEXT_SUB)
          .margin({ top: 3 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text(this.app.pingText(idx))
        .fontSize(12)
        .fontColor(AppTheme.TEXT_SUB)
        .margin({ right: 8 })

      if (this.app.selected === idx) {
        SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
          .fontSize(20)
          .fontColor([AppTheme.PRIMARY])
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
  }

  @Builder
  emptyNodes() {
    Column() {
      SymbolGlyph($r('sys.symbol.list_bullet'))
        .fontSize(34)
        .fontColor([AppTheme.TEXT_WEAK])
      Text('还没有订阅节点')
        .fontSize(14)
        .fontColor(AppTheme.TEXT_SUB)
        .margin({ top: 10 })
      Text('去「配置」页添加订阅后，节点会显示在这里')
        .fontSize(11)
        .fontColor(AppTheme.TEXT_WEAK)
        .margin({ top: 6 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Column() {
      this.header()

      this.groupSelector()

      if (this.app.servers.length === 0) {
        this.emptyNodes()
      } else {
        List({ space: 8 }) {
          ForEach(this.app.servers, (item: ServerConfig, idx: number) => {
            ListItem() {
              this.nodeRow(item, idx)
            }
            .backgroundColor(AppTheme.CARD_BG)
            .borderRadius(14)
            .onClick(() => {
              this.app.selectServer(idx);
            })
          }, (item: ServerConfig, idx: number) => idx.toString() + '|' + item.name + '|' + item.address)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }

      if (this.app.status.length > 0) {
        Text(this.app.status)
          .fontSize(11)
          .fontColor(AppTheme.TEXT_SUB)
          .width('100%')
          .textAlign(TextAlign.Center)
          .maxLines(2)
          .margin({ top: 8, bottom: 8 })
      }

      Button(this.app.connected ? '断开连接' : '连接')
        .width('100%')
        .height(52)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .backgroundColor(this.app.connected ? AppTheme.DANGER : AppTheme.PRIMARY)
        .borderRadius(26)
        .margin({ top: 12 })
        .onClick(() => {
          if (this.app.connected) {
            this.app.disconnect();
          } else {
            this.app.connect();
          }
        })
    }
    .width('100%')
    .height('100%')
    .padding({
      left: AppTheme.PAGE_GAP,
      right: AppTheme.PAGE_GAP,
      top: px2vp(this.topRectPx) + 8,
      bottom: px2vp(this.bottomRectPx) + AppTheme.BAR_RESERVE
    })
  }
}
