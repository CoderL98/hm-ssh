export interface NativeConnectParams {
  host: string;
  port: number;
  username: string;
  password?: string;
  privateKey?: string;
  /** SSH: optional OpenSSH known_hosts file path */
  knownHostsPath?: string;
  /** FTP: request explicit FTPS (AUTH TLS); errors clearly if TLS not linked */
  useTls?: boolean;
}

export interface NativeConnectResult {
  ok: boolean;
  error: string;
  id: number;
  /** SSH: recorded host key fingerprint (stub/SHA256-stub) for UI confirm */
  hostKeyFingerprint?: string;
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

export declare function nativeAvailable(): boolean;
export declare function sshLibAvailable(): boolean;
export declare function sshConnect(params: NativeConnectParams): NativeConnectResult;
export declare function sshDisconnect(id: number): boolean;
export declare function sshSend(id: number, data: string): string;
export declare function sshRead(id: number, maxBytes?: number): string;
export declare function sshResize(id: number, cols: number, rows: number): string;
export declare function ftpConnect(params: NativeConnectParams): NativeConnectResult;
export declare function ftpDisconnect(id: number): boolean;
export declare function ftpCd(id: number, path: string): string;
export declare function ftpCwd(id: number): string;
export declare function ftpList(id: number): NativeFtpListResult;
export declare function ftpRetr(id: number, remotePath: string, localPath: string): string;
export declare function ftpStor(id: number, remotePath: string, localPath: string): string;
export declare function vncConnect(params: NativeConnectParams): NativeConnectResult;
export declare function vncDisconnect(id: number): boolean;
export declare function vncFramebuffer(id: number): NativeVncFramebuffer;
export declare function vncPointerEvent(id: number, x: number, y: number, buttons: number): string;
export declare function vncKeyEvent(id: number, keysym: number, down: boolean): string;
