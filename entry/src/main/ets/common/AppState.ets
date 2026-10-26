import { vpnExtension } from '@kit.NetworkKit';
import { Want, common, ConfigurationConstant, bundleManager } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { buffer } from '@kit.ArkTS';
import testNapi from 'libentry.so';
import { ServerConfig } from '../model/ServerConfig';
import { SubGroup } from '../model/SubGroup';
import { RoutingOptions, GeoOptions, BackupPayload } from '../model/ProxyOptions';
import { parseSubscription } from './V2rayParser';
import { buildXrayConfig, buildTestConfig } from './XrayConf';
import { AppStore } from './AppStore';
import { SubscriptionFetcher } from './SubscriptionFetcher';
import { AppTheme } from './AppTheme';

const VPN_WANT: Want = {
  bundleName: 'com.xii.v2rayh',
  abilityName: 'MyVpnExtAbility'
};

const XRAY_LOG_PATH: string = '/data/storage/el2/base/haps/entry/files/xray_error.log';
const GEO_NAMES: string[] = ['geoip.dat', 'geosite.dat'];

const F_SUBS: string = 'subs.json';
const F_ACTIVE_GROUP: string = 'active_group.txt';
const F_ROUTING: string = 'routing.json';
const F_GEO: string = 'geo.json';
const F_BACKUP_SNAPSHOT: string = 'backup-latest.json';
const F_APPEARANCE: string = 'appearance.json';

const SOCKS_HOST: string = '127.0.0.1';
const SOCKS_PORT: number = 10809;

class IpEcho {
  ip: string = '';
  query: string = '';
}

class AppearanceOptions {
  darkMode: number = 0;
  accentIndex: number = 0;
}


function sleepMs(ms: number): Promise<void> {
  return new Promise<void>((resolve: (value: void) => void) => {
    setTimeout(() => {
      resolve();
    }, ms);
  });
}

@Observed
export class AppState {
  groups: SubGroup[] = [];
  activeGroup: number = 0;
  servers: ServerConfig[] = [];
  selected: number = 0;
  status: string = '';
  subUrl: string = '';
  busy: boolean = false;
  testing: boolean = false;
  connected: boolean = false;
  pings: number[] = [];
  downloadTesting: boolean = false;
  downloadBps: number = 0;
  downloadNodeKey: string = '';
  downloadError: string = '';
  coreVersion: string = '';
  appVersion: string = '0.2.0';
  exitIp: string = '';
  ipBusy: boolean = false;
  ipError: string = '';

  routeBypassCn: boolean = true;
  routeBlockAds: boolean = true;
  routeStrategy: string = 'IPIfNonMatch';
  routeDirectDomains: string[] = [];
  routeProxyDomains: string[] = [];

  geoUrlGeosite: string = '';
  geoUrlGeoip: string = '';
  geoUpdatedAt: number = 0;
  geositeSize: number = 0;
  geoipSize: number = 0;
  geositeAt: number = 0;
  geoipAt: number = 0;

  private store: AppStore = new AppStore();
  private ctx: common.Context | undefined = undefined;

  darkMode: number = 0;
  accentIndex: number = 0;
  systemDark: boolean = false;

