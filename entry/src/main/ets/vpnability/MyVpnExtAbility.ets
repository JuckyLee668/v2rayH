import { VpnExtensionAbility, vpnExtension } from '@kit.NetworkKit';
import { Want } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { buffer } from '@kit.ArkTS';
import testNapi from 'libentry.so';

const SELF_BUNDLE: string = 'com.xii.v2rayh';

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

  onCreate(want: Want): void {
    try {
      this.logFile = this.context.filesDir + '/vpn.log';
      this.configFile = this.context.filesDir + '/xray_config.json';
    } catch (e) {
      this.logFile = '';
    }
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
      mtu: 1400,
      blockedApplications: [SELF_BUNDLE]
    };

    this.log('calling create(config)');
    this.vpnConnection.create(config).then((fd: number) => {
      this.log('vpn create success, fd=' + fd.toString());
      let conn = this.vpnConnection;
      if (conn) {
        conn.protectProcessNet().then(() => {
          let code: number = testNapi.startVpnTun(fd, xrayConfig, this.context.filesDir + '/geo');
          this.log('startVpnTun code=' + code.toString() + ' lastErr=' + testNapi.getLastError());
        }).catch((err: Error) => {
          this.log('protectProcessNet failed: ' + JSON.stringify(err));
          let code: number = testNapi.startVpnTun(fd, xrayConfig, this.context.filesDir + '/geo');
          this.log('startVpnTun(after protect fail) code=' + code.toString());
        });
      }
    }).catch((err: Error) => {
      this.log('vpn create failed: ' + JSON.stringify(err));
    });
  }
}
