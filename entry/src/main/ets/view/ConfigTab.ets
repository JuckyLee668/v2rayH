import { pasteboard, BusinessError } from '@kit.BasicServicesKit';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { scanBarcode } from '@kit.ScanKit';
import { AppState } from '../common/AppState';
import { AppTheme } from '../common/AppTheme';
import { parseSubscription, buildShareLink } from '../common/V2rayParser';
import { usesSingboxKernel } from '../common/SingboxConf';
import { ServerConfig } from '../model/ServerConfig';
import { SubGroup } from '../model/SubGroup';
import { ShareSheet } from './ShareSheet';

const SUB_OVERVIEW: number = 0;
const SUB_GROUPS: number = 1;
const SUB_ROUTING: number = 2;
const SUB_GEO: number = 3;
const SUB_MANUAL: number = 4;
const SUB_NODES: number = 5;
const SUB_PERAPP: number = 6;
const ACT_SCAN: number = 100;
const ACT_CLIPBOARD: number = 101;

@Component
export struct ConfigTab {
  @ObjectLink app: AppState;
  @StorageProp('themeRev') themeRev: number = 0;
  @Prop @Watch('onResetTick') resetTick: number = 0;
  @Prop @Watch('onBackTick') backTick: number = 0;
  @StorageProp('topRectHeight') topRectPx: number = 0;
  @StorageProp('bottomRectHeight') bottomRectPx: number = 0;
  @State @Watch('syncNavDepth') sub: number = SUB_OVERVIEW;
  @State groupUrlDraft: string = '';
  @State groupNameDraft: string = '';
  @State showShare: boolean = false;
  @State shareText: string = '';
  @State shareTitle: string = '分享订阅';
  @State nodeGroupIdx: number = -1;
  @State @Watch('syncNavDepth') groupCreateOpen: boolean = false;
  @State @Watch('syncNavDepth') groupEditIdx: number = -1;
  @State geName: string = '';
  @State geUrl: string = '';
  @State @Watch('syncNavDepth') editIdx: number = -1;
  @State eName: string = '';
  @State eAddress: string = '';
  @State ePort: string = '';
  @State eCredential: string = '';
  @State eKernel: string = 'auto';
  @State eAdvOpen: boolean = false;
  @State eNetwork: string = 'tcp';
  @State eHeaderType: string = 'none';
  @State ePath: string = '';
  @State eHost: string = '';
  @State eSecurity: string = 'none';
  @State eSni: string = '';
  @State eFp: string = '';
  @State eAlpn: string = '';
  @State eFlow: string = '';
  @State eMethod: string = '';
  @State eAlterId: string = '0';
  @State ePbk: string = '';
  @State eSid: string = '';
  @State eSpx: string = '/';
  @State eObfs: string = '';
  @State eObfsPassword: string = '';
  @State ePorts: string = '';
  @State eInsecure: boolean = false;
  @State quickLinkDraft: string = '';
  @State advancedOpen: boolean = false;
  @State directDraft: string = '';
  @State proxyDraft: string = '';
  @State mName: string = '';
  @State mProtocol: string = 'vless';
  @State mAddress: string = '';
  @State mPort: string = '';
  @State mCredential: string = '';
  @State mMethod: string = 'aes-128-gcm';
  @State mNetwork: string = 'tcp';
  @State mPath: string = '';
  @State mSecurity: string = 'none';
  @State mSni: string = '';
  @State mPbk: string = '';
  @State mSid: string = '';
  @State mFp: string = 'chrome';
  @State mPassword2: string = '';
  @State mAlpn: string = '';
  @State mObfs: string = '';
  @State mPorts: string = '';
  @State mInsecure: boolean = false;
  @State perAppDraft: string = '';


  private subTitle(): string {
    if (this.sub === SUB_GROUPS) {
      return '订阅分组';
    }
    if (this.sub === SUB_ROUTING) {
      return '路由设置';
    }
    if (this.sub === SUB_GEO) {
      return '资源文件';
    }
    if (this.sub === SUB_MANUAL) {
      return '手动添加';
    }
    if (this.sub === SUB_NODES) {
      return '节点管理';
    }
    if (this.sub === SUB_PERAPP) {
      return '分应用代理';
    }
    return '配置';
  }

  onResetTick(): void {
    this.sub = SUB_OVERVIEW;
  }

  syncNavDepth(): void {
    let d = 0;
    if (this.sub === SUB_NODES) {
      d = 2;
    } else if (this.sub !== SUB_OVERVIEW) {
      d = 1;
    }
    if (this.editIdx >= 0 || this.groupCreateOpen || this.groupEditIdx >= 0) {
      d += 1;
    }
    this.app.configDepth = d;
  }

  onBackTick(): void {
    if (this.editIdx >= 0) {
      this.editIdx = -1;
      return;
    }
    if (this.groupEditIdx >= 0) {
      this.groupEditIdx = -1;
      return;
    }
    if (this.groupCreateOpen) {
      this.groupCreateOpen = false;
      return;
    }
    if (this.sub === SUB_NODES) {
      this.sub = SUB_GROUPS;
      return;
    }
    if (this.sub !== SUB_OVERVIEW) {
      this.sub = SUB_OVERVIEW;
    }
  }

  private subDesc(): string {
    if (this.sub === SUB_GROUPS) {
      return '管理订阅分组与节点';
    }
    if (this.sub === SUB_ROUTING) {
      return '分流规则与代理策略';
    }
    if (this.sub === SUB_GEO) {
      return 'geosite / geoip 规则文件';
    }
    if (this.sub === SUB_MANUAL) {
      return '粘贴链接快速添加，或手动填写参数';
    }
    if (this.sub === SUB_NODES) {
      return '分组内节点的编辑、删除与分享';
    }
    if (this.sub === SUB_PERAPP) {
      return '选择哪些应用的流量经过 VPN';
    }
    return '订阅 · 分流 · 资源';
  }

  @Builder
  topHeader() {
    Column() {
      Row() {
        if (this.sub !== SUB_OVERVIEW) {
          Row() {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(22)
              .fontColor([AppTheme.TEXT])
            Text('返回')
              .fontSize(15)
              .fontColor(AppTheme.TEXT)
              .margin({ left: 2 })
          }
          .height(36)
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.sub = this.sub === SUB_NODES ? SUB_GROUPS : SUB_OVERVIEW;
          })
        }

        Text(this.subTitle())
          .fontSize(this.sub === SUB_OVERVIEW ? 28 : 15)
          .fontWeight(this.sub === SUB_OVERVIEW ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(AppTheme.TEXT)
          .layoutWeight(1)
          .textAlign(this.sub === SUB_OVERVIEW ? TextAlign.Start : TextAlign.End)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.subDesc())
        .fontSize(12)
        .fontColor(AppTheme.TEXT_SUB)
        .margin({ top: 4 })
        .width('100%')
        .textAlign(this.sub === SUB_OVERVIEW ? TextAlign.Start : TextAlign.End)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  navRow(icon: Resource, title: string, desc: string, target: number) {
    Row({ space: 12 }) {
      SymbolGlyph(icon)
        .fontSize(21)
        .fontColor([AppTheme.PRIMARY])

      Column() {
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT)
        Text(desc)
          .fontSize(11)
          .fontColor(AppTheme.TEXT_SUB)
          .margin({ top: 2 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph($r('sys.symbol.chevron_forward'))
        .fontSize(15)
        .fontColor([AppTheme.TEXT_WEAK])
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 14, right: 14, top: 13, bottom: 13 })
    .onClick(() => {
      this.sub = target;
    })
  }

  @Builder
  navList() {
    Column() {
      this.navRow($r('sys.symbol.list_bullet'), '订阅分组', this.app.groups.length.toString() + ' 个分组', SUB_GROUPS)
      Divider().strokeWidth(1).color(AppTheme.DIVIDER).margin({ left: 14, right: 14 })
      this.navRow($r('sys.symbol.network_acceleration'), '路由设置', this.app.routeBypassCn ? 'CN 直连 · 广告拦截' : '全局代理', SUB_ROUTING)
      Divider().strokeWidth(1).color(AppTheme.DIVIDER).margin({ left: 14, right: 14 })
      this.navRow($r('sys.symbol.square_grid_2x2'), '分应用代理', this.app.perAppModeText() + ' · ' + this.app.perAppBundles.length.toString() + ' 个应用', SUB_PERAPP)
      Divider().strokeWidth(1).color(AppTheme.DIVIDER).margin({ left: 14, right: 14 })
      this.navRow($r('sys.symbol.doc'), '资源文件', 'geosite ' + this.app.sizeText(this.app.geositeSize), SUB_GEO)
    }
    .width('100%')
    .backgroundColor(AppTheme.CARD_BG)
    .borderRadius(AppTheme.CARD_RADIUS)
    .margin({ top: 12 })
    .shadow({ radius: 14, color: '#10000000', offsetY: 3 })
  }

  @Builder
  importButton(icon: Resource, label: string, target: number) {
    Column({ space: 5 }) {
      SymbolGlyph(icon)
        .fontSize(20)
        .fontColor([AppTheme.PRIMARY])
      Text(label)
        .fontSize(11)
        .fontColor(AppTheme.TEXT)
        .maxLines(1)
    }
    .layoutWeight(1)
    .padding({ top: 10, bottom: 10 })
    .backgroundColor(AppTheme.PRIMARY_SOFT)
    .borderRadius(12)
    .onClick(() => {
      if (target === SUB_MANUAL) {
        this.sub = SUB_MANUAL;
      } else if (target === ACT_SCAN) {
        this.importFromScan();
      } else {
        this.importFromClipboard();
      }
    })
  }

  @Builder
  importBar() {
    Row({ space: 10 }) {
      this.importButton($r('sys.symbol.qrcode'), '扫码导入', ACT_SCAN)
      this.importButton($r('sys.symbol.doc_plaintext'), '剪贴板', ACT_CLIPBOARD)
      this.importButton($r('sys.symbol.plus_circle'), '手动添加', SUB_MANUAL)
    }
    .width('100%')
    .margin({ top: 12 })
  }

  private async ensureReadPasteboard(): Promise<boolean> {
    let ctx = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      this.app.status = '上下文未就绪';
      return false;
    }
    try {
      let atManager = abilityAccessCtrl.createAtManager();
      let perms: Array<Permissions> = ['ohos.permission.READ_PASTEBOARD'];
      let res = await atManager.requestPermissionsFromUser(ctx, perms);
      return res.authResults.length > 0 && res.authResults[0] === 0;
    } catch (e) {
      let err = e as BusinessError;
      this.app.status = '申请剪贴板权限失败: ' + err.code.toString();
      return false;
    }
  }

  private async importFromClipboard(): Promise<void> {
    let granted = await this.ensureReadPasteboard();
    if (!granted) {
      this.app.status = '未授予剪贴板读取权限，无法导入';
      return;
    }
    try {
      let board = pasteboard.getSystemPasteboard();
      let has = await board.hasData();
      if (!has) {
        this.app.status = '剪贴板为空';
        return;
      }
      let data = await board.getData();
      let text = data.getPrimaryText();
      if (text === undefined || text.length === 0) {
        this.app.status = '剪贴板里没有文本内容';
        return;
      }
      let list = parseSubscription(text);
      if (list.length === 0) {
        this.app.status = '剪贴板里没有可识别的节点链接';
        return;
      }
      this.app.addServers(list, '本机节点');
    } catch (e) {
      let err = e as BusinessError;
      this.app.status = '读取剪贴板失败: ' + err.code.toString() + ' ' + err.message;
    }
  }

  private confirmScanSubscription(url: string): void {
    AlertDialog.show({
      title: '扫码结果',
      message: '二维码内容是链接，添加为订阅分组并立即更新？\n\n' + url,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '添加订阅',
        fontColor: AppTheme.PRIMARY,
        action: () => {
          let name = this.nextGroupName();
          this.app.addGroup(name, url);
          this.app.updateGroupSubscription(this.app.groups.length - 1);
        }
      }
    });
  }

