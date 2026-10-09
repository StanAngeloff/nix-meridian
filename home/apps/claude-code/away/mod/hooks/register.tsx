import { atom, read } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { WaitingPrompt } from '../types'

// Away mode for one session. /away pins a status line, and every permission prompt, question or plan approval that opens while it is on
// counts down on its tool row, which stays on screen above the dialog.
// The deny itself comes from the claude-away PermissionRequest command hook (../../claude-away.sh), which waits out the timeout this mod
// hands it in its input and then denies. A session with away mode off hands it nothing, and the hook passes at once.

const DEFAULT_MINUTES = 5
const MAXIMUM_MINUTES = 60

// 0 while away mode is off.
const promptTimeoutMs = atom({ plugin: 'away', key: 'promptTimeoutMs' } as const, 0)
// A copy of `waiting` below, for the tool rows to draw from.
const waitingPrompts = atom({ plugin: 'away', key: 'waitingPrompts' } as const, [])
// The ticker's clock: written every second while a prompt waits, so the rows that read it redraw.
const now = atom({ plugin: 'away', key: 'now' } as const, 0)

type Timer = ReturnType<EngineInterface['clock']['every']>

// tool_use_ids of the calls whose verdict was ask, by callKey, until their dialog opens or the call ends.
const askedCalls = new Map<string, string[]>()
// The prompts counting down, kept here rather than read back from $.state: every $.state.get of one dispatch reads one moment,
// so the PermissionRequest hook, which waits through the whole dialog, and the ticker it starts would never see /away off.
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

// Pairs a tool.check verdict, which carries the tool_use_id, with the PermissionRequest event that follows it, which does not.
function callKey(tool: string, input: unknown): string {
  return `${tool}\u0000${JSON.stringify(input)}`
}

function rememberAskedCall(key: string, toolUseId: string): void {
  const toolUseIds = askedCalls.get(key) ?? []
  if (!toolUseIds.includes(toolUseId)) {
    askedCalls.set(key, [...toolUseIds, toolUseId])
  }
}

function takeAskedCall(key: string): string | undefined {
  const [toolUseId, ...rest] = askedCalls.get(key) ?? []
  if (rest.length === 0) {
    askedCalls.delete(key)
  } else {
    askedCalls.set(key, rest)
  }

  return toolUseId
}

function forgetAskedCall(toolUseId: string): void {
  for (const [key, toolUseIds] of askedCalls) {
    const rest = toolUseIds.filter(askedId => askedId !== toolUseId)
    if (rest.length === 0) {
      askedCalls.delete(key)
    } else if (rest.length !== toolUseIds.length) {
      askedCalls.set(key, rest)
    }
  }
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
      await $.state.set({ plugin: 'away', key: 'promptTimeoutMs' }, 0)
      // A prompt still on screen keeps its dialog for the person to answer: its countdown ends here, and the deny its hook sends later is dropped.
      await setWaiting($, [])
      askedCalls.clear()
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

  // Remember which calls are about to ask, so the dialog that opens for one can be matched to its tool row.
  on('tool.check', async ($, e, next) => {
    const verdict = await next(e)
    if (verdict.decision === 'ask' && e.tool_use_id !== undefined && (await read($, promptTimeoutMs)) > 0) {
      rememberAskedCall(callKey(e.tool, e.input), e.tool_use_id)
    }

    return verdict
  }).catch(($, e, next) => next(e))

  // The dialog has opened and the settings PermissionRequest hooks start beside it: the countdown starts now.
  on('classic.PermissionRequest', async ($, e, next) => {
    const timeoutMs = await read($, promptTimeoutMs)
    const toolUseId = timeoutMs === 0 ? undefined : takeAskedCall(callKey(e.tool_name, e.tool_input))
    if (toolUseId === undefined) {
      return next(e)
    }
    const deadline = (await $.clock.now()) + timeoutMs
    await setWaiting($, [...waiting, { toolUseId, tool: e.tool_name, deadline }])
    startTicker($)
    await tick($)
    try {
      const handedDown = { ...e, away_timeout_seconds: timeoutMs / 1000, away_tool_use_id: toolUseId }
      const result = await next(handedDown)
      // /away off emptied the list while the prompt waited: the person answers it, so the hook's deny is dropped.
      if (result.decision !== undefined && !isWaiting(toolUseId)) {
        const { decision: _dropped, ...rest } = result

        return rest
      }

      return result
    } finally {
      await forgetPrompt($, toolUseId)
    }
  }).catch(($, e, next) => next(e))

  // The call has ended (answered, denied or run): its countdown is over, even while the hook beneath still waits.
  on('tool.call', async ($, e, next) => {
    try {
      return await next(e)
    } finally {
      forgetAskedCall(e.tool_use_id)
      await forgetPrompt($, e.tool_use_id)
    }
  }).catch(($, e, next) => next(e))

  // /clear and /resume carry on in this process under another session id, whose state starts over; the pinned status line would stay.
  on('session.end', async ($, e, next) => {
    $.ui.status(undefined)
    askedCalls.clear()
    waiting = []
    stopTicker()

    return next(e)
  })
}