  init(ctx: common.Context): void {
    this.ctx = ctx;
    this.store.init(ctx.filesDir);
    this.systemDark = AppStorage.get<boolean>('systemDarkFlag') === true;
    this.loadGroups();
    this.loadSettings();
    this.loadAppearance();
    this.ensureGeoFiles(ctx);
    this.refreshGeoSize();
    this.coreVersion = testNapi.getCoreVersion();
    try {
      this.appVersion = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT).versionName;
    } catch (e) {
      console.error('read versionName failed: ' + JSON.stringify(e));
    }
  }

  isDark(): boolean {
    return this.darkMode === 2 || (this.darkMode === 0 && this.systemDark);
  }

  private applyAppearance(): void {
    AppTheme.applyAppearance(this.isDark(), this.accentIndex);
    let rev = AppStorage.get<number>('themeRev');
    AppStorage.setOrCreate('themeRev', (rev === undefined ? 0 : rev) + 1);
  }

  private loadAppearance(): void {
    let text = this.store.readText(F_APPEARANCE);
    if (text.length > 0) {
      try {
        let a = JSON.parse(text) as AppearanceOptions;
        this.darkMode = a.darkMode;
        this.accentIndex = a.accentIndex;
      } catch (e) {
        console.error('parse appearance failed: ' + JSON.stringify(e));
      }
    }
    this.applyAppearance();
  }

  private saveAppearance(): void {
    let a = new AppearanceOptions();
    a.darkMode = this.darkMode;
    a.accentIndex = this.accentIndex;
    this.store.writeText(F_APPEARANCE, JSON.stringify(a));
  }

  setDarkMode(mode: number): void {
    this.darkMode = mode;
    this.applyAppearance();
    this.saveAppearance();
    if (this.ctx !== undefined) {
      let cm: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
      if (mode === 2) {
        cm = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      } else if (mode === 1) {
        cm = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
      }
      try {
        this.ctx.getApplicationContext().setColorMode(cm);
      } catch (e) {
        console.error('setColorMode failed: ' + JSON.stringify(e));
      }
    }
  }

  setAccent(idx: number): void {
    this.accentIndex = idx;
    this.applyAppearance();
    this.saveAppearance();
  }

  setSystemDark(v: boolean): void {
    if (this.systemDark === v || this.darkMode !== 0) {
      this.systemDark = v;
      return;
    }
    this.systemDark = v;
    this.applyAppearance();
  }

  darkModeText(): string {
    if (this.darkMode === 1) {
      return '浅色';
    }
    if (this.darkMode === 2) {
      return '深色';
    }
    return '跟随系统';
  }

  private ensureGeoFiles(ctx: common.Context): void {
    let geoDir = ctx.filesDir + '/geo';
    try {
      if (!fs.accessSync(geoDir)) {
        fs.mkdirSync(geoDir);
      }
    } catch (e) {
      console.error('mkdir geo failed: ' + JSON.stringify(e));
    }
    for (let i = 0; i < GEO_NAMES.length; i++) {
      let name = GEO_NAMES[i];
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

  private refreshGeoSize(): void {
    this.geositeSize = this.store.sizeOf('geo/geosite.dat');
    this.geoipSize = this.store.sizeOf('geo/geoip.dat');
    this.geositeAt = this.store.mtimeOf('geo/geosite.dat');
    this.geoipAt = this.store.mtimeOf('geo/geoip.dat');
  }

  // ---------- groups ----------

  private loadGroups(): void {
    let text = this.store.readText(F_SUBS);
    let loaded: SubGroup[] = [];
    if (text.length > 0) {
      try {
        loaded = JSON.parse(text) as SubGroup[];
      } catch (e) {
        console.error('parse subs failed: ' + JSON.stringify(e));
        loaded = [];
      }
    }
    if (loaded.length === 0) {
      let legacy: ServerConfig[] = this.store.loadServers();
      let legacyUrl: string = this.store.loadSubscriptionUrl();
      if (legacy.length > 0 || legacyUrl.length > 0) {
        let g = new SubGroup('legacy', '默认订阅', legacyUrl);
        g.nodes = legacy;
        g.updatedAt = 0;
        loaded.push(g);
        this.store.writeText(F_SUBS, JSON.stringify(loaded));
      }
    }
    this.groups = loaded;
    let idx = this.store.readText(F_ACTIVE_GROUP);
    let active = idx.length > 0 ? parseInt(idx, 10) : 0;
    if (isNaN(active) || active < 0 || active >= loaded.length) {
      active = 0;
    }
    this.activeGroup = active;
    if (loaded.length > 0) {
      let nodes: ServerConfig[] = loaded[active].nodes !== undefined ? loaded[active].nodes : [];
      this.servers = nodes;
      this.subUrl = loaded[active].url !== undefined ? loaded[active].url : '';
    }
    this.selected = this.store.loadSelected();
    if (this.selected >= this.servers.length) {
      this.selected = 0;
    }
  }

  private saveGroups(): void {
    this.store.writeText(F_SUBS, JSON.stringify(this.groups));
  }

  addGroup(name: string, url: string): void {
    let g = new SubGroup('g' + Date.now().toString(), name, url);
    this.groups = this.groups.concat([g]);
    this.saveGroups();
    this.selectGroup(this.groups.length - 1);
    this.status = '已创建分组: ' + name;
  }

  removeGroup(index: number): void {
    if (index < 0 || index >= this.groups.length) {
      return;
    }
    let next: SubGroup[] = [];
    for (let i = 0; i < this.groups.length; i++) {
      if (i !== index) {
        next.push(this.groups[i]);
      }
    }
    this.groups = next;
    this.saveGroups();
    let active = this.activeGroup;
    if (active >= next.length) {
      active = next.length > 0 ? next.length - 1 : 0;
    }
    this.activeGroup = active;
    this.store.writeText(F_ACTIVE_GROUP, active.toString());
    if (next.length > 0) {
      this.selectGroup(active);
    } else {
      this.servers = [];
      this.subUrl = '';
      this.selected = 0;
      this.pings = [];
    }
    this.status = '已删除分组';
  }

  selectGroup(index: number): void {
    if (index < 0 || index >= this.groups.length) {
      return;
    }
    this.activeGroup = index;
    this.store.writeText(F_ACTIVE_GROUP, index.toString());
    let g = this.groups[index];
    this.servers = g.nodes !== undefined ? g.nodes : [];
    this.subUrl = g.url !== undefined ? g.url : '';
    this.selected = 0;
    this.pings = [];
    this.store.saveSelected(0);
  }

  activeGroupName(): string {
    if (this.activeGroup < 0 || this.activeGroup >= this.groups.length) {
      return '无分组';
    }
    return this.groups[this.activeGroup].name;
  }

  // ---------- nodes ----------

  nodeName(): string {
    if (this.servers.length === 0 || this.selected >= this.servers.length) {
      return '未选择节点';
    }
    return this.servers[this.selected].name;
  }

  currentNode(): ServerConfig | undefined {
    if (this.servers.length === 0 || this.selected >= this.servers.length) {
      return undefined;
    }
    return this.servers[this.selected];
  }

  currentPingText(): string {
    if (this.selected >= this.pings.length) {
      return '--';
    }
    let p: number = this.pings[this.selected];
    if (p === -2) {
      return '测速中';
    }
    if (p < 0) {
      return '超时';
    }
    return p.toString() + ' ms';
  }

  pingText(idx: number): string {
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

  private nodeKey(idx: number): string {
    if (idx < 0 || idx >= this.servers.length) {
      return '';
    }
    let s: ServerConfig = this.servers[idx];
    return s.name + '|' + s.address + ':' + s.port.toString();
  }

  downloadMbps(): number {
    return this.downloadBps * 8 / 1000000;
  }

  downloadResultText(): string {
    if (this.downloadNodeKey.length === 0 || this.downloadNodeKey !== this.nodeKey(this.selected)) {
      return '';
    }
    if (this.downloadError.length > 0) {
      return this.downloadError;
    }
    if (this.downloadBps <= 0) {
      return '';
    }
    let mbs: number = this.downloadBps / 1024 / 1024;
    return '下载 ' + this.downloadMbps().toFixed(2) + ' Mbps · ' + mbs.toFixed(2) + ' MB/s';
  }

  selectServer(idx: number): void {
    if (idx < 0 || idx >= this.servers.length) {
      return;
    }
    if (idx === this.selected) {
      return;
    }
    this.selected = idx;
    this.store.saveSelected(idx);
    if (this.connected) {
      this.switchNode();
    }
  }

  addServers(list: ServerConfig[], groupName: string): number {
    if (list.length === 0) {
      return 0;
    }
    let target = -1;
    for (let i = 0; i < this.groups.length; i++) {
      if (this.groups[i].name === groupName) {
        target = i;
        break;
      }
    }
    if (target < 0) {
      this.addGroup(groupName, '');
      target = this.groups.length - 1;
    }
    let base: ServerConfig[] = this.groups[target].nodes !== undefined ? this.groups[target].nodes : [];
    let merged: ServerConfig[] = base.concat(list);
    let next: SubGroup[] = [];
    for (let i = 0; i < this.groups.length; i++) {
      let g = this.groups[i];
      if (i === target) {
        let copy = new SubGroup(g.id, g.name, g.url);
        copy.nodes = merged;
        copy.updatedAt = g.updatedAt;
        next.push(copy);
      } else {
        next.push(g);
      }
    }
    this.groups = next;
    this.saveGroups();
    this.selectGroup(target);
    this.status = '已导入 ' + list.length.toString() + ' 个节点到「' + groupName + '」';
    return list.length;
  }

  private applyServerConfig(): void {
    if (this.selected >= this.servers.length) {
      this.selected = 0;
    }
    let server = this.servers[this.selected];
    let cfg = buildXrayConfig(server, XRAY_LOG_PATH, this.routingOptions());
    this.store.saveXrayConfig(cfg);
  }

  private async startVpnWithRetry(times: number): Promise<boolean> {
    for (let i = 0; i < times; i++) {
      try {
        await vpnExtension.startVpnExtensionAbility(VPN_WANT);
        return true;
      } catch (e) {
        console.error('startVpn attempt ' + i.toString() + ' failed: ' + JSON.stringify(e));
        await sleepMs(700);
      }
    }
    return false;
  }

  async switchNode(): Promise<void> {
    if (this.servers.length === 0) {
      return;
    }
    this.applyServerConfig();
    this.exitIp = '';
    this.ipError = '';
    this.ipBusy = true;
    this.status = '正在切换到: ' + this.nodeName();
    try {
      await vpnExtension.stopVpnExtensionAbility(VPN_WANT);
    } catch (e) {
      console.error('stopVpn during switch failed: ' + JSON.stringify(e));
    }
    await sleepMs(600);
    let ok = await this.startVpnWithRetry(3);
    if (ok) {
      this.connected = true;
      this.status = '';
      this.refreshExitIp();
    } else {
      this.connected = false;
      this.ipBusy = false;
      this.status = '切换节点失败，请重试';
    }
  }

  // ---------- subscription ----------

  updateSubscription(): void {
    let url = this.subUrl.trim();
    if (url.length === 0) {
      this.status = '请输入订阅链接';
      return;
    }
    if (this.groups.length === 0) {
      this.addGroup('默认订阅', url);
    }
    this.busy = true;
    this.status = '正在拉取订阅...';
    let target = this.activeGroup;
    SubscriptionFetcher.fetchText(url).then((content: string) => {
      let list = parseSubscription(content);
      if (list.length === 0) {
        this.status = '拉取失败: ' + content.length.toString() + 'B, err=' + SubscriptionFetcher.lastError;
        this.busy = false;
        return;
      }
      let next: SubGroup[] = [];
      for (let i = 0; i < this.groups.length; i++) {
        let g = this.groups[i];
        if (i === target) {
          let copy = new SubGroup(g.id, g.name, url);
          copy.nodes = list;
          copy.updatedAt = Date.now();
          next.push(copy);
        } else {
          next.push(g);
        }
      }
      this.groups = next;
      this.servers = list;
      this.selected = 0;
      this.pings = [];
      this.subUrl = url;
      this.saveGroups();
      this.store.saveSubscriptionUrl(url);
      this.store.saveSelected(0);
      this.status = '订阅更新成功，共 ' + list.length.toString() + ' 个节点';
      this.busy = false;
    });
  }

  async testAll(): Promise<void> {
    if (this.servers.length === 0 || this.busy || this.testing || this.downloadTesting) {
      return;
    }
    let init: number[] = [];
    for (let i = 0; i < this.servers.length; i++) {
      init.push(-2);
    }
    this.pings = init;
    this.busy = true;
    this.testing = true;
    this.status = '正在测速(经代理实测延迟)...';
    try {
      for (let i = 0; i < this.servers.length; i++) {
        let srv: ServerConfig = this.servers[i];
        let ms: number = -1;
        try {
          let cfg: string = buildTestConfig(srv);
          ms = await testNapi.measureDelay(cfg, 'http://www.gstatic.com/generate_204');
        } catch (e) {
          ms = -1;
        }
        let copy: number[] = [];
        for (let j = 0; j < this.pings.length; j++) {
          copy.push(this.pings[j]);
        }
        copy[i] = ms;
        this.pings = copy;
        this.status = '正在测速 ' + (i + 1).toString() + '/' + this.servers.length.toString() + '...';
      }
      this.status = '测速完成';
    } finally {
      this.busy = false;
      this.testing = false;
    }
  }

  async testDownload(): Promise<void> {
    if (this.servers.length === 0 || this.busy || this.testing || this.downloadTesting) {
      return;
    }
    let srv: ServerConfig | undefined = this.currentNode();
    if (srv === undefined) {
      return;
    }
    this.downloadTesting = true;
    this.downloadBps = 0;
    this.downloadError = '';
    this.downloadNodeKey = this.nodeKey(this.selected);
    this.busy = true;
    this.status = '正在下载测速: ' + srv.name;
    try {
      let cfg: string = buildTestConfig(srv);
      let bps: number = -1;
      let urls: string[] = [
        'http://speed.cloudflare.com/__down?bytes=20000000',
        'http://cachefly.cachefly.net/10mb.test'
      ];
      for (let i = 0; i < urls.length; i++) {
        try {
          bps = await testNapi.measureDownload(cfg, urls[i], 20 * 1024 * 1024);
        } catch (e) {
          bps = -1;
        }
        if (bps > 0) {
          break;
        }
      }
      if (bps > 0) {
        this.downloadBps = bps;
        this.status = '下载测速完成';
      } else {
        this.downloadError = '下载测速失败，请检查节点';
        this.status = this.downloadError;
      }
    } finally {
      this.downloadTesting = false;
      this.busy = false;
    }
  }

  // ---------- connection ----------

  private routingOptions(): RoutingOptions {
    let r = new RoutingOptions();
    r.bypassCn = this.routeBypassCn;
    r.blockAds = this.routeBlockAds;
    r.domainStrategy = this.routeStrategy;
    r.directDomains = this.routeDirectDomains;
    r.proxyDomains = this.routeProxyDomains;
    return r;
  }

  private geoOptions(): GeoOptions {
    let g = new GeoOptions();
    g.geositeUrl = this.geoUrlGeosite;
    g.geoipUrl = this.geoUrlGeoip;
    g.updatedAt = this.geoUpdatedAt;
    return g;
  }

  async connect(): Promise<void> {
    if (this.servers.length === 0) {
      this.status = '请先在配置页添加订阅';
      return;
    }
    this.applyServerConfig();
    this.exitIp = '';
    this.ipError = '';
    this.status = '正在连接: ' + this.nodeName();
    let ok = await this.startVpnWithRetry(2);
    if (ok) {
      this.connected = true;
      this.status = '';
      this.refreshExitIp();
    } else {
      this.connected = false;
      this.ipBusy = false;
      this.status = '连接失败，请重试';
    }
  }

  disconnect(): void {
    this.exitIp = '';
    this.ipError = '';
    this.ipBusy = false;
    vpnExtension.stopVpnExtensionAbility(VPN_WANT).then(() => {
      this.connected = false;
      this.status = '已断开';
    }).catch((err: BusinessError) => {
      this.status = '断开失败: ' + JSON.stringify(err);
    });
  }

  private parseIp(body: string): string {
    if (body.length === 0) {
      return '';
    }
    try {
      let o = JSON.parse(body) as IpEcho;
      if (o.ip !== undefined && o.ip.length > 0) {
        return o.ip.trim();
      }
      if (o.query !== undefined && o.query.length > 0) {
        return o.query.trim();
      }
      return '';
    } catch (e) {
      return '';
    }
  }

  async refreshExitIp(): Promise<void> {
    this.ipBusy = true;
    this.exitIp = '';
    this.ipError = '';
    let urls: string[] = ['http://api.ipify.org?format=json', 'http://ip-api.com/json/?fields=query'];
    for (let attempt = 0; attempt < 6; attempt++) {
      await sleepMs(1200);
      for (let i = 0; i < urls.length; i++) {
        let body = await SubscriptionFetcher.fetchThroughProxy(urls[i], SOCKS_HOST, SOCKS_PORT);
        let ip = this.parseIp(body);
        if (ip.length > 0) {
          this.exitIp = ip;
          this.ipBusy = false;
          return;
        }
        this.ipError = SubscriptionFetcher.lastError;
        console.error('exit ip query failed: ' + urls[i] + ' ' + this.ipError);
      }
    }
    this.ipBusy = false;
    if (this.ipError.length === 0) {
      this.ipError = '代理未返回结果';
    }
  }

  // ---------- routing settings ----------

  private saveRouting(): void {
    let r = this.routingOptions();
    this.store.writeText(F_ROUTING, JSON.stringify(r));
  }

  setBypassCn(v: boolean): void {
    this.routeBypassCn = v;
    this.saveRouting();
  }

  setBlockAds(v: boolean): void {
    this.routeBlockAds = v;
    this.saveRouting();
  }

  setDomainStrategy(v: string): void {
    this.routeStrategy = v;
    this.saveRouting();
  }

  addRouteDomain(proxySide: boolean, domain: string): boolean {
    let d = domain.trim();
    if (d.length === 0) {
      return false;
    }
    if (proxySide) {
      if (this.routeProxyDomains.indexOf(d) >= 0) {
        return false;
      }
      this.routeProxyDomains = this.routeProxyDomains.concat([d]);
    } else {
      if (this.routeDirectDomains.indexOf(d) >= 0) {
        return false;
      }
      this.routeDirectDomains = this.routeDirectDomains.concat([d]);
    }
    this.saveRouting();
    return true;
  }

  removeRouteDomain(proxySide: boolean, domain: string): void {
    let next: string[] = [];
    let src = proxySide ? this.routeProxyDomains : this.routeDirectDomains;
    for (let i = 0; i < src.length; i++) {
      if (src[i] !== domain) {
        next.push(src[i]);
      }
    }
    if (proxySide) {
      this.routeProxyDomains = next;
    } else {
      this.routeDirectDomains = next;
    }
    this.saveRouting();
  }

  // ---------- geo resources ----------

  private saveGeo(): void {
    let g = this.geoOptions();
    this.store.writeText(F_GEO, JSON.stringify(g));
  }

  setGeoUrls(geosite: string, geoip: string): void {
    this.geoUrlGeosite = geosite.trim();
    this.geoUrlGeoip = geoip.trim();
    this.saveGeo();
  }

  async updateGeoFiles(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.status = '正在下载资源文件...';
    let dir = this.store.dirPath() + '/geo';
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir);
      }
    } catch (e) {
      this.status = '创建资源目录失败';
      this.busy = false;
      return;
    }
    let okSite = false;
    let okIp = false;
    if (this.geoUrlGeosite.length > 0) {
      let data = await SubscriptionFetcher.fetchBytes(this.geoUrlGeosite);
      if (data !== undefined) {
        okSite = this.store.writeBytesTo(dir + '/geosite.dat', data);
      }
    }
    if (this.geoUrlGeoip.length > 0) {
      let data = await SubscriptionFetcher.fetchBytes(this.geoUrlGeoip);
      if (data !== undefined) {
        okIp = this.store.writeBytesTo(dir + '/geoip.dat', data);
      }
    }
    this.refreshGeoSize();
    if (okSite || okIp) {
      this.geoUpdatedAt = Date.now();
      this.saveGeo();
      this.status = '资源文件已更新';
    } else {
      this.status = '资源更新失败: ' + SubscriptionFetcher.lastError;
    }
    this.busy = false;
  }

  async importGeoFile(isGeosite: boolean): Promise<void> {
    if (this.ctx === undefined) {
      this.status = '上下文未就绪';
      return;
    }
    let name = isGeosite ? 'geosite.dat' : 'geoip.dat';
    try {
      let p = new picker.DocumentViewPicker(this.ctx);
      let options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['Geo 文件|.dat'];
      let uris = await p.select(options);
      if (uris.length === 0) {
        this.status = '已取消导入';
        return;
      }
      let dir = this.store.dirPath() + '/geo';
      try {
        if (!fs.accessSync(dir)) {
          fs.mkdirSync(dir);
        }
      } catch (e) {
        this.status = '创建资源目录失败';
        return;
      }
      let src = fs.openSync(uris[0], fs.OpenMode.READ_ONLY);
      let out = fs.openSync(dir + '/' + name, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      let buf = new ArrayBuffer(65536);
      let total = 0;
      while (true) {
        let n = fs.readSync(src.fd, buf);
        if (n <= 0) {
          break;
        }
        fs.writeSync(out.fd, buf.slice(0, n));
        total += n;
      }
      fs.closeSync(src);
      fs.closeSync(out);
      this.refreshGeoSize();
      this.geoUpdatedAt = Date.now();
      this.saveGeo();
      this.status = name + ' 已导入 ' + this.sizeText(total);
    } catch (e) {
      let err = e as BusinessError;
      this.status = '导入失败: ' + err.code.toString();
    }
  }

  // ---------- settings io ----------

  private loadSettings(): void {
    let rText = this.store.readText(F_ROUTING);
    if (rText.length > 0) {
      try {
        let r = JSON.parse(rText) as RoutingOptions;
        this.routeBypassCn = r.bypassCn;
        this.routeBlockAds = r.blockAds;
        this.routeStrategy = r.domainStrategy;
        this.routeDirectDomains = r.directDomains !== undefined ? r.directDomains : [];
        this.routeProxyDomains = r.proxyDomains !== undefined ? r.proxyDomains : [];
      } catch (e) {
        console.error('parse routing failed: ' + JSON.stringify(e));
      }
    }
    let gText = this.store.readText(F_GEO);
    if (gText.length > 0) {
      try {
        let g = JSON.parse(gText) as GeoOptions;
        this.geoUrlGeosite = g.geositeUrl;
        this.geoUrlGeoip = g.geoipUrl;
        this.geoUpdatedAt = g.updatedAt;
      } catch (e) {
        console.error('parse geo failed: ' + JSON.stringify(e));
      }
    }
    if (this.geoUrlGeosite.length === 0 || this.geoUrlGeoip.length === 0) {
      let def = new GeoOptions();
      if (this.geoUrlGeosite.length === 0) {
        this.geoUrlGeosite = def.geositeUrl;
      }
      if (this.geoUrlGeoip.length === 0) {
        this.geoUrlGeoip = def.geoipUrl;
      }
    }
  }

  // ---------- backup / restore ----------

  private buildBackup(): BackupPayload {
    let b = new BackupPayload();
    b.version = 1;
    b.createdAt = Date.now();
    b.activeGroup = this.activeGroup;
    b.selected = this.selected;
    b.groups = this.groups;
    b.routing = this.routingOptions();
    b.geo = this.geoOptions();
    return b;
  }

  private backupFileName(): string {
    return 'v2rayh-backup-' + this.timestamp() + '.json';
  }

  private writeBackupSnapshot(payload: string): void {
    this.store.writeText(F_BACKUP_SNAPSHOT, payload);
  }

  hasLocalSnapshot(): boolean {
    return this.store.sizeOf(F_BACKUP_SNAPSHOT) > 0;
  }

  async exportBackup(): Promise<void> {
    if (this.ctx === undefined) {
      this.status = '上下文未就绪';
      return;
    }
    let payload = JSON.stringify(this.buildBackup());
    this.writeBackupSnapshot(payload);
    try {
      let p = new picker.DocumentViewPicker(this.ctx);
      let options = new picker.DocumentSaveOptions();
      options.newFileNames = [this.backupFileName()];
      let uris = await p.save(options);
      if (uris.length === 0) {
        this.status = '已取消导出，已保存本地快照';
        return;
      }
      let f = fs.openSync(uris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(f.fd, payload);
      fs.closeSync(f);
      this.status = '备份已导出（含本地快照）';
    } catch (e) {
      let err = e as BusinessError;
      this.status = '导出失败: ' + err.code.toString() + ' （本地快照已保存）';
    }
  }

  private readTextFromFile(uri: string): string {
    let f = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    let size = 0;
    try {
      size = fs.statSync(f.fd).size;
    } catch (e) {
      size = 0;
    }
    if (size <= 0) {
      fs.closeSync(f);
      return '';
    }
    let buf = new ArrayBuffer(size);
    let read = fs.readSync(f.fd, buf);
    fs.closeSync(f);
    if (read <= 0) {
      return '';
    }
    let text = buffer.from(buf.slice(0, read)).toString('utf-8');
    if (text.length > 0 && text.charCodeAt(0) === 0xFEFF) {
      text = text.substring(1);
    }
    return text;
  }

  async importBackup(): Promise<void> {
    if (this.ctx === undefined) {
      this.status = '上下文未就绪';
      return;
    }
    try {
      let p = new picker.DocumentViewPicker(this.ctx);
      let options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['备份文件|.json'];
      let uris = await p.select(options);
      if (uris.length === 0) {
        this.status = '已取消还原';
        return;
      }
      let text = this.readTextFromFile(uris[0]);
      if (text.length === 0) {
        this.status = '读取失败：文件为空或无访问权限';
        return;
      }
      this.applyBackupText(text);
    } catch (e) {
      let err = e as BusinessError;
      this.status = '还原失败: ' + err.code.toString();
    }
  }

  restoreSnapshot(): void {
    let text = this.store.readText(F_BACKUP_SNAPSHOT);
    if (text.length === 0) {
      this.status = '本地没有可用快照';
      return;
    }
    this.applyBackupText(text);
  }

  private applyBackupText(text: string): void {
    try {
      let payload = JSON.parse(text) as BackupPayload;
      this.applyBackup(payload);
    } catch (e) {
      this.status = '文件格式不正确，不是有效的 v2rayH 备份';
    }
  }

  private applyBackup(b: BackupPayload): void {
    let groups: SubGroup[] = b.groups !== undefined ? b.groups : [];
    this.groups = groups;
    this.saveGroups();
    let active = b.activeGroup;
    if (isNaN(active) || active < 0 || active >= groups.length) {
      active = 0;
    }
    this.activeGroup = active;
    this.store.writeText(F_ACTIVE_GROUP, active.toString());
    if (groups.length > 0) {
      let g = groups[active];
      this.servers = g.nodes !== undefined ? g.nodes : [];
      this.subUrl = g.url !== undefined ? g.url : '';
    } else {
      this.servers = [];
      this.subUrl = '';
    }
    this.selected = b.selected >= 0 && b.selected < this.servers.length ? b.selected : 0;
    this.store.saveSelected(this.selected);
    this.pings = [];
    if (b.routing !== undefined) {
      this.routeBypassCn = b.routing.bypassCn;
      this.routeBlockAds = b.routing.blockAds;
      this.routeStrategy = b.routing.domainStrategy;
      this.routeDirectDomains = b.routing.directDomains !== undefined ? b.routing.directDomains : [];
      this.routeProxyDomains = b.routing.proxyDomains !== undefined ? b.routing.proxyDomains : [];
      this.saveRouting();
    }
    if (b.geo !== undefined) {
      if (b.geo.geositeUrl.length > 0) {
        this.geoUrlGeosite = b.geo.geositeUrl;
      }
      if (b.geo.geoipUrl.length > 0) {
        this.geoUrlGeoip = b.geo.geoipUrl;
      }
      this.geoUpdatedAt = b.geo.updatedAt;
      this.saveGeo();
    }
    this.status = '还原完成，共 ' + groups.length.toString() + ' 个分组';
  }

  clearAll(): void {
    this.groups = [];
    this.servers = [];
    this.selected = 0;
    this.pings = [];
    this.subUrl = '';
    this.activeGroup = 0;
    this.saveGroups();
    this.store.saveSelected(0);
    this.store.saveSubscriptionUrl('');
    this.status = '已清空本地节点与订阅';
  }

  // ---------- misc ----------

  timestamp(): string {
    let d = new Date();
    let m = d.getMonth() + 1;
    let day = d.getDate();
    let hh = d.getHours();
    let mm = d.getMinutes();
    return d.getFullYear().toString() + this.pad2(m) + this.pad2(day) + '-' + this.pad2(hh) + this.pad2(mm);
  }

  private pad2(v: number): string {
    return v < 10 ? '0' + v.toString() : v.toString();
  }

  formatTime(ts: number): string {
    if (ts <= 0) {
      return '未更新';
    }
    let d = new Date(ts);
    return (d.getMonth() + 1).toString() + '/' + d.getDate().toString() + ' '
      + this.pad2(d.getHours()) + ':' + this.pad2(d.getMinutes());
  }

  sizeText(bytes: number): string {
    if (bytes <= 0) {
      return '缺失';
    }
    if (bytes < 1024 * 1024) {
      return (Math.floor(bytes / 1024)).toString() + ' KB';
    }
    return (bytes / 1024 / 1024).toFixed(1) + ' MB';
  }

  apiLevel(): string {
    return '26.0.0';
  }
}
