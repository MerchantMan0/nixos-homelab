{ config, pkgs, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
      ../options/gluster.nix
      ../options/postgresql.nix
    ];

  networking.hostName = "enneacraft";

  users.users."enneacraft" = {
    isNormalUser = true;
    description = "enneacraft";
    extraGroups = [ "networkmanager" "wheel" ];
  };

  custom.postgresql = {
    enable = true;
    role = "follower";
    primaryHost = "paleo";
    sopsFile = ../secrets/common.yaml;
  };

  # sops-nix test: decrypted at activation to /run/secrets/test_secret
  sops.defaultSopsFile = ../secrets/enneacraft.yaml;
  sops.secrets.test_secret = { };

}
