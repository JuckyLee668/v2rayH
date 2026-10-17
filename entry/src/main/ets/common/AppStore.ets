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

  dirPath(): string {
    return this.dir;
  }

  exists(name: string): boolean {
    try {
      return fs.accessSync(this.dir + '/' + name);
    } catch (e) {
      return false;
    }
  }

  sizeOf(name: string): number {
    try {
      let path = this.dir + '/' + name;
      if (!fs.accessSync(path)) {
        return 0;
      }
      return fs.statSync(path).size;
    } catch (e) {
      return 0;
    }
  }

  mtimeOf(name: string): number {
    try {
      let path = this.dir + '/' + name;
      if (!fs.accessSync(path)) {
        return 0;
      }
      return fs.statSync(path).mtime * 1000;
    } catch (e) {
      return 0;
    }
  }

  readText(name: string): string {
    try {
      let path = this.dir + '/' + name;
      if (!fs.accessSync(path)) {
        return '';
      }
      let stat = fs.statSync(path);
      if (stat.size === 0) {
        return '';
      }
      let f = fs.openSync(path, fs.OpenMode.READ_ONLY);
      let buf = new ArrayBuffer(stat.size);
      fs.readSync(f.fd, buf);
      fs.closeSync(f);
      return buffer.from(buf).toString('utf-8');
    } catch (e) {
      console.error('readText failed: ' + name + ' ' + JSON.stringify(e));
      return '';
    }
  }

  writeText(name: string, text: string): boolean {
    try {
      let f = fs.openSync(this.dir + '/' + name, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(f.fd, text);
      fs.closeSync(f);
      return true;
    } catch (e) {
      console.error('writeText failed: ' + name + ' ' + JSON.stringify(e));
      return false;
    }
  }

  writeBytesTo(path: string, data: ArrayBuffer): boolean {
    try {
      let f = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(f.fd, data);
      fs.closeSync(f);
      return true;
    } catch (e) {
      console.error('writeBytes failed: ' + path + ' ' + JSON.stringify(e));
      return false;
    }
  }
}
