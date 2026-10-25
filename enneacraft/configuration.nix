{ config, pkgs, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
    ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "enneacraft";

  networking.networkmanager.enable = true;
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;
  time.timeZone = "America/New_York";

  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  services.xserver.enable = false;
  services.displayManager.sddm.enable = false;
  services.desktopManager.plasma6.enable = false;

  console.keyMap = "us";

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  users.users."enneacraft" = {
    isNormalUser = true;
    description = "enneacraft";
    extraGroups = [ "networkmanager" "wheel" ];
  };

  nixpkgs.config.allowUnfree = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # follower postgres
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_17;
    enableTCPIP = true;
    settings = {
      hot_standby = true;
      primary_conninfo = "host=paleo user=replicator application_name=enneacraft passfile=${config.sops.templates."pgpass".path}";
      primary_slot_name = "enneacraft";
    };
  };

  sops.secrets.pg_replicator_password.sopsFile = ../secrets/common.yaml;
  sops.templates."pgpass" = {
    content = "paleo:5432:*:replicator:${config.sops.placeholder.pg_replicator_password}\n";
    owner = "postgres";
    mode = "0400";
  };

  systemd.services.postgresql.preStart = pkgs.lib.mkBefore ''
    if ! test -e ${config.services.postgresql.dataDir}/PG_VERSION; then
      export PGPASSFILE=${config.sops.templates."pgpass".path}
      until pg_basebackup \
        -d "host=paleo user=replicator application_name=enneacraft" \
        -D ${config.services.postgresql.dataDir} \
        -X stream -C -S enneacraft; do
        echo "waiting for paleo primary..."; rm -rf ${config.services.postgresql.dataDir}/*; sleep 5
      done
      touch ${config.services.postgresql.dataDir}/standby.signal
    fi
  '';

  services.tailscale = {
    enable = true;
    openFirewall = true;
  };
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 22 5432 24007 24008 ];

  # sops-nix test: decrypted at activation to /run/secrets/test_secret
  sops.defaultSopsFile = ../secrets/enneacraft.yaml;
  sops.secrets.test_secret = { };

  services.glusterfs.enable = true;
  environment.systemPackages = [ pkgs.glusterfs ];
  systemd.tmpfiles.rules = [
    "d /var/lib/glusterfs/bricks/gv0 0755 root root -"
    "d /mnt/gv0 0755 root root -"
  ];
  networking.firewall.interfaces."tailscale0".allowedTCPPortRanges = [
    { from = 49152; to = 49251; }
  ];
  fileSystems."/mnt/gv0" = {
    device = "localhost:/gv0";
    fsType = "glusterfs";
    options = [ "_netdev" "nofail" "x-systemd.automount" "x-systemd.requires=glusterd.service" ];
  };

  system.stateVersion = "26.05";

}
