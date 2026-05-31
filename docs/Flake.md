# Fireshare Nix Flake

This repository includes a Nix flake that packages Fireshare, provides a development shell, and exports a NixOS module for running the service on a host.

The flake currently targets:

- `x86_64-linux`
- `aarch64-linux`

## What The Flake Exposes

- `packages.<system>.fireshare`
- `packages.<system>.default`
- `devShells.<system>.default`
- `nixosModules.default`

## Quick Start

Enter the development shell:

```sh
nix develop
```

Build the Fireshare package:

```sh
nix build .#fireshare
```

Inspect the flake outputs:

```sh
nix flake show
```

## Development Shell

The default dev shell includes the tools needed to work on Fireshare locally:

- Python 3.13
- Node.js 24
- FFmpeg
- Nginx
- pkg-config
- OpenLDAP and Cyrus SASL libraries
- The Python dependencies used by the backend

Use it from the repository root:

```sh
nix develop
```

## NixOS Module

The flake exports `nixosModules.default`, which defines `services.fireshare`.

Minimal example:

```nix
{
  inputs.fireshare.url = "path:/path/to/fireshare";

  outputs = { self, nixpkgs, fireshare, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        fireshare.nixosModules.default
        ({ ... }: {
          services.fireshare = {
            enable = true;
            domain = "v.example.com";
            environmentFiles = [ /run/secrets/fireshare.env ];
          };
        })
      ];
    };
  };
}
```

Useful options include:

- `services.fireshare.dataDir`
- `services.fireshare.processedDir`
- `services.fireshare.videoDir`
- `services.fireshare.imageDir`
- `services.fireshare.host`
- `services.fireshare.port`
- `services.fireshare.domain`
- `services.fireshare.environment`
- `services.fireshare.environmentFiles`
- `services.fireshare.enableTranscoding`
- `services.fireshare.transcodeGpu`
- `services.fireshare.minutesBetweenVideoScans`
- `services.fireshare.thumbnailVideoLocation`
- `services.fireshare.gunicornWorkers`
- `services.fireshare.gunicornThreads`
- `services.fireshare.gunicornWorkerCap`
- `services.fireshare.nginx.enable`
- `services.fireshare.nginx.virtualHost`
- `services.fireshare.nginx.openFirewall`

### Defaults Worth Knowing

- `services.fireshare.nginx.enable` defaults to `true`
- `services.fireshare.nginx.openFirewall` defaults to `true`
- `services.fireshare.host` defaults to `127.0.0.1`
- `services.fireshare.port` defaults to `5000`
- `services.fireshare.domain` is passed through to the app as `DOMAIN`
- `services.fireshare.environmentFiles` is the place for secrets such as `SECRET_KEY`, admin credentials, LDAP credentials, and webhook URLs

## Notes

- The module starts Fireshare through `gunicorn` and runs the database migration before the service starts.
- The module also configures nginx to serve the frontend and processed media when `services.fireshare.nginx.enable = true`.
- If you use a public domain, set `services.fireshare.domain` to the bare host name, not a URL.
