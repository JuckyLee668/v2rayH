import { VpnExtensionAbility, vpnExtension } from '@kit.NetworkKit';
import { Want } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { buffer } from '@kit.ArkTS';
import testNapi from 'libentry.so';

const SELF_BUNDLE: string = 'com.xii.v2rayh';
const LOG_ROTATE_MAX: number = 262144;
const LOG_ROTATE_KEEP: number = 65536;

class PerAppFile {
  mode: string = 'all';
  bundles: string[] = [];
}

export default class MyVpnExtAbility extends VpnExtensionAbility {
  private vpnConnection: vpnExtension.VpnConnection | undefined = undefined;
  private logFile: string = '';
  private configFile: string = '';

  private log(msg: string): void {
    console.info('MyVpnExtAbility: ' + msg);
    if (this.logFile.length > 0) {
      try {
        let f = fs.openSync(this.logFile, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.APPEND);
        fs.writeSync(f.fd, msg + '\n');
        fs.closeSync(f);
      } catch (e) {
        console.error('log write failed: ' + JSON.stringify(e));
      }
    }
  }

  private readConfig(): string {
    try {
      if (!fs.accessSync(this.configFile)) {
        return '';
      }
      let stat = fs.statSync(this.configFile);
      if (stat.size === 0) {
        return '';
      }
      let f = fs.openSync(this.configFile, fs.OpenMode.READ_ONLY);
      let buf = new ArrayBuffer(stat.size);
      fs.readSync(f.fd, buf);
      fs.closeSync(f);
      return buffer.from(buf).toString('utf-8');
    } catch (e) {
      this.log('readConfig failed: ' + JSON.stringify(e));
      return '';
    }
  }

  private rotateLog(): void {
    if (this.logFile.length === 0) {
      return;
    }
    try {
      if (!fs.accessSync(this.logFile)) {
        return;
      }
      let size: number = fs.statSync(this.logFile).size;
      if (size <= LOG_ROTATE_MAX) {
        return;
      }
      let keep: number = LOG_ROTATE_KEEP;
      let start: number = size - keep;
      if (start < 0) {
        start = 0;
        keep = size;
      }
      let f = fs.openSync(this.logFile, fs.OpenMode.READ_ONLY);
      let buf = new ArrayBuffer(keep);
      let n: number = fs.readSync(f.fd, buf, { offset: start });
      fs.closeSync(f);
      let out = fs.openSync(this.logFile, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(out.fd, '=== 日志过大，已自动截断 ===\n');
      if (n > 0) {
        fs.writeSync(out.fd, buffer.from(buf.slice(0, n)).toString('utf-8'));
      }
      fs.closeSync(out);
    } catch (e) {
      console.error('rotateLog failed: ' + JSON.stringify(e));
    }
  }

  onCreate(want: Want): void {
    try {
      this.logFile = this.context.filesDir + '/vpn.log';
      this.configFile = this.context.filesDir + '/xray_config.json';
    } catch (e) {
      this.logFile = '';
    }
    this.rotateLog();
    this.log('=== onCreate ===');
    this.setupVpn();
  }

  onDestroy(): void {
    this.log('=== onDestroy ===');
    testNapi.stopVpn();
    if (this.vpnConnection) {
      this.vpnConnection.destroy().then(() => {
        this.log('vpn destroy success');
      }).catch((err: Error) => {
        this.log('vpn destroy failed: ' + JSON.stringify(err));
      });
    }
  }

  private readPerApp(): PerAppFile {
    let p = new PerAppFile();
    try {
      let path = this.context.filesDir + '/perapp.json';
      if (fs.accessSync(path)) {
        let stat = fs.statSync(path);
        if (stat.size > 0) {
          let f = fs.openSync(path, fs.OpenMode.READ_ONLY);
          let buf = new ArrayBuffer(stat.size);
          fs.readSync(f.fd, buf);
          fs.closeSync(f);
          let parsed = JSON.parse(buffer.from(buf).toString('utf-8')) as PerAppFile;
          p.mode = parsed.mode !== undefined ? parsed.mode : 'all';
          p.bundles = parsed.bundles !== undefined ? parsed.bundles : [];
        }
      }
    } catch (e) {
      this.log('readPerApp failed: ' + JSON.stringify(e));
    }
    return p;
  }

  private setupVpn(): void {
    let xrayConfig = this.readConfig();
    this.log('xray config length=' + xrayConfig.length.toString());
    if (xrayConfig.length === 0) {
      this.log('no xray config, abort');
      return;
    }

    this.vpnConnection = vpnExtension.createVpnConnection(this.context);
    this.log('connection created');

    try {
      let p1 = this.context.filesDir + '/xray_error.log';
      try { fs.unlinkSync(p1); } catch (e) {}
      let f1 = fs.openSync(p1, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      fs.closeSync(f1);
    } catch (e) {
      this.log('pre-create log failed: ' + JSON.stringify(e));
    }

    let config: vpnExtension.VpnConfig = {
      addresses: [{
        address: { address: '10.0.0.5', family: 1 },
        prefixLength: 24
      }],
      routes: [{
        interface: 'vpn-tun',
        destination: {
          address: { address: '0.0.0.0', family: 1 },
          prefixLength: 0
        },
        gateway: { address: '', family: 1 },
        hasGateway: false,
        isDefaultRoute: true
      }],
      dnsAddresses: ['8.8.8.8', '8.8.4.4'],
      mtu: 1400
    };

    let perApp = this.readPerApp();
    let bundles: string[] = [];
    for (let i = 0; i < perApp.bundles.length; i++) {
      let b = perApp.bundles[i];
      if (b !== SELF_BUNDLE && bundles.indexOf(b) < 0) {
        bundles.push(b);
      }
    }
    if (perApp.mode === 'trust' && bundles.length > 0) {
      config.trustedApplications = bundles;
      this.log('per-app trust mode, apps=' + bundles.length.toString());
    } else {
      let blocked: string[] = [SELF_BUNDLE];
      if (perApp.mode === 'block') {
        for (let i = 0; i < bundles.length; i++) {
          blocked.push(bundles[i]);
        }
      }
      config.blockedApplications = blocked;
      this.log('per-app block mode, blocked=' + blocked.length.toString());
    }

    this.log('calling create(config)');
    this.vpnConnection.create(config).then((fd: number) => {
      this.log('vpn create success, fd=' + fd.toString());
      let conn = this.vpnConnection;
      if (conn) {
        if (conn.protectProcessNet !== undefined) {
          conn.protectProcessNet().then(() => {
            this.startKernel(fd, xrayConfig);
          }).catch((err: Error) => {
            this.log('protectProcessNet failed: ' + JSON.stringify(err));
            this.startKernel(fd, xrayConfig);
          });
        } else {
          this.startKernel(fd, xrayConfig);
        }
      }
    }).catch((err: Error) => {
      this.log('vpn create failed: ' + JSON.stringify(err));
    });
  }

  private startKernel(fd: number, xrayConfig: string): void {
    let code: number = testNapi.startVpnTun(fd, xrayConfig, this.context.filesDir + '/geo');
    this.log('startVpnTun code=' + code.toString() + ' lastErr=' + testNapi.getLastError());
  }
}
