"""claude-arbiter's second look at a shell command cc-safety-net stopped on a request rule.

The engine stops `gh api` whenever a field or a method could make the call a write (arbiter-writes/gh-api-write), and
`curl` whenever it sends data or a writing method (arbiter-writes/curl-write). Two kinds of those stops are reads in
fact: a GraphQL query, and any request to this machine's loopback address, the local development stack.
This program reads the command, and every script the engine read for it, and answers "reads" only when it can account
for every request in them and each one carrying write flags is a GraphQL query or goes to localhost.
Anything it cannot account for answers "ask", with the reason, and claude-arbiter asks as it did before.

It judges requests only. claude-arbiter has already rerun the engine without the request rules, so every other
objection is the engine's, and the engine sees inside the scripts this program is handed.

It reads one JSON object on stdin, {"command", "cwd", "scripts", "rule", "rulebook"}:
scripts are the {"path", "bytes"} of the engine's explain trace, rule is the stopped rule's id,
and rulebook is the arbiter-writes rulebook the rule comes from, so its flag lists never drift from the engine's.
It prints {"verdict": "reads" | "ask", "reason": ...}, and a non-zero exit means it failed, which the arbiter asks on.
"""

import dataclasses
import json
import os
import pathlib
import re
import sys

REQUEST_RULES = {
    "custom.arbiter-writes/gh-api-write": "gh",
    "custom.arbiter-writes/curl-write": "curl",
}

LOCAL_HOSTS = frozenset({"localhost", "127.0.0.1", "[::1]"})

# A GraphQL keyword that makes a document more than a read, anywhere in the text the engine analysed.
GRAPHQL_WRITE_WORD = re.compile(r"\b(?:mutation|subscription)\b")

# Text that names a request a command would run, inside an argument the second look cannot follow.
# The strict form fits arguments of commands that print or search text; the broad one fits everything else,
# because an interpreter can spell a call as a list of strings.
STRICT_MENTION = re.compile(r"(?<![\w-])(?:gh\s+api\b|curl\s+\S)")
BROAD_MENTION = re.compile(
    r"(?<![\w-])(?:gh(?![\w-])[\s\S]*?(?<![\w-])api(?![\w-])|curl(?![\w-]))"
)

SHELLS = frozenset({"bash", "sh", "zsh", "dash", "ksh", "mksh", "ash"})
INTERPRETER = re.compile(
    r"(?:python[\d.]*|pypy[\d.]*|node|nodejs|perl|ruby|deno|bun|php|lua[\d.]*|tclsh|pwsh|powershell|osascript"
    r"|awk|gawk|mawk|nawk)"
)
# Commands that never run their arguments, so a gh or curl among them is text.
NON_EXECUTORS = frozenset("""
    [ [[ basename case cat cut diff dirname echo egrep fgrep file grep hash head jq less ls man printf readlink
    realpath rg sort stat tail tee test tr true false type uniq wc which yq
    """.split())
KEYWORDS = frozenset(
    {
        "!",
        "{",
        "}",
        "if",
        "then",
        "else",
        "elif",
        "fi",
        "do",
        "done",
        "while",
        "until",
        "esac",
    }
)
ASSIGNMENT = re.compile(r"([A-Za-z_][A-Za-z0-9_]*)(\+?)=")
NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")

GH_API_OPTIONS = {
    # option: (name, takes a value)
    "-X": ("method", True),
    "--method": ("method", True),
    "-H": ("header", True),
    "--header": ("header", True),
    "-q": ("jq", True),
    "--jq": ("jq", True),
    "-t": ("template", True),
    "--template": ("template", True),
    "-f": ("raw-field", True),
    "--raw-field": ("raw-field", True),
    "-F": ("field", True),
    "--field": ("field", True),
    "--input": ("input", True),
    "-p": ("preview", True),
    "--preview": ("preview", True),
    "--hostname": ("hostname", True),
    "--cache": ("cache", True),
    "-i": ("include", False),
    "--include": ("include", False),
    "--paginate": ("paginate", False),
    "--slurp": ("slurp", False),
    "--silent": ("silent", False),
    "--verbose": ("verbose", False),
    "-h": ("help", False),
    "--help": ("help", False),
}

# curl's options, from `curl --help all` of curl 8.22.0. An option missing here makes the second look ask.
CURL_VALUE_OPTIONS = frozenset("""
    --abstract-unix-socket --alt-svc --aws-sigv4 --cacert --capath --cert --cert-type --ciphers --config
    --connect-timeout --connect-to --continue-at --cookie --cookie-jar --create-file-mode --crlfile
    --curves --data --data-ascii --data-binary --data-raw --data-urlencode --delegation --dns-interface
    --dns-ipv4-addr --dns-ipv6-addr --dns-servers --doh-url --dump-header --ech --egd-file --engine
    --etag-compare --etag-save --expect100-timeout --form --form-string --ftp-account
    --ftp-alternative-to-user --ftp-method --ftp-port --ftp-ssl-ccc-mode --happy-eyeballs-timeout-ms
    --haproxy-clientip --header --help --hostpubmd5 --hostpubsha256 --hsts --interface --ip-tos
    --ipfs-gateway --json --keepalive-cnt --keepalive-time --key --key-type --knownhosts --krb --libcurl
    --limit-rate --local-port --login-options --mail-auth --mail-from --mail-rcpt --max-filesize
    --max-redirs --max-time --netrc-file --noproxy --oauth2-bearer --output --output-dir --parallel-max
    --parallel-max-host --pass --pinnedpubkey --preproxy --proto --proto-default --proto-redir --proxy
    --proxy-cacert --proxy-capath --proxy-cert --proxy-cert-type --proxy-ciphers --proxy-crlfile
    --proxy-header --proxy-key --proxy-key-type --proxy-pass --proxy-pinnedpubkey --proxy-service-name
    --proxy-tls13-ciphers --proxy-tlsauthtype --proxy-tlspassword --proxy-tlsuser --proxy-user
    --proxy1.0 --pubkey --quote --random-file --range --rate --referer --request --request-target
    --resolve --retry --retry-delay --retry-max-time --sasl-authzid --service-name --sigalgs --socks4
    --socks4a --socks5 --socks5-gssapi-service --socks5-hostname --speed-limit --speed-time
    --ssl-sessions --stderr --telnet-option --tftp-blksize --time-cond --tls-max --tls13-ciphers
    --tlsauthtype --tlspassword --tlsuser --trace --trace-ascii --trace-config --unix-socket
    --upload-file --upload-flags --url --url-query --user --user-agent --variable --vlan-priority
    --write-out
    """.split())
