{ config, pkgs, lib, ... }:
with lib;
{
  options.services.kinoplex = {
    enable = mkEnableOption "kinoplex";

    package = mkOption {
      type = types.package;
      default = pkgs.kinoplex;
      description = "The Kinoplex package to use";
    };

    user = mkOption {
      type = types.str;
      default = "kino";
      description = "The user under which Kinoplex will start";
    };

    group = mkOption {
      type = types.str;
      default = "kino";
      description = "The group under which Kinoplex will start";
    };
    
    home = mkOption {
      type = types.str;
      default = "/var/lib/kino";
      description = "Path to the Kinoplex home directory";
    };

    config = mkOption {
      type = (types.submodule {
        options = {
          port = mkOption {
            type = types.int;
            default = 9001;
          };

          staticDir = mkOption {
            type = types.str;
            default = "./static";
          };

          basePath = mkOption {
            type = types.str;
            default = "/";
          };

          adminPassword = mkOption {
            type = types.str;
            default = "1337";
          };

          pauseOnChange = mkOption {
            type = types.bool;
            default = true;
          };

          pauseOnLeave = mkOption {
            type = types.bool;
            default = false;
          };
        };
      });
      description = "Kinoplex configuration";
    };
  };

  config =
    let
      cfg = config.services.kinoplex;
      configFile = pkgs.writeText "server.conf" (generators.toINI {} {
        Server = cfg.config;
      });
    in mkIf config.services.kinoplex.enable {
      users.users = optionalAttrs (cfg.user == "kino") {
        kino = {
          isSystemUser = true;
          group = "${cfg.group}";
          home = "${cfg.home}";
          createHome = true;
        };
      };
            
      users.groups = optionalAttrs (cfg.group == "kino") {
        kino = {};
      };

      systemd.services.kinoplex = {
        after = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
              
        serviceConfig = {
          ExecReload = "${pkgs.coreutils}/bin/kill $MAINPID";
          KillMode = "process";
          Restart = "on-failure";
          
          User = "${cfg.user}";
          ExecStartPre = (pkgs.writeShellScript "kinoplex-prestart"
            ''
            install -D -m "0400" ${configFile} ${cfg.home}/server.conf
            '');
          ExecStart = "${cfg.package}/bin/kino_server";
          WorkingDirectory = "${cfg.home}";
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "full";
          PrivateDevices = false;
          CapabilityBoundingSet = "~CAP_SYS_ADMIN";
        };
      };
    };
}
