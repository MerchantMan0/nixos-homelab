{ config, lib, pkgs, ... }:

let
  downloadsPath = "/mnt/gv0/suwayomi";
  user = config.services.suwayomi-server.user;
  group = config.services.suwayomi-server.group;
in
{
  # this is a patch for latest version
  services.suwayomi-server = {
    enable = true;
    package = pkgs.suwayomi-server.overrideAttrs (_prev: {
      version = "2.4.2366";
      src = pkgs.fetchurl {
        url = "https://github.com/Suwayomi/Suwayomi-Server/releases/download/v2.4.2366/Suwayomi-Server-v2.4.2366.jar";
        hash = "sha256-r5/rIK+dfr6eMHaebG68f8erHERziNQuAoCx2l/ge/0=";
      };
    });
    settings.server = {
      extensionStores = [ "$SUWAYOMI_EXTENSION_STORE" ];
      downloadAsCbz = true;
      autoDownloadNewChapters = true;
      downloadsPath = downloadsPath;
      # postgres db
      databaseType = "POSTGRESQL";
      databaseUrl = "postgresql://127.0.0.1:${toString config.services.postgresql.settings.port}/suwayomi";
      databaseUsername = "suwayomi";
      databasePassword = "$SUWAYOMI_DB_PASSWORD";
      flareSolverrEnabled = true;
      flareSolverrUrl = "http://127.0.0.1:${toString config.services.flaresolverr.port}";
    };
  };

  services.postgresql = {
    ensureDatabases = [ "suwayomi" ];
    ensureUsers = [
      {
        name = "suwayomi";
        ensureDBOwnership = true;
      }
    ];
  };

  sops.secrets.suwayomi_extension_store.sopsFile = ../secrets/paleo.yaml;
  sops.secrets.suwayomi_db_password = {
    sopsFile = ../secrets/paleo.yaml;
    owner = "postgres";
  };
  sops.templates."suwayomi-env" = {
    content = ''
      SUWAYOMI_EXTENSION_STORE=${config.sops.placeholder.suwayomi_extension_store}
      SUWAYOMI_DB_PASSWORD=${config.sops.placeholder.suwayomi_db_password}
    '';
    restartUnits = [ "suwayomi-server.service" ];
  };
  # configure postgres account
  systemd.services.postgresql-setup.script = lib.mkAfter ''
    psql -d postgres -v ON_ERROR_STOP=1 -v pw="$(cat ${config.sops.secrets.suwayomi_db_password.path})" <<'SQL'
      ALTER ROLE suwayomi PASSWORD :'pw';
    SQL
  '';

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
    config.services.suwayomi-server.settings.server.port
  ];

  # patched in libraries (required becuase nixos nixstore)
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      alsa-lib
      at-spi2-core
      cairo
      cups
      dbus
      expat
      glib
      libgbm
      libx11
      libxcb
      libxcomposite
      libxdamage
      libxext
      libxfixes
      libxkbcommon
      libxrandr
      nspr
      nss
      pango
    ];
  };

  
  systemd.tmpfiles.rules = [
    "d /tmp/.X11-unix 1777 root root -"
  ];

  systemd.services.suwayomi-xvfb = {
    description = "Virtual display for Suwayomi CEF";
    requiredBy = [ "suwayomi-server.service" ];
    before = [ "suwayomi-server.service" ];
    partOf = [ "suwayomi-server.service" ];
    serviceConfig = {
      User = user;
      Group = group;
      ExecStart = "${lib.getExe' pkgs.xvfb "Xvfb"} :99 -screen 0 1920x1080x24 -nolisten tcp -ac";
      ExecStartPost = "${lib.getExe pkgs.bash} -c 'for _ in $(${lib.getExe' pkgs.coreutils "seq"} 1 50); do ${lib.getExe' pkgs.coreutils "test"} -S /tmp/.X11-unix/X99 && exit 0; ${lib.getExe' pkgs.coreutils "sleep"} 0.1; done; exit 1'";
      Restart = "on-failure";
    };
  };

  systemd.services.suwayomi-server = {
    requires = [ "mnt-gv0.mount" "postgresql-setup.service" "flaresolverr.service" "suwayomi-xvfb.service" ];
    after = [ "mnt-gv0.mount" "postgresql-setup.service" "flaresolverr.service" "suwayomi-xvfb.service" ];
    environment = {
      DISPLAY = ":99";
      LD_LIBRARY_PATH = "/run/current-system/sw/share/nix-ld/lib";
      NIX_LD = "/run/current-system/sw/share/nix-ld/lib/ld.so";
      NIX_LD_LIBRARY_PATH = "/run/current-system/sw/share/nix-ld/lib";
    };
    serviceConfig.EnvironmentFile = config.sops.templates."suwayomi-env".path;
    serviceConfig.ExecStartPre = [
      "+${lib.getExe' pkgs.coreutils "install"} -d -o ${user} -g ${group} -m 0755 ${downloadsPath}"
    ];
  };
}