CURL_BOOLEAN_OPTIONS = frozenset("""
    --anyauth --append --basic --ca-native --cert-status --compressed --compressed-ssh --create-dirs
    --crlf --digest --disable --disable-eprt --disable-epsv --disallow-username-in-url --doh-cert-status
    --doh-insecure --dump-ca-embed --fail --fail-early --fail-with-body --false-start --follow
    --form-escape --ftp-create-dirs --ftp-pasv --ftp-pret --ftp-skip-pasv-ip --ftp-ssl-ccc
    --ftp-ssl-control --get --globoff --haproxy-protocol --head --http0.9 --http1.0 --http1.1 --http2
    --http2-prior-knowledge --http3 --http3-only --ignore-content-length --insecure --ipv4 --ipv6
    --junk-session-cookies --list-only --location --location-trusted --mail-rcpt-allowfails --manual
    --metalink --mptcp --negotiate --netrc --netrc-optional --next --no-alpn --no-buffer --no-clobber
    --no-keepalive --no-npn --no-progress-meter --no-sessionid --ntlm --ntlm-wb --out-null --parallel
    --parallel-immediate --path-as-is --post301 --post302 --post303 --progress-bar --proxy-anyauth
    --proxy-basic --proxy-ca-native --proxy-digest --proxy-http2 --proxy-http3 --proxy-insecure
    --proxy-negotiate --proxy-ntlm --proxy-ssl-allow-beast --proxy-ssl-auto-client-cert --proxy-tlsv1
    --proxytunnel --raw --remote-header-name --remote-name --remote-name-all --remote-time
    --remove-on-error --retry-all-errors --retry-connrefused --sasl-ir --show-error --show-headers
    --silent --skip-existing --socks5-basic --socks5-gssapi --socks5-gssapi-nec --ssl --ssl-allow-beast
    --ssl-auto-client-cert --ssl-no-revoke --ssl-reqd --ssl-revoke-best-effort --sslv2 --sslv3
    --styled-output --suppress-connect-headers --tcp-fastopen --tcp-nodelay --tftp-no-options
    --tls-earlydata --tlsv1 --tlsv1.0 --tlsv1.1 --tlsv1.2 --tlsv1.3 --tr-encoding --trace-ids
    --trace-time --use-ascii --verbose --version --xattr
    """.split())
CURL_SHORT_OPTIONS = {pair[0]: pair[1:] for pair in """
    #--progress-bar 0--http1.0 1--tlsv1 2--sslv2 3--sslv3 4--ipv4 6--ipv6 :--next A--user-agent
    B--use-ascii C--continue-at D--dump-header E--cert F--form G--get H--header I--head
    J--remote-header-name K--config L--location M--manual N--no-buffer O--remote-name P--ftp-port
    Q--quote R--remote-time S--show-error T--upload-file U--proxy-user V--version X--request
    Y--speed-limit Z--parallel a--append b--cookie c--cookie-jar d--data e--referer f--fail g--globoff
    h--help i--show-headers j--junk-session-cookies k--insecure l--list-only m--max-time n--netrc
    o--output p--proxytunnel q--disable r--range s--silent t--telnet-option u--user v--verbose
    w--write-out x--proxy y--speed-time z--time-cond
    """.split()}
# Spellings curl still accepts that its help no longer lists.
CURL_ALIASES = {"--include": "--show-headers"}
# Options that can send a request somewhere other than the URL it names, or read more options from elsewhere.
CURL_REROUTING_OPTIONS = frozenset("""
    --abstract-unix-socket --alt-svc --config --connect-to --dns-interface --dns-ipv4-addr --dns-ipv6-addr
    --dns-servers --doh-url --next --preproxy --proxy --resolve --socks4 --socks4a --socks5
    --socks5-hostname --unix-socket
    """.split())
# Variables curl reads its proxy or its configuration file from.
CURL_ENVIRONMENT = re.compile(
    r"(?i)(?!no_proxy$)\w*_proxy|curl_home|home|xdg_config_home"
)


class MustAsk(Exception):
    """Something the second look cannot account for; its message is the reason the arbiter shows."""


@dataclasses.dataclass
class Verdict:
    reads: bool
    reason: str


# --- Words --------------------------------------------------------------------------------------------------------


@dataclasses.dataclass
class Part:
    text: str
    # "literal" text (after quote removal), a plain "variable" ($NAME or ${NAME}), another "expansion",
    # an unquoted "glob" character, or a leading "tilde".
    kind: str
    quoted: bool = False
    name: str | None = None


class Word:
    def __init__(self, parts):
        merged = []
        for part in parts:
            if merged and part.kind == "literal" and merged[-1].kind == "literal":
                merged[-1] = Part(
                    merged[-1].text + part.text,
                    "literal",
                    merged[-1].quoted or part.quoted,
                )
            else:
                merged.append(part)
        self.parts = merged

    @property
    def text(self):
        return "".join(part.text for part in self.parts)

    @property
    def literal(self):
        return all(part.kind == "literal" for part in self.parts)

    @property
    def unlexed_text(self):
        """The text without command and process substitutions, whose commands the lexer lists on their own."""
        return "".join(
            part.text
            for part in self.parts
            if not (
                part.kind == "expansion"
                and part.text.startswith(("$(", "`", "<(", ">("))
            )
        )

    def literal_prefix(self):
        prefix = []
        for part in self.parts:
            if part.kind != "literal":
                break
            prefix.append(part.text)
        return "".join(prefix)

    def drop(self, count):
        """The word without its first count characters, which must all be literal."""
        if count > len(self.literal_prefix()):
            raise MustAsk(f"an option is built from expansions: {self.text}")
        parts = list(self.parts)
        while count:
            head = parts[0]
            if len(head.text) <= count:
                count -= len(head.text)
                parts.pop(0)
            else:
                parts[0] = Part(head.text[count:], "literal", head.quoted)
                count = 0
        return Word(parts)

    def assignment(self):
        """(name, value) for NAME=value, value None for NAME+=value; None when the word is no assignment."""
        match = ASSIGNMENT.match(self.literal_prefix())
        if not match:
            return None
        if match.group(2):
            return match.group(1), None
        return match.group(1), self.drop(match.end())

    def field(self):
        """(key, value) for key=value, where the key must be literal."""
        prefix = self.literal_prefix()
        if "=" not in prefix:
            raise MustAsk(f"a gh api field has no literal key: {self.text}")
        key = prefix.split("=", 1)[0]
        return key, self.drop(len(key) + 1)


