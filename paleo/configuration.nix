{ config, pkgs, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
    ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "paleo";

  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;

  networking.networkmanager.enable = true;

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

  users.users."paleo" = {
    isNormalUser = true;
    description = "paleo";
    extraGroups = [ "networkmanager" "wheel" ];
  };

  nixpkgs.config.allowUnfree = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 22 5432 ];

  # PostgreSQL primary
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_17;
    enableTCPIP = true;
    settings = {
      wal_level = "replica";
      max_wal_senders = 5;
      max_replication_slots = 5;
      synchronous_standby_names = "FIRST 1 (enneacraft)";
      synchronous_commit = "on";
    };
    ensureUsers = [
      { name = "replicator"; ensureClauses.replication = true; }
    ];
    # Replication is only reachable over Tailscale (CGNAT range), password required.
    authentication = pkgs.lib.mkAfter ''
      host replication replicator 100.64.0.0/10 scram-sha-256
    '';
  };

  sops.secrets.pg_replicator_password = {
    sopsFile = ../secrets/common.yaml;
    owner = "postgres";
  };
  systemd.services.postgresql-setup.environment.PGOPTIONS = "-c synchronous_commit=local";
  systemd.services.postgresql-setup.script = pkgs.lib.mkAfter ''
    psql -d postgres -v ON_ERROR_STOP=1 -v pw="$(cat ${config.sops.secrets.pg_replicator_password.path})" <<'SQL'
      ALTER ROLE replicator PASSWORD :'pw';
    SQL
  '';

  services.tailscale = {
    enable = true;
    openFirewall = true;
  };

  system.stateVersion = "26.05";

}
