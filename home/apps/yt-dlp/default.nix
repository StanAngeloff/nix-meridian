{
  programs.yt-dlp = {
    enable = true;

    settings = {
      # NOTE: YouTube's JavaScript challenges need a runtime and yt-dlp only enables Deno by default.
      js-runtimes = "bun";
    };
  };
}
