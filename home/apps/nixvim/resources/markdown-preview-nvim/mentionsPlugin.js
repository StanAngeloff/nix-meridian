function mentionsPlugin(md) {
  md.core.ruler.push("x_mention", function (state) {
    const Token = state.Token;
    const tokens = state.tokens;

    const RE = /^@(System|You|Assistant)\b([ \t]*:)?/;

    for (let i = 0; i < tokens.length; i++) {
      const token = tokens[i];

      if (token.type !== "inline" || !token.children) continue;

      const children = token.children;
      const newChildren = [];

      let atLineStart = true;

      for (let j = 0; j < children.length; j++) {
        const child = children[j];

        if (child.type === "softbreak" || child.type === "hardbreak") {
          newChildren.push(child);
          atLineStart = true;
          continue;
        }

        if (child.type !== "text") {
          newChildren.push(child);
          atLineStart = false;
          continue;
        }

        if (atLineStart) {
          const m = RE.exec(child.content);
          if (m) {
            const role = m[1];
            const trailing = m[2] || "";
            const hasColon = trailing.length > 0;

            let inner = "@" + role;
            if (hasColon) inner += '<span class="mention-colon">:</span>';

            const html = new Token("html_inline", "", 0);
            html.content = `<x-mention role="${role}">${inner}</x-mention>`;
            newChildren.push(html);

            const rest = child.content.slice(m[0].length);
            if (rest) {
              const tail = new Token("text", "", 0);
              tail.content = rest;
              newChildren.push(tail);
            }

            atLineStart = false;
            continue;
          }
        }

        newChildren.push(child);
        atLineStart = false;
      }

      token.children = newChildren;
    }
  });
}
