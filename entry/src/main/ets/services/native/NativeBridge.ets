/**
 * 动态加载 libhmssh_native.so。Cloud/未编译环境下 import 失败 → available=false。
 * 类型与 entry/src/main/cpp/types/libhmssh_native/Index.d.ts 对齐。
 */

export interface NativeConnectParams {
  host: string;
  port: number;
  username: string;
  password?: string;
  privateKey?: string;
}

export interface NativeConnectResult {
  ok: boolean;
  error: string;
  id: number;
}

export interface NativeFtpEntry {
  name: string;
  path: string;
  isDirectory: boolean;
  size: number;
  modifiedAt: number;
}

export interface NativeFtpListResult {
  error: string;
  entries: NativeFtpEntry[];
}

export interface NativeVncFramebuffer {
  error: string;
  width: number;
  height: number;
  rgba: ArrayBuffer;
}

export interface HmsshNativeModule {
  nativeAvailable(): boolean;
  sshLibAvailable(): boolean;
  sshConnect(params: NativeConnectParams): NativeConnectResult;
  sshDisconnect(id: number): boolean;
  sshSend(id: number, data: string): string;
  sshRead(id: number, maxBytes?: number): string;
  sshResize(id: number, cols: number, rows: number): string;
  ftpConnect(params: NativeConnectParams): NativeConnectResult;
  ftpDisconnect(id: number): boolean;
  ftpCd(id: number, path: string): string;
  ftpCwd(id: number): string;
  ftpList(id: number): NativeFtpListResult;
  ftpRetr(id: number, remotePath: string, localPath: string): string;
  ftpStor(id: number, remotePath: string, localPath: string): string;
  vncConnect(params: NativeConnectParams): NativeConnectResult;
  vncDisconnect(id: number): boolean;
  vncFramebuffer(id: number): NativeVncFramebuffer;
  vncPointerEvent(id: number, x: number, y: number, buttons: number): string;
  vncKeyEvent(id: number, keysym: number, down: boolean): string;
}

let cached: HmsshNativeModule | null = null;
let loadAttempted: boolean = false;
let loadError: string = '';

export function getNativeLoadError(): string {
  return loadError;
}

export function tryLoadNative(): HmsshNativeModule | null {
  if (loadAttempted) {
    return cached;
  }
  loadAttempted = true;
  try {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const mod = require('libhmssh_native.so') as HmsshNativeModule;
    if (mod && typeof mod.nativeAvailable === 'function' && mod.nativeAvailable()) {
      cached = mod;
      loadError = '';
      return cached;
    }
    loadError = 'nativeAvailable() 返回 false';
    cached = null;
    return null;
  } catch (e) {
    loadError = e instanceof Error ? e.message : `${e}`;
    cached = null;
    return null;
  }
}

export function isNativeModulePresent(): boolean {
  return tryLoadNative() !== null;
}
