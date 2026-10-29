import { pasteboard, BusinessError } from '@kit.BasicServicesKit';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { scanBarcode } from '@kit.ScanKit';
import { AppState } from '../common/AppState';
import { AppTheme } from '../common/AppTheme';
import { parseSubscription } from '../common/V2rayParser';
import { ServerConfig } from '../model/ServerConfig';
import { SubGroup } from '../model/SubGroup';

const SUB_OVERVIEW: number = 0;
const SUB_GROUPS: number = 1;
const SUB_ROUTING: number = 2;
const SUB_GEO: number = 3;
const SUB_MANUAL: number = 4;
const ACT_SCAN: number = 100;
const ACT_CLIPBOARD: number = 101;

@Component
export struct ConfigTab {
  @ObjectLink app: AppState;
  @StorageProp('themeRev') themeRev: number = 0;
  @Prop @Watch('onResetTick') resetTick: number = 0;
  @StorageProp('topRectHeight') topRectPx: number = 0;
  @StorageProp('bottomRectHeight') bottomRectPx: number = 0;
  @State sub: number = SUB_OVERVIEW;
  @State groupNameDraft: string = '';
  @State groupUrlDraft: string = '';
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
    return '配置';
  }

  onResetTick(): void {
    this.sub = SUB_OVERVIEW;
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
      return '手动填写节点参数';
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
            this.sub = SUB_OVERVIEW;
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

  private async importFromScan(): Promise<void> {
    let ctx = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      this.app.status = '上下文未就绪';
      return;
    }
    try {
      let res = await scanBarcode.startScanForResult(ctx);
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
        if (g.url.length > 0) {
          SymbolGlyph($r('sys.symbol.arrow_2_circlepath'))
            .fontSize(18)
            .fontColor([this.app.activeGroup === idx ? AppTheme.PRIMARY : AppTheme.TEXT_SUB])
            .padding(8)
            .onClick(() => {
              this.app.updateGroupSubscription(idx);
            })
        }
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

      Column() {
        Text('新建分组')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT)
          .width('100%')
        TextInput({ text: this.groupNameDraft, placeholder: '分组名称，例如 自用 / 机场A' })
          .height(42)
          .fontSize(13)
          .backgroundColor(AppTheme.CHIP_BG)
          .borderRadius(12)
          .margin({ top: 8 })
          .onChange((v: string) => {
            this.groupNameDraft = v;
          })
        TextInput({ text: this.groupUrlDraft, placeholder: '订阅链接（可留空后手动添加）' })
          .height(42)
          .fontSize(13)
          .backgroundColor(AppTheme.CHIP_BG)
          .borderRadius(12)
          .margin({ top: 8 })
          .onChange((v: string) => {
            this.groupUrlDraft = v;
          })
        Button('创建分组并拉取订阅')
          .width('100%')
          .height(44)
          .fontSize(15)
          .fontColor(Color.White)
          .backgroundColor(AppTheme.PRIMARY)
          .borderRadius(22)
          .enabled(!this.app.busy)
          .margin({ top: 10 })
          .onClick(() => {
            this.createGroup();
          })
      }
      .width('100%')
      .padding(16)
      .backgroundColor(AppTheme.CARD_BG)
      .borderRadius(AppTheme.CARD_RADIUS)
      .margin({ top: 10 })
    }
    .width('100%')
    .layoutWeight(1)
  }

  private createGroup(): void {
    let name = this.groupNameDraft.trim();
    if (name.length === 0) {
      return;
    }
    this.app.addGroup(name, this.groupUrlDraft.trim());
    this.groupNameDraft = '';
    this.groupUrlDraft = '';
    this.sub = SUB_OVERVIEW;
    if (this.app.subUrl.length > 0) {
      this.app.updateSubscription();
    }
  }

  // ---------------- manual add ----------------


  private isUuidProtocol(): boolean {
    return this.mProtocol === 'vless' || this.mProtocol === 'vmess';
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

  @Builder
  manualPage() {
    Scroll() {
      Column() {
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
          }
          .width('100%')
          .margin({ top: 4 })

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

          if (this.mProtocol === 'shadowsocks') {
            CfgField({ label: '加密方式', value: this.mMethod, placeholder: 'aes-128-gcm / chacha20-ietf-poly1305', onEdit: (v: string) => {
              this.mMethod = v;
            } })
          }

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
        .padding(16)
        .backgroundColor(AppTheme.CARD_BG)
        .borderRadius(AppTheme.CARD_RADIUS)
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
                this.app.updateGeoFiles();
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
      this.topHeader()

      if (this.sub === SUB_OVERVIEW) {
        this.overview()
      } else if (this.sub === SUB_GROUPS) {
        this.groupsPage()
      } else if (this.sub === SUB_ROUTING) {
        this.routingPage()
      } else if (this.sub === SUB_MANUAL) {
        this.manualPage()
      } else {
        this.geoPage()
      }
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