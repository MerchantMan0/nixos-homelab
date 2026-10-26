{ config, pkgs, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
      ../options/gluster.nix
      ../options/postgresql.nix
      ../options/flaresolverr.nix
      ../options/suwayomi-server.nix
      ../options/bookorbit.nix
    ];

  networking.hostName = "paleo";

  fileSystems."/mnt/hdd" = {
    device = "/dev/disk/by-uuid/77cde92d-a48c-4214-b2d5-6428a6ac01b2";
    fsType = "ext4";
  };

  systemd.tmpfiles.rules = [
    "d /mnt/hdd/bricks/gv0 0755 root root -"
  ];

  users.users."paleo" = {
    isNormalUser = true;
    description = "paleo";
    extraGroups = [ "networkmanager" "wheel" ];
  };

  custom.postgresql = {
    enable = true;
    role = "primary";
    primaryHost = "paleo";
    standbys = [ "enneacraft" ];
    sopsFile = ../secrets/common.yaml;
  };

  # bootstrap
  systemd.services.gluster-bootstrap = {
    description = "Bootstrap GlusterFS pool and volume";
    after = [ "glusterd.service" "tailscaled.service" "mnt-hdd.mount" ];
    wants = [ "glusterd.service" "mnt-hdd.mount" ];
    path = [ pkgs.glusterfs pkgs.gnugrep ];
    serviceConfig.Type = "oneshot";
    script = ''
      g() { gluster --mode=script "$@"; }
      notready() { echo "gluster peer not ready yet, will retry: $*"; exit 0; }

      g peer probe enneacraft >/dev/null 2>&1 || notready "peer probe failed"
      g peer status | grep -q "Peer in Cluster (Connected)" || notready "peer not connected"

      if ! g volume info gv0 >/dev/null 2>&1; then
        g volume create gv0 replica 2 \
          paleo:/mnt/hdd/bricks/gv0 enneacraft:/var/lib/glusterfs/bricks/gv0 force
      fi
      g volume info gv0 | grep -q "Status: Started" || g volume start gv0
    '';
  };
  systemd.timers.gluster-bootstrap = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnActiveSec = "30s";
      OnUnitInactiveSec = "1min";
    };
  };

}
