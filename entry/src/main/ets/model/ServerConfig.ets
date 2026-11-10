export class ServerConfig {
  name: string = '';
  protocol: string = '';
  address: string = '';
  port: number = 0;
  uuid: string = '';
  username: string = '';
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
  // mKCP 加密种子
  seed: string = '';
  // VMess 加密方式（auto / none / zero / aes-128-gcm / chacha20-poly1305 / aes-256-gcm）
  scy: string = '';
  // TUIC 拥塞控制算法（bbr / cubic / new_reno）
  congestionControl: string = '';
}
