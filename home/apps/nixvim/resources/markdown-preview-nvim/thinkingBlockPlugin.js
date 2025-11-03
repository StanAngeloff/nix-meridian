function thinkingBlockPlugin(md) {
  function thinkingBlockRule(state, startLine, endLine, silent) {
    const startTag = /^\s*<thinking>\s*$/;
    const endTag = /^\s*<\/thinking>\s*$/;

    // --- Find the start of the block ---
    const startPos = state.bMarks[startLine] + state.tShift[startLine];
    const startMax = state.eMarks[startLine];
    const startLineText = state.src.substring(startPos, startMax);

    if (!startTag.test(startLineText)) return false;
    if (silent) return true;

    // --- Find the end of the block ---
    let nextLine = startLine + 1;
    let endLineFound = -1;
    while (nextLine < endLine) {
      const lineText = state.src.substring(state.bMarks[nextLine] + state.tShift[nextLine], state.eMarks[nextLine]);
      if (endTag.test(lineText)) {
        endLineFound = nextLine;
        break;
      }
      nextLine++;
    }

    if (endLineFound === -1) return false;

    // --- Generate Tokens ---
    const oldParent = state.parentType;
    const oldLineMax = state.lineMax;
    state.parentType = "container";
    state.lineMax = endLineFound;

    // [1] Push opening <details> and placeholder <summary> tokens
    let token = state.push("details_open", "details", 1);
    token.attrSet("class", "x-thinking");
    token.map = [startLine, endLineFound];

    token = state.push("summary_open", "summary", 1);
    // We need the index of the inline token to update its content later
    const summaryInlineTokenIndex = state.tokens.length;
    token = state.push("inline", "", 0);
    token.content = "Thinking..."; // Placeholder
    token.children = [];
    token = state.push("summary_close", "summary", -1);

    // [2] Recursively process the content between the tags.
    // This will add all the tokens for the inner content to `state.tokens`.
    const tokensBeforeContent = state.tokens.length;
    state.md.block.tokenize(state, startLine + 1, endLineFound);
    const tokensAfterContent = state.tokens.length;

    // [3] Extract plain text from the newly generated inner tokens.
    let innerTextContent = "";
    for (let i = tokensBeforeContent; i < tokensAfterContent; i++) {
      const innerToken = state.tokens[i];
      // We only care about the content of 'inline' tokens, which hold the text.
      // We also check for code blocks to include their content.
      if (innerToken.type === "inline" || innerToken.type === "fence") {
        innerTextContent += ` ${innerToken.content} `;
      }
    }

    // [4] Generate the dynamic summary string
    let summaryText = innerTextContent.replace(/\s+/g, " ").trim(); // Normalize whitespace
    if (summaryText.length > 120) {
      summaryText = summaryText.substring(0, 120 - 1) + "…";
    }

    // [5] Update the placeholder summary token with the new content
    // If there was no text content, keep the default "Thinking..."
    if (summaryText) {
      state.tokens[summaryInlineTokenIndex].content =
        `<span class="thinking-tag tag-open">&lt;thinking&gt;</span>${summaryText}<span class="thinking-tag tag-close">&lt;/thinking&gt;</span>`;
    }

    // [6] Push closing </details> token
    token = state.push("details_close", "details", -1);

    // --- Update parser state ---
    state.parentType = oldParent;
    state.lineMax = oldLineMax;
    state.line = endLineFound + 1;

    return true;
  }

  md.block.ruler.before("fence", "thinking_details", thinkingBlockRule, {
    alt: ["paragraph", "reference", "blockquote", "list"],
  });
}
