# container-machines

Compose container machine images from reusable Dockerfile snippets, driven by a
YAML file. Built for Apple's `container` CLI on Apple Silicon, so every snippet
is arm64 only.

A *component* is a Dockerfile fragment in `templates/Dockerfile.<name>` holding
`ARG`, `RUN`, `COPY` and `ENV` instructions - never a `FROM`. A config lists the
components an image is made of; `compile-dockerfile.py` concatenates them into a
single `Dockerfile` and assembles the matching `container build` command line.

## Usage

```sh
./compile-dockerfile.py cloud-machine.yml            # write Dockerfile, print the build command
./compile-dockerfile.py cloud-machine.yml --build    # ... and run it
./recreate-machine.sh cloud                          # recreate the machine from the built image
```

Requires Python 3 with PyYAML (`apt-get install python3-yaml` on Debian and
Ubuntu, `pip3 install pyyaml` on macOS - Homebrew has no formula for it).

## Configuration

```yaml
name: cloud                 # required, names the image
description: ...            # optional, becomes a comment in the Dockerfile
dockerfile: Dockerfile      # optional, output path
registry: ...               # optional, overrides the registry (see below)
machine: true               # optional, append the machine component (default true)
args:                       # required, values for the build arguments
  BASE_IMAGE: ubuntu:24.04  # required
  NODE_VERSION: 24.19.0
components:                 # required, applied in order
  - ubuntu
  - nodejs
  - azurecli
```

`$HOME` in a value is expanded when the build command is assembled. The image is
tagged `<registry>/<name>:<ubuntu version>`, where the version comes from the
`BASE_IMAGE` tag; only 24.04 and newer are supported. `UBUNTU_VERSION` and
`UBUNTU_CODENAME` are derived from that tag, so no config has to repeat them.

The registry defaults to `container-machines` and is overridden by
`CONTAINER_MACHINES_REGISTRY` in `~/.config/container-machines.env`, the same
file `recreate-machine.sh` reads.

## Components

| Component | Contents |
| --- | --- |
| `ubuntu` | base tooling: git, python3, jq, curl, neovim, build prerequisites |
| `nodejs` | NodeJS from the official tarball, on `PATH` |
| `azurecli` | Azure CLI from the Microsoft repository |
| `gcloud` | Google Cloud SDK from the rapid channel archive, on `PATH` |
| `terraform` | Terraform from the HashiCorp repository, with bash completion |
| `powershell` | PowerShell LTS from the latest GitHub release |
| `cloud-select` | `cloud-select.sh`, the `gcloud`/`az` profile switcher, wired into `/etc/bash.bashrc` |
| `machine` | systemd, sshd and passwordless sudo - what makes the image bootable as a machine |

`machine` is appended automatically as the last layer unless the config sets
`machine: false`, so it must not be listed in `components`.

## Writing a component

Drop a snippet in `templates/Dockerfile.<name>`. Declare every build argument it
uses as a bare `ARG NAME` at the top - those declarations are the component's
requirements, and a config that selects the component must supply a value for
each of them. Defaults are rejected: values live on the build command line, not
in the Dockerfile. `FROM` is rejected too; the compiler emits it.

## License

MIT, see [LICENSE](LICENSE).
