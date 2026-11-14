import { vpnExtension, statistics } from '@kit.NetworkKit';
import { Want, common, ConfigurationConstant, bundleManager, wantAgent, WantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { buffer } from '@kit.ArkTS';
import testNapi from 'libentry.so';
import { ServerConfig } from '../model/ServerConfig';
import { SubGroup, SubUserinfo } from '../model/SubGroup';
import { RoutingOptions, GeoOptions, BackupPayload } from '../model/ProxyOptions';
import { parseSubscription } from './V2rayParser';
import { buildVpnConfigPair, buildTestConfigPair } from './XrayConf';
import { usesSingboxKernel, TEST_SINGBOX_PORT } from './SingboxConf';
import { AppStore } from './AppStore';
import { SubscriptionFetcher } from './SubscriptionFetcher';
import { AppTheme } from './AppTheme';
import { AppContextHolder } from './AppContextHolder';

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
const F_PREFS: string = 'prefs.json';
const F_PERAPP: string = 'perapp.json';
const F_VPN_LOG: string = 'vpn.log';
const F_XRAY_LOG: string = 'xray_error.log';
const F_MULTI: string = 'multi_select.json';
const F_SINGBOX_CONFIG: string = 'singbox_config.json';

const PING_CONCURRENCY: number = 16;
const CHAINED_PING_TIMEOUT_MS: number = 10000;

const FAILOVER_CHECK_MS: number = 45000;
const FAILOVER_FAIL_LIMIT: number = 2;
const FAILOVER_COOLDOWN_MS: number = 120000;
const FAILOVER_PROBE_TIMEOUT_MS: number = 15000;
const LOG_TAIL_LINES: number = 400;

const VPN_WATCHDOG_INTERVAL_MS: number = 10000;
const VPN_HEARTBEAT_STALE_MS: number = 35000;
const VPN_START_GRACE_MS: number = 30000;

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

class PrefsOptions {
  autoUpdateSubs: boolean = false;
  autoConnect: boolean = false;
  failover: boolean = false;
  keepAlive: boolean = false;
  speedTestMB: number = 20;
  speedTestConcurrency: number = 3;
}

class PerAppOptions {
  mode: string = 'all';
  bundles: string[] = [];
}

class PingSortEntry {
  rank: number = 0;
  ping: number = 0;
  oldIdx: number = 0;
  server: ServerConfig = new ServerConfig();

  constructor(rank: number, ping: number, oldIdx: number, server: ServerConfig) {
    this.rank = rank;
    this.ping = ping;
    this.oldIdx = oldIdx;
    this.server = server;
  }
}

class SpeedSortEntry {
  rank: number = 0;
  speed: number = 0;
  oldIdx: number = 0;
  server: ServerConfig = new ServerConfig();

  constructor(rank: number, speed: number, oldIdx: number, server: ServerConfig) {
    this.rank = rank;
    this.speed = speed;
    this.oldIdx = oldIdx;
    this.server = server;
  }
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
  multiKeys: string[] = [];
  // 系统返回键导航深度（由各 Tab 同步，Index.onBackPress 读取）
  homeDepth: number = 0;
  configDepth: number = 0;
  settingsDepth: number = 0;
  status: string = '';
  subUrl: string = '';
  busy: boolean = false;
  testing: boolean = false;
  connected: boolean = false;
  pings: number[] = [];
  speeds: number[] = [];
  downloadTesting: boolean = false;
  sortPromptHandler: ((mode: string) => void) | null = null;
  coreVersion: string = '';
  singboxVersion: string = '';
  appVersion: string = '0.3.0';
  exitIp: string = '';
  ipBusy: boolean = false;
  ipError: string = '';
  connectedAt: number = 0;
  sessionRx: number = 0;
  sessionTx: number = 0;
  autoUpdateSubs: boolean = false;
  autoConnect: boolean = false;
  failover: boolean = false;
  // 下载测速单节点数据量上限（MB），可自定义
  speedTestMB: number = 20;
  // 下载测速同时测试的节点数，节点多时成倍缩短总耗时
  speedTestConcurrency: number = 3;
  // 后台保活：连接期间申请 DATA_TRANSFER 长时任务，防止退后台后进程被冻结
  keepAlive: boolean = false;
  private keepAliveTaskOn: boolean = false;
  private failoverTimerId: number = -1;
  private failoverFails: number = 0;
  private failoverCooldownUntil: number = 0;
  private failoverSwitchCount: number = 0;
  private failoverChecking: boolean = false;
  private vpnWatchdogTimerId: number = -1;
  private vpnWatchdogMisses: number = 0;
  private vpnWatchdogBusy: boolean = false;
  private vpnIntentionalRestart: boolean = false;
  private vpnLastStartAt: number = 0;
  private statsBaseRx: number = -1;
  private statsBaseTx: number = -1;
  private appUid: number = -1;

  routeBypassCn: boolean = true;
  routeBlockAds: boolean = true;
  routeStrategy: string = 'IPIfNonMatch';
  routeDirectDomains: string[] = [];
  routeProxyDomains: string[] = [];
  perAppMode: string = 'all';
  perAppBundles: string[] = [];

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
    this.loadPrefs();
    this.loadMulti();
    this.loadPerApp();
    this.loadAppearance();
    this.ensureGeoFiles(ctx);
    this.refreshGeoSize();
    this.coreVersion = testNapi.getCoreVersion();
    this.singboxVersion = testNapi.getSingboxVersion();
    try {
      this.appVersion = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT).versionName;
    } catch (e) {
      console.error('read versionName failed: ' + JSON.stringify(e));
    }
    if (this.ctx !== undefined) {
      try {
        this.appUid = this.ctx.applicationInfo.uid;
      } catch (e) {
        console.error('read app uid failed: ' + JSON.stringify(e));
      }
    }
  }

  private loadPrefs(): void {
    let text = this.store.readText(F_PREFS);
    if (text.length > 0) {
      try {
        let p = JSON.parse(text) as PrefsOptions;
        this.autoUpdateSubs = p.autoUpdateSubs === true;
        this.autoConnect = p.autoConnect === true;
        this.failover = p.failover === true;
        this.keepAlive = p.keepAlive === true;
        this.speedTestMB = this.normalizeSpeedTestMB(p.speedTestMB);
        this.speedTestConcurrency = this.normalizeSpeedTestConcurrency(p.speedTestConcurrency);
      } catch (e) {
        console.error('parse prefs failed: ' + JSON.stringify(e));
      }
    }
  }

  private savePrefs(): void {
    let p = new PrefsOptions();
    p.autoUpdateSubs = this.autoUpdateSubs;
    p.autoConnect = this.autoConnect;
    p.failover = this.failover;
    p.keepAlive = this.keepAlive;
    p.speedTestMB = this.speedTestMB;
    p.speedTestConcurrency = this.speedTestConcurrency;
    this.store.writeText(F_PREFS, JSON.stringify(p));
  }

  setAutoUpdateSubs(v: boolean): void {
    this.autoUpdateSubs = v;
    this.savePrefs();
  }

  setAutoConnect(v: boolean): void {
    this.autoConnect = v;
    this.savePrefs();
  }

  setFailover(v: boolean): void {
    this.failover = v;
    this.savePrefs();
    if (v) {
      this.startFailoverMonitor();
    } else {
      this.stopFailoverMonitor();
    }
  }

  setKeepAlive(v: boolean): void {
    this.keepAlive = v;
    this.savePrefs();
    if (v) {
      this.startKeepAliveTask();
    } else {
      this.stopKeepAliveTask();
    }
  }

  // ---------- keep alive ----------

  private async startKeepAliveTask(): Promise<void> {
    if (!this.keepAlive || !this.connected || this.keepAliveTaskOn) {
      return;
    }
    let ctx = AppContextHolder.get();
    if (ctx === undefined) {
      return;
    }
    let wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [{
        bundleName: 'com.xii.v2rayh',
        abilityName: 'EntryAbility'
      }],
      operationType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0
    };
    try {
      let agent: WantAgent = await wantAgent.getWantAgent(wantAgentInfo);
      await backgroundTaskManager.startBackgroundRunning(ctx,
        backgroundTaskManager.BackgroundMode.DATA_TRANSFER, agent);
      this.keepAliveTaskOn = true;
      this.appendRuntimeLog('[keepalive] 后台保活长时任务已开启');
    } catch (e) {
      console.error('start keep-alive task failed: ' + JSON.stringify(e));
    }
  }

  private async stopKeepAliveTask(): Promise<void> {
    if (!this.keepAliveTaskOn) {
      return;
    }
    this.keepAliveTaskOn = false;
    let ctx = AppContextHolder.get();
    if (ctx === undefined) {
      return;
    }
    try {
      await backgroundTaskManager.stopBackgroundRunning(ctx);
      this.appendRuntimeLog('[keepalive] 后台保活长时任务已停止');
    } catch (e) {
      console.error('stop keep-alive task failed: ' + JSON.stringify(e));
    }
  }

  // ---------- vpn watchdog ----------

  private vpnExtensionHealthy(): boolean {
    let ctx = AppContextHolder.get();
    if (ctx === undefined) {
      return true;
    }
    try {
      let path = ctx.filesDir + '/heartbeat.txt';
      if (!fs.accessSync(path)) {
        return false;
      }
      let stat = fs.statSync(path);
      if (stat.size <= 0) {
        return false;
      }
      let f = fs.openSync(path, fs.OpenMode.READ_ONLY);
      let buf = new ArrayBuffer(stat.size);
      fs.readSync(f.fd, buf);
      fs.closeSync(f);
      let ts: number = Number(buffer.from(buf).toString('utf-8').trim());
      if (isNaN(ts) || ts <= 0) {
        return false;
      }
      return Date.now() - ts < VPN_HEARTBEAT_STALE_MS;
    } catch (e) {
      console.error('vpnExtensionHealthy check failed: ' + JSON.stringify(e));
      return true;
    }
  }

  private startVpnWatchdog(): void {
    if (!this.connected) {
      return;
    }
    if (this.vpnWatchdogTimerId >= 0) {
      return;
    }
    this.vpnWatchdogMisses = 0;
    this.vpnWatchdogTimerId = setInterval(() => {
      this.checkVpnAlive();
    }, VPN_WATCHDOG_INTERVAL_MS);
  }

  private stopVpnWatchdog(): void {
    if (this.vpnWatchdogTimerId >= 0) {
      clearInterval(this.vpnWatchdogTimerId);
      this.vpnWatchdogTimerId = -1;
    }
    this.vpnWatchdogMisses = 0;
  }

  private async checkVpnAlive(): Promise<void> {
    if (!this.connected || this.vpnIntentionalRestart || this.vpnWatchdogBusy) {
      return;
    }
    if (Date.now() - this.vpnLastStartAt < VPN_START_GRACE_MS) {
      return;
    }
    let healthy: boolean = this.vpnExtensionHealthy();
    if (healthy) {
      this.vpnWatchdogMisses = 0;
      return;
    }
    this.vpnWatchdogMisses++;
    if (this.vpnWatchdogMisses < 2) {
      return;
    }
    this.vpnWatchdogMisses = 0;
    await this.recoverVpnExtension();
  }

  private async recoverVpnExtension(): Promise<void> {
    if (!this.connected || this.vpnIntentionalRestart || this.vpnWatchdogBusy) {
      return;
    }
    this.vpnWatchdogBusy = true;
    this.appendRuntimeLog('[vpn] 检测到 VPN 扩展心跳超时，正在自动重启');
    this.status = 'VPN 扩展无响应，正在自动重启...';
    try {
      await vpnExtension.stopVpnExtensionAbility(VPN_WANT);
    } catch (e) {
      console.error('stopVpn during watchdog recover failed: ' + JSON.stringify(e));
    }
    await sleepMs(500);
    let ok = await this.startVpnWithRetry(3);
    if (ok) {
      this.vpnLastStartAt = Date.now();
      this.status = '';
      this.refreshExitIp();
      this.startKeepAliveTask();
      this.beginTrafficSession();
      this.appendRuntimeLog('[vpn] VPN 扩展自动重启成功');
    } else {
      this.connected = false;
      this.ipBusy = false;
      this.endTrafficSession();
      this.stopFailoverMonitor();
      this.stopKeepAliveTask();
      this.stopVpnWatchdog();
      this.status = 'VPN 已被系统终止，自动重启失败，请手动重连';
      this.appendRuntimeLog('[vpn] VPN 扩展自动重启失败');
    }
    this.vpnWatchdogBusy = false;
  }

  async onAppStartVpnCheck(): Promise<void> {
    if (this.connected) {
      return;
    }
    if (this.vpnExtensionHealthy()) {
      this.appendRuntimeLog('[vpn] 检测到 VPN 扩展仍在运行，恢复连接状态');
      this.connected = true;
      this.vpnLastStartAt = Date.now();
      this.status = '';
      this.startFailoverMonitor();
      this.startVpnWatchdog();
      this.beginTrafficSession();
      this.startKeepAliveTask();
      this.refreshExitIp();
      return;
    }
    this.maybeAutoConnect();
  }

  private normalizeSpeedTestMB(v: number): number {
    if (typeof v !== 'number' || isNaN(v) || v < 10) {
      return 20;
    }
    if (v > 500) {
      return 500;
    }
    return Math.round(v);
  }

  setSpeedTestMB(mb: number): void {
    this.speedTestMB = this.normalizeSpeedTestMB(mb);
    this.savePrefs();
  }

  private normalizeSpeedTestConcurrency(v: number): number {
    if (typeof v !== 'number' || isNaN(v) || v < 1) {
      return 3;
    }
    if (v > 6) {
      return 6;
    }
    return Math.round(v);
  }

  setSpeedTestConcurrency(n: number): void {
    this.speedTestConcurrency = this.normalizeSpeedTestConcurrency(n);
    this.savePrefs();
  }

  private loadMulti(): void {
    this.multiKeys = [];
    let text = this.store.readText(F_MULTI);
    if (text.length > 0) {
      try {
        this.multiKeys = JSON.parse(text) as string[];
      } catch (e) {
        this.multiKeys = [];
      }
    }
  }

  private saveMulti(): void {
    this.store.writeText(F_MULTI, JSON.stringify(this.multiKeys));
  }

  private loadPerApp(): void {
    let text = this.store.readText(F_PERAPP);
    if (text.length > 0) {
      try {
        let p = JSON.parse(text) as PerAppOptions;
        this.perAppMode = p.mode === 'trust' || p.mode === 'block' ? p.mode : 'all';
        this.perAppBundles = p.bundles !== undefined ? p.bundles : [];
      } catch (e) {
        console.error('parse perapp failed: ' + JSON.stringify(e));
      }
    }
    this.savePerApp();
  }

  private savePerApp(): void {
    let p = new PerAppOptions();
    p.mode = this.perAppMode;
    p.bundles = this.perAppBundles;
    this.store.writeText(F_PERAPP, JSON.stringify(p));
  }

  setPerAppMode(mode: string): void {
    this.perAppMode = mode;
    this.savePerApp();
  }

  addPerAppBundle(bundle: string): boolean {
    let b = bundle.trim();
    if (b.length === 0 || this.perAppBundles.indexOf(b) >= 0) {
      return false;
    }
    this.perAppBundles = this.perAppBundles.concat([b]);
    this.savePerApp();
    return true;
  }

  removePerAppBundle(bundle: string): void {
    let next: string[] = [];
    for (let i = 0; i < this.perAppBundles.length; i++) {
      if (this.perAppBundles[i] !== bundle) {
        next.push(this.perAppBundles[i]);
      }
    }
    this.perAppBundles = next;
    this.savePerApp();
  }

  perAppModeText(): string {
    if (this.perAppMode === 'trust') {
      return '仅代理选中应用';
    }
    if (this.perAppMode === 'block') {
      return '排除选中应用';
    }
    return '全部应用';
  }

  isDark(): boolean {
    return this.darkMode === 2 || (this.darkMode === 0 && this.systemDark);
  }

  private applyAppearance(): void {
    AppTheme.applyAppearance(this.isDark(), this.accentIndex);
    AppStorage.setOrCreate('theme.pageBg', AppTheme.PAGE_BG);
    AppStorage.setOrCreate('theme.primary', AppTheme.PRIMARY);
    AppStorage.setOrCreate('theme.textSub', AppTheme.TEXT_SUB);
    let rev = AppStorage.get<number>('themeRev');
    AppStorage.setOrCreate('themeRev', (rev === undefined ? 0 : rev) + 1);
  }

  private applyColorMode(): void {
    if (this.ctx === undefined) {
      return;
    }
    let cm: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    if (this.darkMode === 2) {
      cm = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    } else if (this.darkMode === 1) {
      cm = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    }
    try {
      this.ctx.getApplicationContext().setColorMode(cm);
    } catch (e) {
      console.error('setColorMode failed: ' + JSON.stringify(e));
    }
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
    this.applyColorMode();
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
    this.applyColorMode();
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

  private normalizeServer(raw: ServerConfig): ServerConfig {
    let s = new ServerConfig();
    s.name = raw.name !== undefined ? raw.name : '';
    s.protocol = raw.protocol !== undefined ? raw.protocol : '';
    s.address = raw.address !== undefined ? raw.address : '';
    s.port = raw.port !== undefined ? raw.port : 0;
    s.uuid = raw.uuid !== undefined ? raw.uuid : '';
    s.username = raw.username !== undefined ? raw.username : '';
    s.password = raw.password !== undefined ? raw.password : '';
    s.method = raw.method !== undefined ? raw.method : '';
    s.alterId = raw.alterId !== undefined ? raw.alterId : 0;
    s.flow = raw.flow !== undefined ? raw.flow : '';
    s.security = raw.security !== undefined ? raw.security : 'none';
    s.sni = raw.sni !== undefined ? raw.sni : '';
    s.fp = raw.fp !== undefined ? raw.fp : '';
    s.pbk = raw.pbk !== undefined ? raw.pbk : '';
    s.sid = raw.sid !== undefined ? raw.sid : '';
    s.spx = raw.spx !== undefined ? raw.spx : '/';
    s.network = raw.network !== undefined ? raw.network : 'tcp';
    s.headerType = raw.headerType !== undefined ? raw.headerType : 'none';
    s.path = raw.path !== undefined ? raw.path : '';
    s.host = raw.host !== undefined ? raw.host : '';
    s.kernel = typeof raw.kernel === 'string' && raw.kernel.length > 0 ? raw.kernel : 'auto';
    s.obfs = raw.obfs !== undefined ? raw.obfs : '';
    s.obfsPassword = raw.obfsPassword !== undefined ? raw.obfsPassword : '';
    s.insecure = raw.insecure === true;
    s.alpn = raw.alpn !== undefined ? raw.alpn : '';
    s.ports = raw.ports !== undefined ? raw.ports : '';
    s.seed = raw.seed !== undefined ? raw.seed : '';
    s.scy = raw.scy !== undefined ? raw.scy : '';
    s.congestionControl = raw.congestionControl !== undefined ? raw.congestionControl : '';
    return s;
  }

  private normalizeGroups(groups: SubGroup[]): SubGroup[] {
    let out: SubGroup[] = [];
    for (let i = 0; i < groups.length; i++) {
      let g = groups[i];
      let copy = new SubGroup(g.id, g.name !== undefined ? g.name : '', g.url !== undefined ? g.url : '');
      copy.updatedAt = g.updatedAt !== undefined ? g.updatedAt : 0;
      copy.upload = g.upload !== undefined ? g.upload : 0;
      copy.download = g.download !== undefined ? g.download : 0;
      copy.total = g.total !== undefined ? g.total : 0;
      copy.expire = g.expire !== undefined ? g.expire : 0;
      let rawNodes = g.nodes !== undefined ? g.nodes : [];
      let nodes: ServerConfig[] = [];
      for (let j = 0; j < rawNodes.length; j++) {
        nodes.push(this.normalizeServer(rawNodes[j]));
      }
      copy.nodes = nodes;
      out.push(copy);
    }
    return out;
  }

  private loadGroups(): void {
    let text = this.store.readText(F_SUBS);
    let loaded: SubGroup[] = [];
    if (text.length > 0) {
      try {
        loaded = this.normalizeGroups(JSON.parse(text) as SubGroup[]);
      } catch (e) {
        console.error('parse subs failed: ' + JSON.stringify(e));
        loaded = [];
      }
    }
    if (loaded.length === 0) {
      let legacy: ServerConfig[] = this.store.loadServers();
      let legacyUrl: string = this.store.loadSubscriptionUrl();
      if (legacy.length > 0 || legacyUrl.length > 0) {
        let legacyNodes: ServerConfig[] = [];
        for (let i = 0; i < legacy.length; i++) {
          legacyNodes.push(this.normalizeServer(legacy[i]));
        }
        let g = new SubGroup('legacy', '默认订阅', legacyUrl);
        g.nodes = legacyNodes;
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

  updateGroupMeta(index: number, name: string, url: string): void {
    if (index < 0 || index >= this.groups.length) {
      return;
    }
    let next: SubGroup[] = [];
    for (let i = 0; i < this.groups.length; i++) {
      let g = this.groups[i];
      if (i === index) {
        let copy = new SubGroup(g.id, name, url);
        copy.nodes = g.nodes;
        copy.updatedAt = g.updatedAt;
        next.push(copy);
      } else {
        next.push(g);
      }
    }
    this.groups = next;
    this.saveGroups();
    if (index === this.activeGroup) {
      this.subUrl = url;
    }
    this.status = '分组已更新';
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
      this.speeds = [];
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
    this.speeds = [];
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
    if (p === -3) {
      return '--';
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
    if (p === -3) {
      return '';
    }
    if (p < 0) {
      return '超时';
    }
    return p.toString() + 'ms';
  }

  // ---------- multi select ----------

  isMulti(idx: number): boolean {
    let key = this.nodeKey(idx);
    if (key.length === 0) {
      return false;
    }
    return this.multiKeys.indexOf(key) >= 0;
  }

  multiCount(): number {
    return this.multiIndices().length;
  }

  multiIndices(): number[] {
    let out: number[] = [];
    for (let i = 0; i < this.servers.length; i++) {
      if (this.multiKeys.indexOf(this.nodeKey(i)) >= 0) {
        out.push(i);
      }
    }
    return out;
  }

  toggleMulti(idx: number): void {
    let key = this.nodeKey(idx);
    if (key.length === 0) {
      return;
    }
    let next: string[] = [];
    let found = false;
    for (let i = 0; i < this.multiKeys.length; i++) {
      if (this.multiKeys[i] === key) {
        found = true;
      } else {
        next.push(this.multiKeys[i]);
      }
    }
    if (!found) {
      next.push(key);
    }
    this.multiKeys = next;
    this.saveMulti();
  }

  clearMulti(): void {
    this.multiKeys = [];
    this.saveMulti();
  }

  private serverKeyOf(s: ServerConfig): string {
    return s.name + '|' + s.address + ':' + s.port.toString();
  }

  private nodeKey(idx: number): string {
    if (idx < 0 || idx >= this.servers.length) {
      return '';
    }
    return this.serverKeyOf(this.servers[idx]);
  }

  downloadTargetsCount(): number {
    return this.downloadTargetIndices().length;
  }

  downloadTargetIndices(): number[] {
    let selected: number[] = this.multiIndices();
    if (selected.length > 0) {
      return selected;
    }
    let out: number[] = [];
    for (let i = 0; i < this.servers.length; i++) {
      if (i < this.pings.length && this.pings[i] === -1) {
        continue;
      }
      out.push(i);
    }
    return out;
  }

  pingTimeoutCount(): number {
    let n: number = 0;
    for (let i = 0; i < this.servers.length && i < this.pings.length; i++) {
      if (this.pings[i] === -1) {
        n++;
      }
    }
    return n;
  }

  speedText(idx: number): string {
    if (idx >= this.speeds.length) {
      return '';
    }
    let s: number = this.speeds[idx];
    if (s === -2) {
      return '测速中';
    }
    if (s === -3) {
      return '';
    }
    if (s === -1) {
      return '失败';
    }
    return (s * 8 / 1000000).toFixed(2) + ' Mbps';
  }

  speedFailed(idx: number): boolean {
    return idx < this.speeds.length && this.speeds[idx] === -1;
  }

  selectServer(idx: number, manual: boolean = true): void {
    if (idx < 0 || idx >= this.servers.length) {
      return;
    }
    if (idx === this.selected) {
      return;
    }
    if (manual) {
      this.failoverSwitchCount = 0;
    }
    this.selected = idx;
    this.store.saveSelected(idx);
    if (this.connected) {
      this.switchNode();
    }
  }

  private commitGroupNodes(groupIdx: number, nodes: ServerConfig[]): void {
    if (groupIdx < 0 || groupIdx >= this.groups.length) {
      return;
    }
    let next: SubGroup[] = [];
    for (let i = 0; i < this.groups.length; i++) {
      let g = this.groups[i];
      if (i === groupIdx) {
        let copy = new SubGroup(g.id, g.name, g.url);
        copy.nodes = nodes;
        copy.updatedAt = g.updatedAt;
        next.push(copy);
      } else {
        next.push(g);
      }
    }
    this.groups = next;
    this.saveGroups();
    if (groupIdx === this.activeGroup) {
      this.servers = nodes;
      if (this.selected >= nodes.length) {
        this.selected = nodes.length > 0 ? nodes.length - 1 : 0;
        this.store.saveSelected(this.selected);
      }
      this.pings = [];
      this.speeds = [];
    }
  }

  updateGroupNode(groupIdx: number, nodeIdx: number, s: ServerConfig): void {
    if (groupIdx < 0 || groupIdx >= this.groups.length) {
      return;
    }
    let nodes: ServerConfig[] = this.groups[groupIdx].nodes !== undefined ? this.groups[groupIdx].nodes : [];
    if (nodeIdx < 0 || nodeIdx >= nodes.length) {
      return;
    }
    let next: ServerConfig[] = [];
    for (let i = 0; i < nodes.length; i++) {
      next.push(i === nodeIdx ? s : nodes[i]);
    }
    this.commitGroupNodes(groupIdx, next);
    this.status = '节点已更新';
    if (this.connected && groupIdx === this.activeGroup && nodeIdx === this.selected) {
      this.switchNode();
    }
  }

  removeGroupNode(groupIdx: number, nodeIdx: number): void {
    if (groupIdx < 0 || groupIdx >= this.groups.length) {
      return;
    }
    let nodes: ServerConfig[] = this.groups[groupIdx].nodes !== undefined ? this.groups[groupIdx].nodes : [];
    if (nodeIdx < 0 || nodeIdx >= nodes.length) {
      return;
    }
    let name = nodes[nodeIdx].name;
    let wasSelected = groupIdx === this.activeGroup && nodeIdx === this.selected;
    let next: ServerConfig[] = [];
    for (let i = 0; i < nodes.length; i++) {
      if (i !== nodeIdx) {
        next.push(nodes[i]);
      }
    }
    if (groupIdx === this.activeGroup && nodeIdx < this.selected) {
      this.selected = this.selected - 1;
      this.store.saveSelected(this.selected);
    }
    this.commitGroupNodes(groupIdx, next);
    this.status = '已删除节点: ' + name;
    if (this.connected && groupIdx === this.activeGroup) {
      if (next.length === 0) {
        this.disconnect();
      } else if (wasSelected) {
        this.switchNode();
      }
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
    let pair = buildVpnConfigPair(server, XRAY_LOG_PATH, this.routingOptions());
    this.store.saveXrayConfig(pair.xrayConfig);
    this.store.writeText(F_SINGBOX_CONFIG, pair.singboxConfig);
  }

  isNodeSingbox(idx: number): boolean {
    if (idx < 0 || idx >= this.servers.length) {
      return false;
    }
    return usesSingboxKernel(this.servers[idx]);
  }

  currentIsSingbox(): boolean {
    return this.isNodeSingbox(this.selected);
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
    this.vpnIntentionalRestart = true;
    try {
      await vpnExtension.stopVpnExtensionAbility(VPN_WANT);
    } catch (e) {
      console.error('stopVpn during switch failed: ' + JSON.stringify(e));
    }
    await sleepMs(600);
    let ok = await this.startVpnWithRetry(3);
    this.vpnIntentionalRestart = false;
    if (ok) {
      this.connected = true;
      this.vpnLastStartAt = Date.now();
      this.status = '';
      this.failoverCooldownUntil = 0;
      this.startFailoverMonitor();
      this.beginTrafficSession();
      this.refreshExitIp();
      this.startKeepAliveTask();
      this.startVpnWatchdog();
    } else {
      this.connected = false;
      this.ipBusy = false;
      this.endTrafficSession();
      this.stopFailoverMonitor();
      this.stopKeepAliveTask();
      this.stopVpnWatchdog();
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
    this.updateGroupSubscription(this.activeGroup);
  }

  private async fetchSubscriptionText(url: string): Promise<string> {
    if (this.connected) {
      let body = await SubscriptionFetcher.fetchThroughProxy(url, SOCKS_HOST, SOCKS_PORT, 15000, 30000);
      if (body.length > 0) {
        return body;
      }
    }
    let last: string = '';
    for (let attempt = 0; attempt < 3; attempt++) {
      last = await SubscriptionFetcher.fetchText(url);
      if (last.length > 0) {
        return last;
      }
      if (attempt < 2) {
        await sleepMs(800);
      }
    }
    return last;
  }

  async updateGroupSubscription(index: number): Promise<void> {
    if (this.busy) {
      return;
    }
    if (index < 0 || index >= this.groups.length) {
      return;
    }
    let name = this.groups[index].name;
    let url = this.groups[index].url.trim();
    if (url.length === 0) {
      this.status = '「' + name + '」未设置订阅链接';
      return;
    }
    this.busy = true;
    this.status = (this.connected ? '正在通过代理更新订阅: ' : '正在更新订阅: ') + name + '...';
    let content = await this.fetchSubscriptionText(url);
    let userinfo = this.parseSubUserinfo(SubscriptionFetcher.lastUserinfo);
    let list = parseSubscription(content);
    if (list.length === 0) {
      let reason = SubscriptionFetcher.lastError.length > 0 ? SubscriptionFetcher.lastError : '内容无法解析';
      this.status = '「' + name + '」更新失败: ' + reason;
      this.busy = false;
      return;
    }
    let prevKey = index === this.activeGroup ? this.nodeKey(this.selected) : '';
    let next: SubGroup[] = [];
    for (let i = 0; i < this.groups.length; i++) {
      let g = this.groups[i];
      if (i === index) {
        let copy = new SubGroup(g.id, g.name, url);
        copy.nodes = list;
        copy.updatedAt = Date.now();
        copy.upload = g.upload !== undefined ? g.upload : 0;
        copy.download = g.download !== undefined ? g.download : 0;
        copy.total = g.total !== undefined ? g.total : 0;
        copy.expire = g.expire !== undefined ? g.expire : 0;
        if (userinfo !== undefined) {
          copy.upload = userinfo.upload;
          copy.download = userinfo.download;
          copy.total = userinfo.total;
          copy.expire = userinfo.expire;
        }
        next.push(copy);
      } else {
        next.push(g);
      }
    }
    this.groups = next;
    this.saveGroups();
    if (index === this.activeGroup) {
      this.subUrl = url;
      this.store.saveSubscriptionUrl(url);
      this.servers = list;
      let keep = 0;
      if (prevKey.length > 0) {
        for (let i = 0; i < list.length; i++) {
          if (this.serverKeyOf(list[i]) === prevKey) {
            keep = i;
            break;
          }
        }
      }
      this.selected = keep;
      this.store.saveSelected(keep);
      this.pings = [];
      this.speeds = [];
      if (this.connected) {
        this.busy = false;
        await this.switchNode();
        return;
      }
    }
    this.status = '「' + name + '」已更新，共 ' + list.length.toString() + ' 个节点';
    this.busy = false;
  }

  async updateAllGroups(): Promise<void> {
    if (this.busy) {
      return;
    }
    let updated = 0;
    for (let i = 0; i < this.groups.length; i++) {
      if (this.groups[i].url.trim().length > 0) {
        updated++;
        await this.updateGroupSubscription(i);
      }
    }
    if (updated === 0) {
      this.status = '没有可更新的订阅分组';
    }
  }

  async maybeAutoUpdateSubs(): Promise<void> {
    if (!this.autoUpdateSubs || this.busy) {
      return;
    }
    let count = 0;
    for (let i = 0; i < this.groups.length; i++) {
      if (this.groups[i].url.trim().length > 0) {
        count++;
      }
    }
    if (count === 0) {
      return;
    }
    for (let i = 0; i < this.groups.length; i++) {
      if (this.groups[i].url.trim().length > 0) {
        await this.updateGroupSubscription(i);
      }
    }
    this.status = '已自动更新 ' + count.toString() + ' 个订阅分组';
  }

  maybeAutoConnect(): void {
    if (!this.autoConnect || this.connected || this.servers.length === 0) {
      return;
    }
    this.appendRuntimeLog('[app] 启动自动连接: ' + this.nodeName());
    this.connect();
  }

  // ---------- failover ----------

  private startFailoverMonitor(): void {
    if (!this.failover || !this.connected) {
      return;
    }
    if (this.failoverTimerId >= 0) {
      return;
    }
    this.failoverFails = 0;
    this.failoverTimerId = setInterval(() => {
      this.runFailoverCheck();
    }, FAILOVER_CHECK_MS);
  }

  private stopFailoverMonitor(): void {
    if (this.failoverTimerId >= 0) {
      clearInterval(this.failoverTimerId);
      this.failoverTimerId = -1;
    }
    this.failoverFails = 0;
    this.failoverCooldownUntil = 0;
    this.failoverChecking = false;
  }

  private async testNodeAlive(srv: ServerConfig): Promise<boolean> {
    let pair = buildTestConfigPair(srv);
    let timeout: Promise<number> = sleepMs(FAILOVER_PROBE_TIMEOUT_MS).then((): number => -999);
    try {
      let ms: number = await Promise.race([
        testNapi.measureDelay(pair.xrayConfig, pair.singboxConfig, 'http://www.gstatic.com/generate_204'),
        timeout
      ]);
      return ms >= 0;
    } catch (e) {
      return false;
    }
  }

  private async runFailoverCheck(): Promise<void> {
    if (!this.failover || !this.connected || this.failoverChecking) {
      return;
    }
    if (Date.now() < this.failoverCooldownUntil) {
      return;
    }
    let srv: ServerConfig | undefined = this.currentNode();
    if (srv === undefined) {
      return;
    }
    this.failoverChecking = true;
    let alive: boolean = await this.testNodeAlive(srv);
    this.failoverChecking = false;
    if (!this.failover || !this.connected) {
      return;
    }
    if (alive) {
      this.failoverFails = 0;
      return;
    }
    this.failoverFails++;
    this.appendRuntimeLog('[failover] 节点不可达 ' + srv.name + ' ('
      + this.failoverFails.toString() + '/' + FAILOVER_FAIL_LIMIT.toString() + ')');
    if (this.failoverFails >= FAILOVER_FAIL_LIMIT) {
      this.doFailoverSwitch(srv.name);
    }
  }

  private pickFailoverTarget(): number {
    let best: number = -1;
    let bestPing: number = -1;
    for (let i = 0; i < this.servers.length; i++) {
      if (i === this.selected) {
        continue;
      }
      let ping: number = i < this.pings.length ? this.pings[i] : -3;
      if (ping >= 0 && (best < 0 || ping < bestPing)) {
        best = i;
        bestPing = ping;
      }
    }
    if (best >= 0) {
      return best;
    }
    return (this.selected + 1) % this.servers.length;
  }

  private doFailoverSwitch(badName: string): void {
    this.failoverFails = 0;
    this.failoverCooldownUntil = Date.now() + FAILOVER_COOLDOWN_MS;
    if (this.servers.length < 2) {
      this.appendRuntimeLog('[failover] 没有其他节点可切换');
      this.status = '节点「' + badName + '」不可用（没有其他节点可切换）';
      return;
    }
    if (this.failoverSwitchCount >= this.servers.length - 1) {
      this.appendRuntimeLog('[failover] 所有节点均不可用，停止自动切换');
      this.status = '所有节点均不可用，已停止自动切换';
      this.stopFailoverMonitor();
      return;
    }
    let next: number = this.pickFailoverTarget();
    let nextName: string = this.servers[next].name;
    this.failoverSwitchCount++;
    this.appendRuntimeLog('[failover] 自动切换 ' + badName + ' -> ' + nextName);
    this.status = '故障转移: 「' + badName + '」不可用，已切换到「' + nextName + '」';
    this.selectServer(next, false);
  }

  private applyPingSort(): void {
    if (this.servers.length < 2) {
      return;
    }
    let selectedKey = this.nodeKey(this.selected);
    let entries: PingSortEntry[] = [];
    for (let i = 0; i < this.servers.length; i++) {
      let ping = -3;
      if (i < this.pings.length) {
        ping = this.pings[i];
      }
      let rank = 1;
      if (ping >= 0) {
        rank = 0;
      } else if (ping === -1) {
        rank = 2;
      }
      entries.push(new PingSortEntry(rank, ping, i, this.servers[i]));
    }
    entries.sort((a: PingSortEntry, b: PingSortEntry): number => {
      if (a.rank !== b.rank) {
        return a.rank - b.rank;
      }
      if (a.rank === 0 && a.ping !== b.ping) {
        return a.ping - b.ping;
      }
      return a.oldIdx - b.oldIdx;
    });
    let nextServers: ServerConfig[] = [];
    let nextPings: number[] = [];
    let nextSpeeds: number[] = [];
    for (let i = 0; i < entries.length; i++) {
      let old = entries[i].oldIdx;
      nextServers.push(entries[i].server);
      nextPings.push(old < this.pings.length ? this.pings[old] : -3);
      nextSpeeds.push(old < this.speeds.length ? this.speeds[old] : -3);
    }
    this.commitSortedNodes(nextServers, nextPings, nextSpeeds, selectedKey);
  }

  sortByPing(): void {
    this.applyPingSort();
    this.status = '已按延迟从低到高排序';
  }

  private applySpeedSort(): void {
    if (this.servers.length < 2) {
      return;
    }
    let selectedKey = this.nodeKey(this.selected);
    let entries: SpeedSortEntry[] = [];
    for (let i = 0; i < this.servers.length; i++) {
      let speed = -3;
      if (i < this.speeds.length) {
        speed = this.speeds[i];
      }
      let rank = 1;
      if (speed > 0) {
        rank = 0;
      } else if (speed === -1) {
        rank = 2;
      }
      entries.push(new SpeedSortEntry(rank, speed, i, this.servers[i]));
    }
    entries.sort((a: SpeedSortEntry, b: SpeedSortEntry): number => {
      if (a.rank !== b.rank) {
        return a.rank - b.rank;
      }
      if (a.rank === 0 && a.speed !== b.speed) {
        return b.speed - a.speed;
      }
      return a.oldIdx - b.oldIdx;
    });
    let nextServers: ServerConfig[] = [];
    let nextPings: number[] = [];
    let nextSpeeds: number[] = [];
    for (let i = 0; i < entries.length; i++) {
      let old = entries[i].oldIdx;
      nextServers.push(entries[i].server);
      nextPings.push(old < this.pings.length ? this.pings[old] : -3);
      nextSpeeds.push(old < this.speeds.length ? this.speeds[old] : -3);
    }
    this.commitSortedNodes(nextServers, nextPings, nextSpeeds, selectedKey);
  }

  sortBySpeed(): void {
    this.applySpeedSort();
    this.status = '已按速率从高到低排序';
  }

  private commitSortedNodes(nodes: ServerConfig[], pings: number[], speeds: number[], selectedKey: string): void {
    this.servers = nodes;
    this.pings = pings;
    this.speeds = speeds;
    if (this.activeGroup >= 0 && this.activeGroup < this.groups.length) {
      let next: SubGroup[] = [];
      for (let i = 0; i < this.groups.length; i++) {
        let g = this.groups[i];
        if (i === this.activeGroup) {
          let copy = new SubGroup(g.id, g.name, g.url);
          copy.nodes = nodes;
          copy.updatedAt = g.updatedAt;
          next.push(copy);
        } else {
          next.push(g);
        }
      }
      this.groups = next;
      this.saveGroups();
    }
    let sel = 0;
    if (selectedKey.length > 0) {
      for (let i = 0; i < nodes.length; i++) {
        if (this.serverKeyOf(nodes[i]) === selectedKey) {
          sel = i;
          break;
        }
      }
    }
    this.selected = sel;
    this.store.saveSelected(sel);
  }

  private pingStopRequested: boolean = false;

  requestStopTestAll(): void {
    if (!this.testing || this.pingStopRequested) {
      return;
    }
    this.pingStopRequested = true;
    this.status = '停止测延迟: 等待当前批次完成...';
  }

  pingStopPending(): boolean {
    return this.testing && this.pingStopRequested;
  }

  async testAll(): Promise<void> {
    if (this.servers.length === 0 || this.busy || this.testing || this.downloadTesting) {
      return;
    }
    let targets: number[] = this.multiIndices();
    if (targets.length === 0) {
      for (let i = 0; i < this.servers.length; i++) {
        targets.push(i);
      }
    }
    let init: number[] = [];
    for (let i = 0; i < this.servers.length; i++) {
      init.push(i < this.pings.length ? this.pings[i] : -3);
    }
    for (let i = 0; i < targets.length; i++) {
      init[targets[i]] = -2;
    }
    this.pings = init;
    this.busy = true;
    this.testing = true;
    this.pingStopRequested = false;
    this.status = '正在测延迟...';
    let stopped = false;
    try {
      let done = 0;
      let sbPortOffset = 0;
      for (let c = 0; c < targets.length; c += PING_CONCURRENCY) {
        if (this.pingStopRequested) {
          stopped = true;
          break;
        }
        let chunk: number[] = targets.slice(c, c + PING_CONCURRENCY);
        let jobs: Promise<number>[] = [];
        for (let j = 0; j < chunk.length; j++) {
          let idx = chunk[j];
          if (this.isNodeSingbox(idx)) {
            jobs.push(this.chainedPingServer(this.servers[idx], TEST_SINGBOX_PORT + 1 + sbPortOffset));
            sbPortOffset++;
          } else {
            jobs.push(this.chainedPingServer(this.servers[idx]));
          }
        }
        let results: number[] = await Promise.all(jobs);
        let copy: number[] = [];
        for (let j = 0; j < this.pings.length; j++) {
          copy.push(this.pings[j]);
        }
        for (let j = 0; j < chunk.length; j++) {
          copy[chunk[j]] = results[j];
        }
        this.pings = copy;
        done += chunk.length;
        if (!this.pingStopRequested) {
          this.status = '正在测延迟 ' + done.toString() + '/' + targets.length.toString() + '...';
        }
      }
      if (stopped) {
        let copy: number[] = [];
        for (let j = 0; j < this.pings.length; j++) {
          copy.push(this.pings[j]);
        }
        for (let j = 0; j < targets.length; j++) {
          if (copy[targets[j]] === -2) {
            copy[targets[j]] = -3;
          }
        }
        this.pings = copy;
        this.status = '测延迟已停止: ' + done.toString() + '/' + targets.length.toString();
      } else {
        this.status = '测延迟完成';
      }
    } finally {
      this.busy = false;
      this.testing = false;
    }
    if (!stopped && this.servers.length > 1 && this.sortPromptHandler !== null) {
      this.sortPromptHandler('ping');
    }
  }

  private async chainedPingServer(srv: ServerConfig, singboxListenPort: number = TEST_SINGBOX_PORT): Promise<number> {
    let pair = buildTestConfigPair(srv, singboxListenPort);
    let timeout: Promise<number> = sleepMs(CHAINED_PING_TIMEOUT_MS).then((): number => -999);
    try {
      let ms: number = await Promise.race([
        testNapi.measureDelay(pair.xrayConfig, pair.singboxConfig, 'http://www.gstatic.com/generate_204'),
        timeout
      ]);
      return ms >= 0 ? ms : -1;
    } catch (e) {
      return -1;
    }
  }

  private downloadStopRequested: boolean = false;

  requestStopDownloadTest(): void {
    if (!this.downloadTesting || this.downloadStopRequested) {
      return;
    }
    this.downloadStopRequested = true;
    this.status = '停止测下载: 等待当前批次完成...';
  }

  downloadStopPending(): boolean {
    return this.downloadTesting && this.downloadStopRequested;
  }

  async testDownload(): Promise<void> {
    if (this.servers.length === 0 || this.busy || this.testing || this.downloadTesting) {
      return;
    }
    let targets: number[] = this.downloadTargetIndices();
    if (targets.length === 0) {
      this.status = '测下载跳过: 延迟测速均超时，无可测节点';
      return;
    }
    let init: number[] = [];
    for (let i = 0; i < this.servers.length; i++) {
      init.push(i < this.speeds.length ? this.speeds[i] : -3);
    }
    for (let i = 0; i < targets.length; i++) {
      init[targets[i]] = -2;
    }
    this.speeds = init;
    this.downloadTesting = true;
    this.busy = true;
    this.downloadStopRequested = false;
    let ok = 0;
    let stopped = false;
    try {
      let done = 0;
      let sbPortOffset = 0;
      let concurrency: number = this.speedTestConcurrency;
      for (let c = 0; c < targets.length; c += concurrency) {
        if (this.downloadStopRequested) {
          stopped = true;
          break;
        }
        let chunk: number[] = targets.slice(c, c + concurrency);
        let jobs: Promise<number>[] = [];
        for (let j = 0; j < chunk.length; j++) {
          let idx = chunk[j];
          if (this.isNodeSingbox(idx)) {
            jobs.push(this.chainedDownloadServer(this.servers[idx], TEST_SINGBOX_PORT + 1 + sbPortOffset));
            sbPortOffset++;
          } else {
            jobs.push(this.chainedDownloadServer(this.servers[idx], TEST_SINGBOX_PORT));
          }
        }
        let results: number[] = await Promise.all(jobs);
        let copy: number[] = [];
        for (let j = 0; j < this.speeds.length; j++) {
          copy.push(this.speeds[j]);
        }
        for (let j = 0; j < chunk.length; j++) {
          copy[chunk[j]] = results[j] > 0 ? results[j] : -1;
          if (results[j] > 0) {
            ok++;
          }
        }
        this.speeds = copy;
        done += chunk.length;
        if (!this.downloadStopRequested) {
          this.status = '正在测下载 ' + done.toString() + '/' + targets.length.toString() + '...';
        }
      }
      if (stopped) {
        let copy: number[] = [];
        for (let j = 0; j < this.speeds.length; j++) {
          copy.push(this.speeds[j]);
        }
        for (let j = 0; j < targets.length; j++) {
          if (copy[targets[j]] === -2) {
            copy[targets[j]] = -3;
          }
        }
        this.speeds = copy;
        this.status = '测下载已停止: ' + ok.toString() + '/' + targets.length.toString() + ' 个节点成功';
      } else {
        this.status = '测下载完成: ' + ok.toString() + '/' + targets.length.toString() + ' 个节点成功';
      }
    } finally {
      this.downloadTesting = false;
      this.busy = false;
    }
    if (!stopped && this.servers.length > 1 && this.sortPromptHandler !== null) {
      this.sortPromptHandler('download');
    }
  }

  private async chainedDownloadServer(srv: ServerConfig, singboxListenPort: number): Promise<number> {
    let pair = buildTestConfigPair(srv, singboxListenPort);
    let mb: number = this.speedTestMB;
    let ovhFile: string = '1Gb.dat';
    if (mb <= 10) {
      ovhFile = '10Mb.dat';
    } else if (mb <= 100) {
      ovhFile = '100Mb.dat';
    }
    let urls: string[] = [
      'http://speed.cloudflare.com/__down?bytes=' + (mb * 1000000).toString(),
      'http://proof.ovh.net/files/' + ovhFile
    ];
    for (let i = 0; i < urls.length; i++) {
      let bps: number = -1;
      try {
        bps = await testNapi.measureDownload(pair.xrayConfig, pair.singboxConfig, urls[i], mb * 1024 * 1024);
      } catch (e) {
        bps = -1;
      }
      if (bps > 0) {
        return bps;
      }
    }
    return -1;
  }

  // ---------- connection ----------

  async beginTrafficSession(): Promise<void> {
    this.connectedAt = Date.now();
    this.sessionRx = 0;
    this.sessionTx = 0;
    this.statsBaseRx = -1;
    this.statsBaseTx = -1;
    if (this.appUid < 0) {
      return;
    }
    try {
      this.statsBaseRx = await statistics.getUidRxBytes(this.appUid);
      this.statsBaseTx = await statistics.getUidTxBytes(this.appUid);
    } catch (e) {
      console.error('read uid stats baseline failed: ' + JSON.stringify(e));
    }
  }

  async refreshTrafficStats(): Promise<void> {
    if (!this.connected || this.appUid < 0 || this.statsBaseRx < 0 || this.statsBaseTx < 0) {
      return;
    }
    try {
      let rx = await statistics.getUidRxBytes(this.appUid);
      let tx = await statistics.getUidTxBytes(this.appUid);
      this.sessionRx = rx - this.statsBaseRx;
      this.sessionTx = tx - this.statsBaseTx;
    } catch (e) {
      console.error('read uid stats failed: ' + JSON.stringify(e));
    }
  }

  endTrafficSession(): void {
    this.connectedAt = 0;
    this.sessionRx = 0;
    this.sessionTx = 0;
    this.statsBaseRx = -1;
    this.statsBaseTx = -1;
  }

  connectedDurationText(): string {
    if (this.connectedAt <= 0) {
      return '';
    }
    let s = Math.floor((Date.now() - this.connectedAt) / 1000);
    let hh = Math.floor(s / 3600);
    let mm = Math.floor((s % 3600) / 60);
    let ss = s % 60;
    if (hh > 0) {
      return hh.toString() + ':' + this.pad2(mm) + ':' + this.pad2(ss);
    }
    return this.pad2(mm) + ':' + this.pad2(ss);
  }

  trafficText(bytes: number): string {
    if (bytes < 1024) {
      return bytes.toString() + ' B';
    }
    if (bytes < 1024 * 1024) {
      return (bytes / 1024).toFixed(1) + ' KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return (bytes / 1024 / 1024).toFixed(1) + ' MB';
    }
    return (bytes / 1024 / 1024 / 1024).toFixed(2) + ' GB';
  }

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
      this.vpnLastStartAt = Date.now();
      this.status = '';
      this.failoverSwitchCount = 0;
      this.failoverCooldownUntil = 0;
      this.startFailoverMonitor();
      this.beginTrafficSession();
      this.refreshExitIp();
      this.startKeepAliveTask();
      this.startVpnWatchdog();
    } else {
      this.connected = false;
      this.ipBusy = false;
      this.endTrafficSession();
      this.stopFailoverMonitor();
      this.stopKeepAliveTask();
      this.stopVpnWatchdog();
      this.status = '连接失败，请重试';
    }
  }

  disconnect(): void {
    this.exitIp = '';
    this.ipError = '';
    this.ipBusy = false;
    this.stopFailoverMonitor();
    this.stopKeepAliveTask();
    this.stopVpnWatchdog();
    this.failoverSwitchCount = 0;
    this.vpnIntentionalRestart = true;
    vpnExtension.stopVpnExtensionAbility(VPN_WANT).then(() => {
      this.connected = false;
      this.vpnIntentionalRestart = false;
      this.endTrafficSession();
      this.status = '已断开';
    }).catch((err: BusinessError) => {
      this.vpnIntentionalRestart = false;
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

  private routingReconnectPending: boolean = false;

  private saveRouting(): void {
    let r = this.routingOptions();
    this.store.writeText(F_ROUTING, JSON.stringify(r));
    this.scheduleRoutingReconnect();
  }

  private scheduleRoutingReconnect(): void {
    if (!this.connected || this.routingReconnectPending) {
      return;
    }
    this.routingReconnectPending = true;
    sleepMs(800).then(() => {
      this.routingReconnectPending = false;
      this.applyRoutingChange();
    });
  }

  private async applyRoutingChange(): Promise<void> {
    if (!this.connected) {
      return;
    }
    this.applyServerConfig();
    this.exitIp = '';
    this.ipError = '';
    this.ipBusy = true;
    this.status = '正在应用分流设置';
    this.vpnIntentionalRestart = true;
    try {
      await vpnExtension.stopVpnExtensionAbility(VPN_WANT);
    } catch (e) {
      console.error('stopVpn during routing apply failed: ' + JSON.stringify(e));
    }
    await sleepMs(600);
    let ok = await this.startVpnWithRetry(3);
    this.vpnIntentionalRestart = false;
    if (ok) {
      this.connected = true;
      this.vpnLastStartAt = Date.now();
      this.status = '';
      this.refreshExitIp();
      this.startVpnWatchdog();
    } else {
      this.connected = false;
      this.ipBusy = false;
      this.endTrafficSession();
      this.stopFailoverMonitor();
      this.stopKeepAliveTask();
      this.stopVpnWatchdog();
      this.status = '应用分流设置失败，请重连';
    }
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

  private async fetchGeoBytes(url: string): Promise<ArrayBuffer | undefined> {
    if (this.connected) {
      let data = await SubscriptionFetcher.fetchBytesThroughProxy(url, SOCKS_HOST, SOCKS_PORT);
      if (data !== undefined) {
        return data;
      }
    }
    return SubscriptionFetcher.fetchBytes(url);
  }

  async updateGeoFiles(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.status = this.connected ? '正在通过代理下载资源文件...' : '正在下载资源文件...';
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
      let data = await this.fetchGeoBytes(this.geoUrlGeosite);
      if (data !== undefined) {
        okSite = this.store.writeBytesTo(dir + '/geosite.dat', data);
      }
    }
    if (this.geoUrlGeoip.length > 0) {
      let data = await this.fetchGeoBytes(this.geoUrlGeoip);
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
    let groups: SubGroup[] = b.groups !== undefined ? this.normalizeGroups(b.groups) : [];
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
    let nodeCount = 0;
    for (let i = 0; i < groups.length; i++) {
      let nodes = groups[i].nodes;
      if (nodes !== undefined) {
        nodeCount += nodes.length;
      }
    }
    this.status = '还原完成，共 ' + groups.length.toString() + ' 个分组、' + nodeCount.toString() + ' 个节点';
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

  // ---------- runtime logs ----------

  appendRuntimeLog(line: string): void {
    let t = new Date();
    let stamp = this.pad2(t.getHours()) + ':' + this.pad2(t.getMinutes()) + ':' + this.pad2(t.getSeconds());
    this.store.appendText(F_VPN_LOG, stamp + ' ' + line + '\n');
  }

  logText(kind: number): string {
    let text = this.store.readText(kind === 1 ? F_XRAY_LOG : F_VPN_LOG);
    if (text.length === 0) {
      return '';
    }
    let lines = text.split('\n');
    let out: string[] = [];
    for (let i = lines.length - 1; i >= 0 && out.length < LOG_TAIL_LINES; i--) {
      let l: string = lines[i];
      if (l.trim().length > 0) {
        out.push(l);
      }
    }
    return out.join('\n');
  }

  logMetaText(kind: number): string {
    let name = kind === 1 ? F_XRAY_LOG : F_VPN_LOG;
    let size = this.store.sizeOf(name);
    if (size <= 0) {
      return '空';
    }
    return this.sizeText(size) + ' · 更新 ' + this.formatTime(this.store.mtimeOf(name));
  }

  clearLog(kind: number): void {
    this.store.writeText(kind === 1 ? F_XRAY_LOG : F_VPN_LOG, '');
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

  formatDate(ts: number): string {
    if (ts <= 0) {
      return '';
    }
    let d = new Date(ts);
    return d.getFullYear().toString() + '-' + this.pad2(d.getMonth() + 1) + '-' + this.pad2(d.getDate());
  }

  formatTraffic(bytes: number): string {
    if (bytes <= 0) {
      return '0 B';
    }
    let kb = 1024;
    let mb = 1024 * 1024;
    let gb = 1024 * 1024 * 1024;
    if (bytes >= gb) {
      return (bytes / gb).toFixed(2) + ' GB';
    }
    if (bytes >= mb) {
      return (bytes / mb).toFixed(1) + ' MB';
    }
    if (bytes >= kb) {
      return (bytes / kb).toFixed(0) + ' KB';
    }
    return bytes.toString() + ' B';
  }

  private parseSubUserinfo(raw: string): SubUserinfo | undefined {
    if (raw.length === 0) {
      return undefined;
    }
    let out = new SubUserinfo();
    let seen = false;
    let parts = raw.split(';');
    for (let i = 0; i < parts.length; i++) {
      let kv = parts[i].trim().split('=');
      if (kv.length !== 2) {
        continue;
      }
      let key = kv[0].trim().toLowerCase();
      let val = parseInt(kv[1].trim(), 10);
      if (isNaN(val) || val < 0) {
        continue;
      }
      if (key === 'upload') {
        out.upload = val;
        seen = true;
      } else if (key === 'download') {
        out.download = val;
        seen = true;
      } else if (key === 'total') {
        out.total = val;
        seen = true;
      } else if (key === 'expire') {
        out.expire = val;
        seen = true;
      }
    }
    return seen ? out : undefined;
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