def basename(word):
    return word.text.rsplit("/", 1)[-1] if word.literal else None


@dataclasses.dataclass
class Heredoc:
    body: str
    expands: bool


@dataclasses.dataclass
class Command:
    words: list = dataclasses.field(default_factory=list)
    heredocs: list = dataclasses.field(default_factory=list)
    here_strings: list = dataclasses.field(default_factory=list)


# --- Tokenizer ----------------------------------------------------------------------------------------------------


class ShellLexer:
    """Splits shell text into commands of words, keeping track of which parts of a word the shell expands.

    Command substitutions, backticks and process substitutions are lexed too, and their commands land in the same
    list, since the shell runs them as well. A heredoc's body is kept on its command for the caller to judge.
    """

    def __init__(self, text, commands):
        self.text = text
        self.pos = 0
        self.commands = commands
        self.pending_heredocs = []
        # One entry per open case statement: "header" up to its `in`, "pattern" while reading `pattern)`, "body" after.
        self.cases = []

    def at_end(self):
        return self.pos >= len(self.text)

    def peek(self, offset=0):
        index = self.pos + offset
        return self.text[index] if index < len(self.text) else None

    def lex(self, closing=False):
        """Lexes to the end of the text, or past the parenthesis that closes a substitution when closing."""
        command = Command()
        depth = 0
        while True:
            self.skip_blanks()
            if self.at_end():
                if closing:
                    raise MustAsk("a command substitution is never closed")
                self.finish(command)
                self.read_heredocs()
                return self.pos
            char = self.text[self.pos]
            if self.cases and self.cases[-1] == "pattern" and char not in "#\n":
                command = self.read_case_pattern(command)
            elif char == "#":
                while not self.at_end() and self.text[self.pos] != "\n":
                    self.pos += 1
            elif char == "\n":
                self.pos += 1
                command = self.finish(command)
                self.read_heredocs()
            elif char == "&" and self.peek(1) == ">":
                self.read_redirection(command)
            elif char in ";&|":
                start = self.pos
                while not self.at_end() and self.text[self.pos] in ";&|":
                    self.pos += 1
                if (
                    self.cases
                    and self.cases[-1] == "body"
                    and self.text[start : self.pos] in (";;", ";&", ";;&")
                ):
                    self.cases[-1] = "pattern"
                command = self.finish(command)
            elif char == "(":
                self.pos += 1
                depth += 1
                command = self.finish(command)
            elif char == ")":
                self.pos += 1
                if depth == 0:
                    if not closing:
                        raise MustAsk("a closing parenthesis has no opening one")
                    self.finish(command)
                    return self.pos
                depth -= 1
                command = self.finish(command)
            elif char in "<>" and self.peek(1) != "(":
                self.read_redirection(command)
            else:
                word = self.read_word()
                if word.literal and word.text.isdigit() and self.peek() in ("<", ">"):
                    continue  # the file descriptor of a redirection, such as the 2 of 2>&1
                if not command.words and word.text == "case":
                    self.cases.append("header")
                elif (
                    not command.words
                    and word.text == "esac"
                    and self.cases
                    and self.cases[-1] == "body"
                ):
                    self.cases.pop()
                command.words.append(word)
                if (
                    self.cases
                    and self.cases[-1] == "header"
                    and len(command.words) >= 3
                    and word.text == "in"
                ):
                    self.cases[-1] = "pattern"
                    command = self.finish(command)

    def read_case_pattern(self, command):
        """Reads one `pattern | pattern)` of a case statement, or the `esac` that closes it."""
        self.finish(command)
        if self.text[self.pos] == "(":
            self.pos += 1
            self.skip_blanks()
        start = self.pos
        word = self.read_word()
        if word.text == "esac" and self.peek() != ")":
            self.cases.pop()
            return Command()
        self.pos = start
        while True:
            self.skip_blanks()
            if self.at_end():
                raise MustAsk("a case pattern is never closed")
            char = self.text[self.pos]
            if char == ")":
                self.pos += 1
                self.cases[-1] = "body"
                return Command()
            if char == "|":
                self.pos += 1
                continue
            if char in "\n;&(<>":
                raise MustAsk(
                    "a case pattern holds something the second look cannot read"
                )
            self.read_word()

    def finish(self, command):
        if command.words or command.heredocs or command.here_strings:
            self.commands.append(command)
        return Command()

    def skip_blanks(self):
        while not self.at_end():
            char = self.text[self.pos]
            if char in " \t\r":
                self.pos += 1
            elif char == "\\" and self.peek(1) == "\n":
                self.pos += 2
            else:
                return

    def read_redirection(self, command):
        for operator in (
            "&>>",
            "&>",
            "<<<",
            "<<-",
            "<<",
            "<>",
            "<&",
            ">>",
            ">|",
            ">&",
            "<",
            ">",
        ):
            if self.text.startswith(operator, self.pos):
                break
        self.pos += len(operator)
        self.skip_blanks()
        if self.at_end() or self.text[self.pos] in "\n;&|()":
            raise MustAsk(f"a {operator} redirection has no target")
        start = self.pos
        target = self.read_word()
        if operator in ("<<", "<<-"):
            if not target.literal:
                raise MustAsk("a heredoc delimiter is built from expansions")
            source = self.text[start : self.pos]
            expands = not any(char in source for char in "'\"\\")
            self.pending_heredocs.append(
                (target.text, operator == "<<-", expands, command)
            )
        elif operator == "<<<":
            command.here_strings.append(target)

    def read_heredocs(self):
        for delimiter, strip_tabs, expands, command in self.pending_heredocs:
            lines = []
            while not self.at_end():
                end = self.text.find("\n", self.pos)
                if end == -1:
                    end = len(self.text)
                line = self.text[self.pos : end]
                self.pos = end + 1
                if (line.lstrip("\t") if strip_tabs else line) == delimiter:
                    break
                lines.append(line)
            command.heredocs.append(Heredoc("\n".join(lines), expands))
        self.pending_heredocs = []

    def read_word(self):
        parts = []
        start = self.pos
        while not self.at_end():
            char = self.text[self.pos]
            if char in "<>" and self.peek(1) == "(":
                parts.append(self.read_substitution(2))
            elif char in " \t\r\n;&|()<>":
                break
            elif char == "\\":
                following = self.peek(1)
                if following == "\n":
                    self.pos += 2
                elif following is None:
                    parts.append(Part("\\", "literal"))
                    self.pos += 1
                else:
                    parts.append(Part(following, "literal", quoted=True))
                    self.pos += 2
            elif char == "'":
                end = self.text.find("'", self.pos + 1)
                if end == -1:
                    raise MustAsk("a single quote is never closed")
                parts.append(
                    Part(self.text[self.pos + 1 : end], "literal", quoted=True)
                )
                self.pos = end + 1
            elif char == '"':
                self.pos += 1
                parts.extend(self.read_double_quoted('"'))
            elif char == "$":
                parts.extend(self.read_dollar(quoted=False))
            elif char == "`":
                parts.append(self.read_backticks(quoted=False))
            elif char in "*?[]{}":
                parts.append(Part(char, "glob"))
                self.pos += 1
            elif char == "~" and self.pos == start:
                parts.append(Part(char, "tilde"))
                self.pos += 1
            else:
                parts.append(Part(char, "literal"))
                self.pos += 1
        return Word(parts)

    def read_double_quoted(self, terminator):
        """Reads up to the terminator, or to the end when it is None, as the inside of double quotes."""
        parts = []
        while True:
            if self.at_end():
                if terminator is None:
                    return parts
                raise MustAsk("a double quote is never closed")
            char = self.text[self.pos]
            if char == terminator:
                self.pos += 1
                return parts
            if char == "\\":
                following = self.peek(1)
                if following == "\n":
                    self.pos += 2
                elif following in ("$", "`", '"', "\\"):
                    parts.append(Part(following, "literal", quoted=True))
                    self.pos += 2
                else:
                    parts.append(Part("\\", "literal", quoted=True))
                    self.pos += 1
            elif char == "$":
                parts.extend(self.read_dollar(quoted=True))
            elif char == "`":
                parts.append(self.read_backticks(quoted=True))
            else:
                parts.append(Part(char, "literal", quoted=True))
                self.pos += 1

    def read_dollar(self, quoted):
        start = self.pos
        following = self.peek(1)
        if following == "(":
            return [self.read_substitution(2, quoted)]
        if following == "{":
            end = self.closing_brace(self.pos + 2)
            body = self.text[self.pos + 2 : end]
            self.pos = end + 1
            if NAME.fullmatch(body):
                return [
                    Part(self.text[start : self.pos], "variable", quoted, name=body)
                ]
            # A default such as ${X:-$(cmd)} runs cmd, so the body is read for substitutions.
            ShellLexer(body, self.commands).read_double_quoted(None)
            return [Part(self.text[start : self.pos], "expansion", quoted)]
        if following == "'" and not quoted:
            return [self.read_ansi_c()]
        if following == '"' and not quoted:
            self.pos += 2
            return self.read_double_quoted('"')
        match = NAME.match(self.text, self.pos + 1)
        if match:
            self.pos = match.end()
            return [
                Part(
                    self.text[start : self.pos], "variable", quoted, name=match.group()
                )
            ]
        if following is not None and following in "@*#?$!-0123456789":
            self.pos += 2
            return [Part(self.text[start : self.pos], "expansion", quoted)]
        self.pos += 1
        return [Part("$", "literal", quoted)]

    def read_substitution(self, opening_length, quoted=False):
        start = self.pos
        inner = ShellLexer(self.text, self.commands)
        inner.pos = self.pos + opening_length
        self.pos = inner.lex(closing=True)
        return Part(self.text[start : self.pos], "expansion", quoted)

    def read_backticks(self, quoted):
        start = self.pos
        self.pos += 1
        inner = []
        while True:
            if self.at_end():
                raise MustAsk("a backtick is never closed")
            char = self.text[self.pos]
            if char == "`":
                self.pos += 1
                break
            if char == "\\" and self.peek(1) in ("`", "\\", "$"):
                inner.append(self.peek(1))
                self.pos += 2
                continue
            inner.append(char)
            self.pos += 1
        ShellLexer("".join(inner), self.commands).lex()
        return Part(self.text[start : self.pos], "expansion", quoted)

    def read_ansi_c(self):
        escapes = {
            "n": "\n",
            "t": "\t",
            "r": "\r",
            "a": "\a",
            "b": "\b",
            "e": "\x1b",
            "E": "\x1b",
            "f": "\f",
        }
        escapes.update({"v": "\v", "\\": "\\", "'": "'", '"': '"', "?": "?"})
        self.pos += 2
        value = []
        while True:
            if self.at_end():
                raise MustAsk("a $'...' string is never closed")
            char = self.text[self.pos]
            if char == "'":
                self.pos += 1
                return Part("".join(value), "literal", quoted=True)
            if char == "\\" and self.peek(1) is not None:
                following = self.peek(1)
                value.append(escapes.get(following, "\\" + following))
                self.pos += 2
                continue
            value.append(char)
            self.pos += 1

    def closing_brace(self, pos):
        depth = 1
        while pos < len(self.text):
            char = self.text[pos]
            if char == "\\":
                pos += 2
                continue
            if char == "'":
                end = self.text.find("'", pos + 1)
                if end == -1:
                    break
                pos = end + 1
                continue
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    return pos
            pos += 1
        raise MustAsk("a ${...} expansion is never closed")


