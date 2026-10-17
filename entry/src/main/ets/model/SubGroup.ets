import { ServerConfig } from './ServerConfig';

export class SubGroup {
  id: string = '';
  name: string = '';
  url: string = '';
  updatedAt: number = 0;
  nodes: ServerConfig[] = [];

  constructor(id: string, name: string, url: string) {
    this.id = id;
    this.name = name;
    this.url = url;
  }
}
