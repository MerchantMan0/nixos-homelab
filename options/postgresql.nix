{ config, lib, pkgs, ... }:

let
  cfg = config.custom.postgresql;
  pgpass = config.sops.templates."pgpass".path;
  dataDir = config.services.postgresql.dataDir;
  self = config.networking.hostName;
in
{
  options.custom.postgresql = {
    enable = lib.mkEnableOption "PostgreSQL with streaming replication";

    role = lib.mkOption {
      type = lib.types.enum [ "primary" "follower" ];
      description = "Whether this node is the primary or a streaming-replication follower.";
    };

    package = lib.mkPackageOption pkgs "postgresql_17" { };

    primaryHost = lib.mkOption {
      type = lib.types.str;
      description = "Hostname of the primary (followers connect to it).";
    };

    standbys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Primary only: standby names that must confirm synchronous commits (FIRST 1).";
    };

    replicationUser = lib.mkOption {
      type = lib.types.str;
      default = "replicator";
    };

    replicationSubnet = lib.mkOption {
      type = lib.types.str;
      default = "100.64.0.0/10";
      description = "Primary only: CIDR allowed to replicate (default: Tailscale CGNAT range).";
    };

    passwordSecret = lib.mkOption {
      type = lib.types.str;
      default = "pg_replicator_password";
      description = "Name of the sops secret holding the replication user's password.";
    };

    sopsFile = lib.mkOption {
      type = lib.types.path;
      description = "sops file containing the replication password secret.";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      services.postgresql = {
        enable = true;
        package = cfg.package;
        enableTCPIP = true;
        #pg vector is for bookorbit
        extensions = lib.mkDefault (ps: with ps; [ pgvector ]);
      };
      sops.secrets.${cfg.passwordSecret}.sopsFile = cfg.sopsFile;
    }

    (lib.mkIf (cfg.role == "primary") {
      services.postgresql = {
        settings = {
          wal_level = "replica";
          max_wal_senders = 5;
          max_replication_slots = 5;
          synchronous_commit = "on";
        } // lib.optionalAttrs (cfg.standbys != [ ]) {
          synchronous_standby_names = "FIRST 1 (${lib.concatStringsSep ", " cfg.standbys})";
        };
        ensureUsers = [
          { name = cfg.replicationUser; ensureClauses.replication = true; }
        ];
        authentication = lib.mkAfter ''
          host replication ${cfg.replicationUser} ${cfg.replicationSubnet} scram-sha-256
        '';
      };

      sops.secrets.${cfg.passwordSecret}.owner = "postgres";
      systemd.services.postgresql-setup.environment.PGOPTIONS = "-c synchronous_commit=local";
      systemd.services.postgresql-setup.script = lib.mkAfter ''
        psql -d postgres -v ON_ERROR_STOP=1 -v pw="$(cat ${config.sops.secrets.${cfg.passwordSecret}.path})" <<'SQL'
          ALTER ROLE ${cfg.replicationUser} PASSWORD :'pw';
        SQL
      '';
    })

    (lib.mkIf (cfg.role == "follower") {
      services.postgresql.settings = {
        hot_standby = true;
        primary_conninfo = "host=${cfg.primaryHost} user=${cfg.replicationUser} application_name=${self} passfile=${pgpass}";
        primary_slot_name = self;
      };

      sops.templates."pgpass" = {
        content = "${cfg.primaryHost}:5432:*:${cfg.replicationUser}:${config.sops.placeholder.${cfg.passwordSecret}}\n";
        owner = "postgres";
        mode = "0400";
      };

      systemd.services.postgresql.preStart = lib.mkBefore ''
        if ! test -e ${dataDir}/PG_VERSION; then
          export PGPASSFILE=${pgpass}
          until pg_basebackup \
            -d "host=${cfg.primaryHost} user=${cfg.replicationUser} application_name=${self}" \
            -D ${dataDir} \
            -X stream -C -S ${self}; do
            echo "waiting for ${cfg.primaryHost} primary..."; rm -rf ${dataDir}/*; sleep 5
          done
          touch ${dataDir}/standby.signal
        fi
      '';
    })
  ]);
}
