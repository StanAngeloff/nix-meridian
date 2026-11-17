import type { EngineInterface, Register } from 'claude-code'

// /profile: the account profile this session runs as, with that account's email and organization.
// The bubble names the profile in CLAUDE_BUBBLE_PROFILE (bubble/modules/profiles/hooks.sh); the account comes from
// .claude.json, which inside a bubble is the profile's own copy. A session outside the bubble runs as the default profile.

type Account = { emailAddress?: string; organizationName?: string }

async function readAccount($: EngineInterface): Promise<Account | undefined> {
  const configPath = (await $.env.get('CLAUDE_CONFIG_DIR')) ?? `${await $.env.get('HOME')}/.claude`
  try {
    const config = JSON.parse(await $.fs.read(`${configPath}/.claude.json`)) as { oauthAccount?: Account }

    return config.oauthAccount
  } catch {
    return undefined
  }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'profile',
      description: 'Show the account profile this session runs as',
      immediate: true,
    })

    return next(e)
  })

  on('command.run', { command: 'profile' }, async $ => {
    const profile = (await $.env.get('CLAUDE_BUBBLE_PROFILE')) ?? 'the default profile (outside the bubble)'
    const account = await readAccount($)
    if (account?.emailAddress === undefined) {
      return { text: `🪪 ${profile} · not logged in` }
    }
    // Claude.ai names a personal account's own organization after its email; that name repeats the email, so it is left out.
    const organizationName =
      account.organizationName === `${account.emailAddress}'s Organization` ? undefined : account.organizationName
    const organization = organizationName ? ` (${organizationName})` : ''

    return { text: `🪪 ${profile} · ${account.emailAddress}${organization}` }
  })
}
