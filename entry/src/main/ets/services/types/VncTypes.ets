import { HostConfig } from '../../models/HostConfig';

export enum VncSessionState {
  Idle = 'idle',
  Connecting = 'connecting',
  Connected = 'connected',
  Disconnected = 'disconnected',
  Error = 'error'
}

export interface VncFramebufferInfo {
  width: number;
  height: number;
  placeholderColor: string;
  label: string;
  hasPixelBuffer?: boolean;
}

export interface IVncSession {
  connect(host: HostConfig): Promise<void>;
  disconnect(): Promise<void>;
  isConnected(): boolean;
  getFramebuffer(): VncFramebufferInfo | null;
  sendPointer(x: number, y: number, buttons: number): void;
  sendKey(keysym: number, down: boolean): void;
  getStatusMessage(): string;
  onStatus(listener: (msg: string) => void): void;
}