# --- Requests -----------------------------------------------------------------------------------------------------


@dataclasses.dataclass
class GhApiCall:
    endpoint: Word | None
    options: list  # (name, value Word or None)
    words: list

    def carries(self, flags):
        return any(name in flags.gh_options for name, _ in self.options)


@dataclasses.dataclass
class CurlCall:
    urls: list
    methods: list
    options: list  # (canonical option, value Word or None)
    words: list

    @property
    def option_names(self):
        return {name for name, _ in self.options}

    def carries(self, flags):
        if self.option_names & flags.curl_options:
            return True
        if any(word.literal and word.text in flags.curl_methods for word in self.words):
            return True
        return any(
            not method.literal or method.text.upper() in flags.curl_methods
            for method in self.methods
        )


@dataclasses.dataclass
class RequestFlags:
    """The flags with which the arbiter-writes rulebook stops gh api and curl, in the parsers' own names."""

    gh_options: set
    curl_options: set
    curl_methods: set

    @classmethod
    def load(cls, path):
        rules = {
            rule["name"]: rule
            for rule in json.loads(pathlib.Path(path).read_text())["rules"]
        }
        if "gh-api-write" not in rules or "curl-write" not in rules:
            raise MustAsk(f"{path} has no gh-api-write or curl-write rule")
        gh_options = set()
        for argument in rules["gh-api-write"]["block_args"]:
            option = argument.split("=", 1)[0]
            if option not in GH_API_OPTIONS:
                raise MustAsk(
                    f"the rulebook stops gh api on {argument}, which the second look does not know"
                )
            gh_options.add(GH_API_OPTIONS[option][0])
        curl_options, curl_methods = set(), set()
        for argument in rules["curl-write"]["block_args"]:
            method = re.fullmatch(r"(?:-X)?([A-Z]+)", argument)
            if method:
                curl_methods.add(method.group(1))
                continue
            option = (
                curl_option(argument)
                if argument.startswith("--")
                else CURL_SHORT_OPTIONS.get(argument[1:])
            )
            if option is None or len(argument) == 1:
                raise MustAsk(
                    f"the rulebook stops curl on {argument}, which the second look does not know"
                )
            curl_options.add(option)
        return cls(gh_options, curl_options, curl_methods)


