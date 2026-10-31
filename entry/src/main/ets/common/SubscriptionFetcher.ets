import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';

export class SubscriptionFetcher {
  static lastError: string = '';

  static async fetchText(url: string): Promise<string> {
    SubscriptionFetcher.lastError = '';
    let req = http.createHttp();
    try {
      let resp = await req.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 15000,
        header: { 'User-Agent': 'v2rayNG/1.0' } as Record<string, string>
      });
      if (resp.responseCode === 200) {
        let data: string | Object | ArrayBuffer = resp.result;
        if (typeof data === 'string') {
          return data;
        }
        SubscriptionFetcher.lastError = 'result type mismatch';
        return '';
      }
      SubscriptionFetcher.lastError = 'HTTP ' + resp.responseCode.toString();
      return '';
    } catch (e) {
      let err = e as BusinessError;
      SubscriptionFetcher.lastError = 'code=' + err.code.toString() + ' msg=' + err.message;
      return '';
    } finally {
      req.destroy();
    }
  }

  static async fetchThroughProxy(url: string, host: string, port: number,
    connectTimeoutMs: number = 5000, readTimeoutMs: number = 5000): Promise<string> {
    SubscriptionFetcher.lastError = '';
    let req = http.createHttp();
    let proxy: http.HttpProxy = { host: host, port: port, exclusionList: [] };
    try {
      let resp = await req.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: connectTimeoutMs,
        readTimeout: readTimeoutMs,
        usingProxy: proxy
      });
      if (resp.responseCode === 200) {
        let data: string | Object | ArrayBuffer = resp.result;
        if (typeof data === 'string') {
          return data;
        }
        SubscriptionFetcher.lastError = 'result type mismatch';
        return '';
      }
      SubscriptionFetcher.lastError = 'HTTP ' + resp.responseCode.toString();
      return '';
    } catch (e) {
      let err = e as BusinessError;
      SubscriptionFetcher.lastError = 'code=' + err.code.toString() + ' msg=' + err.message;
      return '';
    } finally {
      req.destroy();
    }
  }

  static async fetchBytesThroughProxy(url: string, host: string, port: number): Promise<ArrayBuffer | undefined> {
    SubscriptionFetcher.lastError = '';
    let req = http.createHttp();
    let proxy: http.HttpProxy = { host: host, port: port, exclusionList: [] };
    try {
      let resp = await req.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 30000,
        readTimeout: 120000,
        usingProxy: proxy
      });
      if (resp.responseCode !== 200) {
        SubscriptionFetcher.lastError = 'HTTP ' + resp.responseCode.toString();
        return undefined;
      }
      let data: string | Object | ArrayBuffer = resp.result;
      if (data instanceof ArrayBuffer) {
        return data;
      }
      SubscriptionFetcher.lastError = 'result type mismatch';
      return undefined;
    } catch (e) {
      let err = e as BusinessError;
      SubscriptionFetcher.lastError = 'code=' + err.code.toString() + ' msg=' + err.message;
      return undefined;
    } finally {
      req.destroy();
    }
  }

  static async fetchBytes(url: string): Promise<ArrayBuffer | undefined> {
    SubscriptionFetcher.lastError = '';
    let req = http.createHttp();
    try {
      let resp = await req.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 30000,
        readTimeout: 60000,
        header: { 'User-Agent': 'v2rayNG/1.0' } as Record<string, string>
      });
      if (resp.responseCode !== 200) {
        SubscriptionFetcher.lastError = 'HTTP ' + resp.responseCode.toString();
        return undefined;
      }
      let data: string | Object | ArrayBuffer = resp.result;
      if (data instanceof ArrayBuffer) {
        return data;
      }
      SubscriptionFetcher.lastError = 'result type mismatch';
      return undefined;
    } catch (e) {
      let err = e as BusinessError;
      SubscriptionFetcher.lastError = 'code=' + err.code.toString() + ' msg=' + err.message;
      return undefined;
    } finally {
      req.destroy();
    }
  }
}
