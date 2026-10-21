# Prepares the daily standup an hour ahead, so the sheet is ready and there is time to act on what it flags.
{
  triggers.schedule = {
    at = "Mon..Fri 10:00";
    # The standup is at 11:00. From then on the skill prepares the next day's standup instead.
    maximum-drift = "50min";
  };
  # The skill writes the sheet only once every source it reads has answered, so a missing file means a failed attempt.
  prompt = "/stans-additions:prepare-standup Write the finished sheet to {{output}}";
  output = "/data/tmp/cosuno/standups/{{run}}.md";
  # A source that is down for a few minutes, such as the claude.ai connector list, gets three more chances.
  retry = {
    attempts = 4;
    delay = "2min";
  };
  session = {
    cwd = "/data/projects/github.com/cosuno/cosuno";
    profile = "cosuno";
  };
}
