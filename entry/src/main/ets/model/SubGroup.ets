import { ServerConfig } from './ServerConfig';

export class SubGroup {
  id: string = '';
  name: string = '';
  url: string = '';
  updatedAt: number = 0;
  nodes: ServerConfig[] = [];
  upload: number = 0;
  download: number = 0;
  total: number = 0;
  expire: number = 0;

  constructor(id: string, name: string, url: string) {
    this.id = id;
    this.name = name;
    this.url = url;
  }
}

export class SubUserinfo {
  upload: number = 0;
  download: number = 0;
  total: number = 0;
  expire: number = 0;
}
