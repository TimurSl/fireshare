{
  description = "Native Nix package and NixOS module for Fireshare";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = lib.genAttrs systems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          python = pkgs.python313;
          pythonPackages = pkgs.python313Packages;

          client = pkgs.buildNpmPackage {
            pname = "fireshare-client";
            version = "1.6.13";
            src = ./app/client;
            nodejs = pkgs.nodejs_24;
            npmDepsHash = "sha256-InbnjBCY9hQ/3M8fj0X+O0Ih/6po7OtOPMnYS8nlJ40=";
            npmBuildScript = "build";
            installPhase = ''
              runHook preInstall
              mkdir -p $out/build
              cp -r build/. $out/build/
              runHook postInstall
            '';
          };
        in
        rec {
          fireshare = pythonPackages.buildPythonPackage {
            pname = "fireshare";
            version = "1.6.13";
            src = ./app/server;
            pyproject = true;
            pythonRelaxDeps = true;

            build-system = [
              pythonPackages.setuptools
            ];

            dependencies = with pythonPackages; [
              apscheduler
              click
              ffmpeg-python
              flask
              flask-cors
              flask-login
              flask-migrate
              flask-sqlalchemy
              flask-wtf
              greenlet
              gunicorn
              itsdangerous
              jinja2
              markupsafe
              pillow
              python-ldap
              rapidfuzz
              requests
              six
              sqlalchemy
              werkzeug
              wtforms
              xxhash
            ];

            pythonImportsCheck = [
              "fireshare"
              "fireshare.cli"
            ];

            postInstall = ''
              sitePackages="$out/${python.sitePackages}"
              mkdir -p "$sitePackages/fireshare/build"
              cp -r ${client}/build/. "$sitePackages/fireshare/build/"

              mkdir -p "$out/share/fireshare"
              cp -r ${./migrations} "$out/share/fireshare/migrations"
              cp -r ${./app/server/fireshare/templates} "$out/share/fireshare/templates"
              cp ${./app/server/gunicorn.conf.py} "$out/share/fireshare/gunicorn.conf.py"
              cp -r ${client}/build "$out/share/fireshare/client"

              mkdir -p "$out/share/fireshare/nginx"
              cp ${./app/nginx/error.html} "$out/share/fireshare/nginx/error.html"
              cp ${./app/nginx/api_unavailable.html} "$out/share/fireshare/nginx/api_unavailable.html"
            '';
          };

          default = fireshare;
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          pythonPackages = pkgs.python313Packages;
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.nodejs_24
              pkgs.ffmpeg
              pkgs.nginx
              pkgs.pkg-config
              pkgs.openldap
              pkgs.cyrus_sasl
              pkgs.python313
            ] ++ (with pythonPackages; [
              apscheduler
              click
              ffmpeg-python
              flask
              flask-cors
              flask-login
              flask-migrate
              flask-sqlalchemy
              flask-wtf
              gunicorn
              pillow
              python-ldap
              rapidfuzz
              requests
              xxhash
            ]);
          };
        }
      );

      nixosModules.default =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.services.fireshare;
          package = cfg.package;
          pythonPackages = pkgs.python313Packages;
          fireshareRuntimeDeps = with pythonPackages; [
            apscheduler
            click
            ffmpeg-python
            flask
            flask-cors
            flask-login
            flask-migrate
            flask-sqlalchemy
            flask-wtf
            greenlet
            itsdangerous
            jinja2
            markupsafe
            pillow
            python-ldap
            rapidfuzz
            requests
            six
            sqlalchemy
            werkzeug
            wtforms
            xxhash
          ];
          boolEnv = value: if value then "true" else "false";
          proxyHeaders = ''
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header Host $host;
            proxy_set_header X-Forwarded-Proto $scheme;
          '';
          app = "http://${cfg.host}:${toString cfg.port}";
          vhostName =
            if cfg.nginx.virtualHost != null then
              cfg.nginx.virtualHost
            else if cfg.domain != null && cfg.domain != "" then
              cfg.domain
            else
              "_";
        in
        {
          options.services.fireshare = {
            enable = lib.mkEnableOption "Fireshare";

            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
              defaultText = lib.literalExpression "self.packages.\${pkgs.stdenv.hostPlatform.system}.default";
              description = "Fireshare package to run.";
            };

            user = lib.mkOption {
              type = lib.types.str;
              default = "fireshare";
              description = "User account that runs Fireshare.";
            };

            group = lib.mkOption {
              type = lib.types.str;
              default = "fireshare";
              description = "Group account that runs Fireshare.";
            };

            dataDir = lib.mkOption {
              type = lib.types.path;
              default = "/var/lib/fireshare/data";
              description = "Directory for Fireshare database and configuration.";
            };

            processedDir = lib.mkOption {
              type = lib.types.path;
              default = "/var/lib/fireshare/processed";
              description = "Directory for generated media, links, and derived assets.";
            };

            videoDir = lib.mkOption {
              type = lib.types.path;
              default = "/var/lib/fireshare/videos";
              description = "Directory containing source videos.";
            };

            imageDir = lib.mkOption {
              type = lib.types.path;
              default = "/var/lib/fireshare/images";
              description = "Directory containing source images and uploads.";
            };

            host = lib.mkOption {
              type = lib.types.str;
              default = "127.0.0.1";
              description = "Local address for gunicorn to bind.";
            };

            port = lib.mkOption {
              type = lib.types.port;
              default = 5000;
              description = "Local port for gunicorn to bind.";
            };

            domain = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Public domain passed to Fireshare as DOMAIN.";
            };

            environment = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
              example = {
                ADMIN_USERNAME = "admin";
                FS_LOGLEVEL = "INFO";
              };
              description = "Additional non-secret environment variables for Fireshare.";
            };

            environmentFiles = lib.mkOption {
              type = lib.types.listOf lib.types.path;
              default = [ ];
              description = "Environment files containing secrets such as SECRET_KEY, ADMIN_PASSWORD, LDAP credentials, webhook URLs, or API keys.";
            };

            enableTranscoding = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Whether Fireshare should enable video transcoding.";
            };

            transcodeGpu = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Whether Fireshare should request GPU transcoding support from ffmpeg.";
            };

            transcodeTimeout = lib.mkOption {
              type = lib.types.ints.positive;
              default = 7200;
              description = "Transcode timeout in seconds.";
            };

            minutesBetweenVideoScans = lib.mkOption {
              type = lib.types.ints.positive;
              default = 5;
              description = "Minutes between scheduled video scans.";
            };

            thumbnailVideoLocation = lib.mkOption {
              type = lib.types.int;
              default = 0;
              description = "Timestamp location used by Fireshare when creating thumbnails.";
            };

            gunicornWorkers = lib.mkOption {
              type = lib.types.nullOr lib.types.ints.positive;
              default = null;
              description = "Explicit gunicorn worker count. Null uses Fireshare's gunicorn config default.";
            };

            gunicornThreads = lib.mkOption {
              type = lib.types.ints.positive;
              default = 8;
              description = "Gunicorn threads per worker.";
            };

            gunicornWorkerCap = lib.mkOption {
              type = lib.types.int;
              default = 4;
              description = "Maximum gunicorn workers for the default worker formula. Set 0 to remove the cap.";
            };

            nginx = {
              enable = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Whether to configure the NixOS nginx reverse proxy and static media serving.";
              };

              virtualHost = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Nginx virtual host name. Defaults to services.fireshare.domain, or '_' when no domain is set.";
              };

              openFirewall = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Whether to open the HTTP firewall port for nginx.";
              };
            };
          };

          config = lib.mkIf cfg.enable {
            users.groups = lib.mkIf (cfg.group == "fireshare") {
              fireshare = { };
            };

            users.users = lib.mkIf (cfg.user == "fireshare") {
              fireshare = {
                isSystemUser = true;
                group = cfg.group;
                home = cfg.dataDir;
              };
            };

            users.users.${config.services.nginx.user}.extraGroups = lib.mkIf cfg.nginx.enable [ cfg.group ];

            systemd.tmpfiles.rules = [
              "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} -"
              "d ${cfg.processedDir} 0750 ${cfg.user} ${cfg.group} -"
              "d ${cfg.processedDir}/video_links 0750 ${cfg.user} ${cfg.group} -"
              "d ${cfg.processedDir}/image_links 0750 ${cfg.user} ${cfg.group} -"
              "d ${cfg.processedDir}/derived 0750 ${cfg.user} ${cfg.group} -"
              "d ${cfg.videoDir} 0750 ${cfg.user} ${cfg.group} -"
              "d ${cfg.imageDir} 0750 ${cfg.user} ${cfg.group} -"
              "d ${cfg.dataDir}/game_assets 0750 ${cfg.user} ${cfg.group} -"
            ];

            systemd.services.fireshare =
              let
                pythonEnv = pkgs.python313.withPackages (_: [
                  package
                ] ++ fireshareRuntimeDeps ++ [
                  pythonPackages.gunicorn
                ]);
              in
              {
                description = "Fireshare media server";
                wantedBy = [ "multi-user.target" ];
                after = [ "network-online.target" ];
                wants = [ "network-online.target" ];

                environment = {
                  FLASK_APP = "fireshare:create_app()";
                  ENVIRONMENT = "production";
                  DATA_DIRECTORY = toString cfg.dataDir;
                  PROCESSED_DIRECTORY = toString cfg.processedDir;
                  VIDEO_DIRECTORY = toString cfg.videoDir;
                  IMAGE_DIRECTORY = toString cfg.imageDir;
                  PYTHONPATH = "${package}/${pkgs.python313.sitePackages}:${pythonEnv}/${pkgs.python313.sitePackages}";
                  TEMPLATE_PATH = "${package}/share/fireshare/templates";
                  FIRESHARE_MIGRATIONS_DIRECTORY = "${package}/share/fireshare/migrations";
                  ENABLE_TRANSCODING = boolEnv cfg.enableTranscoding;
                  TRANSCODE_GPU = boolEnv cfg.transcodeGpu;
                  TRANSCODE_TIMEOUT = toString cfg.transcodeTimeout;
                  MINUTES_BETWEEN_VIDEO_SCANS = toString cfg.minutesBetweenVideoScans;
                  THUMBNAIL_VIDEO_LOCATION = toString cfg.thumbnailVideoLocation;
                  GUNICORN_THREADS = toString cfg.gunicornThreads;
                  GUNICORN_WORKER_CAP = toString cfg.gunicornWorkerCap;
                }
                // lib.optionalAttrs (cfg.domain != null) { DOMAIN = cfg.domain; }
                // lib.optionalAttrs (cfg.gunicornWorkers != null) { GUNICORN_WORKERS = toString cfg.gunicornWorkers; }
                // cfg.environment;

                serviceConfig = {
                  Type = "exec";
                  User = cfg.user;
                  Group = cfg.group;
                  EnvironmentFile = cfg.environmentFiles;
                  WorkingDirectory = package;
                  RuntimeDirectory = "fireshare";
                  RuntimeDirectoryMode = "0750";
                  ExecStartPre = [
                    "${pkgs.writeShellScript "fireshare-cleanup" ''
                      set -eu
                      ${pkgs.coreutils}/bin/rm -f ${toString cfg.dataDir}/*.lock ${toString cfg.dataDir}/jobs.sqlite
                    ''}"
                    "${package}/bin/fireshare upgrade-db"
                    "${package}/bin/fireshare migrate-game-assets"
                    "${pkgs.writeShellScript "fireshare-boomerangs" ''
                      set -eu
                      flag="${toString cfg.dataDir}/.boomerangs_generated"
                      if [ ! -f "$flag" ]; then
                        ${package}/bin/fireshare create-boomerang-posters || true
                        ${pkgs.coreutils}/bin/touch "$flag"
                      fi
                    ''}"
                  ];
                  ExecStart = "${pythonEnv}/bin/python -m gunicorn --config ${package}/share/fireshare/gunicorn.conf.py --bind=${cfg.host}:${toString cfg.port} 'fireshare:create_app(init_schedule=True)'";
                  Restart = "on-failure";
                  RestartSec = "5s";
                  KillSignal = "SIGINT";
                  TimeoutStartSec = "30min";
                };

                path = [
                  pythonEnv
                  pkgs.ffmpeg
                ];
              };

            services.nginx = lib.mkIf cfg.nginx.enable {
              enable = true;
              recommendedGzipSettings = true;
              recommendedOptimisation = true;
              recommendedProxySettings = true;
              appendConfig = ''
                thread_pool fireshare_default threads=64 max_queue=131072;
              '';
              appendHttpConfig = ''
                proxy_cache_path /var/cache/nginx/fireshare
                                 keys_zone=FIRESHAREPROXYCACHE:200m
                                 inactive=120m
                                 max_size=2g
                                 levels=1:2;
                proxy_cache_key "$scheme$request_method$host$request_uri";
                proxy_cache_min_uses 1;
                proxy_cache_revalidate on;
                proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
                proxy_cache_background_update on;
                proxy_cache_lock on;
                proxy_cache_lock_timeout 10s;
              '';
              virtualHosts.${vhostName} = {
                default = vhostName == "_";
                extraConfig = ''
                  add_header X-Cache-Status $upstream_cache_status;
                  client_body_buffer_size 256k;
                  client_body_timeout 60s;
                  aio threads=fireshare_default;
                  open_file_cache max=10000 inactive=60s;
                  open_file_cache_valid 120s;
                  open_file_cache_min_uses 2;
                  open_file_cache_errors on;

                  error_page 400 /error/400;
                  error_page 401 /error/401;
                  error_page 403 /error/403;
                  error_page 404 /error/404;
                  error_page 405 /error/405;
                  error_page 408 /error/408;
                  error_page 410 /error/410;
                  error_page 413 /error/413;
                  error_page 414 /error/414;
                  error_page 429 /error/429;
                  error_page 500 /error/500;
                  error_page 502 /api-unavailable;
                  error_page 503 /api-unavailable;
                  error_page 504 /api-unavailable;
                '';
                locations = {
                  "/assets/" = {
                    root = "${package}/share/fireshare/client";
                    extraConfig = ''
                      add_header Cache-Control "public, max-age=31536000, immutable";
                      try_files $uri =404;
                    '';
                  };

                  "/" = {
                    root = "${package}/share/fireshare/client";
                    index = "index.html";
                    extraConfig = ''
                      add_header Cache-Control "no-cache, must-revalidate";
                      try_files $uri $uri/ /index.html;
                    '';
                  };

                  "/_content/" = {
                    root = cfg.processedDir;
                    extraConfig = ''
                      rewrite ^/_content/(.*)$ /$1 break;
                      proxy_cache FIRESHAREPROXYCACHE;
                      proxy_cache_valid 200 302 30m;
                      proxy_cache_valid 404 5m;
                      add_header Cache-Control "public, max-age=1800";
                    '';
                  };

                  "= /internal/video-auth" = {
                    proxyPass = "${app}/api/video/nginx-auth";
                    extraConfig = ''
                      internal;
                      proxy_pass_request_body off;
                      proxy_set_header Content-Length "";
                      proxy_set_header X-Original-URI $request_uri;
                      proxy_set_header Cookie $http_cookie;
                    '';
                  };

                  "= /internal/video-auth-admin" = {
                    proxyPass = "${app}/api/video/nginx-auth-admin";
                    extraConfig = ''
                      internal;
                      proxy_pass_request_body off;
                      proxy_set_header Content-Length "";
                      proxy_set_header Cookie $http_cookie;
                    '';
                  };

                  "~ ^/_content/derived/([^/]+)/thumbnail$" = {
                    root = cfg.processedDir;
                    extraConfig = ''
                      set $video_id $1;
                      add_header Cache-Control "no-cache, must-revalidate";
                      try_files /derived/$video_id/custom_poster.webp /derived/$video_id/poster.jpg =404;
                    '';
                  };

                  "~ ^/_content/derived/" = {
                    root = cfg.processedDir;
                    extraConfig = ''
                      auth_request /internal/video-auth;
                      rewrite ^/_content/(.*)$ /$1 break;
                      add_header Cache-Control "public, max-age=31536000, immutable";
                    '';
                  };

                  "~ ^/_content/video/([\\w-]+)(\\.[^/]+)$" = {
                    root = cfg.processedDir;
                    extraConfig = ''
                      auth_request /internal/video-auth;
                      sendfile off;
                      mp4;
                      mp4_buffer_size 2m;
                      mp4_max_buffer_size 50m;
                      directio 4m;
                      directio_alignment 512;
                      output_buffers 2 2m;
                      add_header Cache-Control "public, max-age=31536000, immutable";
                      add_header Accept-Ranges bytes;
                      limit_rate_after 5m;
                      set $video_id $1;
                      set $video_ext $2;
                      try_files /derived/$video_id/$video_id-cropped.mp4 /video_links/$video_id$video_ext =404;
                    '';
                  };

                  "~ ^/_content/video-raw/([\\w-]+)(\\.[^/]+)$" = {
                    root = cfg.processedDir;
                    extraConfig = ''
                      auth_request /internal/video-auth-admin;
                      sendfile off;
                      mp4;
                      mp4_buffer_size 2m;
                      mp4_max_buffer_size 50m;
                      directio 4m;
                      directio_alignment 512;
                      output_buffers 2 2m;
                      add_header Cache-Control "no-store";
                      add_header Accept-Ranges bytes;
                      limit_rate_after 5m;
                      set $video_id $1;
                      set $video_ext $2;
                      try_files /video_links/$video_id$video_ext =404;
                    '';
                  };

                  "/_content/image/" = {
                    root = "${cfg.processedDir}/image_links";
                    extraConfig = ''
                      sendfile off;
                      add_header Cache-Control "public, max-age=86400";
                      rewrite ^/_content/image/(.*)$ /$1 break;
                    '';
                  };

                  "~ ^/_content/game_assets/(.*)$" = {
                    extraConfig = ''
                      alias ${cfg.dataDir}/game_assets/$1;
                      add_header Cache-Control "public, max-age=86400";
                      error_page 404 = @game_asset_fallback;
                    '';
                  };

                  "@game_asset_fallback" = {
                    proxyPass = app;
                    extraConfig = ''
                      rewrite ^/_content/game_assets/(.*)$ /api/game/assets/$1 break;
                      ${proxyHeaders}
                      proxy_buffering off;
                    '';
                  };

                  "~ ^/error/([0-9]+)$" = {
                    root = "${package}/share/fireshare/nginx";
                    extraConfig = ''
                      internal;
                      set $error_code $1;
                      ssi on;
                      rewrite ^ /error.html break;
                    '';
                  };

                  "= /api-unavailable" = {
                    root = "${package}/share/fireshare/nginx";
                    extraConfig = ''
                      internal;
                      rewrite ^ /api_unavailable.html break;
                    '';
                  };

                  "= /api/admin/stream" = {
                    proxyPass = app;
                    extraConfig = ''
                      ${proxyHeaders}
                      proxy_buffering off;
                      proxy_cache off;
                      proxy_read_timeout 86400s;
                      add_header Cache-Control "no-cache";
                      add_header X-Accel-Buffering "no";
                    '';
                  };

                  "= /api/uploadChunked" = {
                    proxyPass = app;
                    extraConfig = ''
                      ${proxyHeaders}
                      proxy_request_buffering off;
                      client_max_body_size 0;
                      proxy_connect_timeout 60s;
                      proxy_send_timeout 120s;
                      proxy_read_timeout 999999s;
                    '';
                  };

                  "~ /api/.*$" = {
                    proxyPass = app;
                    extraConfig = ''
                      ${proxyHeaders}
                      proxy_buffering on;
                      proxy_buffer_size 4k;
                      proxy_buffers 8 4k;
                      proxy_busy_buffers_size 8k;
                      proxy_connect_timeout 60s;
                      proxy_send_timeout 120s;
                      proxy_read_timeout 999999s;
                      client_max_body_size 0;
                    '';
                  };

                  "~ /w/.*$" = {
                    proxyPass = app;
                    extraConfig = ''
                      proxy_http_version 1.1;
                      proxy_set_header Connection "";
                      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                      proxy_set_header X-Real-IP $remote_addr;
                      proxy_set_header Host $host;
                      proxy_connect_timeout 60s;
                      proxy_read_timeout 60s;
                    '';
                  };

                  "~ /i/.*$" = {
                    proxyPass = app;
                    extraConfig = ''
                      proxy_http_version 1.1;
                      proxy_set_header Connection "";
                      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                      proxy_set_header X-Real-IP $remote_addr;
                      proxy_set_header Host $host;
                      proxy_connect_timeout 60s;
                      proxy_read_timeout 60s;
                    '';
                  };
                };
              };
            };

            networking.firewall.allowedTCPPorts = lib.mkIf (cfg.nginx.enable && cfg.nginx.openFirewall) [ 80 ];
          };
        };
    };
}
