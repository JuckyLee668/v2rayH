import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { pasteboard, BusinessError } from '@kit.BasicServicesKit';
import { AppTheme } from '../common/AppTheme';

@Component
export struct ShareSheet {
  @Link shareText: string;
  @Prop sheetTitle: string = '分享';
  @State copied: boolean = false;
  @State sharing: boolean = false;

  private copyText(): void {
    try {
      let board = pasteboard.getSystemPasteboard();
      let data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.shareText);
      board.setData(data).then(() => {
        this.copied = true;
      }).catch((err: BusinessError) => {
        console.error('copy to pasteboard failed: ' + JSON.stringify(err));
      });
    } catch (e) {
      console.error('copy to pasteboard failed: ' + JSON.stringify(e));
    }
  }

  private shareToSystem(): void {
    if (this.sharing) {
      return;
    }
    try {
      let ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      let record: systemShare.SharedRecord = {
        utd: utd.UniformDataType.TEXT,
        content: this.shareText,
        title: this.sheetTitle
      };
      let data: systemShare.SharedData = new systemShare.SharedData(record);
      let controller: systemShare.ShareController = new systemShare.ShareController(data);
      this.sharing = true;
      controller.show(ctx, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL
      }).then(() => {
        this.sharing = false;
      }).catch((err: BusinessError) => {
        this.sharing = false;
        console.error('system share failed: ' + JSON.stringify(err));
      });
    } catch (e) {
      this.sharing = false;
      console.error('system share failed: ' + JSON.stringify(e));
    }
  }

  build() {
    Column({ space: 14 }) {
      Text(this.sheetTitle)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.TEXT)
        .width('100%')
        .textAlign(TextAlign.Start)

      Scroll() {
        Text(this.shareText)
          .fontSize(13)
          .fontColor(AppTheme.TEXT_SUB)
          .width('100%')
          .textAlign(TextAlign.Start)
          .copyOption(CopyOptions.InApp)
          .padding(12)
      }
      .constraintSize({ maxHeight: 180 })
      .width('100%')
      .scrollBar(BarState.Auto)
      .backgroundColor(AppTheme.CHIP_BG)
      .borderRadius(12)

      Row({ space: 10 }) {
        Button(this.copied ? '已复制' : '复制链接')
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .fontColor(this.copied ? AppTheme.OK : AppTheme.PRIMARY)
          .backgroundColor(AppTheme.CHIP_BG)
          .borderRadius(22)
          .onClick(() => {
            this.copyText();
          })

        Button('系统分享')
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .backgroundColor(AppTheme.PRIMARY)
          .borderRadius(22)
          .onClick(() => {
            this.shareToSystem();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(20)
    .backgroundColor(AppTheme.PAGE_BG)
  }
}
