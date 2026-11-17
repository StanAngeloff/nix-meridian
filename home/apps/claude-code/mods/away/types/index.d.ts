export type WaitingPrompt = { toolUseId: string; tool: string; deadline: number }

declare module 'claude-code' {
  interface PluginState {
    away: { promptTimeoutMs: number; waitingPrompts: WaitingPrompt[]; now: number }
  }
}