  private async importFromScan(): Promise<void> {
    let ctx = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      this.app.status = '上下文未就绪';
      return;
    }
    try {
      let res = await scanBarcode.startScanForResult(ctx);
      let raw = res.originalValue.trim();
      if (raw.startsWith('http://') || raw.startsWith('https://')) {
        this.confirmScanSubscription(raw);
        return;
      }
      let list = parseSubscription(res.originalValue);
      if (list.length === 0) {
        this.app.status = '二维码内容不是有效的节点链接';
        return;
      }
      this.app.addServers(list, '本机节点');
    } catch (e) {
      this.app.status = '扫码已取消或失败';
    }
  }

  @Builder
  overview() {
    List({ space: 8 }) {
      ListItem() {
        this.importBar()
      }

      ListItem() {
        this.navList()
      }

      ListItem() {
        Text(this.app.status)
          .fontSize(11)
          .fontColor(AppTheme.TEXT_WEAK)
          .width('100%')
          .textAlign(TextAlign.Center)
          .maxLines(2)
          .margin({ top: 8 })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  // ---------------- groups ----------------

  @Builder
  groupRow(g: SubGroup, idx: number) {
    Row() {
      Column() {
        Row({ space: 6 }) {
          Text(g.name)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.app.activeGroup === idx ? AppTheme.PRIMARY : AppTheme.TEXT)
            .maxLines(1)
          if (this.app.activeGroup === idx) {
            Text('使用中')
              .fontSize(10)
              .fontColor(AppTheme.PRIMARY)
              .backgroundColor(AppTheme.PRIMARY_SOFT)
              .borderRadius(6)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          }
        }
        Text((g.nodes !== undefined ? g.nodes.length : 0).toString() + ' 个节点 · ' + this.app.formatTime(g.updatedAt))
          .fontSize(11)
          .fontColor(AppTheme.TEXT_SUB)
          .margin({ top: 3 })
        Text(g.url.length > 0 ? g.url : '未设置订阅链接')
          .fontSize(11)
          .fontColor(AppTheme.TEXT_WEAK)
          .margin({ top: 2 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Row({ space: 2 }) {
        SymbolGlyph($r('sys.symbol.list_bullet'))
          .fontSize(18)
          .fontColor([AppTheme.PRIMARY])
          .padding(8)
          .onClick(() => {
            this.openGroupNodes(idx);
          })
        SymbolGlyph($r('sys.symbol.share'))
          .fontSize(18)
          .fontColor([AppTheme.TEXT_SUB])
          .padding(8)
          .onClick(() => {
            this.shareGroup(idx);
          })
        if (g.url.length > 0) {
          SymbolGlyph($r('sys.symbol.arrow_2_circlepath'))
            .fontSize(18)
            .fontColor([this.app.activeGroup === idx ? AppTheme.PRIMARY : AppTheme.TEXT_SUB])
            .padding(8)
            .onClick(() => {
              this.app.updateGroupSubscription(idx);
            })
        }
        SymbolGlyph($r('sys.symbol.square_and_pencil'))
          .fontSize(18)
          .fontColor([AppTheme.TEXT_SUB])
          .padding(8)
          .onClick(() => {
            this.openGroupEdit(idx);
          })
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(18)
          .fontColor([AppTheme.DANGER])
          .padding(8)
          .onClick(() => {
            this.confirmRemoveGroup(idx);
          })
      }
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 14, right: 10, top: 12, bottom: 12 })
  }

  private confirmRemoveGroup(idx: number): void {
    AlertDialog.show({
      title: '删除分组',
      message: '确定删除「' + this.app.groups[idx].name + '」及其节点？',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        action: () => {
          this.app.removeGroup(idx);
        }
      }
    });
  }

  @Builder
  groupsPage() {
    Column() {
      Row() {
        Column() {
          Text('启动时自动更新')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.TEXT)
          Text('打开应用时静默更新所有带链接的分组')
            .fontSize(11)
            .fontColor(AppTheme.TEXT_SUB)
            .margin({ top: 2 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Toggle({ type: ToggleType.Switch, isOn: this.app.autoUpdateSubs })
          .onChange((v: boolean) => {
            this.app.setAutoUpdateSubs(v);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 14, right: 14, top: 11, bottom: 11 })
      .backgroundColor(AppTheme.CARD_BG)
      .borderRadius(AppTheme.CARD_RADIUS)
      .margin({ top: 10 })

      Row() {
        Text('共 ' + this.app.groups.length.toString() + ' 个分组')
          .fontSize(12)
          .fontColor(AppTheme.TEXT_WEAK)
        Blank()
        Button(this.app.busy ? '更新中...' : '全部更新')
          .fontSize(12)
          .height(30)
          .fontColor(AppTheme.PRIMARY)
          .backgroundColor(AppTheme.PRIMARY_SOFT)
          .borderRadius(15)
          .enabled(!this.app.busy)
          .onClick(() => {
            this.app.updateAllGroups();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ top: 10, bottom: 2 })

      List({ space: 8 }) {
        ForEach(this.app.groups, (g: SubGroup, idx: number) => {
          ListItem() {
            this.groupRow(g, idx)
          }
          .backgroundColor(AppTheme.CARD_BG)
          .borderRadius(14)
          .onClick(() => {
            this.app.selectGroup(idx);
          })
        }, (g: SubGroup, idx: number) => g.id + '|' + idx.toString())
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      if (this.groupEditIdx >= 0) {
        Column({ space: 8 }) {
          Text('编辑分组「' + (this.groupEditIdx >= 0 && this.groupEditIdx < this.app.groups.length ? this.app.groups[this.groupEditIdx].name : '') + '」')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.TEXT)
            .width('100%')
          TextInput({ text: this.geName, placeholder: '分组名称' })
            .height(40)
            .fontSize(13)
            .backgroundColor(AppTheme.CHIP_BG)
            .borderRadius(12)
            .onChange((v: string) => {
              this.geName = v;
            })
          TextInput({ text: this.geUrl, placeholder: '订阅链接（可留空）' })
            .height(40)
            .fontSize(13)
            .backgroundColor(AppTheme.CHIP_BG)
            .borderRadius(12)
            .onChange((v: string) => {
              this.geUrl = v;
            })
          Row({ space: 8 }) {
            Button('取消')
              .layoutWeight(1)
              .height(38)
              .fontSize(14)
              .fontColor(AppTheme.TEXT_SUB)
              .backgroundColor(AppTheme.CHIP_BG)
              .borderRadius(19)
              .onClick(() => {
                this.groupEditIdx = -1;
              })
            Button('保存修改')
              .layoutWeight(1)
              .height(38)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
              .backgroundColor(AppTheme.PRIMARY)
              .borderRadius(19)
              .onClick(() => {
                this.saveGroupEdit();
              })
          }
          .width('100%')
        }
        .width('100%')
        .padding(12)
        .backgroundColor(AppTheme.CARD_BG)
        .borderRadius(AppTheme.CARD_RADIUS)
        .margin({ top: 10 })
      } else if (!this.groupCreateOpen) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.plus_circle'))
            .fontSize(16)
            .fontColor([AppTheme.PRIMARY])
          Text('新建分组')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.PRIMARY)
        }
        .width('100%')
        .height(40)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(AppTheme.CARD_BG)
        .borderRadius(20)
        .margin({ top: 10 })
        .onClick(() => {
          this.groupCreateOpen = true;
        })
      } else {
        Column({ space: 8 }) {
          TextInput({ text: this.groupNameDraft, placeholder: '分组名称（可留空自动命名）' })
            .height(40)
            .fontSize(13)
            .backgroundColor(AppTheme.CHIP_BG)
            .borderRadius(12)
            .onChange((v: string) => {
              this.groupNameDraft = v;
            })
          TextInput({ text: this.groupUrlDraft, placeholder: '订阅链接（可留空）' })
            .height(40)
            .fontSize(13)
            .backgroundColor(AppTheme.CHIP_BG)
            .borderRadius(12)
            .onChange((v: string) => {
              this.groupUrlDraft = v;
            })
          Row({ space: 8 }) {
            Button('取消')
              .layoutWeight(1)
              .height(38)
              .fontSize(14)
              .fontColor(AppTheme.TEXT_SUB)
              .backgroundColor(AppTheme.CHIP_BG)
              .borderRadius(19)
              .onClick(() => {
                this.groupCreateOpen = false;
                this.groupNameDraft = '';
                this.groupUrlDraft = '';
              })
            Button('创建分组')
              .layoutWeight(1)
              .height(38)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
              .backgroundColor(AppTheme.PRIMARY)
              .borderRadius(19)
              .onClick(() => {
                this.createGroupSimple();
              })
          }
          .width('100%')
        }
        .width('100%')
        .padding(12)
        .backgroundColor(AppTheme.CARD_BG)
        .borderRadius(AppTheme.CARD_RADIUS)
        .margin({ top: 10 })
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  private nextGroupName(): string {
    let n = this.app.groups.length + 1;
    let name = '订阅' + n.toString();
    let clash = true;
    while (clash) {
      clash = false;
      for (let i = 0; i < this.app.groups.length; i++) {
        if (this.app.groups[i].name === name) {
          clash = true;
          break;
        }
      }
      if (clash) {
        n++;
        name = '订阅' + n.toString();
      }
    }
    return name;
  }

  private createGroupSimple(): void {
    let name = this.groupNameDraft.trim();
    if (name.length === 0) {
      name = this.nextGroupName();
    }
    let url = this.groupUrlDraft.trim();
    this.app.addGroup(name, url);
    this.groupNameDraft = '';
    this.groupUrlDraft = '';
    this.groupCreateOpen = false;
    if (url.length > 0) {
      this.app.updateGroupSubscription(this.app.groups.length - 1);
    }
  }

  private openGroupEdit(idx: number): void {
    if (idx < 0 || idx >= this.app.groups.length) {
      return;
    }
    let g = this.app.groups[idx];
    this.geName = g.name;
    this.geUrl = g.url;
    this.groupCreateOpen = false;
    this.groupEditIdx = idx;
  }

  private saveGroupEdit(): void {
    let idx = this.groupEditIdx;
    if (idx < 0 || idx >= this.app.groups.length) {
      this.groupEditIdx = -1;
      return;
    }
    let name = this.geName.trim();
    if (name.length === 0) {
      this.app.status = '分组名称不能为空';
      return;
    }
    this.app.updateGroupMeta(idx, name, this.geUrl.trim());
    this.groupEditIdx = -1;
  }

  private shareGroup(idx: number): void {
    if (idx < 0 || idx >= this.app.groups.length) {
      return;
    }
    let g = this.app.groups[idx];
    if (g.url.trim().length > 0) {
      this.shareTitle = '分享订阅';
      this.shareText = g.url.trim();
      this.showShare = true;
      return;
    }
    let nodes: ServerConfig[] = Array.isArray(g.nodes) ? g.nodes : [];
    let links: string[] = [];
    for (let i = 0; i < nodes.length; i++) {
      let link = buildShareLink(nodes[i]);
      if (link.length > 0) {
        links.push(link);
      }
    }
    if (links.length === 0) {
      this.app.status = '该分组没有可分享的节点';
      return;
    }
    this.shareTitle = '分享分组节点';
    this.shareText = links.join('\n');
    this.showShare = true;
  }

  @Builder
  shareSheetBuilder() {
    ShareSheet({ shareText: $shareText, sheetTitle: this.shareTitle })
  }

  // ---------------- group nodes management ----------------

  private openGroupNodes(idx: number): void {
    if (!Array.isArray(this.app.groups) || idx < 0 || idx >= this.app.groups.length) {
      return;
    }
    this.nodeGroupIdx = idx;
    this.editIdx = -1;
    this.sub = SUB_NODES;
  }

  private nodeGroup(): SubGroup | undefined {
    let groups: SubGroup[] | undefined = this.app.groups;
    if (!Array.isArray(groups) || this.nodeGroupIdx < 0 || this.nodeGroupIdx >= groups.length) {
      return undefined;
    }
    return groups[this.nodeGroupIdx];
  }

  private groupNodes(): ServerConfig[] {
    let g = this.nodeGroup();
    if (g === undefined) {
      return [];
    }
    let nodes: ServerConfig[] | undefined = g.nodes;
    return Array.isArray(nodes) ? nodes : [];
  }

  private nodeGroupTitle(): string {
    let g = this.nodeGroup();
    if (g === undefined) {
      return '分组不存在';
    }
    let nodes = Array.isArray(g.nodes) ? g.nodes : [];
    return '「' + g.name + '」· ' + nodes.length.toString() + ' 个节点';
  }

  private openNodeEdit(idx: number): void {
    let nodes = this.groupNodes();
    if (idx < 0 || idx >= nodes.length) {
      return;
    }
    let s: ServerConfig = nodes[idx];
    let name: string | undefined = s.name;
    let address: string | undefined = s.address;
    let port: number | undefined = s.port;
    let kernel: string | undefined = s.kernel;
    let uuid: string | undefined = s.uuid;
    let password: string | undefined = s.password;
    this.eName = typeof name === 'string' ? name : '';
    this.eAddress = typeof address === 'string' ? address : '';
    this.ePort = typeof port === 'number' ? port.toString() : '0';
    this.eCredential = s.protocol === 'vless' || s.protocol === 'vmess'
      ? (typeof uuid === 'string' ? uuid : '')
      : (typeof password === 'string' ? password : '');
    this.eKernel = typeof kernel === 'string' && kernel.length > 0 ? kernel : 'auto';
    this.eAdvOpen = false;
    this.eNetwork = s.network.length > 0 ? s.network : 'tcp';
    this.eHeaderType = s.headerType.length > 0 ? s.headerType : 'none';
    this.ePath = s.path;
    this.eHost = s.host;
    this.eSecurity = s.security.length > 0 ? s.security : 'none';
    this.eSni = s.sni;
    this.eFp = s.fp;
    this.eAlpn = s.alpn;
    this.eFlow = s.flow;
    this.eMethod = s.method;
    this.eAlterId = s.alterId.toString();
    this.ePbk = s.pbk;
    this.eSid = s.sid;
    this.eSpx = s.spx.length > 0 ? s.spx : '/';
    this.eObfs = s.obfs;
    this.eObfsPassword = s.obfsPassword;
    this.ePorts = s.ports;
    this.eInsecure = s.insecure;
    this.editIdx = idx;
  }

  private credentialLabel(): string {
    let nodes = this.groupNodes();
    if (this.editIdx >= 0 && this.editIdx < nodes.length) {
      let p: string = nodes[this.editIdx].protocol;
      if (p === 'vless' || p === 'vmess') {
        return '用户 ID (UUID)';
      }
    }
    return '密码';
  }

  private editProtocol(): string {
    let nodes = this.groupNodes();
    if (this.editIdx >= 0 && this.editIdx < nodes.length) {
      return nodes[this.editIdx].protocol;
    }
    return '';
  }

  private editIsXrayFamily(): boolean {
    let p = this.editProtocol();
    return p === 'vless' || p === 'vmess' || p === 'trojan';
  }

  @Builder
  advToggleRow(label: string, on: boolean, desc: string, onFlip: (v: boolean) => void) {
    Row() {
      Column() {
        Text(label)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT)
        Text(desc)
          .fontSize(11)
          .fontColor(AppTheme.TEXT_SUB)
          .margin({ top: 2 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: on })
        .onChange((v: boolean) => {
          onFlip(v);
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .margin({ top: 12 })
  }

  @Builder
  advLabel(text: string) {
    Text(text)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(AppTheme.TEXT)
      .width('100%')
      .margin({ top: 14 })
  }

  @Builder
  nodeAdvFields() {
    if (this.editIsXrayFamily()) {
      this.advLabel('TLS / 传输安全')
      Flex({ wrap: FlexWrap.Wrap }) {
        CfgChoiceChip({ label: 'none', active: this.eSecurity === 'none', onPick: () => {
          this.eSecurity = 'none';
        } })
        CfgChoiceChip({ label: 'tls', active: this.eSecurity === 'tls', onPick: () => {
          this.eSecurity = 'tls';
        } })
        if (this.editProtocol() === 'vless') {
          CfgChoiceChip({ label: 'reality', active: this.eSecurity === 'reality', onPick: () => {
            this.eSecurity = 'reality';
          } })
        }
      }
      .width('100%')
      .margin({ top: 4 })

      if (this.eSecurity !== 'none') {
        CfgField({ label: 'SNI (服务器名称指示)', value: this.eSni, placeholder: '与服务器地址一致时留空', onEdit: (v: string) => {
          this.eSni = v;
        } })
        this.advLabel('TLS 指纹 (fingerprint)')
        Flex({ wrap: FlexWrap.Wrap }) {
          CfgChoiceChip({ label: '留空', active: this.eFp.length === 0, onPick: () => {
            this.eFp = '';
          } })
          CfgChoiceChip({ label: 'chrome', active: this.eFp === 'chrome', onPick: () => {
            this.eFp = 'chrome';
          } })
          CfgChoiceChip({ label: 'firefox', active: this.eFp === 'firefox', onPick: () => {
            this.eFp = 'firefox';
          } })
          CfgChoiceChip({ label: 'safari', active: this.eFp === 'safari', onPick: () => {
            this.eFp = 'safari';
          } })
          CfgChoiceChip({ label: 'ios', active: this.eFp === 'ios', onPick: () => {
            this.eFp = 'ios';
          } })
          CfgChoiceChip({ label: 'android', active: this.eFp === 'android', onPick: () => {
            this.eFp = 'android';
          } })
          CfgChoiceChip({ label: 'randomized', active: this.eFp === 'randomized', onPick: () => {
            this.eFp = 'randomized';
          } })
        }
        .width('100%')
        .margin({ top: 4 })
        this.advLabel('ALPN')
        Flex({ wrap: FlexWrap.Wrap }) {
          CfgChoiceChip({ label: '留空', active: this.eAlpn.length === 0, onPick: () => {
            this.eAlpn = '';
          } })
          CfgChoiceChip({ label: 'h2', active: this.eAlpn === 'h2', onPick: () => {
            this.eAlpn = 'h2';
          } })
          CfgChoiceChip({ label: 'http/1.1', active: this.eAlpn === 'http/1.1', onPick: () => {
            this.eAlpn = 'http/1.1';
          } })
          CfgChoiceChip({ label: 'h2,http/1.1', active: this.eAlpn === 'h2,http/1.1', onPick: () => {
            this.eAlpn = 'h2,http/1.1';
          } })
        }
        .width('100%')
        .margin({ top: 4 })
      }
      if (this.eSecurity === 'reality') {
        CfgField({ label: '公钥 (pbk)', value: this.ePbk, placeholder: 'Reality public key', onEdit: (v: string) => {
          this.ePbk = v;
        } })
        CfgField({ label: '短 ID (sid)', value: this.eSid, placeholder: '', onEdit: (v: string) => {
          this.eSid = v;
        } })
        CfgField({ label: 'spiderX', value: this.eSpx, placeholder: '/', onEdit: (v: string) => {
          this.eSpx = v;
        } })
      }

      this.advLabel('传输协议')
      Flex({ wrap: FlexWrap.Wrap }) {
        CfgChoiceChip({ label: 'tcp', active: this.eNetwork === 'tcp', onPick: () => {
          this.eNetwork = 'tcp';
        } })
        CfgChoiceChip({ label: 'ws', active: this.eNetwork === 'ws', onPick: () => {
          this.eNetwork = 'ws';
        } })
        CfgChoiceChip({ label: 'grpc', active: this.eNetwork === 'grpc', onPick: () => {
          this.eNetwork = 'grpc';
        } })
      }
      .width('100%')
      .margin({ top: 4 })

      if (this.eNetwork !== 'tcp') {
        CfgField({ label: this.eNetwork === 'grpc' ? 'serviceName' : '路径 (path)', value: this.ePath, placeholder: this.eNetwork === 'grpc' ? 'grpc 服务名' : '/', onEdit: (v: string) => {
          this.ePath = v;
        } })
        CfgField({ label: this.eNetwork === 'ws' ? '伪装域名 (Host)' : 'Authority', value: this.eHost, placeholder: 'example.com', onEdit: (v: string) => {
          this.eHost = v;
        } })
      }
      if (this.editProtocol() === 'vless' && this.eSecurity !== 'none') {
        this.advLabel('流控 (flow)')
        Flex({ wrap: FlexWrap.Wrap }) {
          CfgChoiceChip({ label: '留空', active: this.eFlow.length === 0, onPick: () => {
            this.eFlow = '';
          } })
          CfgChoiceChip({ label: 'xtls-rprx-vision', active: this.eFlow === 'xtls-rprx-vision', onPick: () => {
            this.eFlow = 'xtls-rprx-vision';
          } })
        }
        .width('100%')
        .margin({ top: 4 })
      }
      if (this.editProtocol() === 'vmess') {
        CfgField({ label: '额外 ID (alterId)', value: this.eAlterId, placeholder: '0', onEdit: (v: string) => {
          this.eAlterId = v;
        } })
      }
      this.advToggleRow('允许不安全连接', this.eInsecure, '跳过证书校验（insecure）', (v: boolean) => {
        this.eInsecure = v;
      })
    }
    if (this.editProtocol() === 'ss') {
      this.advLabel('加密方式 (method)')
      Flex({ wrap: FlexWrap.Wrap }) {
        CfgChoiceChip({ label: 'aes-128-gcm', active: this.eMethod === 'aes-128-gcm', onPick: () => {
          this.eMethod = 'aes-128-gcm';
        } })
        CfgChoiceChip({ label: 'aes-256-gcm', active: this.eMethod === 'aes-256-gcm', onPick: () => {
          this.eMethod = 'aes-256-gcm';
        } })
        CfgChoiceChip({ label: 'chacha20-ietf-poly1305', active: this.eMethod === 'chacha20-ietf-poly1305', onPick: () => {
          this.eMethod = 'chacha20-ietf-poly1305';
        } })
        CfgChoiceChip({ label: '2022-blake3-aes-128-gcm', active: this.eMethod === '2022-blake3-aes-128-gcm', onPick: () => {
          this.eMethod = '2022-blake3-aes-128-gcm';
        } })
        CfgChoiceChip({ label: '2022-blake3-aes-256-gcm', active: this.eMethod === '2022-blake3-aes-256-gcm', onPick: () => {
          this.eMethod = '2022-blake3-aes-256-gcm';
        } })
      }
      .width('100%')
      .margin({ top: 4 })
    }
    if (this.editProtocol() === 'hy2' || this.editProtocol() === 'tuic') {
      CfgField({ label: 'SNI (服务器名称指示)', value: this.eSni, placeholder: '与服务器地址一致时留空', onEdit: (v: string) => {
        this.eSni = v;
      } })
      this.advLabel('ALPN')
      Flex({ wrap: FlexWrap.Wrap }) {
        CfgChoiceChip({ label: '留空', active: this.eAlpn.length === 0, onPick: () => {
          this.eAlpn = '';
        } })
        CfgChoiceChip({ label: 'h3', active: this.eAlpn === 'h3', onPick: () => {
          this.eAlpn = 'h3';
        } })
      }
      .width('100%')
      .margin({ top: 4 })
    }
    if (this.editProtocol() === 'hy2') {
      this.advLabel('混淆 (obfs)')
      Flex({ wrap: FlexWrap.Wrap }) {
        CfgChoiceChip({ label: '关闭', active: this.eObfs.length === 0, onPick: () => {
          this.eObfs = '';
        } })
        CfgChoiceChip({ label: 'salamander', active: this.eObfs.length > 0, onPick: () => {
          this.eObfs = 'salamander';
        } })
      }
      .width('100%')
      .margin({ top: 4 })
      if (this.eObfs.length > 0) {
        CfgField({ label: '混淆密码 (obfs-password)', value: this.eObfsPassword, placeholder: '', onEdit: (v: string) => {
          this.eObfsPassword = v;
        } })
      }
      CfgField({ label: '端口跳跃 (mport)', value: this.ePorts, placeholder: '如 20000-30000，留空关闭', onEdit: (v: string) => {
        this.ePorts = v;
      } })
    }
    if (this.editProtocol() === 'hy2' || this.editProtocol() === 'tuic') {
      this.advToggleRow('允许不安全连接', this.eInsecure, '跳过证书校验（insecure）', (v: boolean) => {
        this.eInsecure = v;
      })
    }
  }

  private editKernelEffective(): boolean {
    if (this.eKernel === 'singbox') {
      return true;
    }
    if (this.eKernel === 'xray') {
      return false;
    }
    let nodes = this.groupNodes();
    if (this.editIdx < 0 || this.editIdx >= nodes.length) {
      return false;
    }
    let p: string = nodes[this.editIdx].protocol;
    return p === 'hy2' || p === 'tuic';
  }

  private saveNodeEdit(): void {
    let nodes = this.groupNodes();
    let idx = this.editIdx;
    if (idx < 0 || idx >= nodes.length) {
      this.editIdx = -1;
      return;
    }
    let port = parseInt(this.ePort, 10);
    let address = this.eAddress.trim();
    if (address.length === 0 || isNaN(port) || port <= 0 || port > 65535) {
      this.app.status = '请检查地址与端口';
      return;
    }
    let s: ServerConfig = nodes[idx];
    s.name = this.eName.trim().length > 0 ? this.eName.trim() : s.name;
    s.address = address;
    s.port = port;
    let cred = this.eCredential.trim();
    if (cred.length > 0) {
      if (s.protocol === 'vless' || s.protocol === 'vmess') {
        s.uuid = cred;
      } else {
        s.password = cred;
      }
    }
    s.kernel = this.eKernel;
    s.network = this.eNetwork.trim().length > 0 ? this.eNetwork.trim() : 'tcp';
    s.headerType = this.eHeaderType.trim();
    s.path = this.ePath.trim();
    s.host = this.eHost.trim();
    s.security = this.eSecurity;
    s.sni = this.eSni.trim();
    s.fp = this.eFp.trim();
    s.alpn = this.eAlpn.trim();
    s.flow = this.eFlow.trim();
    s.method = this.eMethod.trim();
    let aid = parseInt(this.eAlterId, 10);
    s.alterId = isNaN(aid) || aid < 0 ? 0 : aid;
    s.pbk = this.ePbk.trim();
    s.sid = this.eSid.trim();
    s.spx = this.eSpx.trim().length > 0 ? this.eSpx.trim() : '/';
    s.obfs = this.eObfs.trim();
    s.obfsPassword = this.eObfsPassword.trim();
    s.ports = this.ePorts.trim();
    s.insecure = this.eInsecure;
    this.app.updateGroupNode(this.nodeGroupIdx, idx, s);
    this.editIdx = -1;
  }

  private openNodeShare(idx: number): void {
    let nodes = this.groupNodes();
    if (idx < 0 || idx >= nodes.length) {
      return;
    }
    let link = buildShareLink(nodes[idx]);
    if (link.length === 0) {
      this.app.status = '该节点协议不支持分享';
      return;
    }
    this.shareText = link;
    this.shareTitle = '分享节点';
    this.showShare = true;
  }

  private confirmUpdateGeo(): void {
    if (this.app.connected) {
      this.app.updateGeoFiles();
      return;
    }
    AlertDialog.show({
      title: '未连接代理',
      message: '资源文件需要通过代理下载。当前未连接 VPN，将使用直连下载，境外资源可能失败。仍要继续？',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '继续下载',
        action: () => {
          this.app.updateGeoFiles();
        }
      }
    });
  }

  private confirmRemoveNode(idx: number): void {
    let nodes = this.groupNodes();
    if (idx < 0 || idx >= nodes.length) {
      return;
    }
    let name = nodes[idx].name;
    AlertDialog.show({
      title: '删除节点',
      message: '确定删除「' + name + '」？',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        action: () => {
          this.app.removeGroupNode(this.nodeGroupIdx, idx);
        }
      }
    });
  }

  @Builder
  groupNodeRow(item: ServerConfig, idx: number) {
    Row() {
      Column() {
        Row({ space: 6 }) {
          Text(item.name)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.TEXT)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (usesSingboxKernel(item)) {
            Text('SB')
              .fontSize(9)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.PRIMARY)
              .backgroundColor(AppTheme.PRIMARY_SOFT)
              .borderRadius(5)
              .padding({ left: 5, right: 5, top: 1, bottom: 1 })
          }
        }
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

      Row() {
        Text('分享')
          .fontSize(11)
          .fontColor(AppTheme.PRIMARY)
          .padding({ left: 8, right: 8, top: 5, bottom: 5 })
          .backgroundColor(AppTheme.CHIP_BG)
          .borderRadius(100)
          .onClick(() => {
            this.openNodeShare(idx);
          })
        Text('编辑')
          .fontSize(11)
          .fontColor(AppTheme.TEXT_SUB)
          .padding({ left: 8, right: 8, top: 5, bottom: 5 })
          .backgroundColor(AppTheme.CHIP_BG)
          .borderRadius(100)
          .margin({ left: 6 })
          .onClick(() => {
            this.openNodeEdit(idx);
          })
        Text('删除')
          .fontSize(11)
          .fontColor(AppTheme.DANGER)
          .padding({ left: 8, right: 8, top: 5, bottom: 5 })
          .backgroundColor(AppTheme.CHIP_BG)
          .borderRadius(100)
          .margin({ left: 6 })
          .onClick(() => {
            this.confirmRemoveNode(idx);
          })
      }
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 14, right: 10, top: 12, bottom: 12 })
  }

  @Builder
  nodeEditPanel() {
    Scroll() {
      Column() {
        Text('编辑节点')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT)
          .width('100%')

        Column() {
          CfgField({ label: '备注名称', value: this.eName, placeholder: '节点显示名称', onEdit: (v: string) => {
            this.eName = v;
          } })
          CfgField({ label: '服务器地址', value: this.eAddress, placeholder: '域名或 IP', onEdit: (v: string) => {
            this.eAddress = v;
          } })
          CfgField({ label: '端口', value: this.ePort, placeholder: '443', onEdit: (v: string) => {
            this.ePort = v;
          } })
          CfgField({
            label: this.credentialLabel(),
            value: this.eCredential,
            placeholder: this.credentialLabel(),
            onEdit: (v: string) => {
              this.eCredential = v;
            }
          })

          Row() {
            Text('运行内核')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppTheme.TEXT)
            Blank()
            if (this.eKernel === 'auto') {
              Text(this.editIdx >= 0 && this.editKernelEffective() ? '自动 · sing-box' : '自动 · Xray')
                .fontSize(11)
                .fontColor(AppTheme.TEXT_WEAK)
            }
          }
          .width('100%')
          .margin({ top: 14 })

          Flex({ wrap: FlexWrap.Wrap }) {
            CfgChoiceChip({ label: '自动', active: this.eKernel === 'auto', onPick: () => {
              this.eKernel = 'auto';
            } })
            CfgChoiceChip({ label: 'Xray', active: this.eKernel === 'xray', onPick: () => {
              this.eKernel = 'xray';
            } })
            CfgChoiceChip({ label: 'sing-box', active: this.eKernel === 'singbox', onPick: () => {
              this.eKernel = 'singbox';
            } })
          }
          .width('100%')
          .margin({ top: 4 })

          Text('hy2 / tuic 节点始终由 sing-box 承载；其余协议可在此手动指定内核')
            .fontSize(11)
            .fontColor(AppTheme.TEXT_WEAK)
            .width('100%')
            .margin({ top: 6 })

          Divider()
            .strokeWidth(1)
            .color(AppTheme.DIVIDER)
            .margin({ top: 16 })

          Row() {
            Text('其他信息')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppTheme.TEXT)
            Blank()
            SymbolGlyph(this.eAdvOpen ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_forward'))
              .fontSize(15)
              .fontColor([AppTheme.TEXT_WEAK])
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .margin({ top: 14 })
          .onClick(() => {
            this.eAdvOpen = !this.eAdvOpen;
          })

          if (this.eAdvOpen) {
            this.nodeAdvFields()
            Text('修改后请保存；不熟悉的参数建议保持原值')
              .fontSize(11)
              .fontColor(AppTheme.TEXT_WEAK)
              .width('100%')
              .margin({ top: 10 })
          }
        }
        .width('100%')
        .padding(16)
        .backgroundColor(AppTheme.CARD_BG)
        .borderRadius(AppTheme.CARD_RADIUS)
        .margin({ top: 12 })

        Button('保存修改')
          .width('100%')
          .height(46)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .backgroundColor(AppTheme.PRIMARY)
          .borderRadius(23)
          .margin({ top: 14 })
          .onClick(() => {
            this.saveNodeEdit();
          })

        Button('取消')
          .width('100%')
          .height(42)
          .fontSize(14)
          .fontColor(AppTheme.TEXT_SUB)
          .backgroundColor(AppTheme.CHIP_BG)
          .borderRadius(21)
          .margin({ top: 10 })
          .onClick(() => {
            this.editIdx = -1;
          })

        Text('展开「其他信息」可修改 TLS、传输协议等高级参数')
          .fontSize(11)
          .fontColor(AppTheme.TEXT_WEAK)
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 10 })
      }
      .width('100%')
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  @Builder
  nodesPage() {
    Column() {
      if (this.editIdx >= 0) {
        this.nodeEditPanel()
      } else {
        Text(this.nodeGroupTitle())
          .fontSize(12)
          .fontColor(AppTheme.TEXT_WEAK)
          .width('100%')
          .margin({ top: 10, bottom: 2 })

        if (this.groupNodes().length === 0) {
          Column() {
            SymbolGlyph($r('sys.symbol.list_bullet'))
              .fontSize(34)
              .fontColor([AppTheme.TEXT_WEAK])
            Text('该分组还没有节点')
              .fontSize(14)
              .fontColor(AppTheme.TEXT_SUB)
              .margin({ top: 10 })
            Text('可通过更新订阅或手动添加导入节点')
              .fontSize(11)
              .fontColor(AppTheme.TEXT_WEAK)
              .margin({ top: 6 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 8 }) {
            ForEach(this.groupNodes(), (item: ServerConfig, idx: number) => {
              ListItem() {
                this.groupNodeRow(item, idx)
              }
              .backgroundColor(AppTheme.CARD_BG)
              .borderRadius(14)
            }, (item: ServerConfig, idx: number) => idx.toString() + '|' + item.name + '|'
              + item.address + '|' + (typeof item.kernel === 'string' && item.kernel.length > 0 ? item.kernel : 'auto'))
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        }

        if (this.app.status.length > 0) {
          Text(this.app.status)
            .fontSize(11)
            .fontColor(AppTheme.TEXT_WEAK)
            .width('100%')
            .textAlign(TextAlign.Center)
            .maxLines(2)
            .margin({ top: 8, bottom: 8 })
        }
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  // ---------------- manual add ----------------


  private isUuidProtocol(): boolean {
    return this.mProtocol === 'vless' || this.mProtocol === 'vmess' || this.mProtocol === 'tuic';
  }

  private isSingboxProtocol(): boolean {
    return this.mProtocol === 'hy2' || this.mProtocol === 'tuic';
  }

  private buildManualServer(): ServerConfig | undefined {
    let port = parseInt(this.mPort, 10);
    if (this.mAddress.trim().length === 0 || isNaN(port) || port <= 0 || port > 65535) {
      return undefined;
    }
    let s = new ServerConfig();
    s.protocol = this.mProtocol;
    s.address = this.mAddress.trim();
    s.port = port;
    s.name = this.mName.trim().length > 0 ? this.mName.trim() : (s.address + ':' + port.toString());
    if (this.isUuidProtocol()) {
      s.uuid = this.mCredential.trim();
      s.alterId = 0;
    } else {
      s.password = this.mCredential.trim();
    }
    if (this.mProtocol === 'shadowsocks') {
      s.method = this.mMethod.trim().length > 0 ? this.mMethod.trim() : 'aes-128-gcm';
    }
    if (this.isSingboxProtocol()) {
      s.security = 'tls';
      s.sni = this.mSni.trim();
      s.alpn = this.mAlpn.trim();
      s.insecure = this.mInsecure;
      if (this.mProtocol === 'hy2') {
        if (this.mObfs.trim().length > 0) {
          s.obfs = 'salamander';
          s.obfsPassword = this.mObfs.trim();
        }
        s.ports = this.mPorts.trim();
      } else {
        s.password = this.mPassword2.trim();
      }
      return s;
    }
    s.network = this.mNetwork;
    s.path = this.mPath.trim();
    s.security = this.mSecurity;
    s.sni = this.mSni.trim();
    s.pbk = this.mPbk.trim();
    s.sid = this.mSid.trim();
    s.fp = this.mFp.trim().length > 0 ? this.mFp.trim() : 'chrome';
    return s;
  }

  private saveManual(): void {
    let s = this.buildManualServer();
    if (s === undefined) {
      this.app.status = '请检查地址与端口';
      return;
    }
    this.app.addServers([s], '本机节点');
    this.sub = SUB_OVERVIEW;
  }

  private quickAdd(): void {
    let text = this.quickLinkDraft.trim();
    if (text.length === 0) {
      this.app.status = '请先粘贴节点分享链接';
      return;
    }
    let list = parseSubscription(text);
    if (list.length === 0) {
      this.app.status = '无法识别的节点链接';
      return;
    }
    this.app.addServers(list, '本机节点');
    this.quickLinkDraft = '';
    this.sub = SUB_OVERVIEW;
  }

  @Builder
  manualPage() {
    Scroll() {
      Column() {
        Column() {
          Text('快速添加')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.TEXT)
            .width('100%')
          Text('粘贴 vless / vmess / trojan / ss / hy2 / tuic 分享链接，自动解析全部参数，支持一次多个')
            .fontSize(11)
            .fontColor(AppTheme.TEXT_WEAK)
            .width('100%')
            .margin({ top: 4 })
          TextInput({ text: this.quickLinkDraft, placeholder: 'vless://...' })
            .height(46)
            .fontSize(13)
            .backgroundColor(AppTheme.CHIP_BG)
            .borderRadius(12)
            .margin({ top: 10 })
            .onChange((v: string) => {
              this.quickLinkDraft = v;
            })
          Button('解析并添加')
            .width('100%')
            .height(44)
            .fontSize(15)
            .fontColor(Color.White)
            .backgroundColor(AppTheme.PRIMARY)
            .borderRadius(22)
            .margin({ top: 10 })
            .onClick(() => {
              this.quickAdd();
            })
        }
        .width('100%')
        .padding(16)
        .backgroundColor(AppTheme.CARD_BG)
        .borderRadius(AppTheme.CARD_RADIUS)

        Row() {
          Text('手动填写参数（高级）')
            .fontSize(13)
            .fontColor(AppTheme.TEXT_SUB)
          Blank()
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(15)
            .fontColor([AppTheme.TEXT_WEAK])
            .rotate({ z: 1, angle: this.advancedOpen ? 180 : 0 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: 16, right: 16, top: 14, bottom: 10 })
        .onClick(() => {
          this.advancedOpen = !this.advancedOpen;
        })

        if (this.advancedOpen) {
          Column() {
            Text('协议')
              .fontSize(12)
              .fontColor(AppTheme.TEXT_SUB)
              .width('100%')
            Flex({ wrap: FlexWrap.Wrap }) {
              CfgChoiceChip({ label: 'VLESS', active: this.mProtocol === 'vless', onPick: () => {
                this.mProtocol = 'vless';
              } })
              CfgChoiceChip({ label: 'VMess', active: this.mProtocol === 'vmess', onPick: () => {
                this.mProtocol = 'vmess';
              } })
              CfgChoiceChip({ label: 'Trojan', active: this.mProtocol === 'trojan', onPick: () => {
                this.mProtocol = 'trojan';
              } })
              CfgChoiceChip({ label: 'Shadowsocks', active: this.mProtocol === 'shadowsocks', onPick: () => {
                this.mProtocol = 'shadowsocks';
              } })
              CfgChoiceChip({ label: 'Hysteria2', active: this.mProtocol === 'hy2', onPick: () => {
                this.mProtocol = 'hy2';
              } })
              CfgChoiceChip({ label: 'TUIC', active: this.mProtocol === 'tuic', onPick: () => {
                this.mProtocol = 'tuic';
              } })
            }
            .width('100%')
            .margin({ top: 4 })
            if (this.isSingboxProtocol()) {
              Text('hy2 / tuic 由 sing-box 内核承载，TLS 为协议内置，无需单独配置')
                .fontSize(11)
                .fontColor(AppTheme.TEXT_WEAK)
                .width('100%')
                .margin({ top: 6 })
            }

            CfgField({ label: '备注名称', value: this.mName, placeholder: '例如 香港01', onEdit: (v: string) => {
              this.mName = v;
            } })
            CfgField({ label: '服务器地址', value: this.mAddress, placeholder: '域名或 IP', onEdit: (v: string) => {
              this.mAddress = v;
            } })
            CfgField({ label: '端口', value: this.mPort, placeholder: '443', onEdit: (v: string) => {
              this.mPort = v;
            } })
            CfgField({
              label: this.isUuidProtocol() ? '用户 ID (UUID)' : '密码',
              value: this.mCredential,
              placeholder: this.isUuidProtocol() ? 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' : '密码',
              onEdit: (v: string) => {
                this.mCredential = v;
              }
            })

            if (this.mProtocol === 'tuic') {
              CfgField({ label: '密码', value: this.mPassword2, placeholder: 'TUIC 密码', onEdit: (v: string) => {
                this.mPassword2 = v;
              } })
            }

            if (this.mProtocol === 'shadowsocks') {
              CfgField({ label: '加密方式', value: this.mMethod, placeholder: 'aes-128-gcm / chacha20-ietf-poly1305', onEdit: (v: string) => {
                this.mMethod = v;
              } })
            }

            if (this.isSingboxProtocol()) {
              CfgField({ label: 'SNI', value: this.mSni, placeholder: '例如 www.example.com', onEdit: (v: string) => {
                this.mSni = v;
              } })
              CfgField({
                label: 'ALPN',
                value: this.mAlpn,
                placeholder: this.mProtocol === 'tuic' ? 'h3（默认）' : 'h3 / http1.1，可留空',
                onEdit: (v: string) => {
                  this.mAlpn = v;
                }
              })
              if (this.mProtocol === 'hy2') {
                CfgField({
                  label: '混淆密码 (obfs)',
                  value: this.mObfs,
                  placeholder: 'salamander 混淆密码，可留空',
                  onEdit: (v: string) => {
                    this.mObfs = v;
                  }
                })
                CfgField({
                  label: '端口跳跃',
                  value: this.mPorts,
                  placeholder: '例如 20000-30000，可留空',
                  onEdit: (v: string) => {
                    this.mPorts = v;
                  }
                })
              }
              Text('跳过证书验证 (insecure)')
                .fontSize(12)
                .fontColor(AppTheme.TEXT_SUB)
                .width('100%')
                .margin({ top: 14 })
              Flex({ wrap: FlexWrap.Wrap }) {
                CfgChoiceChip({ label: '关闭', active: !this.mInsecure, onPick: () => {
                  this.mInsecure = false;
                } })
                CfgChoiceChip({ label: '开启', active: this.mInsecure, onPick: () => {
                  this.mInsecure = true;
                } })
              }
              .width('100%')
              .margin({ top: 4 })
            }

            if (!this.isSingboxProtocol()) {
            Text('传输方式')
              .fontSize(12)
              .fontColor(AppTheme.TEXT_SUB)
              .width('100%')
              .margin({ top: 14 })
            Flex({ wrap: FlexWrap.Wrap }) {
              CfgChoiceChip({ label: 'TCP', active: this.mNetwork === 'tcp', onPick: () => {
                this.mNetwork = 'tcp';
              } })
              CfgChoiceChip({ label: 'WebSocket', active: this.mNetwork === 'ws', onPick: () => {
                this.mNetwork = 'ws';
              } })
              CfgChoiceChip({ label: 'gRPC', active: this.mNetwork === 'grpc', onPick: () => {
                this.mNetwork = 'grpc';
              } })
            }
            .width('100%')
            .margin({ top: 4 })

            if (this.mNetwork !== 'tcp') {
              CfgField({ label: this.mNetwork === 'grpc' ? '服务名' : '路径 (path)', value: this.mPath, placeholder: '/ws', onEdit: (v: string) => {
                this.mPath = v;
              } })
            }

            Text('安全')
              .fontSize(12)
              .fontColor(AppTheme.TEXT_SUB)
              .width('100%')
              .margin({ top: 14 })
            Flex({ wrap: FlexWrap.Wrap }) {
              CfgChoiceChip({ label: '无', active: this.mSecurity === 'none', onPick: () => {
                this.mSecurity = 'none';
              } })
              CfgChoiceChip({ label: 'TLS', active: this.mSecurity === 'tls', onPick: () => {
                this.mSecurity = 'tls';
              } })
              CfgChoiceChip({ label: 'REALITY', active: this.mSecurity === 'reality', onPick: () => {
                this.mSecurity = 'reality';
              } })
            }
            .width('100%')
            .margin({ top: 4 })

            if (this.mSecurity === 'tls' || this.mSecurity === 'reality') {
              CfgField({ label: 'SNI', value: this.mSni, placeholder: '例如 www.example.com', onEdit: (v: string) => {
                this.mSni = v;
              } })
            }
            if (this.mSecurity === 'reality') {
              CfgField({ label: '公钥 (pbk)', value: this.mPbk, placeholder: 'REALITY 公钥', onEdit: (v: string) => {
                this.mPbk = v;
              } })
              CfgField({ label: 'Short ID', value: this.mSid, placeholder: '可留空', onEdit: (v: string) => {
                this.mSid = v;
              } })
              CfgField({ label: '指纹 (fp)', value: this.mFp, placeholder: 'chrome', onEdit: (v: string) => {
                this.mFp = v;
              } })
            }
            }

            Button('保存到「' + this.app.activeGroupName() + '」')
              .width('100%')
              .height(46)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
              .backgroundColor(AppTheme.PRIMARY)
              .borderRadius(23)
              .margin({ top: 18 })
              .onClick(() => {
                this.saveManual();
              })
          }
          .width('100%')
          .padding(16)
          .backgroundColor(AppTheme.CARD_BG)
          .borderRadius(AppTheme.CARD_RADIUS)
        }

        if (this.app.status.length > 0) {
          Text(this.app.status)
            .fontSize(11)
            .fontColor(AppTheme.TEXT_WEAK)
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ top: 10 })
            .maxLines(2)
        }
      }
      .width('100%')
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  // ---------------- routing ----------------

  @Builder
  domainList(title: string, items: string[], proxySide: boolean, hint: string) {
    Column() {
      Row() {
        Text(title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT)
        Blank()
        Text(items.length.toString() + ' 条')
          .fontSize(11)
          .fontColor(AppTheme.TEXT_WEAK)
      }
      .width('100%')

      Text(hint)
        .fontSize(11)
        .fontColor(AppTheme.TEXT_WEAK)
        .width('100%')
        .margin({ top: 4 })

      ForEach(items, (d: string) => {
        Row() {
          Text(d)
            .fontSize(14)
            .fontColor(AppTheme.TEXT)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          SymbolGlyph($r('sys.symbol.xmark_circle'))
            .fontSize(16)
            .fontColor([AppTheme.TEXT_WEAK])
            .onClick(() => {
              this.app.removeRouteDomain(proxySide, d);
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ top: 8 })
      }, (d: string, i: number) => proxySide.toString() + '|' + i.toString() + '|' + d)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(AppTheme.CARD_BG)
    .borderRadius(AppTheme.CARD_RADIUS)
    .margin({ top: 12 })
  }

  @Builder
  routingPage() {
    Scroll() {
      Column() {
        Column() {
          Row() {
            Column() {
              Text('绕过中国大陆')
                .fontSize(15)
                .fontColor(AppTheme.TEXT)
              Text('geosite:cn 与 geoip:cn 直连')
                .fontSize(11)
                .fontColor(AppTheme.TEXT_SUB)
                .margin({ top: 3 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Toggle({ type: ToggleType.Switch, isOn: this.app.routeBypassCn })
              .onChange((v: boolean) => {
                this.app.setBypassCn(v);
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })

          Divider().strokeWidth(1).color(AppTheme.DIVIDER).margin({ left: 16, right: 16 })

          Row() {
            Column() {
              Text('拦截广告')
                .fontSize(15)
                .fontColor(AppTheme.TEXT)
              Text('geosite:category-ads-all 走 blackhole')
                .fontSize(11)
                .fontColor(AppTheme.TEXT_SUB)
                .margin({ top: 3 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Toggle({ type: ToggleType.Switch, isOn: this.app.routeBlockAds })
              .onChange((v: boolean) => {
                this.app.setBlockAds(v);
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        }
        .width('100%')
        .backgroundColor(AppTheme.CARD_BG)
        .borderRadius(AppTheme.CARD_RADIUS)

        Row({ space: 8 }) {
          TextInput({ text: this.directDraft, placeholder: '直连域名，如 example.com' })
            .layoutWeight(1)
            .height(42)
            .fontSize(13)
            .backgroundColor(AppTheme.CARD_BG)
            .borderRadius(12)
            .onChange((v: string) => {
              this.directDraft = v;
            })
          Button('添加')
            .width(72)
            .height(42)
            .fontSize(14)
            .fontColor(Color.White)
            .backgroundColor(AppTheme.PRIMARY)
            .borderRadius(21)
            .onClick(() => {
              if (this.app.addRouteDomain(false, this.directDraft)) {
                this.directDraft = '';
              }
            })
        }
        .width('100%')
        .margin({ top: 12 })

        this.domainList('直连域名', this.app.routeDirectDomains, false, '支持 domain: / full: / geosite: 前缀，留空自动补 domain:')

        Row({ space: 8 }) {
          TextInput({ text: this.proxyDraft, placeholder: '强制代理域名，如 openai.com' })
            .layoutWeight(1)
            .height(42)
            .fontSize(13)
            .backgroundColor(AppTheme.CARD_BG)
            .borderRadius(12)
            .onChange((v: string) => {
              this.proxyDraft = v;
            })
          Button('添加')
            .width(72)
            .height(42)
            .fontSize(14)
            .fontColor(Color.White)
            .backgroundColor(AppTheme.PRIMARY)
            .borderRadius(21)
            .onClick(() => {
              if (this.app.addRouteDomain(true, this.proxyDraft)) {
                this.proxyDraft = '';
              }
            })
        }
        .width('100%')
        .margin({ top: 12 })

        this.domainList('强制代理域名', this.app.routeProxyDomains, true, '优先级高于 CN 直连，命中即走代理')

        Text('修改后需重新连接 VPN 生效')
          .fontSize(11)
          .fontColor(AppTheme.TEXT_WEAK)
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 14 })
      }
      .width('100%')
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  // ---------------- per-app proxy ----------------

  private perAppModeDesc(): string {
    if (this.app.perAppMode === 'trust') {
      return '仅列表内应用的流量经过 VPN，其余应用直连（v2rayH 自身始终直连）';
    }
    if (this.app.perAppMode === 'block') {
      return '除列表内应用外的所有流量经过 VPN（v2rayH 自身始终直连）';
    }
    return '所有应用的流量都经过 VPN';
  }

  @Builder
  perappPage() {
    Scroll() {
      Column() {
        Column() {
          Text('代理模式')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.TEXT)
            .width('100%')
          Flex({ wrap: FlexWrap.Wrap }) {
            CfgChoiceChip({ label: '全部应用', active: this.app.perAppMode === 'all', onPick: () => {
              this.app.setPerAppMode('all');
            } })
            CfgChoiceChip({ label: '仅选中应用', active: this.app.perAppMode === 'trust', onPick: () => {
              this.app.setPerAppMode('trust');
            } })
            CfgChoiceChip({ label: '排除选中应用', active: this.app.perAppMode === 'block', onPick: () => {
              this.app.setPerAppMode('block');
            } })
          }
          .width('100%')
          .margin({ top: 4 })

          Text(this.perAppModeDesc())
            .fontSize(11)
            .fontColor(AppTheme.TEXT_WEAK)
            .width('100%')
            .margin({ top: 10 })

          Divider()
            .strokeWidth(1)
            .color(AppTheme.DIVIDER)
            .margin({ top: 14, bottom: 14 })

          Row() {
            Text('应用列表')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppTheme.TEXT)
            Blank()
            Text(this.app.perAppBundles.length.toString() + ' 个')
              .fontSize(11)
              .fontColor(AppTheme.TEXT_WEAK)
          }
          .width('100%')

          Row({ space: 8 }) {
            TextInput({ text: this.perAppDraft, placeholder: '应用包名，如 com.example.app' })
              .layoutWeight(1)
              .height(42)
              .fontSize(13)
              .backgroundColor(AppTheme.CHIP_BG)
              .borderRadius(12)
              .onChange((v: string) => {
                this.perAppDraft = v;
              })
            Button('添加')
              .width(72)
              .height(42)
              .fontSize(14)
              .fontColor(Color.White)
              .backgroundColor(AppTheme.PRIMARY)
              .borderRadius(21)
              .onClick(() => {
                if (this.app.addPerAppBundle(this.perAppDraft)) {
                  this.perAppDraft = '';
                } else if (this.perAppDraft.trim().length > 0) {
                  this.app.status = '包名为空或已存在';
                }
              })
          }
          .width('100%')
          .margin({ top: 10 })

          ForEach(this.app.perAppBundles, (b: string) => {
            Row() {
              Text(b)
                .fontSize(13)
                .fontColor(AppTheme.TEXT)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              SymbolGlyph($r('sys.symbol.xmark_circle'))
                .fontSize(16)
                .fontColor([AppTheme.TEXT_WEAK])
                .onClick(() => {
                  this.app.removePerAppBundle(b);
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .backgroundColor(AppTheme.CHIP_BG)
            .borderRadius(10)
            .margin({ top: 8 })
          }, (b: string, i: number) => i.toString() + '|' + b)
        }
        .width('100%')
        .padding(16)
        .backgroundColor(AppTheme.CARD_BG)
        .borderRadius(AppTheme.CARD_RADIUS)
        .margin({ top: 12 })
        .shadow({ radius: 14, color: '#10000000', offsetY: 3 })

        Text('系统不允许应用读取已安装应用列表，需手动输入应用包名（bundle name）。修改后需重新连接 VPN 生效。')
          .fontSize(11)
          .fontColor(AppTheme.TEXT_WEAK)
          .width('100%')
          .margin({ top: 12, left: 4 })
          .maxLines(4)

        if (this.app.status.length > 0) {
          Text(this.app.status)
            .fontSize(11)
            .fontColor(AppTheme.PRIMARY)
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ top: 8 })
            .maxLines(2)
        }
      }
      .width('100%')
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  // ---------------- geo ----------------

  private geoSourceLabel(): string {
    let u = this.app.geoUrlGeosite;
    if (u.indexOf('cdn.jsdelivr.net') >= 0) {
      return 'Loyalsoldier CDN';
    }
    if (u.indexOf('github.com/Loyalsoldier') >= 0) {
      return 'Loyalsoldier GitHub';
    }
    if (u.indexOf('v2fly') >= 0) {
      return 'v2fly 官方';
    }
    return '自定义';
  }

  private applyGeoPreset(idx: number): void {
    let site = '';
    let ip = '';
    if (idx === 0) {
      site = 'https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/geosite.dat';
      ip = 'https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/geoip.dat';
    } else if (idx === 1) {
      site = 'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat';
      ip = 'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat';
    } else {
      site = 'https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat';
      ip = 'https://github.com/v2fly/geoip/releases/latest/download/geoip.dat';
    }
    this.app.setGeoUrls(site, ip);
    this.app.status = '来源已切换，点立即更新';
  }

  private async pasteGeoLinks(): Promise<void> {
    let granted = await this.ensureReadPasteboard();
    if (!granted) {
      return;
    }
    try {
      let board = pasteboard.getSystemPasteboard();
      let has = await board.hasData();
      if (!has) {
        this.app.status = '剪贴板为空';
        return;
      }
      let data = await board.getData();
      let text = data.getPrimaryText();
      if (text === undefined) {
        this.app.status = '剪贴板为空';
        return;
      }
      text = text.trim();
      if (text.length === 0) {
        this.app.status = '剪贴板为空';
        return;
      }
      let lines = text.split('\n');
      let site = lines[0].trim();
      let ip = lines.length > 1 ? lines[1].trim() : this.app.geoUrlGeoip;
      this.app.setGeoUrls(site, ip);
      this.app.status = '已从剪贴板导入链接';
    } catch (e) {
      let err = e as BusinessError;
      this.app.status = '读取剪贴板失败: ' + err.code.toString();
    }
  }

  private geoSourceMenu(): MenuElement[] {
    let items: MenuElement[] = [];
    items.push({ value: 'Loyalsoldier CDN', action: () => {
      this.applyGeoPreset(0);
    } });
    items.push({ value: 'Loyalsoldier GitHub', action: () => {
      this.applyGeoPreset(1);
    } });
    items.push({ value: 'v2fly 官方', action: () => {
      this.applyGeoPreset(2);
    } });
    items.push({ value: '从剪贴板读取链接', action: () => {
      this.pasteGeoLinks();
    } });
    return items;
  }

  private localFileMenu(): MenuElement[] {
    let items: MenuElement[] = [];
    items.push({ value: '导入为 geosite.dat', action: () => {
      this.app.importGeoFile(true);
    } });
    items.push({ value: '导入为 geoip.dat', action: () => {
      this.app.importGeoFile(false);
    } });
    return items;
  }

  @Builder
  geoPage() {
    Scroll() {
      Column() {
        Column() {
          CfgEntryRow({
            icon: $r('sys.symbol.network_acceleration'),
            title: 'geo 文件来源',
            value: this.geoSourceLabel(),
            items: this.geoSourceMenu()
          })
          Divider().strokeWidth(1).color(AppTheme.DIVIDER).margin({ left: 16, right: 16 })
          CfgEntryRow({
            icon: $r('sys.symbol.doc'),
            title: '选择本地文件',
            value: '把本地 .dat 导入为 geosite / geoip',
            items: this.localFileMenu()
          })
        }
        .width('100%')
        .backgroundColor(AppTheme.CARD_BG)
        .borderRadius(AppTheme.CARD_RADIUS)
        .margin({ top: 18 })
        .shadow({ radius: 14, color: '#10000000', offsetY: 3 })

        Column() {
          Row() {
            Text('已有资源文件')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppTheme.TEXT)
            Blank()
            Button(this.app.downloadTesting ? '下载测速中...' : (this.app.testing ? '测速中...' : (this.app.busy ? '更新中...' : '立即更新')))
              .fontSize(12)
              .height(30)
              .fontColor(AppTheme.PRIMARY)
              .backgroundColor(AppTheme.PRIMARY_SOFT)
              .borderRadius(15)
              .enabled(!this.app.busy)
              .onClick(() => {
                this.confirmUpdateGeo();
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          CfgGeoFileRow({ fileName: 'geosite.dat', fileSize: this.app.geositeSize, fileAt: this.app.geositeAt })
          CfgGeoFileRow({ fileName: 'geoip.dat', fileSize: this.app.geoipSize, fileAt: this.app.geoipAt })
        }
        .width('100%')
        .padding(16)
        .backgroundColor(AppTheme.CARD_BG)
        .borderRadius(AppTheme.CARD_RADIUS)
        .margin({ top: 12 })
        .shadow({ radius: 14, color: '#10000000', offsetY: 3 })

        Text('文件存放在应用沙箱 files/geo，Xray 从该目录加载分流规则。')
          .fontSize(11)
          .fontColor(AppTheme.TEXT_WEAK)
          .width('100%')
          .margin({ top: 12 })

        if (this.app.status.length > 0) {
          Text(this.app.status)
            .fontSize(11)
            .fontColor(AppTheme.PRIMARY)
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ top: 8 })
            .maxLines(2)
        }
      }
      .width('100%')
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  build() {
    Column() {
      ForEach([this.themeRev], (rev: number) => {
        Column() {
          this.topHeader()

          if (this.sub === SUB_OVERVIEW) {
            this.overview()
          } else if (this.sub === SUB_GROUPS) {
            this.groupsPage()
          } else if (this.sub === SUB_ROUTING) {
            this.routingPage()
          } else if (this.sub === SUB_MANUAL) {
            this.manualPage()
          } else if (this.sub === SUB_NODES) {
            this.nodesPage()
          } else if (this.sub === SUB_PERAPP) {
            this.perappPage()
          } else {
            this.geoPage()
          }
        }
        .width('100%')
        .layoutWeight(1)
      }, (rev: number) => 'theme-' + rev.toString())
    }
    .width('100%')
    .height('100%')
    .padding({
      left: AppTheme.PAGE_GAP,
      right: AppTheme.PAGE_GAP,
      top: px2vp(this.topRectPx) + 8,
      bottom: px2vp(this.bottomRectPx) + AppTheme.BAR_RESERVE
    })
    .bindSheet($$this.showShare, this.shareSheetBuilder(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: true
    })
  }
}

@Component
struct CfgChoiceChip {
  label: string = '';
  @Prop active: boolean = false;
  onPick: () => void = () => {};

  build() {
    Text(this.label)
      .fontSize(12)
      .fontColor(this.active ? Color.White : AppTheme.TEXT)
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .backgroundColor(this.active ? AppTheme.PRIMARY : AppTheme.CHIP_BG)
      .borderRadius(100)
      .margin({ right: 8, top: 6 })
      .onClick(() => {
        this.onPick();
      })
  }
}

@Component
struct CfgField {
  label: string = '';
  @Prop value: string = '';
  placeholder: string = '';
  onEdit: (v: string) => void = () => {};

  build() {
    Column() {
      Text(this.label)
        .fontSize(12)
        .fontColor(AppTheme.TEXT_SUB)
        .width('100%')
      TextInput({ text: this.value, placeholder: this.placeholder })
        .width('100%')
        .height(42)
        .fontSize(13)
        .backgroundColor(AppTheme.CHIP_BG)
        .borderRadius(12)
        .margin({ top: 6 })
        .onChange((v: string) => {
          this.onEdit(v);
        })
    }
    .width('100%')
    .margin({ top: 12 })
  }
}
@Component
struct CfgEntryRow {
  icon: Resource = $r('sys.symbol.doc');
  title: string = '';
  @Prop value: string = '';
  items: MenuElement[] = [];

  build() {
    Row({ space: 12 }) {
      SymbolGlyph(this.icon)
        .fontSize(20)
        .fontColor([AppTheme.PRIMARY])

      Column() {
        Text(this.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT)
        Text(this.value)
          .fontSize(11)
          .fontColor(AppTheme.TEXT_SUB)
          .margin({ top: 2 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph($r('sys.symbol.chevron_forward'))
        .fontSize(15)
        .fontColor([AppTheme.TEXT_WEAK])
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .bindMenu(this.items)
  }
}

@Component
struct CfgGeoFileRow {
  fileName: string = '';
  @Prop fileSize: number = 0;
  @Prop fileAt: number = 0;

  private sizeText(): string {
    if (this.fileSize <= 0) {
      return '缺失';
    }
    if (this.fileSize < 1024 * 1024) {
      return Math.floor(this.fileSize / 1024).toString() + ' KB';
    }
    return (this.fileSize / 1024 / 1024).toFixed(1) + ' MB';
  }

  private timeText(): string {
    if (this.fileAt <= 0) {
      return '未更新';
    }
    let d = new Date(this.fileAt);
    let mm = d.getMonth() + 1;
    let dd = d.getDate();
    let hh = d.getHours();
    let mi = d.getMinutes();
    let mStr = mm < 10 ? '0' + mm.toString() : mm.toString();
    let dStr = dd < 10 ? '0' + dd.toString() : dd.toString();
    let hStr = hh < 10 ? '0' + hh.toString() : hh.toString();
    let iStr = mi < 10 ? '0' + mi.toString() : mi.toString();
    return d.getFullYear().toString() + '-' + mStr + '-' + dStr + ' ' + hStr + ':' + iStr;
  }

  build() {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.doc'))
        .fontSize(18)
        .fontColor([AppTheme.TEXT_SUB])

      Column() {
        Text(this.fileName)
          .fontSize(14)
          .fontColor(AppTheme.TEXT)
        Text(this.sizeText() + ' · ' + this.timeText())
          .fontSize(11)
          .fontColor(AppTheme.TEXT_WEAK)
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ top: 12, bottom: 4 })
  }
}