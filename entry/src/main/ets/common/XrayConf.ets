import { ServerConfig } from '../model/ServerConfig';

function q(s: string): string {
  let r = s.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
  return '"' + r + '"';
}

function buildStreamSettings(s: ServerConfig): string {
  let net = s.network.length > 0 ? s.network : 'tcp';
  let parts: string[] = [];
  parts.push(q('network') + ':' + q(net));

  if (net === 'ws') {
    let ws = '{';
    ws += q('path') + ':' + q(s.path.length > 0 ? s.path : '/');
    if (s.host.length > 0) {
      ws += ',' + q('headers') + ':{' + q('Host') + ':' + q(s.host) + '}';
    }
    ws += '}';
    parts.push(q('wsSettings') + ':' + ws);
  } else if (net === 'grpc') {
    parts.push(q('grpcSettings') + ':{' + q('serviceName') + ':' + q(s.path) + '}');
  }

  if (s.security === 'reality') {
    let rs = '{';
    rs += q('serverName') + ':' + q(s.sni);
    rs += ',' + q('fingerprint') + ':' + q(s.fp.length > 0 ? s.fp : 'chrome');
    rs += ',' + q('publicKey') + ':' + q(s.pbk);
    rs += ',' + q('shortId') + ':' + q(s.sid);
    rs += ',' + q('spiderX') + ':' + q(s.spx);
    rs += '}';
    parts.push(q('security') + ':' + q('reality'));
    parts.push(q('realitySettings') + ':' + rs);
  } else if (s.security === 'tls') {
    let ts = '{';
    ts += q('serverName') + ':' + q(s.sni);
    if (s.fp.length > 0) {
      ts += ',' + q('fingerprint') + ':' + q(s.fp);
    }
    ts += '}';
    parts.push(q('security') + ':' + q('tls'));
    parts.push(q('tlsSettings') + ':' + ts);
  }

  return '{' + parts.join(',') + '}';
}

function buildProxyOutbound(s: ServerConfig): string {
  let stream = buildStreamSettings(s);
  let body = '';
  if (s.protocol === 'vless') {
    let user = '{' + q('id') + ':' + q(s.uuid) + ',' + q('encryption') + ':' + q('none');
    if (s.flow.length > 0) {
      user += ',' + q('flow') + ':' + q(s.flow);
    }
    user += '}';
    let vnext = '{' + q('address') + ':' + q(s.address) + ',' + q('port') + ':' + s.port.toString() + ',' + q('users') + ':[' + user + ']}';
    body = '{' + q('protocol') + ':' + q('vless') + ',' + q('settings') + ':{' + q('vnext') + ':[' + vnext + ']},' + q('streamSettings') + ':' + stream + '}';
  } else if (s.protocol === 'vmess') {
    let user = '{' + q('id') + ':' + q(s.uuid) + ',' + q('alterId') + ':' + s.alterId.toString() + ',' + q('security') + ':' + q('auto') + '}';
    let vnext = '{' + q('address') + ':' + q(s.address) + ',' + q('port') + ':' + s.port.toString() + ',' + q('users') + ':[' + user + ']}';
    body = '{' + q('protocol') + ':' + q('vmess') + ',' + q('settings') + ':{' + q('vnext') + ':[' + vnext + ']},' + q('streamSettings') + ':' + stream + '}';
  } else if (s.protocol === 'trojan') {
    let server = '{' + q('address') + ':' + q(s.address) + ',' + q('port') + ':' + s.port.toString() + ',' + q('password') + ':' + q(s.password) + '}';
    body = '{' + q('protocol') + ':' + q('trojan') + ',' + q('settings') + ':{' + q('servers') + ':[' + server + ']},' + q('streamSettings') + ':' + stream + '}';
  } else if (s.protocol === 'shadowsocks') {
    let server = '{' + q('address') + ':' + q(s.address) + ',' + q('port') + ':' + s.port.toString() + ',' + q('method') + ':' + q(s.method) + ',' + q('password') + ':' + q(s.password) + '}';
    body = '{' + q('protocol') + ':' + q('shadowsocks') + ',' + q('settings') + ':{' + q('servers') + ':[' + server + ']}}';
  } else {
    body = '{' + q('protocol') + ':' + q('freedom') + '}';
  }
  return body.substring(0, body.length - 1) + ',' + q('tag') + ':' + q('proxy') + '}';
}

const TUN_INBOUND: string = '{"tag":"tun-in","protocol":"tun","settings":{"name":"vpn-tun","MTU":1400,"userLevel":0}}';
const DIRECT_OUTBOUND: string = '{"protocol":"freedom","tag":"direct"}';
const ROUTING: string = '{"domainStrategy":"IPIfNonMatch","rules":[{"type":"field","ip":["geoip:private"],"outboundTag":"direct"},{"type":"field","domain":["geosite:cn"],"outboundTag":"direct"},{"type":"field","ip":["geoip:cn"],"outboundTag":"direct"}]}';

export function buildTestConfig(server: ServerConfig): string {
  return '{' + q('outbounds') + ':[' + buildProxyOutbound(server) + ']}';
}

export function buildXrayConfig(server: ServerConfig, logErrorPath: string): string {
  let logCfg = '{' + q('loglevel') + ':' + q('warning');
  if (logErrorPath.length > 0) {
    logCfg += ',' + q('error') + ':' + q(logErrorPath);
  }
  logCfg += '}';
  return '{' + q('log') + ':' + logCfg
    + ',' + q('inbounds') + ':[' + TUN_INBOUND + ']'
    + ',' + q('outbounds') + ':[' + buildProxyOutbound(server) + ',' + DIRECT_OUTBOUND + ']'
    + ',' + q('routing') + ':' + ROUTING
    + '}';
}
