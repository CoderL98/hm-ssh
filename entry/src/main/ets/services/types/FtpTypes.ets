import { HostConfig } from '../../models/HostConfig';

export interface FtpEntry {
  name: string;
  path: string;
  isDirectory: boolean;
  size: number;
  modifiedAt: number;
}

export enum FtpSessionState {
  Idle = 'idle',
  Connecting = 'connecting',
  Connected = 'connected',
  Disconnected = 'disconnected',
  Error = 'error'
}

export interface IFtpSession {
  connect(host: HostConfig): Promise<void>;
  disconnect(): Promise<void>;
  isConnected(): boolean;
  getCwd(): string;
  list(): Promise<FtpEntry[]>;
  cd(path: string): Promise<void>;
  download(remotePath: string): Promise<string>;
  upload(remotePath: string, content: string): Promise<void>;
  getStatusMessage(): string;
  onStatus(listener: (msg: string) => void): void;
}
