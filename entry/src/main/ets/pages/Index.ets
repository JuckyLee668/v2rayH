import { vpnExtension } from '@kit.NetworkKit';
import { Want, common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import testNapi from 'libentry.so';
import { ServerConfig } from '../model/ServerConfig';
import { parseSubscription } from '../common/V2rayParser';
import { buildXrayConfig, buildTestConfig } from '../common/XrayConf';
import { AppStore } from '../common/AppStore';
import { SubscriptionFetcher } from '../common/SubscriptionFetcher';

const VPN_WANT: Want = {
  bundleName: 'com.xii.v2rayh',
  abilityName: 'MyVpnExtAbility'
};

const COLOR_PRIMARY: string = '#0a59f7';
const COLOR_DANGER: string = '#e84026';
const COLOR_OK: string = '#34c759';

@Entry
@Component
struct Index {
  @State servers: ServerConfig[] = [];
  @State selected: number = 0;
  @State status: string = '';
  @State subUrl: string = '';
  @State busy: boolean = false;
  @State connected: boolean = false;
  @State pings: number[] = [];
  private store: AppStore = new AppStore();

  aboutToAppear(): void {
    let ctx = this.getUIContext().getHostContext();
    if (ctx !== undefined) {
      this.store.init(ctx.filesDir);
    }
    this.subUrl = this.store.loadSubscriptionUrl();
    this.servers = this.store.loadServers();
    this.selected = this.store.loadSelected();
    this.ensureGeoFiles();
  }

  private ensureGeoFiles(): void {
    let ctx = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return;
    }
    let geoDir = ctx.filesDir + '/geo';
    try {
      if (!fs.accessSync(geoDir)) {
        fs.mkdirSync(geoDir);
      }
    } catch (e) {
      console.error('mkdir geo failed: ' + JSON.stringify(e));
    }
    let names: string[] = ['geoip.dat', 'geosite.dat'];
    for (let i = 0; i < names.length; i++) {
      let name = names[i];
      let dest = geoDir + '/' + name;
      try {
        if (fs.accessSync(dest)) {
          continue;
        }
        let data = ctx.resourceManager.getRawFileContentSync(name);
        let f = fs.openSync(dest, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
        fs.writeSync(f.fd, data.buffer);
        fs.closeSync(f);
      } catch (e) {
        console.error('copy geo failed: ' + name + ' ' + JSON.stringify(e));
      }
    }
  }

  private currentNodeName(): string {
    if (this.servers.length === 0 || this.selected >= this.servers.length) {
      return '未选择节点';
    }
    return this.servers[this.selected].name;
  }

  private doUpdateSubscription(): void {
    let url = this.subUrl.trim();
    if (url.length === 0) {
      this.status = '请输入订阅链接';
      return;
    }
    this.busy = true;
    this.status = '正在拉取订阅...';
    SubscriptionFetcher.fetchText(url).then((content: string) => {
      let list = parseSubscription(content);
      if (list.length === 0) {
        this.status = '拉取失败: ' + content.length.toString() + 'B, err=' + SubscriptionFetcher.lastError;
        this.busy = false;
        return;
      }
      this.servers = list;
      this.selected = 0;
      this.pings = [];
      this.store.saveServers(list);
      this.store.saveSubscriptionUrl(url);
      this.store.saveSelected(0);
      this.status = '订阅更新成功，共 ' + list.length.toString() + ' 个节点';
      this.busy = false;
    });
  }

  private async doTestAll(): Promise<void> {
    if (this.servers.length === 0) {
      return;
    }
    let init: number[] = [];
    for (let i = 0; i < this.servers.length; i++) {
      init.push(-2);
    }
    this.pings = init;
    this.status = '正在测速(经代理实测延迟)...';
    for (let i = 0; i < this.servers.length; i++) {
      let srv: ServerConfig = this.servers[i];
      let cfg: string = buildTestConfig(srv);
      let ms: number = await testNapi.measureDelay(cfg, 'http://www.gstatic.com/generate_204');
      let copy: number[] = [];
      for (let j = 0; j < this.pings.length; j++) {
        copy.push(this.pings[j]);
      }
      copy[i] = ms;
      this.pings = copy;
    }
    this.status = '测速完成';
  }

  private pingText(idx: number): string {
    if (idx >= this.pings.length) {
      return '';
    }
    let p: number = this.pings[idx];
    if (p === -2) {
      return '测试中';
    }
    if (p < 0) {
      return '超时';
    }
    return p.toString() + 'ms';
  }

  private doConnect(): void {
    if (this.servers.length === 0) {
      this.status = '请先添加订阅';
      return;
    }
    if (this.selected >= this.servers.length) {
      this.selected = 0;
    }
    let server = this.servers[this.selected];
    let cfg = buildXrayConfig(server, '/data/storage/el2/base/haps/entry/files/xray_error.log');
    this.store.saveXrayConfig(cfg);
    this.status = '正在连接: ' + server.name;
    vpnExtension.startVpnExtensionAbility(VPN_WANT).then(() => {
      this.connected = true;
      this.status = '';
    }).catch((err: BusinessError) => {
      this.status = '连接失败: ' + JSON.stringify(err);
    });
  }

  private doDisconnect(): void {
    vpnExtension.stopVpnExtensionAbility(VPN_WANT).then(() => {
      this.connected = false;
      this.status = '已断开';
    }).catch((err: BusinessError) => {
      this.status = '断开失败: ' + JSON.stringify(err);
    });
  }

  @Builder
  statusCard() {
    Column() {
      Row() {
        Circle()
          .width(10)
          .height(10)
          .fill(this.connected ? COLOR_OK : '#c7c7cc')
        Text(this.connected ? '已连接' : '未连接')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 8 })
      }
      .width('100%')

      Text(this.currentNodeName())
        .fontSize(13)
        .fontColor('#8a8a8e')
        .width('100%')
        .margin({ top: 6 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Button(this.connected ? '断开连接' : '连接')
        .width('100%')
        .height(44)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .backgroundColor(this.connected ? COLOR_DANGER : COLOR_PRIMARY)
        .margin({ top: 16 })
        .onClick(() => {
          if (this.connected) {
            this.doDisconnect();
          } else {
            this.doConnect();
          }
        })
    }
    .width('92%')
    .padding(18)
    .backgroundColor('#ffffff')
    .borderRadius(16)
    .shadow({ radius: 10, color: '#14000000', offsetY: 2 })
  }

  @Builder
  serverItem(item: ServerConfig, idx: number) {
    Row() {
      Column() {
        Text(item.name)
          .fontSize(15)
          .fontWeight(this.selected === idx ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.selected === idx ? COLOR_PRIMARY : '#1c1c1e')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(item.protocol + ' · ' + item.address + ':' + item.port.toString())
          .fontSize(11)
          .fontColor('#8a8a8e')
          .margin({ top: 3 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)

      Text(this.pingText(idx))
        .fontSize(12)
        .fontColor('#8a8a8e')
        .margin({ right: 8 })

      if (this.selected === idx) {
        Text('✓')
          .fontColor(COLOR_PRIMARY)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
  }

  build() {
    Column() {
      Row() {
        Text('v2rayH')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
        Text(this.connected ? '  VPN 运行中' : '')
          .fontSize(12)
          .fontColor(COLOR_OK)
      }
      .width('100%')
      .height(52)
      .padding({ left: 16 })

      this.statusCard()

      Text(this.status)
        .fontSize(12)
        .fontColor('#8a8a8e')
        .width('92%')
        .margin({ top: 8 })
        .maxLines(2)

      Row() {
        Text('服务器 (' + this.servers.length.toString() + ')')
          .fontSize(14)
          .fontColor('#666666')
        Blank()
        Button('测速')
          .fontSize(13)
          .height(30)
          .backgroundColor('#e8e8ed')
          .fontColor('#1c1c1e')
          .onClick(() => {
            this.doTestAll();
          })
      }
      .width('92%')
      .margin({ top: 14, bottom: 8 })

      List({ space: 8 }) {
        ForEach(this.servers, (item: ServerConfig, idx: number) => {
          ListItem() {
            this.serverItem(item, idx)
          }
          .backgroundColor('#ffffff')
          .borderRadius(12)
          .onClick(() => {
            this.selected = idx;
            this.store.saveSelected(idx);
            if (this.connected) {
              this.status = '节点已切换，请重新连接';
            }
          })
        }, (item: ServerConfig, idx: number) => idx.toString() + '|' + item.name)
      }
      .width('92%')
      .layoutWeight(1)

      Row({ space: 8 }) {
        TextInput({ text: this.subUrl, placeholder: '订阅链接 (Base64)' })
          .layoutWeight(1)
          .fontSize(13)
          .height(40)
          .backgroundColor('#ffffff')
          .onChange((v: string) => {
            this.subUrl = v;
          })
        Button('更新订阅')
          .fontSize(13)
          .height(40)
          .enabled(!this.busy)
          .onClick(() => {
            this.doUpdateSubscription();
          })
      }
      .width('92%')
      .margin({ top: 8, bottom: 12 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#f2f2f7')
    .alignItems(HorizontalAlign.Center)
  }
}
