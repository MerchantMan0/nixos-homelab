{ config, nixpkgs-unstable, ... }:

let
  booksPath = "/mnt/gv0";
  port = 3000;
in
{
  imports = [ "${nixpkgs-unstable}/nixos/modules/services/web-apps/bookorbit.nix" ];

  nixpkgs.overlays = [
    (final: prev: {
      bookorbit = nixpkgs-unstable.legacyPackages.${prev.stdenv.hostPlatform.system}.bookorbit;
    })
  ];

  services.bookorbit = {
    enable = true;
    environment = {
      PORT = port;
      APP_URL = "http://paleo:${toString port}";
      LIBRARY_BROWSE_ROOT = booksPath;
    };
    environmentFile = config.sops.templates."bookorbit-env".path;
  };

  sops.secrets.bookorbit_jwt_secret.sopsFile = ../secrets/paleo.yaml;
  sops.secrets.bookorbit_setup_token.sopsFile = ../secrets/paleo.yaml;
  sops.secrets.bookorbit_podcast_encryption_key.sopsFile = ../secrets/paleo.yaml;
  sops.templates."bookorbit-env" = {
    content = ''
      JWT_SECRET=${config.sops.placeholder.bookorbit_jwt_secret}
      SETUP_BOOTSTRAP_TOKEN=${config.sops.placeholder.bookorbit_setup_token}
      PODCAST_ENCRYPTION_KEY=${config.sops.placeholder.bookorbit_podcast_encryption_key}
    '';
    restartUnits = [ "bookorbit.service" ];
  };

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
    config.services.bookorbit.environment.PORT
  ];

  systemd.services.bookorbit = {
    requires = [ "mnt-gv0.mount" ];
    after = [ "mnt-gv0.mount" ];
    serviceConfig.BindReadOnlyPaths = [ booksPath ];
  };
}
