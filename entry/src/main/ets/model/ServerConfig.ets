export class ServerConfig {
  name: string = '';
  protocol: string = '';
  address: string = '';
  port: number = 0;
  uuid: string = '';
  password: string = '';
  method: string = '';
  alterId: number = 0;
  flow: string = '';
  security: string = 'none';
  sni: string = '';
  fp: string = '';
  pbk: string = '';
  sid: string = '';
  spx: string = '/';
  network: string = 'tcp';
  headerType: string = 'none';
  path: string = '';
  host: string = '';
  kernel: string = 'auto'; // 'auto' | 'xray' | 'singbox'
  obfs: string = '';
  obfsPassword: string = '';
  insecure: boolean = false;
  alpn: string = '';
  ports: string = '';
}
