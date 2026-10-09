import type { Args, On } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'

const BASH_INPUT = { command: 'echo away-test' }
const BASH_CALL = { tool_name: 'Bash', tool_input: BASH_INPUT }

function away(args: string): Args<'command.run'> {
  return { command: 'away', args, origin: { kind: 'composer' }, presentation: { isFullscreen: false, columns: 120 } }
}

function bashRow(toolUseId: string, isRunning: boolean) {
  return {
    plugin: 'away',
    surface: 'terminal',
    component: 'ToolUse',
    requestId: toolUseId,
    props: { tool_use_id: toolUseId, tool: 'Bash', input: BASH_INPUT, isRunning, isErrored: false, isInterrupted: false },
  } as const
}

// The countdown line the mod draws under the call's tool row, if any.
async function countdownOn($: Engine, toolUseId: string, isRunning = false): Promise<string | undefined> {
  const row = await $.ui.mount(bashRow(toolUseId, isRunning))
  const countdown = (await row.find({ type: 'Text', text: /away:/ }))?.text
  await row.unmount()

  return countdown
}

// Stands for the engine's own drawing, status line and session end beneath the mod; statuses, when given, gets each text the mod
// sets the status line to, undefined for cleared.
function engineBottoms(on: On, statuses?: (string | undefined)[]): void {
  on('ui.render', { component: 'ToolUse' }, ($, e) => {
    const { Text } = $.ui.resolve(e)

    return <Text>Bash(echo away-test)</Text>
  })
  on('ui.status', (_$, e) => {
    statuses?.push(e.text)

    return { value: undefined }
  })
  on('session.end', (_$, e) => ({ sessionId: e.sessionId }))
}

// Stands for the engine beneath the mod: every call asks, and the dialog's PermissionRequest command hook answers when the test says so,
// with a deny when it was handed a timeout, as claude-away does.
function engineThatAsks(on: On) {
  let handedDown: Record<string, unknown> | undefined
  let opened = (): void => {}
  let answer = (): void => {}
  const dialogOpened = new Promise<void>(resolve => {
    opened = resolve
  })
  const hookAnswers = new Promise<void>(resolve => {
    answer = resolve
  })

  engineBottoms(on)
  on('tool.check', () => ({ decision: 'ask' }))
  on('classic.PermissionRequest', async (_$, e) => {
    handedDown = { ...e }
    opened()
    await hookAnswers

    return 'away_timeout_seconds' in e ? { decision: { behavior: 'deny', message: 'nobody answered' } } : {}
  })

  return { handedDown: () => handedDown, dialogOpened, answer }
}

function recordStatuses(on: On): (string | undefined)[] {
  const statuses: (string | undefined)[] = []
  engineBottoms(on, statuses)

  return statuses
}

test('away mode hands the timeout and the call to the hook, and the deny stands', async ($, on) => {
  mock.clock(on, { now: 1_000_000 })
  const engine = engineThatAsks(on)

  expect((await $.command.run(away('1'))).text).toContain('denied after 1:00')
  await $.tool.check({ tool: 'Bash', input: BASH_INPUT, tool_use_id: 'toolu_1' })
  const settled = $.classic.PermissionRequest(BASH_CALL)
  await engine.dialogOpened
  expect(engine.handedDown()).toMatchObject({ away_timeout_seconds: 60, away_tool_use_id: 'toolu_1' })

  engine.answer()
  expect(await settled).toMatchObject({ decision: { behavior: 'deny', message: 'nobody answered' } })
})

test('the tool row counts down while the dialog waits, and not once the call runs', async ($, on) => {
  const clock = mock.clock(on, { now: 1_000_000 })
  const engine = engineThatAsks(on)

  await $.command.run(away('1'))
  await $.tool.check({ tool: 'Bash', input: BASH_INPUT, tool_use_id: 'toolu_1' })
  const settled = $.classic.PermissionRequest(BASH_CALL)
  await engine.dialogOpened

  expect(await countdownOn($, 'toolu_1')).toContain('away: denied in 1:00 unless you answer')
  await clock.advance(1000)
  expect(await countdownOn($, 'toolu_1')).toContain('away: denied in 0:59 unless you answer')
  // isRunning turns true when the person approves.
  expect(await countdownOn($, 'toolu_1', true)).toBeUndefined()
  // Another call's row is left alone.
  expect(await countdownOn($, 'toolu_2')).toBeUndefined()

  engine.answer()
  await settled
  expect(await countdownOn($, 'toolu_1')).toBeUndefined()
})

test('without away mode, or for a call that did not ask, the hook is handed nothing', async ($, on) => {
  mock.clock(on)
  const engine = engineThatAsks(on)
  engine.answer()

  await $.tool.check({ tool: 'Bash', input: BASH_INPUT, tool_use_id: 'toolu_1' })
  expect(await $.classic.PermissionRequest(BASH_CALL)).toEqual({})
  expect(engine.handedDown()).not.toHaveProperty('away_timeout_seconds')

  await $.command.run(away('1'))
  // No tool.check ask came first, so the dialog cannot be matched to a tool row.
  expect(await $.classic.PermissionRequest({ tool_name: 'Bash', tool_input: { command: 'echo other' } })).toEqual({})
  expect(engine.handedDown()).not.toHaveProperty('away_timeout_seconds')
})

test('/away off while a prompt waits ends its countdown and drops the late deny', async ($, on) => {
  mock.clock(on, { now: 1_000_000 })
  const engine = engineThatAsks(on)

  await $.command.run(away('1'))
  await $.tool.check({ tool: 'Bash', input: BASH_INPUT, tool_use_id: 'toolu_1' })
  const settled = $.classic.PermissionRequest(BASH_CALL)
  await engine.dialogOpened
  expect(await countdownOn($, 'toolu_1')).toBeDefined()

  expect((await $.command.run(away('off'))).text).toBe('Away mode is off.')
  expect(await countdownOn($, 'toolu_1')).toBeUndefined()

  engine.answer()
  expect((await settled).decision).toBeUndefined()
})

test('the status line and the notes to the model follow /away and /away off', async ($, on) => {
  mock.clock(on)
  const session = mock.session(on)
  const statuses = recordStatuses(on)
  const notes = () => session.appended().map(row => JSON.stringify(row.message))

  await $.command.run(away(''))
  expect(statuses.at(-1)).toBe('AWAY · unanswered prompts are denied after 5:00 · /away off')
  expect(notes().at(-1)).toContain('The user has stepped away')

  await $.command.run(away('off'))
  expect(statuses.at(-1)).toBeUndefined()
  expect(notes().at(-1)).toContain('The user is back')

  // Turning it off again tells the model nothing new.
  const noteCount = notes().length
  expect((await $.command.run(away('off'))).text).toBe('Away mode was not on.')
  expect(notes()).toHaveLength(noteCount)
})

test('/clear clears the status line', async ($, on) => {
  mock.clock(on)
  const statuses = recordStatuses(on)

  await $.command.run(away('2'))
  expect(statuses.at(-1)).toContain('AWAY')
  await $.session.end({ reason: 'clear', sessionId: 'session-1', resume: { id: 'session-1' } })
  expect(statuses.at(-1)).toBeUndefined()
})

test('a timeout outside 1 second to 60 minutes is refused', async ($, on) => {
  mock.clock(on)
  const statuses = recordStatuses(on)

  for (const argument of ['0', '0.001', '61', '-1', 'soon']) {
    expect((await $.command.run(away(argument))).text).toStartWith('Usage: /away')
  }
  expect(statuses).toHaveLength(0)
  expect((await $.command.run(away('0.5'))).text).toContain('denied after 0:30')
})