def curl_option(name):
    """curl's own name for a long option, or None when curl does not know it."""
    name = CURL_ALIASES.get(name, name)
    if name in CURL_VALUE_OPTIONS or name in CURL_BOOLEAN_OPTIONS:
        return name
    if name.startswith("--no-") and "--" + name[5:] in CURL_BOOLEAN_OPTIONS:
        return "--" + name[5:]
    return None


def parse_gh_api(words):
    endpoint = None
    options = []
    index = 0
    options_end = False
    while index < len(words):
        word = words[index]
        text = word.text
        if not options_end and text == "--":
            options_end = True
        elif not options_end and text.startswith("-") and text != "-":
            prefix = word.literal_prefix()
            if text.startswith("--"):
                option = prefix.split("=", 1)[0]
                if option not in GH_API_OPTIONS:
                    raise MustAsk(
                        f"gh api option {option} is unknown to the second look"
                    )
                name, takes_value = GH_API_OPTIONS[option]
                if "=" in prefix:
                    if not takes_value:
                        raise MustAsk(f"gh api option {option} takes no value")
                    options.append((name, word.drop(len(option) + 1)))
                elif takes_value:
                    index += 1
                    if index >= len(words):
                        raise MustAsk(f"gh api option {option} has no value")
                    options.append((name, words[index]))
                else:
                    options.append((name, None))
            else:
                for offset, letter in enumerate(prefix[1:], start=1):
                    if "-" + letter not in GH_API_OPTIONS:
                        raise MustAsk(
                            f"gh api option -{letter} is unknown to the second look"
                        )
                    name, takes_value = GH_API_OPTIONS["-" + letter]
                    if not takes_value:
                        options.append((name, None))
                        continue
                    value = word.drop(offset + 1)
                    if value.text.startswith("="):
                        raise MustAsk(f"gh api option -{letter}= is ambiguous")
                    if not value.text:
                        index += 1
                        if index >= len(words):
                            raise MustAsk(f"gh api option -{letter} has no value")
                        value = words[index]
                    options.append((name, value))
                    break
                else:
                    if len(prefix) < len(text):
                        raise MustAsk(
                            f"a gh api option is built from expansions: {text}"
                        )
        elif endpoint is None:
            endpoint = word
        else:
            raise MustAsk("gh api takes one endpoint, and this call names more")
        index += 1
    return GhApiCall(endpoint, options, words)


def parse_curl(words):
    urls, methods, options = [], [], []
    index = 0
    options_end = False
    while index < len(words):
        word = words[index]
        text = word.text
        if not options_end and text == "--":
            options_end = True
        elif not options_end and text.startswith("-") and text != "-":
            if text.startswith("--"):
                if not word.literal:
                    raise MustAsk(f"a curl option is built from expansions: {text}")
                option = curl_option(text)
                if option is None:
                    raise MustAsk(f"curl option {text} is unknown to the second look")
                value = None
                if option in CURL_VALUE_OPTIONS:
                    index += 1
                    if index >= len(words):
                        raise MustAsk(f"curl option {text} has no value")
                    value = words[index]
                options.append((option, value))
            else:
                prefix = word.literal_prefix()
                for offset, letter in enumerate(prefix[1:], start=1):
                    option = CURL_SHORT_OPTIONS.get(letter)
                    if option is None:
                        raise MustAsk(
                            f"curl option -{letter} is unknown to the second look"
                        )
                    if option not in CURL_VALUE_OPTIONS:
                        options.append((option, None))
                        continue
                    value = word.drop(offset + 1)
                    if not value.text:
                        index += 1
                        if index >= len(words):
                            raise MustAsk(f"curl option -{letter} has no value")
                        value = words[index]
                    options.append((option, value))
                    break
                else:
                    if len(prefix) < len(text):
                        raise MustAsk(f"a curl option is built from expansions: {text}")
        else:
            urls.append(word)
        index += 1
    for option, value in options:
        if option == "--request":
            methods.append(value)
        elif option == "--url":
            urls.append(value)
    return CurlCall(urls, methods, options, words)


