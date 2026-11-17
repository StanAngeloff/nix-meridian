import type { Elements, Register, RenderChildren } from 'claude-code'

// Left bars that tell the person's prompts, Claude's replies and Claude's tool calls apart,
// and a closing line per turn that names the model. Each bar wraps Claude Code's own drawing of its row,
// so the row shows what it always did; the only change asked of Claude Code is a reply without its ● bullet.
// Terminal only: the mobile app turns a Box with a background or a border around a tool row into a card.

type Ui = Pick<Elements['terminal'], 'Box' | 'Text'>

// The prompts the person sent: typed, from the phone over Remote Control, or from an app built on the SDK.
// Notifications, plugin prompts and messages from other agents keep Claude Code's own look.
const OWN_PROMPT_KINDS = new Set(['composer', 'bridge', 'sdk'])

// A Box border is drawn on all four sides or none, so each bar is a column of one glyph, clipped to the height of its row:
// ▏ for a tool call, ▌ (the left half of the cell) for a prompt and a reply. A row taller than this keeps its bar for this many rows only.
const BAR_ROWS = 1000
const THIN_BAR = '▏\n'.repeat(BAR_ROWS)
const HALF_BAR = '▌\n'.repeat(BAR_ROWS)

// A light gray, not a theme color: no theme key names a neutral this bright that is not also the prose.
const PROMPT_BAR_COLOR = 'rgb(192,192,192)'

// The bar's column at the left edge of its row, starting `top` rows down; it holds only the bar's own Text, so it may clip.
// A cell's background, where given, fills the half of the cell the glyph leaves empty.
function barColumn({ Box, Text }: Ui, column: string, color: string, top: number, backgroundColor?: string) {
  return (
    <Box position="absolute" top={top} bottom={0} left={0} width={1} overflow="hidden">
      {backgroundColor === undefined ? (
        <Text color={color}>{column}</Text>
      ) : (
        <Text color={color} backgroundColor={backgroundColor}>
          {column}
        </Text>
      )}
    </Box>
  )
}

// A half-cell bar on the theme's message background, with a row of air below the text.
// Claude Code's own drawing opens with the blank row it keeps between messages, which becomes the panel's top row of air,
// so the panel keeps a clear row of its own above it; without one it would butt against a closing line or a tool result.
function promptPanel(ui: Ui, drawn: RenderChildren) {
  const { Box } = ui

  return (
    <Box
      flexDirection="column"
      marginTop={1}
      backgroundColor="userMessageBackground"
      paddingLeft={2}
      paddingRight={1}
      paddingBottom={1}
    >
      {barColumn(ui, HALF_BAR, PROMPT_BAR_COLOR, 0, 'userMessageBackground')}
      {drawn}
    </Box>
  )
}

// The bar starts `barTop` rows down. A tool call's row opens with the blank row between messages,
// and starting below it leaves a gap between one call's bar and the next.
function thinBar(ui: Ui, drawn: RenderChildren, barTop: number) {
  const { Box } = ui

  return (
    <Box flexDirection="column" paddingLeft={2}>
      {barColumn(ui, THIN_BAR, 'subtle', barTop)}
      {drawn}
    </Box>
  )
}

// A half-cell bar in Claude's own color in place of the reply's ● bullet, with no background: the text stays where the
// bullet left it. Like a tool call's row, a reply's row opens with the blank row between messages, so the bar starts below it.
function replyBar(ui: Ui, drawn: RenderChildren) {
  const { Box } = ui

  return (
    <Box flexDirection="column" paddingLeft={2}>
      {barColumn(ui, HALF_BAR, 'claude', 1)}
      {drawn}
    </Box>
  )
}

// claude-opus-5-5[1m] reads as Opus 5.5; an id of another shape is shown as it is.
export const modelLabel = (id: string): string => {
  const match = /claude-([a-z]+)-(\d+)(?:-(\d{1,2}))?(?!\d)/i.exec(id)
  if (!match) {
    return id
  }
  const family = match[1]!

  return `${family[0]!.toUpperCase()}${family.slice(1)} ${[match[2], match[3]].filter(Boolean).join('.')}`
}

// As Claude Code writes a turn's length: 3s, 1m 12s, 1h 2m.
export const durationLabel = (milliseconds: number): string => {
  const seconds = Math.round(milliseconds / 1000)
  if (seconds < 60) {
    return `${seconds}s`
  }
  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) {
    return `${minutes}m ${seconds % 60}s`
  }

  return `${Math.floor(minutes / 60)}h ${minutes % 60}m`
}

export const register: Register = on => {
  on('ui.render', { component: 'UserMessage' }, async ($, e, next) => {
    if (e.surface !== 'terminal' || !OWN_PROMPT_KINDS.has(e.props.origin.kind)) {
      return next(e)
    }

    return promptPanel($.ui.resolve(e), await next(e))
  })

  // Claude Code draws the reply itself, Markdown and all, only asked to leave out its ● bullet.
  // Rows marked `· summary` are Claude's thinking, shown as narration, and get the same bar.
  on('ui.render', { component: 'AssistantMessage' }, async ($, e, next) =>
    e.surface === 'terminal'
      ? replyBar($.ui.resolve(e), await next({ ...e, props: { ...e.props, isFirstOfReply: false } }))
      : next(e),
  )

  on('ui.render', { component: 'ToolUse' }, async ($, e, next) =>
    e.surface === 'terminal' ? thinBar($.ui.resolve(e), await next(e), 1) : next(e),
  )

  on('ui.render', { component: 'ToolResult' }, async ($, e, next) =>
    e.surface === 'terminal' ? thinBar($.ui.resolve(e), await next(e), 0) : next(e),
  )

  // An expanded group draws each call as a ToolUse row, which brings its own bar.
  on('ui.render', { component: 'ToolGroup' }, async ($, e, next) =>
    e.surface === 'terminal' && !e.props.isExpanded ? thinBar($.ui.resolve(e), await next(e), 1) : next(e),
  )

  // `▣ Claude · Opus 5.5 · 1m 12s` in place of Claude Code's `Cooked for 1m 12s`, whose verb is drawn at random.
  // The model is the session's when the line is drawn. A line waiting on background agents keeps Claude Code's text.
  on('ui.render', { component: 'TurnDuration' }, async ($, e, next) => {
    if (e.surface !== 'terminal' || e.props.waitingFor) {
      return next(e)
    }
    let model = ''
    try {
      model = modelLabel(await $.session.model())
    } catch {
      // No model to name: the line leaves it out.
    }
    const { Box, Text } = $.ui.resolve(e)
    const details = [model, durationLabel(e.props.durationMs)].filter(Boolean).join(' · ')

    return (
      <Box marginTop={1}>
        <Text>
          <Text color="claude">▣</Text> <Text bold>Claude</Text>
          <Text dimColor>{` · ${details}`}</Text>
        </Text>
      </Box>
    )
  })
}
