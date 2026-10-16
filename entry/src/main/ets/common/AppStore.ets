import { fileIo as fs } from '@kit.CoreFileKit';
import { buffer } from '@kit.ArkTS';
import { ServerConfig } from '../model/ServerConfig';

const SERVERS_FILE = '/servers.json';
const CONFIG_FILE = '/xray_config.json';

export class AppStore {
  private dir: string = '';

  init(filesDir: string): void {
    this.dir = filesDir;
  }

  isReady(): boolean {
    return this.dir.length > 0;
  }

  saveServers(servers: ServerConfig[]): void {
    try {
      let f = fs.openSync(this.dir + SERVERS_FILE, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(f.fd, JSON.stringify(servers));
      fs.closeSync(f);
    } catch (e) {
      console.error('saveServers failed: ' + JSON.stringify(e));
    }
  }

  loadServers(): ServerConfig[] {
    try {
      let path = this.dir + SERVERS_FILE;
      if (!fs.accessSync(path)) {
        return [];
      }
      let stat = fs.statSync(path);
      if (stat.size === 0) {
        return [];
      }
      let f = fs.openSync(path, fs.OpenMode.READ_ONLY);
      let buf = new ArrayBuffer(stat.size);
      fs.readSync(f.fd, buf);
      fs.closeSync(f);
      let text = buffer.from(buf).toString('utf-8');
      return JSON.parse(text) as ServerConfig[];
    } catch (e) {
      console.error('loadServers failed: ' + JSON.stringify(e));
      return [];
    }
  }

  saveSelected(index: number): void {
    try {
      let f = fs.openSync(this.dir + '/selected.txt', fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(f.fd, index.toString());
      fs.closeSync(f);
    } catch (e) {
      console.error('saveSelected failed: ' + JSON.stringify(e));
    }
  }

  loadSelected(): number {
    try {
      let path = this.dir + '/selected.txt';
      if (!fs.accessSync(path)) {
        return 0;
      }
      let stat = fs.statSync(path);
      let f = fs.openSync(path, fs.OpenMode.READ_ONLY);
      let buf = new ArrayBuffer(stat.size);
      fs.readSync(f.fd, buf);
      fs.closeSync(f);
      let text = buffer.from(buf).toString('utf-8');
      return parseInt(text, 10);
    } catch (e) {
      return 0;
    }
  }

  saveXrayConfig(config: string): void {
    let f = fs.openSync(this.dir + CONFIG_FILE, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    fs.writeSync(f.fd, config);
    fs.closeSync(f);
  }

  saveSubscriptionUrl(url: string): void {
    try {
      let f = fs.openSync(this.dir + '/sub.txt', fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(f.fd, url);
      fs.closeSync(f);
    } catch (e) {
      console.error('saveSubscriptionUrl failed: ' + JSON.stringify(e));
    }
  }

  loadSubscriptionUrl(): string {
    try {
      let path = this.dir + '/sub.txt';
      if (!fs.accessSync(path)) {
        return '';
      }
      let stat = fs.statSync(path);
      let f = fs.openSync(path, fs.OpenMode.READ_ONLY);
      let buf = new ArrayBuffer(stat.size);
      fs.readSync(f.fd, buf);
      fs.closeSync(f);
      return buffer.from(buf).toString('utf-8');
    } catch (e) {
      return '';
    }
  }
}
