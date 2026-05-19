function indeterminateTaskPlugin(md) {
  function addAttr(token, key, value) {
    var existing = token.attrGet(key);
    token.attrSet(key, existing ? existing + " " + value : value);
  }

  function findListOpen(tokens, listItemIndex) {
    var level = tokens[listItemIndex].level - 1;
    for (var i = listItemIndex - 1; i >= 0; i--) {
      if (
        tokens[i].level === level &&
        (tokens[i].type === "bullet_list_open" ||
          tokens[i].type === "ordered_list_open")
      ) {
        return i;
      }
    }
    return -1;
  }

  md.core.ruler.push("indeterminate-task-lists", function (state) {
    var tokens = state.tokens;

    for (var i = 2; i < tokens.length; i++) {
      if (tokens[i].type !== "inline") continue;
      if (tokens[i - 2].type !== "list_item_open") continue;
      if (tokens[i].content.indexOf("[-] ") !== 0) continue;

      var token = tokens[i];

      var checkbox = new state.Token("html_inline", "", 0);
      checkbox.content =
        '<input class="task-list-item-checkbox indeterminate" disabled="" type="checkbox">';

      token.children.unshift(checkbox);
      token.children[1].content = token.children[1].content.slice(3);
      token.content = token.content.slice(3);

      addAttr(tokens[i - 2], "class", "task-list-item");

      var listOpenIndex = findListOpen(tokens, i - 2);
      if (listOpenIndex >= 0) {
        addAttr(tokens[listOpenIndex], "class", "contains-task-list");
      }
    }
  });
}

(function () {
  if (typeof document === "undefined") return;

  function apply(root) {
    var inputs = root.querySelectorAll
      ? root.querySelectorAll("input.indeterminate")
      : [];
    for (var i = 0; i < inputs.length; i++) {
      inputs[i].indeterminate = true;
    }
  }

  new MutationObserver(function (mutations) {
    for (var i = 0; i < mutations.length; i++) {
      var added = mutations[i].addedNodes;
      for (var j = 0; j < added.length; j++) {
        if (added[j].nodeType === 1) apply(added[j]);
      }
    }
  }).observe(document.documentElement, { childList: true, subtree: true });

  apply(document);
})();
