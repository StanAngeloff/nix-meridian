import type { Args, On } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'

const BASH_INPUT = { command: 'echo away-test' }
const ALLOWED_INPUT = { command: 'echo allowed' }
const SESSION_ID = 'session-1'

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

type EngineOptions = {
  // Each text the mod sets the status line to, undefined for cleared.
  statuses?: (string | undefined)[]
  // Why the engine holds the mod's write to CLAUDE_AWAY, when it does.
  refusal?: string
}

// Stands for the engine beneath the mod: its drawing, status line, session and environment. Every call asks, except one with
// ALLOWED_INPUT, and runs at once. Hands back each value the mod set CLAUDE_AWAY to, undefined for unset.
function engineBeneath(on: On, options: EngineOptions = {}) {
  const handedOver: (string | undefined)[] = []

  on('ui.render', { component: 'ToolUse' }, ($, e) => {
    const { Text } = $.ui.resolve(e)

    return <Text>Bash(echo away-test)</Text>
  })
  on('ui.status', (_$, e) => {
    options.statuses?.push(e.text)

    return { value: undefined }
  })
  on('session.id', () => ({ value: SESSION_ID }))
  on('session.end', (_$, e) => ({ sessionId: e.sessionId }))
  on('env.set', (_$, e) => {
    if (options.refusal !== undefined) {
      return { value: { deny: options.refusal } }
    }
    if (e.name === 'CLAUDE_AWAY') {
      handedOver.push(e.value)
    }

    return { value: {} }
  })
  on('tool.check', (_$, e) => ({ decision: JSON.stringify(e.input) === JSON.stringify(ALLOWED_INPUT) ? 'allow' : 'ask' }))
  on('tool.call', () => ({ result: 'ran' }))

  return { handedOver: () => handedOver }
}

test('/away hands the session and the timeout to the hook through the environment, and /away off takes them back', async ($, on) => {
  mock.clock(on)
  const engine = engineBeneath(on)

  expect((await $.command.run(away('1'))).text).toContain('denied after 1:00')
  expect(engine.handedOver().map(value => (value === undefined ? undefined : JSON.parse(value)))).toEqual([
    { session_id: SESSION_ID, timeout_seconds: 60 },
  ])

  await $.command.run(away('off'))
  expect(engine.handedOver().at(-1)).toBeUndefined()
  expect(engine.handedOver()).toHaveLength(2)
})

test('the tool row counts down from the ask, and not once the call runs or has ended', async ($, on) => {
  const clock = mock.clock(on, { now: 1_000_000 })
  engineBeneath(on)

  await $.command.run(away('1'))
  await $.tool.check({ tool: 'Bash', input: BASH_INPUT, tool_use_id: 'toolu_1' })

  expect(await countdownOn($, 'toolu_1')).toContain('away: denied in 1:00 unless you answer')
  await clock.advance(1000)
  expect(await countdownOn($, 'toolu_1')).toContain('away: denied in 0:59 unless you answer')
  // isRunning turns true when the person approves.
  expect(await countdownOn($, 'toolu_1', true)).toBeUndefined()
  // Another call's row is left alone.
  expect(await countdownOn($, 'toolu_2')).toBeUndefined()

  await $.tool.call({ tool: 'Bash', ...BASH_INPUT, tool_use_id: 'toolu_1' })
  expect(await countdownOn($, 'toolu_1')).toBeUndefined()
})

test('without away mode, for a call that does not ask, or for a query, nothing counts down', async ($, on) => {
  mock.clock(on)
  engineBeneath(on)

  await $.tool.check({ tool: 'Bash', input: BASH_INPUT, tool_use_id: 'toolu_1' })
  expect(await countdownOn($, 'toolu_1')).toBeUndefined()

  await $.command.run(away('1'))
  await $.tool.check({ tool: 'Bash', input: ALLOWED_INPUT, tool_use_id: 'toolu_2' })
  expect(await countdownOn($, 'toolu_2')).toBeUndefined()
  // A query carries no tool_use_id: no call, so no row to count down on.
  await $.tool.check({ tool: 'Bash', input: BASH_INPUT })
  expect(await countdownOn($, 'toolu_1')).toBeUndefined()
})

test('/away off while a prompt waits ends its countdown', async ($, on) => {
  mock.clock(on, { now: 1_000_000 })
  const engine = engineBeneath(on)

  await $.command.run(away('1'))
  await $.tool.check({ tool: 'Bash', input: BASH_INPUT, tool_use_id: 'toolu_1' })
  expect(await countdownOn($, 'toolu_1')).toBeDefined()

  expect((await $.command.run(away('off'))).text).toBe('Away mode is off.')
  expect(await countdownOn($, 'toolu_1')).toBeUndefined()
  expect(engine.handedOver().at(-1)).toBeUndefined()
})

test('the status line and the notes to the model follow /away and /away off', async ($, on) => {
  mock.clock(on)
  const session = mock.session(on)
  const statuses: (string | undefined)[] = []
  engineBeneath(on, { statuses })
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

test('/clear clears the status line and takes the timeout back from the hook', async ($, on) => {
  mock.clock(on)
  const statuses: (string | undefined)[] = []
  const engine = engineBeneath(on, { statuses })

  await $.command.run(away('2'))
  expect(statuses.at(-1)).toContain('AWAY')
  expect(engine.handedOver().at(-1)).toBeDefined()
  await $.session.end({ reason: 'clear', sessionId: SESSION_ID, resume: { id: SESSION_ID } })
  expect(statuses.at(-1)).toBeUndefined()
  expect(engine.handedOver().at(-1)).toBeUndefined()
})

test('a timeout outside 1 second to 60 minutes is refused', async ($, on) => {
  mock.clock(on)
  const statuses: (string | undefined)[] = []
  const engine = engineBeneath(on, { statuses })

  for (const argument of ['0', '0.001', '61', '-1', 'soon']) {
    expect((await $.command.run(away(argument))).text).toStartWith('Usage: /away')
  }
  expect(statuses).toHaveLength(0)
  expect(engine.handedOver()).toHaveLength(0)
  expect((await $.command.run(away('0.5'))).text).toContain('denied after 0:30')
})

test('when the engine holds the variable, away mode stays off and says why', async ($, on) => {
  mock.clock(on)
  const session = mock.session(on)
  const statuses: (string | undefined)[] = []
  engineBeneath(on, { statuses, refusal: 'pinned by the organization' })

  const reply = (await $.command.run(away('1'))).text
  expect(reply).toStartWith('Away mode was not changed')
  expect(reply).toContain('pinned by the organization')
  expect(statuses).toHaveLength(0)
  expect(session.appended()).toHaveLength(0)

  await $.tool.check({ tool: 'Bash', input: BASH_INPUT, tool_use_id: 'toolu_1' })
  expect(await countdownOn($, 'toolu_1')).toBeUndefined()
})
