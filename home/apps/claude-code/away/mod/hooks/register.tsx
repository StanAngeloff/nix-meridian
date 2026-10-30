import { atom, read } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { WaitingPrompt } from '../types'

// Away mode for one session. /away pins a status line, and every permission prompt, question or plan approval that opens while it is on
// counts down on its tool row, which stays on screen above the dialog.
// The deny itself comes from the claude-away PermissionRequest command hook (../../claude-away.sh), which waits out the timeout this mod
// leaves in the session's environment and then denies. A session with away mode off leaves nothing there, and the hook passes at once.
// The handoff can't go through the hook's input: Claude Code's built-in sec-default plugin, seated on Team and Enterprise logins and on
// machines with managed settings, sends every classic.* event past the plugins a person installs, this one included.

const DEFAULT_MINUTES = 5
const MAXIMUM_MINUTES = 60

// 0 while away mode is off.
const promptTimeoutMs = atom({ plugin: 'away', key: 'promptTimeoutMs' } as const, 0)
// A copy of `waiting` below, for the tool rows to draw from.
const waitingPrompts = atom({ plugin: 'away', key: 'waitingPrompts' } as const, [])
// The ticker's clock: written every second while a prompt waits, so the rows that read it redraw.
const now = atom({ plugin: 'away', key: 'now' } as const, 0)

type Timer = ReturnType<EngineInterface['clock']['every']>

// The prompts counting down, kept here rather than read back from $.state: every $.state.get of one dispatch reads one moment,
// so the ticker, which lives as long as a prompt waits, would never see /away off.
let waiting: WaitingPrompt[] = []
let ticker: Timer | undefined

function formatDuration(milliseconds: number): string {
  const totalSeconds = Math.max(0, Math.ceil(milliseconds / 1000))
  const minutes = Math.floor(totalSeconds / 60)
  const seconds = totalSeconds % 60

  return `${minutes}:${String(seconds).padStart(2, '0')}`
}

function countdownText(prompt: WaitingPrompt, currentTime: number): string {
  const remainingMs = prompt.deadline - currentTime

  return remainingMs > 0 ? `away: denied in ${formatDuration(remainingMs)} unless you answer` : 'away: no answer, denying'
}

// Leaves the timeout for the claude-away hooks this session starts, or takes it back with undefined; the session id keeps a claude
// started from the Bash tool, which inherits the variable, out of it. Resolves with why the engine refused, if it did.
async function handOver($: EngineInterface, away: { sessionId: string; timeoutMs: number } | undefined): Promise<string | undefined> {
  const value = away === undefined ? undefined : JSON.stringify({ session_id: away.sessionId, timeout_seconds: away.timeoutMs / 1000 })
  const result = await $.env.set('CLAUDE_AWAY', value).catch((error: unknown) => ({
    deny: error instanceof Error ? error.message : String(error),
  }))

  return result.deny
}

function showStatus($: EngineInterface, timeoutMs: number): void {
  $.ui.status(timeoutMs === 0 ? undefined : `AWAY · unanswered prompts are denied after ${formatDuration(timeoutMs)} · /away off`)
}

async function appendNote($: EngineInterface, text: string): Promise<void> {
  await $.session.append({ message: { type: 'user', content: [{ type: 'text', text }] } })
}

async function tick($: EngineInterface): Promise<void> {
  if (waiting.length === 0) {
    stopTicker()
    return
  }
  await $.state.set({ plugin: 'away', key: 'now' }, await $.clock.now())
}

function startTicker($: EngineInterface): void {
  ticker ??= $.clock.every(1000, () => {
    void tick($).catch(stopTicker)
  })
}

function stopTicker(): void {
  ticker?.cancel()
  ticker = undefined
}

async function setWaiting($: EngineInterface, prompts: WaitingPrompt[]): Promise<void> {
  waiting = prompts
  await $.state.set({ plugin: 'away', key: 'waitingPrompts' }, prompts)
}

function isWaiting(toolUseId: string): boolean {
  return waiting.some(prompt => prompt.toolUseId === toolUseId)
}

