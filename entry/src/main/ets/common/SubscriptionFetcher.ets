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
}
