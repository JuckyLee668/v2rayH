import { ServerConfig } from '../model/ServerConfig';

function q(s: string): string {
  let r = s.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
  return '"' + r + '"';
}

export function usesSingboxKernel(s: ServerConfig): boolean {
  if (s.kernel === 'singbox') {
    return true;
  }
  if (s.kernel === 'xray') {
    return false;
  }
  return s.protocol === 'hy2' || s.protocol === 'tuic';
}

function tlsFields(s: ServerConfig): string[] {
  let parts: string[] = [];
  if (s.sni.length > 0) {
    parts.push(q('server_name') + ':' + q(s.sni));
  }
  if (s.insecure) {
    parts.push(q('insecure') + ':true');
  }
  if (s.alpn.length > 0) {
    let items: string[] = [];
    let raw = s.alpn.split(',');
    for (let i = 0; i < raw.length; i++) {
      let t = raw[i].trim();
      if (t.length > 0) {
        items.push(q(t));
      }
    }
    if (items.length > 0) {
      parts.push(q('alpn') + ':[' + items.join(',') + ']');
    }
  }
  if (s.fp.length > 0) {
    parts.push(q('utls') + ':{' + q('enabled') + ':true,' + q('fingerprint') + ':' + q(s.fp) + '}');
  }
  if (s.security === 'reality') {
    let fp = s.fp.length > 0 ? s.fp : 'chrome';
    parts.push(q('utls') + ':{' + q('enabled') + ':true,' + q('fingerprint') + ':' + q(fp) + '}');
    parts.push(q('reality') + ':{' + q('enabled') + ':true,' + q('public_key') + ':' + q(s.pbk)
      + ',' + q('short_id') + ':' + q(s.sid) + '}');
  }
  return parts;
}

function buildTls(s: ServerConfig): string {
  let fields = tlsFields(s);
  return '{' + q('enabled') + ':true' + (fields.length > 0 ? ',' + fields.join(',') : '') + '}';
}

function buildTransport(s: ServerConfig): string {
  let net = s.network.length > 0 ? s.network : 'tcp';
  if (net === 'ws') {
    let ws = q('type') + ':' + q('ws');
    ws += ',' + q('path') + ':' + q(s.path.length > 0 ? s.path : '/');
    if (s.host.length > 0) {
      ws += ',' + q('headers') + ':{' + q('Host') + ':' + q(s.host) + '}';
    }
    return '{' + ws + '}';
  }
  if (net === 'grpc') {
    return '{' + q('type') + ':' + q('grpc') + ',' + q('service_name') + ':' + q(s.path) + '}';
  }
  return '';
}

