import type { On } from 'claude-code'
import { expect, test } from 'claude-code/testing'

// Stands for Claude Code beneath the mod: every row it is asked to draw is one Text reading "engine".
function engineDraws(on: On): void {
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)

    return <Text>engine</Text>
  })
}

function prompt(kind: 'composer' | 'task-notification') {
  return {
    plugin: 'glowup',
    component: 'UserMessage',
    requestId: 'message-1',
    surface: 'terminal',
    props: { text: 'hello', origin: { kind }, isExpanded: true },
  } as const
}

const TOOL_USE = {
  plugin: 'glowup',
  component: 'ToolUse',
  requestId: 'toolu_1',
  surface: 'terminal',
  props: {
    tool_use_id: 'toolu_1',
    tool: 'Bash',
    input: { command: 'ls' },
    isRunning: false,
    isErrored: false,
    isInterrupted: false,
  },
} as const

function turnDuration(waitingFor?: { agents: []; workflows: number }) {
  return {
    plugin: 'glowup',
    component: 'TurnDuration',
    requestId: 'turn-1',
    surface: 'terminal',
    props: { word: 'Cooked', durationMs: 72_000, ...(waitingFor && { waitingFor }) },
  } as const
}

test('a typed prompt sits on the message background behind a half-cell bar, around Claude Code’s own row', async ($, on) => {
  engineDraws(on)
  const ui = await $.ui.mount(prompt('composer'))
  const backgrounds = (await ui.findAll({ type: 'Box' })).map(box => box.props.backgroundColor)
  const bar = await ui.find({ type: 'Text', text: /^▌\n/ })

  expect(backgrounds).toContain('userMessageBackground')
  expect(bar?.props.color).toBe('rgb(192,192,192)')
  expect(bar?.props.backgroundColor).toBe('userMessageBackground')
  expect((await ui.find({ type: 'Text', text: 'engine' }))?.text).toBe('engine')
  await ui.unmount()
})

test('a notification keeps Claude Code’s own row', async ($, on) => {
  engineDraws(on)
  const ui = await $.ui.mount(prompt('task-notification'))

  expect(await ui.findAll({ type: 'Box' })).toHaveLength(0)
  expect((await ui.find({ type: 'Text', text: 'engine' }))?.text).toBe('engine')
  await ui.unmount()
})

test('a tool call gets a thin bar beside Claude Code’s own row', async ($, on) => {
  engineDraws(on)
  const ui = await $.ui.mount(TOOL_USE)

  expect(await ui.find({ type: 'Text', text: /^▏\n/ })).toBeDefined()
  expect((await ui.find({ type: 'Text', text: 'engine' }))?.text).toBe('engine')
  await ui.unmount()
})

test('the closing line names the model and the turn’s length', async ($, on) => {
  engineDraws(on)
  on('session.model', () => ({ value: 'claude-opus-5-5[1m]' }))
  const ui = await $.ui.mount(turnDuration())

  expect((await ui.find({ type: 'Text', text: /Claude/ }))?.text).toBe('▣ Claude · Opus 5.5 · 1m 12s')
  await ui.unmount()
})

test('a closing line waiting on background agents keeps Claude Code’s text', async ($, on) => {
  engineDraws(on)
  const ui = await $.ui.mount(turnDuration({ agents: [], workflows: 1 }))

  expect((await ui.find({ type: 'Text' }))?.text).toBe('engine')
  await ui.unmount()
})

test('a reply keeps Claude Code’s own drawing, without its bullet, beside a half-cell bar in Claude’s color', async ($, on) => {
  // Stands for Claude Code: the row says whether it was asked for its bullet.
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    const props = e.props as { isFirstOfReply?: boolean }

    return <Text>{`bullet: ${props.isFirstOfReply}`}</Text>
  })
  const ui = await $.ui.mount({
    plugin: 'glowup',
    component: 'AssistantMessage',
    requestId: 'reply-1',
    surface: 'terminal',
    props: { text: 'hello', isFirstOfReply: true },
  } as const)
  const bar = await ui.find({ type: 'Text', text: /^▌\n/ })

  expect(bar?.props.color).toBe('claude')
  expect(bar?.props.backgroundColor).toBeUndefined()
  expect((await ui.find({ type: 'Text', text: /bullet/ }))?.text).toBe('bullet: false')
  await ui.unmount()
})