def graphql_document_reads(document):
    """True when a GraphQL document holds only a query, in full or shorthand form."""
    lines = document.split("\n")
    while lines and (not lines[0].strip() or lines[0].lstrip().startswith("#")):
        lines.pop(0)
    start = "\n".join(lines).lstrip()
    return start.startswith("{") or re.match(r"query(?!\w)", start) is not None


# --- The survey ---------------------------------------------------------------------------------------------------


class Survey:
    """Every command in the command text and its scripts, with the requests, assignments and directories in them."""

    def __init__(self, cwd):
        self.cwd = pathlib.Path(cwd)
        self.commands = []
        self.texts = []
        self.gh_calls = []
        self.curl_calls = []
        self.assignments = {}
        self.bound_names = set()
        self.directories = []
        self.sourced = []
        self.surveyed = 0

    def add_text(self, text):
        self.texts.append(text)
        ShellLexer(text, self.commands).lex()
        # Surveying a command can add text, which re-enters here, so each command is claimed before it is surveyed.
        while self.surveyed < len(self.commands):
            command = self.commands[self.surveyed]
            self.surveyed += 1
            self.survey(command)

    def record_assignment(self, word):
        name, value = word.assignment()
        self.assignments.setdefault(name, []).append(value)

    def survey(self, command):
        words = command.words
        index = 0
        while index < len(words) and words[index].assignment():
            self.record_assignment(words[index])
            index += 1
        index = self.skip_prefixes(words, index)
        if index is None:
            return
        if index >= len(words):
            self.survey_heredocs(command, None)
            return
        head, arguments = words[index], words[index + 1 :]
        name = basename(head)
        if name == "gh":
            if arguments and arguments[0].text == "api":
                self.gh_calls.append(parse_gh_api(arguments[1:]))
            elif any(argument.text == "api" for argument in arguments) and arguments[
                0
            ].text.startswith("-"):
                raise MustAsk(
                    "gh takes options before api, which the second look does not follow"
                )
            self.survey_heredocs(command, name)
            return
        if name == "curl":
            self.curl_calls.append(parse_curl(arguments))
            self.survey_heredocs(command, name)
            return
        if name == "eval":
            raise MustAsk("eval runs text the second look cannot read")
        followed = set()
        if name in SHELLS:
            followed = self.survey_shell(command, arguments)
        elif name in ("source", "."):
            if not arguments or not arguments[0].literal:
                raise MustAsk(f"{name} runs a file named by an expansion")
            self.sourced.append(arguments[0].text)
        elif name in ("cd", "pushd"):
            if (
                arguments
                and arguments[-1].literal
                and not arguments[-1].text.startswith("-")
            ):
                self.directories.append(arguments[-1].text)
        elif name in ("export", "declare", "typeset", "local", "readonly"):
            for argument in arguments:
                if argument.assignment():
                    self.record_assignment(argument)
        elif name in ("read", "mapfile", "readarray"):
            self.bound_names.update(
                argument.text
                for argument in arguments
                if not argument.text.startswith("-")
            )
        elif name in ("for", "select") and arguments:
            self.bound_names.add(arguments[0].text)
        elif name == "printf" and len(arguments) > 1 and arguments[0].text == "-v":
            self.bound_names.add(arguments[1].text)
        elif name == "getopts" and len(arguments) > 1:
            self.bound_names.add(arguments[1].text)
        self.check_arguments(name, arguments, followed)
        if name not in SHELLS:
            self.survey_heredocs(command, name)

    def skip_prefixes(self, words, index):
        """The index of the command word after keywords and the wrappers that run it; None when nothing runs."""
        while index < len(words):
            word = words[index]
            name = basename(word)
            if word.text in KEYWORDS:
                index += 1
                continue
            if name in (
                "timeout",
                "nice",
                "nohup",
                "time",
                "command",
                "exec",
                "stdbuf",
                "ionice",
                "chronic",
                "setsid",
            ):
                index += 1
                if (
                    name == "command"
                    and index < len(words)
                    and words[index].text in ("-v", "-V")
                ):
                    return None
                if name == "ionice" and any(
                    w.text in ("-p", "-P", "-u", "--pid", "--pgid", "--uid")
                    for w in words
                ):
                    return None
                values = {
                    "timeout": ("-k", "--kill-after", "-s", "--signal"),
                    "nice": ("-n", "--adjustment"),
                    "exec": ("-a",),
                    "stdbuf": ("-i", "-o", "-e"),
                    "ionice": ("-c", "-n", "--class", "--classdata"),
                }.get(name, ())
                while (
                    index < len(words)
                    and words[index].text.startswith("-")
                    and words[index].text != "-"
                ):
                    index += 2 if words[index].text in values else 1
                if name == "timeout":
                    index += 1  # the duration
                continue
            if name == "env":
                index += 1
                while index < len(words):
                    text = words[index].text
                    if text.startswith("-S") or text.startswith("--split-string"):
                        raise MustAsk(
                            "env -S splits a string into a command the second look does not follow"
                        )
                    if text in ("-u", "--unset", "-C", "--chdir"):
                        index += 2
                    elif text.startswith("-"):
                        index += 1
                    elif words[index].assignment():
                        self.record_assignment(words[index])
                        index += 1
                    else:
                        break
                continue
            return index
        return index

    def survey_shell(self, command, arguments):
        """Follows a shell's -c code or heredoc; returns the indices of arguments it followed."""
        index = 0
        runs_code = reads_input = False
        while index < len(arguments):
            argument = arguments[index]
            text = argument.text
            if not argument.literal or not (
                text.startswith("-") or text.startswith("+")
            ):
                break
            if text == "--":
                index += 1
                break
            if text in ("-o", "+o", "-O", "+O", "--rcfile", "--init-file"):
                index += 2
                continue
            if not text.startswith("--"):
                runs_code = runs_code or "c" in text[1:]
                reads_input = reads_input or "s" in text[1:]
            index += 1
        if runs_code:
            if index >= len(arguments):
                raise MustAsk("a shell's -c has no code")
            code = arguments[index]
            if not code.literal:
                raise MustAsk("a shell's -c runs code built from expansions")
            self.add_text(code.text)
            return {index}
        if index < len(arguments) and not reads_input:
            return set()  # a script, which the engine's trace names
        if command.heredocs or command.here_strings:
            for heredoc in command.heredocs:
                self.add_text(heredoc.body)
            for here_string in command.here_strings:
                if not here_string.literal:
                    raise MustAsk("a shell reads a here-string built from expansions")
                self.add_text(here_string.text)
            return set()
        raise MustAsk(
            "a shell reads commands from its standard input, which the second look cannot see"
        )

    def check_arguments(self, name, arguments, followed):
        executor = name not in NON_EXECUTORS
        mention = BROAD_MENTION if executor else STRICT_MENTION
        for index, argument in enumerate(arguments):
            if index in followed:
                continue
            following = arguments[index + 1] if index + 1 < len(arguments) else None
            runs = basename(argument) == "curl" or (
                basename(argument) == "gh"
                and following is not None
                and following.text == "api"
            )
            runner = name or "a command built from expansions"
            if runs and executor:
                raise MustAsk(
                    f"{basename(argument)} runs under {runner}, which the second look cannot follow"
                )
            if not runs and mention.search(argument.unlexed_text):
                raise MustAsk(
                    f"{runner} carries text naming gh api or curl, which the second look cannot follow"
                )

    def survey_heredocs(self, command, name):
        for heredoc in command.heredocs:
            if name is not None and INTERPRETER.fullmatch(name):
                if BROAD_MENTION.search(heredoc.body):
                    raise MustAsk(
                        f"{name} reads a heredoc naming gh or curl, which the second look cannot follow"
                    )
            elif STRICT_MENTION.search(heredoc.body):
                # Over-inclusive: data that names a request is read as the script it most likely becomes.
                self.add_text(heredoc.body)
        for here_string in command.here_strings:
            if BROAD_MENTION.search(here_string.text):
                raise MustAsk(
                    "a here-string names gh or curl, which the second look cannot follow"
                )