async function forgetPrompt($: EngineInterface, toolUseId: string): Promise<void> {
  if (isWaiting(toolUseId)) {
    await setWaiting($, waiting.filter(prompt => prompt.toolUseId !== toolUseId))
  }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'away',
      description: 'Away mode: unanswered prompts are denied after a timeout (default 5 minutes)',
      argumentHint: '[minutes|off]',
      immediate: true,
    })
    showStatus($, await read($, promptTimeoutMs))

    return next(e)
  })

  on('command.run', { command: 'away' }, async ($, e) => {
    const argument = e.args.trim()

    if (argument === 'off') {
      const wasAway = (await read($, promptTimeoutMs)) > 0
      await handOver($, undefined)
      await $.state.set({ plugin: 'away', key: 'promptTimeoutMs' }, 0)
      // A prompt still on screen loses its countdown here, but its hook started with the timeout and still denies at the deadline.
      await setWaiting($, [])
      stopTicker()
      showStatus($, 0)
      if (!wasAway) {
        return { text: 'Away mode was not on.' }
      }
      await appendNote($, 'The user is back: away mode is off, and permission prompts wait for an answer again.')

      return { text: 'Away mode is off.' }
    }

    const minutes = argument === '' ? DEFAULT_MINUTES : Number(argument)
    // The hook waits in whole seconds.
    const timeoutMs = Math.round(minutes * 60) * 1000
    if (!Number.isFinite(minutes) || timeoutMs < 1000 || minutes > MAXIMUM_MINUTES) {
      return { text: `Usage: /away [minutes, up to ${MAXIMUM_MINUTES}; ${DEFAULT_MINUTES} when left out] or /away off` }
    }
    const refusal = await handOver($, { sessionId: await $.session.id(), timeoutMs })
    if (refusal !== undefined) {
      return { text: `Away mode was not changed: the claude-away hook can't be told the timeout (${refusal}).` }
    }
    await $.state.set({ plugin: 'away', key: 'promptTimeoutMs' }, timeoutMs)
    showStatus($, timeoutMs)
    await appendNote(
      $,
      `The user has stepped away (away mode). Any permission prompt, question or plan approval nobody answers within ` +
        `${formatDuration(timeoutMs)} is denied automatically. Prefer approaches that need no approval, and collect what needs ` +
        `the user's sign-off to list when you finish.`,
    )

    return { text: `Away mode is on: unanswered prompts are denied after ${formatDuration(timeoutMs)}.` }
  })

  // The waiting call's tool row stays on screen above its dialog: draw the engine's row with the countdown under it.
  on('ui.render', { component: 'ToolUse' }, async ($, e, next) => {
    const prompt = (await read($, waitingPrompts)).find(waiting => waiting.toolUseId === e.requestId)
    // isRunning turns true the moment the person approves: from then on the row is the command's, not the prompt's.
    if (prompt === undefined || e.props.isRunning) {
      return next(e)
    }
    const currentTime = await read($, now)
    const drawing = await next(e)
    const { Box, Text } = $.ui.resolve(e)

    return (
      <Box flexDirection="column">
        {drawing}
        <Text color="warning">  {countdownText(prompt, currentTime)}</Text>
      </Box>
    )
  })

  // A call about to ask: its dialog opens and the claude-away hook starts beside it, so the countdown starts now.
  on('tool.check', async ($, e, next) => {
    const verdict = await next(e)
    const timeoutMs = await read($, promptTimeoutMs)
    if (verdict.decision === 'ask' && e.tool_use_id !== undefined && timeoutMs > 0 && !isWaiting(e.tool_use_id)) {
      const deadline = (await $.clock.now()) + timeoutMs
      await setWaiting($, [...waiting, { toolUseId: e.tool_use_id, tool: e.tool, deadline }])
      startTicker($)
      await tick($)
    }

    return verdict
  }).catch(($, e, next) => next(e))

  // The call has ended (answered, denied or run): its countdown is over, even while the hook still waits.
  on('tool.call', async ($, e, next) => {
    try {
      return await next(e)
    } finally {
      await forgetPrompt($, e.tool_use_id)
    }
  }).catch(($, e, next) => next(e))

  // /clear and /resume carry on in this process under another session id, whose state starts over; the pinned status line and the
  // variable the hook reads would stay.
  on('session.end', async ($, e, next) => {
    $.ui.status(undefined)
    waiting = []
    stopTicker()
    await handOver($, undefined)

    return next(e)
  })
}
