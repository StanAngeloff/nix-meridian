{
  systemd.tmpfiles.rules = [
    "d \"/data/\" 0755 stan users -"
    "d \"/data/projects/\" 0755 stan users -"
    "d \"/data/projects/github.com/\" 0755 stan users -"
    "d \"/data/public/\" 0755 stan users -"
    "d \"/data/public/github.com/\" 0755 stan users -"
  ];
}