# --- Judgement ----------------------------------------------------------------------------------------------------


class Judge:
    def __init__(self, survey, flags):
        self.survey = survey
        self.flags = flags

    def check_variable(self, name, digits):
        if name in self.survey.bound_names:
            raise MustAsk(
                f"${name} is set by a command the second look cannot evaluate"
            )
        for value in self.survey.assignments.get(name, []):
            if value is None or not value.literal:
                raise MustAsk(f"${name} is assigned from an expansion")
            if digits and not value.text.isdigit():
                raise MustAsk(
                    f"${name} is assigned {value.text!r}, which is no port number"
                )
            if re.search(r"[\s*?\[\]{}]", value.text):
                raise MustAsk(
                    f"${name} is assigned {value.text!r}, which splits into several arguments"
                )

    def check_unquoted(self, words):
        """An unquoted expansion splits into any number of arguments, options included; only plain variables pass."""
        for word in words:
            for part in word.parts:
                if part.quoted or part.kind in ("literal", "glob", "tilde"):
                    continue
                if part.kind == "variable":
                    self.check_variable(part.name, digits=False)
                else:
                    raise MustAsk(
                        f"the unquoted expansion {part.text} could add arguments"
                    )

    def judge_gh(self, call):
        names = {name for name, _ in call.options}
        endpoint = call.endpoint
        if endpoint is None:
            raise MustAsk("gh api names no endpoint")
        text = endpoint.text
        graphql = endpoint.literal and (
            text in ("graphql", "/graphql")
            or re.fullmatch(r"https://[^/\s]+/(?:api/)?graphql", text)
        )
        if not graphql:
            raise MustAsk(
                f"gh api {text} carries fields or a method, which makes it a write"
            )
        if "method" in names:
            raise MustAsk("gh api graphql sets a method")
        if "input" in names:
            raise MustAsk(
                "gh api graphql reads its request from --input, which the second look does not read"
            )
        documents = []
        for name, value in call.options:
            if name in ("raw-field", "field"):
                key, field_value = value.field()
                if key == "query":
                    documents.append((name, field_value))
        if len(documents) != 1:
            raise MustAsk(
                f"gh api graphql carries {len(documents)} query fields, and the second look reads one"
            )
        name, value = documents[0]
        if not value.literal:
            raise MustAsk("the GraphQL document is built from expansions")
        document = value.text
        if name == "field" and document.startswith("@"):
            document = self.read_document(document[1:])
        if GRAPHQL_WRITE_WORD.search(document):
            raise MustAsk("the GraphQL document holds a mutation or subscription")
        if not graphql_document_reads(document):
            raise MustAsk("the GraphQL document does not open with a query")
        self.check_unquoted(call.words)

    def read_document(self, path):
        if path == "-":
            raise MustAsk("gh api graphql reads its document from standard input")
        resolved = (
            pathlib.Path(path) if path.startswith("/") else self.survey.cwd / path
        )
        try:
            document = resolved.read_text()
        except (OSError, UnicodeDecodeError) as error:
            raise MustAsk(
                f"cannot read the GraphQL document {path}: {error.strerror or error}"
            ) from None
        self.survey.texts.append(document)
        return document

    def judge_curl(self, call):
        rerouting = sorted(
            name
            for name in call.option_names
            if name in CURL_REROUTING_OPTIONS or name.startswith("--proxy")
        )
        if rerouting:
            raise MustAsk(
                f"curl {rerouting[0]} can send the request somewhere other than its URL"
            )
        if not call.urls:
            raise MustAsk("curl names no URL")
        for url in call.urls:
            self.check_local_url(url)
        self.check_unquoted([word for word in call.words if word not in call.urls])
        self.check_curl_environment(call)

    def check_local_url(self, word):
        prefix = word.literal_prefix()
        rest = word.parts[self.literal_part_count(word) :]
        scheme = re.match(r"([A-Za-z][A-Za-z0-9+.-]*)://", prefix)
        if scheme:
            if scheme.group(1).lower() not in ("http", "https"):
                raise MustAsk(f"curl sends to a {scheme.group(1)} URL")
            after = prefix[scheme.end() :]
        elif not prefix:
            raise MustAsk(f"curl sends to {word.text}, a URL built from expansions")
        else:
            after = prefix
        end = re.search(r"[/?#]", after)
        if end or not rest:
            self.check_authority(after[: end.start()] if end else after)
            return
        # The authority runs on into an expansion: only a port in a plain variable, such as localhost:$PORT, passes.
        if not after.endswith(":"):
            raise MustAsk(
                f"curl sends to {word.text}, whose host is built from expansions"
            )
        self.check_authority(after[:-1])
        port = rest[0]
        if port.kind != "variable":
            raise MustAsk(
                f"curl sends to {word.text}, whose port is built from expansions"
            )
        if len(rest) > 1 and not (
            rest[1].kind == "literal" and rest[1].text[:1] in ("/", "?", "#")
        ):
            raise MustAsk(
                f"curl sends to {word.text}, whose authority continues past its port variable"
            )
        self.check_variable(port.name, digits=True)

    @staticmethod
    def literal_part_count(word):
        count = 0
        for part in word.parts:
            if part.kind != "literal":
                break
            count += 1
        return count

    @staticmethod
    def check_authority(authority):
        if "@" in authority:
            raise MustAsk(f"curl sends to {authority}, a URL carrying user information")
        if authority.startswith("["):
            host, _, port = authority.partition("]")
            host += "]"
            port = port[1:] if port.startswith(":") else port
        else:
            host, _, port = authority.partition(":")
        if port and not port.isdigit():
            raise MustAsk(f"curl sends to {authority}, whose port is no number")
        if host.lower() not in LOCAL_HOSTS:
            raise MustAsk(
                f"curl sends to {host or authority}, which is not this machine"
            )

    def check_curl_environment(self, call):
        for name in self.survey.assignments:
            if CURL_ENVIRONMENT.fullmatch(name):
                raise MustAsk(f"the command sets {name}, which curl reads")
        for name, value in os.environ.items():
            if value and re.fullmatch(r"(?i)(?!no_proxy$)\w*_proxy", name):
                raise MustAsk(
                    f"{name} is set in the environment, and curl sends through it"
                )
        first = call.words[0].text if call.words else ""
        if first in ("-q", "--disable"):
            return
        candidates = []
        if os.environ.get("CURL_HOME"):
            candidates.append(pathlib.Path(os.environ["CURL_HOME"]) / ".curlrc")
        if os.environ.get("XDG_CONFIG_HOME"):
            candidates.append(pathlib.Path(os.environ["XDG_CONFIG_HOME"]) / "curlrc")
        if os.environ.get("HOME"):
            candidates.append(pathlib.Path(os.environ["HOME"]) / ".curlrc")
        for candidate in candidates:
            if candidate.exists():
                raise MustAsk(f"{candidate} exists, and curl reads its options from it")


