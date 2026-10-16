import { buffer } from '@kit.ArkTS';
import { ServerConfig } from '../model/ServerConfig';

interface VmessJson {
  ps?: string;
  add?: string;
  port?: string;
  id?: string;
  aid?: string;
  scy?: string;
  net?: string;
  type?: string;
  host?: string;
  path?: string;
  tls?: string;
  sni?: string;
  fp?: string;
}

function b64Decode(input: string): string {
  let clean = input.replace(/-/g, '+').replace(/_/g, '/');
  let pad = clean.length % 4;
  if (pad === 2) {
    clean += '==';
  } else if (pad === 3) {
    clean += '=';
  }
  try {
    return buffer.from(clean, 'base64').toString('utf-8');
  } catch (e) {
    return '';
  }
}

function getParam(query: string, key: string): string {
  if (query.length === 0) {
    return '';
  }
  let parts = query.split('&');
  for (let i = 0; i < parts.length; i++) {
    let eq = parts[i].indexOf('=');
    if (eq > 0 && parts[i].substring(0, eq) === key) {
      return decodeURIComponent(parts[i].substring(eq + 1));
    }
  }
  return '';
}

function splitName(link: string, schemeLen: number): string[] {
  let body = link.substring(schemeLen);
  let name = '';
  let hashIdx = body.indexOf('#');
  if (hashIdx >= 0) {
    name = decodeURIComponent(body.substring(hashIdx + 1));
    body = body.substring(0, hashIdx);
  }
  let query = '';
  let qIdx = body.indexOf('?');
  if (qIdx >= 0) {
    query = body.substring(qIdx + 1);
    body = body.substring(0, qIdx);
  }
  return [body, query, name];
}

function parseHostPort(hp: string): string[] {
  let colonIdx = hp.lastIndexOf(':');
  if (colonIdx < 0) {
    return ['', '0'];
  }
  return [hp.substring(0, colonIdx), hp.substring(colonIdx + 1)];
}

function parseVless(link: string): ServerConfig | undefined {
  let parts = splitName(link, 'vless://'.length);
  let atIdx = parts[0].lastIndexOf('@');
  if (atIdx < 0) {
    return undefined;
  }
  let s = new ServerConfig();
  s.protocol = 'vless';
  s.uuid = parts[0].substring(0, atIdx);
  let hp = parseHostPort(parts[0].substring(atIdx + 1));
  s.address = hp[0];
  s.port = parseInt(hp[1], 10);
  s.name = parts[2].length > 0 ? parts[2] : (s.address + ':' + s.port.toString());
  s.flow = getParam(parts[1], 'flow');
  s.security = getParam(parts[1], 'security');
  if (s.security.length === 0) { s.security = 'none'; }
  s.sni = getParam(parts[1], 'sni');
  s.fp = getParam(parts[1], 'fp');
  s.pbk = getParam(parts[1], 'pbk');
  s.sid = getParam(parts[1], 'sid');
  let spx = getParam(parts[1], 'spx');
  s.spx = spx.length > 0 ? spx : '/';
  s.network = getParam(parts[1], 'type');
  if (s.network.length === 0) { s.network = 'tcp'; }
  s.headerType = getParam(parts[1], 'headerType');
  if (s.headerType.length === 0) { s.headerType = 'none'; }
  s.path = getParam(parts[1], 'path');
  s.host = getParam(parts[1], 'host');
  return s;
}

function parseVmess(link: string): ServerConfig | undefined {
  let json = b64Decode(link.substring('vmess://'.length));
  if (json.length === 0) {
    return undefined;
  }
  let v = JSON.parse(json) as VmessJson;
  let s = new ServerConfig();
  s.protocol = 'vmess';
  s.name = v.ps ? v.ps : (v.add ? v.add : 'vmess');
  s.address = v.add ? v.add : '';
  s.port = v.port ? parseInt(v.port, 10) : 0;
  s.uuid = v.id ? v.id : '';
  s.alterId = v.aid ? parseInt(v.aid, 10) : 0;
  s.network = v.net ? v.net : 'tcp';
  s.headerType = v.type ? v.type : 'none';
  s.host = v.host ? v.host : '';
  s.path = v.path ? v.path : '';
  s.sni = v.sni ? v.sni : '';
  s.fp = v.fp ? v.fp : '';
  s.security = (v.tls && v.tls.length > 0) ? 'tls' : 'none';
  return s;
}

function parseTrojan(link: string): ServerConfig | undefined {
  let parts = splitName(link, 'trojan://'.length);
  let atIdx = parts[0].lastIndexOf('@');
  if (atIdx < 0) {
    return undefined;
  }
  let s = new ServerConfig();
  s.protocol = 'trojan';
  s.password = decodeURIComponent(parts[0].substring(0, atIdx));
  let hp = parseHostPort(parts[0].substring(atIdx + 1));
  s.address = hp[0];
  s.port = parseInt(hp[1], 10);
  s.name = parts[2].length > 0 ? parts[2] : (s.address + ':' + s.port.toString());
  s.security = getParam(parts[1], 'security');
  if (s.security.length === 0) { s.security = 'tls'; }
  s.sni = getParam(parts[1], 'sni');
  s.fp = getParam(parts[1], 'fp');
  s.network = getParam(parts[1], 'type');
  if (s.network.length === 0) { s.network = 'tcp'; }
  s.path = getParam(parts[1], 'path');
  s.host = getParam(parts[1], 'host');
  return s;
}

function parseSs(link: string): ServerConfig | undefined {
  let s = new ServerConfig();
  s.protocol = 'shadowsocks';
  let body = link.substring('ss://'.length);
  let hashIdx = body.indexOf('#');
  if (hashIdx >= 0) {
    s.name = decodeURIComponent(body.substring(hashIdx + 1));
    body = body.substring(0, hashIdx);
  }
  let atIdx = body.lastIndexOf('@');
  let methodPwd = '';
  let hpStr = '';
  if (atIdx >= 0) {
    methodPwd = b64Decode(body.substring(0, atIdx));
    hpStr = body.substring(atIdx + 1);
  } else {
    let decoded = b64Decode(body);
    let at = decoded.lastIndexOf('@');
    if (at < 0) {
      return undefined;
    }
    methodPwd = decoded.substring(0, at);
    hpStr = decoded.substring(at + 1);
  }
  let mc = methodPwd.indexOf(':');
  s.method = mc >= 0 ? methodPwd.substring(0, mc) : methodPwd;
  s.password = mc >= 0 ? methodPwd.substring(mc + 1) : '';
  let hp = parseHostPort(hpStr);
  s.address = hp[0];
  s.port = parseInt(hp[1], 10);
  if (s.name.length === 0) {
    s.name = s.address + ':' + s.port.toString();
  }
  return s;
}

export function parseShareLink(link: string): ServerConfig | undefined {
  let l = link.trim();
  if (l.startsWith('vless://')) {
    return parseVless(l);
  }
  if (l.startsWith('vmess://')) {
    return parseVmess(l);
  }
  if (l.startsWith('trojan://')) {
    return parseTrojan(l);
  }
  if (l.startsWith('ss://')) {
    return parseSs(l);
  }
  return undefined;
}

export function parseSubscription(content: string): ServerConfig[] {
  let text = content;
  if (text.indexOf('://') < 0) {
    text = b64Decode(content);
  }
  let result: ServerConfig[] = [];
  let lines = text.split('\n');
  for (let i = 0; i < lines.length; i++) {
    let s = parseShareLink(lines[i]);
    if (s !== undefined) {
      result.push(s);
    }
  }
  return result;
}
