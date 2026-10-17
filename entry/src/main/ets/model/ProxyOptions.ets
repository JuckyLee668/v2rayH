import { SubGroup } from './SubGroup';

export class RoutingOptions {
  bypassCn: boolean = true;
  blockAds: boolean = true;
  directDomains: string[] = [];
  proxyDomains: string[] = [];
  domainStrategy: string = 'IPIfNonMatch';
}

export class GeoOptions {
  geositeUrl: string = 'https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/geosite.dat';
  geoipUrl: string = 'https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/geoip.dat';
  updatedAt: number = 0;
}

export class BackupPayload {
  version: number = 1;
  createdAt: number = 0;
  activeGroup: number = 0;
  selected: number = 0;
  groups: SubGroup[] = [];
  routing: RoutingOptions = new RoutingOptions();
  geo: GeoOptions = new GeoOptions();
}
