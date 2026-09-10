/**
 * SSH 会话类型（与实现解耦，避免 Native ↔ Mock 循环依赖）
 */
import { HostConfig } from '../../models/HostConfig';

export interface ISshSession {
  connect(host: HostConfig): Promise<void>;
  disconnect(): Promise<void>;
  send(command: string): Promise<void>;
  isConnected(): boolean;
  getOutput(): string;
  onOutput(listener: (chunk: string) => void): void;
  clearOutput(): void;
}

export enum SshSessionState {
  Idle = 'idle',
  Connecting = 'connecting',
  Connected = 'connected',
  Disconnected = 'disconnected',
  Error = 'error'
}
