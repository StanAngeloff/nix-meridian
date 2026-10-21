# A job is a Claude Code prompt that runs headless in a directory whenever one of its triggers fires.
# Each job gets a systemd user service that runs it once through claude-jobs (./jobs.sh), plus one unit per trigger.
# Every file in ./entries declares one job under nix-meridian.claude.jobs, named for the file.
{ claude-jobs }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  jobs = config.nix-meridian.claude.jobs;

  scheduleTrigger = types.submodule {
    options = {
      at = mkOption {
        type = types.coercedTo types.str lib.singleton (types.nonEmptyListOf types.str);
        example = "Mon..Fri 10:00";
        description = "The systemd OnCalendar expressions the job runs at, one or a list. The build fails on one systemd-analyze cannot parse.";
      };
      maximum-drift = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "50min";
        description = "How late a missed slot may still run, as a systemd time span. A slot missed while the machine slept or was off runs once the machine is back, unless the slot lies further back than this. null runs every missed slot.";
      };
    };
  };

  jobType = types.submodule {
    options = {
      triggers.schedule = mkOption {
        type = types.nullOr scheduleTrigger;
        default = null;
        description = "Runs the job at fixed times, through a systemd timer.";
      };
      prompt = mkOption {
        type = types.nonEmptyStr;
        example = "/stans-additions:prepare-standup Write the finished sheet to {{output}}";
        description = "The prompt the session runs headless. A slash command runs that command or skill. {{output}} stands for the run's output file.";
      };
      output = mkOption {
        type = types.nullOr (types.strMatching "/.*");
        default = null;
        example = "/data/tmp/cosuno/standups/{{run}}.md";
        description = "A file the session must write for an attempt to succeed, with {{run}} standing for the run's stamp. It must lie where the session's bubble can write. null judges an attempt by its exit and its final message alone.";
      };
      retry = {
        attempts = mkOption {
          type = types.ints.positive;
          default = 1;
          description = "How many times a run is attempted before it counts as failed.";
        };
        delay = mkOption {
          type = types.str;
          default = "1min";
          description = "The wait before the second attempt, as a systemd time span. Each later wait doubles the one before it.";
        };
      };
      session = {
        cwd = mkOption {
          type = types.strMatching "/.*";
          description = "The directory the session starts in, which decides its plugins, its .mcp.json servers and the .envrc it loads.";
        };
        profile = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "The account profile the session runs as (cc -P). null runs as whichever profile is active when the job starts.";
        };
        prefix = mkOption {
          type = types.str;
          default = "x-";
          description = "The start of the session name, which reads <prefix><job>-<run>. An .envrc can require session names to match a pattern.";
        };
        timeout = mkOption {
          type = types.str;
          default = "1h";
          description = "How long one attempt may take, as a systemd time span. An attempt that takes longer is stopped and counts as failed.";
        };
      };
    };
  };

  # The job as claude-jobs reads it. The build fails on an OnCalendar expression or a time span systemd-analyze rejects.
  jobFile =
    name: job:
    pkgs.runCommand "claude-job-${name}.json"
      {
        nativeBuildInputs = [
          pkgs.jq
          pkgs.systemd
        ];
        job = builtins.toJSON {
          inherit name;
          inherit (job) prompt output;
          triggers.schedule = lib.mapNullable (schedule: {
            inherit (schedule) at maximum-drift;
          }) job.triggers.schedule;
          retry = {
            inherit (job.retry) attempts delay;
          };
          session = {
            inherit (job.session)
              cwd
              profile
              prefix
              timeout
              ;
          };
        };
        passAsFile = [ "job" ];
      }
      ''
        fail() {
          echo "nix-meridian.claude.jobs.${name}: $*" >&2
          exit 1
        }

        # Prints a systemd time span in whole seconds.
        seconds() {
          local spans
          spans=$(systemd-analyze timespan "$1") || fail "'$1' is not a systemd time span"
          echo $(($(awk '$2 ~ /^[0-9]+$/ { print $2 }' <<<"$spans") / 1000000))
        }

        mapfile -t expressions < <(jq -r '.triggers.schedule.at[]?' "$jobPath")
        for expression in "''${expressions[@]}"; do
          systemd-analyze calendar "$expression" >/dev/null || fail "systemd-analyze cannot parse '$expression'"
        done

        delay=$(seconds "$(jq -r '.retry.delay' "$jobPath")") || exit 1
        timeout=$(seconds "$(jq -r '.session.timeout' "$jobPath")") || exit 1
        drift=$(jq -r '.triggers.schedule["maximum-drift"] // empty' "$jobPath")
        if [ -n "$drift" ]; then
          drift=$(seconds "$drift") || exit 1
        else
          drift=null
        fi
        jq --argjson delay "$delay" --argjson timeout "$timeout" --argjson drift "$drift" '
          .retry["delay-seconds"] = $delay
          | .session["timeout-seconds"] = $timeout
          | if $drift == null then . else .triggers.schedule["maximum-drift-seconds"] = $drift end
        ' "$jobPath" >"$out"
      '';

  scheduledJobs = lib.filterAttrs (_: job: job.triggers.schedule != null) jobs;
in
{
  options.nix-meridian.claude.jobs = mkOption {
    type = types.attrsOf jobType;
    default = { };
    description = "Claude Code sessions that run headless on their own, by job name. `cc jobs run <job>` starts one by hand. `cc jobs resume <job>` reopens its latest run.";
  };

  config = {
    nix-meridian.claude.jobs =
      lib.mapAttrs'
        (file: _: lib.nameValuePair (lib.removeSuffix ".nix" file) (import (./entries + "/${file}")))
        (
          lib.filterAttrs (file: kind: kind == "regular" && lib.hasSuffix ".nix" file) (
            builtins.readDir ./entries
          )
        );

    assertions = lib.mapAttrsToList (name: job: {
      assertion = job.triggers.schedule != null;
      message = "nix-meridian.claude.jobs.${name}: set a trigger, such as triggers.schedule";
    }) jobs;

    systemd.user.services = lib.mapAttrs' (
      name: job:
      lib.nameValuePair "claude-job-${name}" {
        Unit.Description = "Claude Code job ${name}";
        Service = {
          Type = "oneshot";
          ExecStart = "${lib.getExe claude-jobs} execute ${jobFile name job}";
          # claude-jobs finds claude-cc in the profile. The session also runs the profile's tools (python3, git, gh, jq)
          # inside the bubble. So PATH names the profile rather than leaving the run with whatever the user manager inherited.
          Environment = [
            "PATH=/run/wrappers/bin:${config.home.profileDirectory}/bin:/run/current-system/sw/bin"
          ];
          # claude-jobs limits each attempt to session.timeout. A limit on the whole service would have to cover every
          # attempt and every wait between them.
          TimeoutStartSec = "infinity";
        };
      }
    ) jobs;

    systemd.user.timers = lib.mapAttrs' (
      name: job:
      lib.nameValuePair "claude-job-${name}" {
        Unit.Description = "Schedule of Claude Code job ${name}";
        Timer = {
          OnCalendar = job.triggers.schedule.at;
          # A slot missed while the machine slept or was off runs once the machine is back.
          # claude-jobs skips a slot further back than the job's maximum drift.
          Persistent = true;
        };
        Install.WantedBy = [ "timers.target" ];
      }
    ) scheduledJobs;
  };
}
