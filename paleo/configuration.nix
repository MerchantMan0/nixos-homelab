{ config, pkgs, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
      ../options/gluster.nix
      ../options/postgresql.nix
      ../options/flaresolverr.nix
      ../options/suwayomi-server.nix
    ];

  networking.hostName = "paleo";

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
    after = [ "glusterd.service" "tailscaled.service" ];
    wants = [ "glusterd.service" ];
    path = [ pkgs.glusterfs pkgs.gnugrep ];
    serviceConfig.Type = "oneshot";
    script = ''
      g() { gluster --mode=script "$@"; }
      notready() { echo "gluster peer not ready yet, will retry: $*"; exit 0; }

      g peer probe enneacraft >/dev/null 2>&1 || notready "peer probe failed"
      g peer status | grep -q "Peer in Cluster (Connected)" || notready "peer not connected"

      if ! g volume info gv0 >/dev/null 2>&1; then
        g volume create gv0 replica 2 \
          paleo:/var/lib/glusterfs/bricks/gv0 enneacraft:/var/lib/glusterfs/bricks/gv0 force
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
