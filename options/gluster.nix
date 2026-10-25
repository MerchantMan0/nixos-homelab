{ pkgs, ... }:

{
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
}
