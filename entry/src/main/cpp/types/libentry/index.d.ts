export const startXray: (config: string) => number;
export const stopXray: () => number;
export const isXrayRunning: () => number;
export const getLastError: () => string;
export const startVpnTun: (fd: number, config: string, assetDir: string) => number;
export const stopVpn: () => number;
export const measureDelay: (config: string, testUrl: string) => Promise<number>;
