/**
 * A markdown-it plugin to parse @./file references, inspired by Flemma's Lua parser.
 *
 * This plugin finds references like:
 * - @./file.txt
 * - @./path/to/file.txt
 * - @../file.txt
 * - @./file%20with%20spaces.txt
 * - @./file.txt;type=text/plain
 *
 * It handles URL decoding, strips trailing punctuation, and parses an optional MIME type override, converting the reference into an <x-file-ref> HTML tag.
 */
function fileRefPlugin(md) {
  // Regex to find potential file references starting with @./ or @../
  // It's intentionally greedy (\S+) to capture the path and any trailing punctuation or MIME type, which we'll parse manually.
  const FILE_REF_RE = /@(\.\.?\/\S+)/g;

  // Regex to detect and strip common trailing punctuation.
  const TRAILING_PUNCTUATION_RE = /[.,!?;:]+$/;

  /**
   * Decodes a URL-encoded string.
   *
   * Also converts '+' to spaces, which is part of the 'application/x-www-form-urlencoded' spec and used in the reference Lua code.
   *
   * @param {string} s The string to decode.
   *
   * @returns {string} The decoded string.
   */
  function urlDecode(s) {
    if (!s) return "";

    // First, replace '+' with spaces, then use decodeURIComponent for %xx sequences.
    return decodeURIComponent(s.replace(/\+/g, " "));
  }

  /**
   * Sanitizes a string for use as an HTML attribute value.
   *
   * @param {string} s The string to sanitize.
   *
   * @returns {string} The sanitized string.
   */
  function htmlEncode(s) {
    return s
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function fileRefRule(state) {
    const Token = state.Token;

    // Iterate through all tokens, but only act on 'text' tokens
    for (let i = 0; i < state.tokens.length; i++) {
      const token = state.tokens[i];
      if (token.type !== "text") continue;

      const text = token.content;
      FILE_REF_RE.lastIndex = 0; // Reset regex state
      let match;
      let lastIndex = 0;
      const newNodes = [];

      // Loop through all file reference matches in the current text token
      while ((match = FILE_REF_RE.exec(text)) !== null) {
        const fullMatch = match[0]; // e.g., '@./file.pdf.'
        let payload = match[1]; // e.g., './file.pdf.'

        // Push any text that appeared before this match
        if (match.index > lastIndex) {
          const textToken = new Token("text", "", 0);
          textToken.content = text.slice(lastIndex, match.index);
          newNodes.push(textToken);
        }

        // --- Start of logic adapted from the Lua parser ---
        let rawPath = "";
        let mimeOverride = null;
        let trailingPunctuation = "";

        const mimeMatch = payload.match(/^(.*?);type=(.*)$/);
        if (mimeMatch) {
          // Case 1: A MIME type override is present (e.g., './file.pdf;type=app/pdf.')
          rawPath = mimeMatch[1];
          const mimeWithPunct = mimeMatch[2];

          // Strip punctuation only from the MIME part, as per Lua logic
          const puncMatch = mimeWithPunct.match(TRAILING_PUNCTUATION_RE);
          trailingPunctuation = puncMatch ? puncMatch[0] : "";
          mimeOverride = mimeWithPunct.substring(0, mimeWithPunct.length - trailingPunctuation.length);
        } else {
          // Case 2: No MIME type override (e.g., './file.pdf.')
          const pathWithPunct = payload;

          // Strip punctuation from the path part
          const puncMatch = pathWithPunct.match(TRAILING_PUNCTUATION_RE);
          trailingPunctuation = puncMatch ? puncMatch[0] : "";
          rawPath = pathWithPunct.substring(0, pathWithPunct.length - trailingPunctuation.length);
        }
        // --- End of adapted logic ---

        // The part of the original string that forms the reference (without trailing punctuation)
        const referenceText = "@" + rawPath + (mimeOverride ? `;type=${mimeOverride}` : "");

        // Create the attributes for the HTML tag
        const decodedPath = urlDecode(rawPath);
        const titleAttr = `title="${htmlEncode(decodedPath.replace(/^[.\/]+/g, ""))}"`;
        const mimeAttr = mimeOverride ? ` mime-override="${htmlEncode(mimeOverride)}"` : "";

        // Create the unescaped HTML token
        const htmlToken = new Token("html_inline", "", 0);
        htmlToken.content = `<x-file-ref ${titleAttr}${mimeAttr}>${md.utils.escapeHtml(referenceText)}</x-file-ref>`;
        newNodes.push(htmlToken);

        // Update the last index to the end of the reference part
        lastIndex = match.index + referenceText.length;
      }

      // If no matches were found, just continue to the next token
      if (newNodes.length === 0) {
        continue;
      }

      // Add any remaining text after the last match
      if (lastIndex < text.length) {
        const tailToken = new Token("text", "", 0);
        tailToken.content = text.slice(lastIndex);
        newNodes.push(tailToken);
      }

      // Replace the original text token with the new sequence of text/html tokens
      state.tokens.splice(i, 1, ...newNodes);
      // Adjust the loop index to account for the newly inserted tokens
      i += newNodes.length - 1;
    }
  }

  // Add the rule to the 'inline' ruler. 'ruler2' runs after default rules.
  md.inline.ruler2.push("file_ref", fileRefRule);
}
