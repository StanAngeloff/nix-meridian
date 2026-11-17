import type { Args, On } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'

function profile(): Args<'command.run'> {
  return { command: 'profile', args: '', origin: { kind: 'composer' }, presentation: { isFullscreen: false, columns: 120 } }
}

// Stands for the file system beneath the mod: the given .claude.json holds text, and every other path is missing.
function configHolds(on: On, path: string, text: string): void {
  on('fs.read', (_$, e) => {
    if (e.path !== path) {
      return { deny: `ENOENT: no such file or directory, open '${e.path}'` }
    }

    return { value: text }
  })
}

const WORK_CONFIG = JSON.stringify({
  oauthAccount: { emailAddress: 'someone@work.example', organizationName: 'Example Org' },
  projects: {},
})

test('names the profile, the email and the organization', async ($, on) => {
  mock.env(on, { HOME: '/home/someone', CLAUDE_CONFIG_DIR: '/home/someone/.claude', CLAUDE_BUBBLE_PROFILE: 'work' })
  configHolds(on, '/home/someone/.claude/.claude.json', WORK_CONFIG)

  expect((await $.command.run(profile())).text).toBe('🪪 work · someone@work.example (Example Org)')
})

test('leaves the organization out when the account has none', async ($, on) => {
  mock.env(on, { HOME: '/home/someone', CLAUDE_CONFIG_DIR: '/home/someone/.claude', CLAUDE_BUBBLE_PROFILE: 'personal' })
  configHolds(on, '/home/someone/.claude/.claude.json', JSON.stringify({ oauthAccount: { emailAddress: 'someone@personal.example' } }))

  expect((await $.command.run(profile())).text).toBe('🪪 personal · someone@personal.example')
})

test('leaves out the organization named after a personal account', async ($, on) => {
  mock.env(on, { HOME: '/home/someone', CLAUDE_CONFIG_DIR: '/home/someone/.claude', CLAUDE_BUBBLE_PROFILE: 'personal' })
  const account = { emailAddress: 'someone@personal.example', organizationName: "someone@personal.example's Organization" }
  configHolds(on, '/home/someone/.claude/.claude.json', JSON.stringify({ oauthAccount: account }))

  expect((await $.command.run(profile())).text).toBe('🪪 personal · someone@personal.example')
})

test('outside the bubble it names the default profile', async ($, on) => {
  mock.env(on, { HOME: '/home/someone', CLAUDE_CONFIG_DIR: '/home/someone/.claude' })
  configHolds(on, '/home/someone/.claude/.claude.json', WORK_CONFIG)

  expect((await $.command.run(profile())).text).toBe(
    '🪪 the default profile (outside the bubble) · someone@work.example (Example Org)',
  )
})

test('reads ~/.claude when CLAUDE_CONFIG_DIR is unset', async ($, on) => {
  mock.env(on, { HOME: '/home/someone', CLAUDE_BUBBLE_PROFILE: 'work' })
  configHolds(on, '/home/someone/.claude/.claude.json', WORK_CONFIG)

  expect((await $.command.run(profile())).text).toBe('🪪 work · someone@work.example (Example Org)')
})

test('says so when the profile has no account yet', async ($, on) => {
  mock.env(on, { HOME: '/home/someone', CLAUDE_CONFIG_DIR: '/home/someone/.claude', CLAUDE_BUBBLE_PROFILE: 'second' })
  configHolds(on, '/home/someone/.claude/.claude.json', '{}')

  expect((await $.command.run(profile())).text).toBe('🪪 second · not logged in')
})

test('says so when .claude.json cannot be read', async ($, on) => {
  mock.env(on, { HOME: '/home/someone', CLAUDE_CONFIG_DIR: '/home/someone/.claude', CLAUDE_BUBBLE_PROFILE: 'work' })
  configHolds(on, '/elsewhere/.claude.json', WORK_CONFIG)

  expect((await $.command.run(profile())).text).toBe('🪪 work · not logged in')
})