# --- Entry points -------------------------------------------------------------------------------------------------


def resolve_script(survey, script):
    """The file the engine read, found by its traced path and size, trying every directory the command enters.

    The engine passes its trace through a secret redactor, which can replace a step's path; such a step asks.
    """
    path, size = script.get("path"), script["bytes"]
    if not path or path == "<redacted>":
        raise MustAsk("the engine's trace names no path for a script it read")
    if path.startswith("/"):
        candidates = [pathlib.Path(path)]
    else:
        candidates = [survey.cwd / path] + [
            (
                pathlib.Path(directory)
                if directory.startswith("/")
                else survey.cwd / directory
            )
            / path
            for directory in survey.directories
        ]
    found = {
        candidate.resolve()
        for candidate in candidates
        if candidate.is_file() and candidate.stat().st_size == size
    }
    if not found:
        raise MustAsk(f"cannot find the script {path}")
    if len(found) > 1:
        raise MustAsk(f"the script {path} could be any of {len(found)} files")
    return found.pop()


def classify(command, cwd, scripts, rule, rulebook):
    try:
        kind = REQUEST_RULES.get(rule)
        if kind is None:
            raise MustAsk(f"the second look does not judge {rule}")
        flags = RequestFlags.load(rulebook)
        survey = Survey(cwd)
        survey.add_text(command)
        read_scripts = set()
        for script in scripts:
            path = resolve_script(survey, script)
            try:
                text = path.read_text()
            except (OSError, UnicodeDecodeError) as error:
                raise MustAsk(
                    f"cannot read the script {script['path']}: {error}"
                ) from None
            read_scripts.add(path)
            survey.add_text(text)
        for sourced in survey.sourced:
            candidate = (
                pathlib.Path(sourced)
                if sourced.startswith("/")
                else survey.cwd / sourced
            )
            if candidate.resolve() not in read_scripts:
                raise MustAsk(
                    f"the command sources {sourced}, which the engine did not read"
                )
        judge = Judge(survey, flags)
        gh_writes = [call for call in survey.gh_calls if call.carries(flags)]
        curl_writes = [call for call in survey.curl_calls if call.carries(flags)]
        if not (gh_writes if kind == "gh" else curl_writes):
            raise MustAsk(
                f"found no {kind} request with write flags, where the engine stopped"
            )
        for call in gh_writes:
            judge.judge_gh(call)
        for call in curl_writes:
            judge.judge_curl(call)
        if gh_writes and any(GRAPHQL_WRITE_WORD.search(text) for text in survey.texts):
            raise MustAsk(
                "a GraphQL mutation or subscription appears in the command or a script it runs"
            )
    except MustAsk as reason:
        return Verdict(False, str(reason))
    return Verdict(
        True,
        f"{len(gh_writes)} GraphQL queries and {len(curl_writes)} requests to this machine, all reads",
    )


def main():
    request = json.load(sys.stdin)
    verdict = classify(
        command=request["command"],
        cwd=request["cwd"],
        scripts=request["scripts"],
        rule=request["rule"],
        rulebook=request["rulebook"],
    )
    json.dump(
        {"verdict": "reads" if verdict.reads else "ask", "reason": verdict.reason},
        sys.stdout,
    )
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