function buildProxyOutbound(s: ServerConfig): string {
  let parts: string[] = [];
  parts.push(q('tag') + ':' + q('proxy'));
  if (s.protocol === 'hy2') {
    parts.push(q('type') + ':' + q('hysteria2'));
    parts.push(q('server') + ':' + q(s.address));
    parts.push(q('server_port') + ':' + s.port.toString());
    if (s.password.length > 0) {
      parts.push(q('password') + ':' + q(s.password));
    }
    if (s.ports.length > 0) {
      let items: string[] = [];
      let raw = s.ports.split(',');
      for (let i = 0; i < raw.length; i++) {
        let t = raw[i].trim();
        if (t.length > 0) {
          items.push(q(t.replace(/-/g, ':')));
        }
      }
      if (items.length > 0) {
        parts.push(q('server_ports') + ':[' + items.join(',') + ']');
      }
    }
    if (s.obfs.length > 0) {
      let ob = '{' + q('type') + ':' + q(s.obfs);
      if (s.obfsPassword.length > 0) {
        ob += ',' + q('password') + ':' + q(s.obfsPassword);
      }
      ob += '}';
      parts.push(q('obfs') + ':' + ob);
    }
    parts.push(q('tls') + ':' + buildTls(s));
  } else if (s.protocol === 'tuic') {
    parts.push(q('type') + ':' + q('tuic'));
    parts.push(q('server') + ':' + q(s.address));
    parts.push(q('server_port') + ':' + s.port.toString());
    parts.push(q('uuid') + ':' + q(s.uuid));
    if (s.password.length > 0) {
      parts.push(q('password') + ':' + q(s.password));
    }
    parts.push(q('congestion_control') + ':' + q('bbr'));
    let tlsFieldsJson = tlsFields(s);
    if (s.alpn.length === 0) {
      tlsFieldsJson.push(q('alpn') + ':[' + q('h3') + ']');
    }
    parts.push(q('tls') + ':{' + q('enabled') + ':true'
      + (tlsFieldsJson.length > 0 ? ',' + tlsFieldsJson.join(',') : '') + '}');
  } else if (s.protocol === 'vless') {
    parts.push(q('type') + ':' + q('vless'));
    parts.push(q('server') + ':' + q(s.address));
    parts.push(q('server_port') + ':' + s.port.toString());
    parts.push(q('uuid') + ':' + q(s.uuid));
    if (s.flow.length > 0) {
      parts.push(q('flow') + ':' + q(s.flow));
    }
  } else if (s.protocol === 'vmess') {
    parts.push(q('type') + ':' + q('vmess'));
    parts.push(q('server') + ':' + q(s.address));
    parts.push(q('server_port') + ':' + s.port.toString());
    parts.push(q('uuid') + ':' + q(s.uuid));
    parts.push(q('security') + ':' + q('auto'));
    parts.push(q('alter_id') + ':' + s.alterId.toString());
  } else if (s.protocol === 'trojan') {
    parts.push(q('type') + ':' + q('trojan'));
    parts.push(q('server') + ':' + q(s.address));
    parts.push(q('server_port') + ':' + s.port.toString());
    parts.push(q('password') + ':' + q(s.password));
  } else if (s.protocol === 'shadowsocks') {
    parts.push(q('type') + ':' + q('shadowsocks'));
    parts.push(q('server') + ':' + q(s.address));
    parts.push(q('server_port') + ':' + s.port.toString());
    parts.push(q('method') + ':' + q(s.method.length > 0 ? s.method : 'aes-128-gcm'));
    parts.push(q('password') + ':' + q(s.password));
  }
  if (s.protocol !== 'hy2' && s.protocol !== 'tuic') {
    if (s.security === 'tls' || s.security === 'reality') {
      parts.push(q('tls') + ':' + buildTls(s));
    }
    let transport = buildTransport(s);
    if (transport.length > 0) {
      parts.push(q('transport') + ':' + transport);
    }
  }
  return '{' + parts.join(',') + '}';
}

export const VPN_SINGBOX_PORT: number = 10810;
export const TEST_SINGBOX_PORT: number = 10812;

function buildFullConfig(s: ServerConfig, listenPort: number): string {
  let log = '{' + q('level') + ':' + q('warn') + '}';
  let dnsServer = '{' + q('type') + ':' + q('local') + ',' + q('tag') + ':' + q('dns-local') + '}';
  let dns = '{' + q('servers') + ':[' + dnsServer + ']}';
  let inbound = '{' + q('type') + ':' + q('mixed') + ',' + q('tag') + ':' + q('in-mixed') + ','
    + q('listen') + ':' + q('127.0.0.1') + ',' + q('listen_port') + ':' + listenPort.toString() + '}';
  let outbounds = buildProxyOutbound(s) + ',{' + q('type') + ':' + q('direct') + ',' + q('tag') + ':' + q('direct') + '}';
  let route = '{' + q('final') + ':' + q('proxy') + ','
    + q('default_domain_resolver') + ':{' + q('server') + ':' + q('dns-local') + '}}';
  return '{' + q('log') + ':' + log + ',' + q('dns') + ':' + dns + ',' + q('inbounds') + ':[' + inbound + ']'
    + ',' + q('outbounds') + ':[' + outbounds + ']' + ',' + q('route') + ':' + route + '}';
}

export function buildVpnSingboxConfig(s: ServerConfig): string {
  return buildFullConfig(s, VPN_SINGBOX_PORT);
}

export function buildTestSingboxConfig(s: ServerConfig): string {
  return buildFullConfig(s, TEST_SINGBOX_PORT);
}
