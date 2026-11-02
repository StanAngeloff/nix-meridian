---
name: dictated
description: Use when Stan types /dictated before a message, or sends a long message whose punctuation, sentences, paragraphs and capitalisation are uniformly clean, the mark of his speech-to-text with a cleanup pass. Words in such a message can be misheard, with an acronym, a name, a file or a code term replaced by a similar-sounding one.
---

# Dictated messages

Stan dictates long messages. A transcription service turns his audio into text, and a cleanup model fixes punctuation, casing, sentences and paragraphs. The cleanup cannot fix a misheard word, so a dictated message can carry a term, acronym, name or file name replaced by one that sounds alike. `/dictated` before a message means: dictated, not read back.

## Dictated or typed

| Dictated                                                  | Typed                                                 |
| --------------------------------------------------------- | ----------------------------------------------------- |
| long, often several paragraphs                            | short, one or two lines                               |
| clean punctuation, capitals and full sentences throughout | loose punctuation, lowercase starts, typos, fragments |

A message after `/dictated` is dictated, whatever it looks like.

## Reading a dictated message

1. Check each term that carries meaning (an acronym, a name, a file, a code identifier, a unit) against the conversation, the journal, the code and the domain. A term that fits none of them but sounds like one that does is a likely slip, such as "AC pool size" for "SC pool size" or "Claude.lockout.md" for "CLAUDE.local.md".
2. Work from the reading that matches what was discussed and the area being worked on. Never stop the work to ask.
3. Open the reply with one line per suspected slip, in this shape:
   `Dictation check: I read "<as written>" as "<reading>" and worked from that. Tell me if you meant something else.`
   Name every suspected slip, the ones you are sure of included. A silent correction leaves Stan no way to catch a wrong reading.
4. Where his words are quoted elsewhere (a journal, notes, a story), quote them as written and put the reading beside them.
5. Once he confirms or corrects a reading, it is settled. Never raise it again.
