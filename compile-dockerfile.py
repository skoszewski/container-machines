#!/usr/bin/env python3
"""Compile a Dockerfile out of templates/ snippets, driven by a YAML config.

    ./compile-dockerfile.py azurecli-machine.yml [--build]

Without --build the Dockerfile is written and the container build command line
is printed; with --build that command is executed.
"""

import argparse
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

try:
    import yaml
except ModuleNotFoundError:
    sys.exit(
        "compile-dockerfile: PyYAML is missing.\n"
        "  Debian/Ubuntu: sudo apt-get install python3-yaml\n"
        "  macOS:         pip3 install pyyaml"
    )

REPO_ROOT = Path(__file__).resolve().parent
TEMPLATE_DIR = REPO_ROOT / "templates"
DEFAULT_DOCKERFILE = "Dockerfile"
DEFAULT_REGISTRY = "container-machines"
REGISTRY_ENV_FILE = Path.home() / ".config" / "container-machines.env"
REGISTRY_ENV_NAME = "CONTAINER_MACHINES_REGISTRY"
MACHINE_COMPONENT = "machine"
BASE_IMAGE_ARG = "BASE_IMAGE"

# Only 24.04 and newer are considered.
UBUNTU_CODENAMES = {
    "24.04": "noble",
    "24.10": "oracular",
    "25.04": "plucky",
    "25.10": "questing",
    "26.04": "resolute",
}
UBUNTU_VERSIONS = {codename: version for version, codename in UBUNTU_CODENAMES.items()}

ARG_NAME_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
ARG_LINE_RE = re.compile(r"^\s*ARG\s+([A-Za-z_][A-Za-z0-9_]*)\s*(=.*)?$")
FROM_LINE_RE = re.compile(r"^\s*FROM\s", re.IGNORECASE)
ENV_LINE_RE = re.compile(r"^\s*ENV\s", re.IGNORECASE)
REFERENCE_RE = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}")


class ConfigError(Exception):
    """A problem with the configuration file or a snippet it selects."""


def load_config(path):
    with open(path, encoding="utf-8") as handle:
        config = yaml.safe_load(handle)

    if not isinstance(config, dict):
        raise ConfigError("the file must contain a YAML mapping")

    known = {"name", "description", "dockerfile", "registry", "machine", "args", "components"}
    for key in config:
        if key not in known:
            raise ConfigError("unknown key %r, expected one of %s" % (key, ", ".join(sorted(known))))

    name = config.get("name")
    if not isinstance(name, str) or not name:
        raise ConfigError("'name' is required and must be a string")

    components = config.get("components")
    if not isinstance(components, list) or not components:
        raise ConfigError("'components' is required and must be a non-empty list")
    for component in components:
        if not isinstance(component, str):
            raise ConfigError("component %r is not a string" % (component,))

    seen = set()
    for component in components:
        if component in seen:
            raise ConfigError("component %r is listed twice" % component)
        seen.add(component)

    machine = config.get("machine", True)
    if not isinstance(machine, bool):
        raise ConfigError("'machine' must be true or false")
    if machine and MACHINE_COMPONENT in seen:
        raise ConfigError(
            "component %r is appended automatically, remove it from 'components' "
            "or set 'machine: false'" % MACHINE_COMPONENT
        )

    args = config.get("args", {})
    if not isinstance(args, dict):
        raise ConfigError("'args' must be a mapping")
    for arg_name, value in args.items():
        if not isinstance(arg_name, str) or not ARG_NAME_RE.match(arg_name):
            raise ConfigError("%r is not a valid build argument name" % (arg_name,))
        if not isinstance(value, str):
            raise ConfigError(
                "the value of %s is a %s, not a string - quote it in the YAML"
                % (arg_name, type(value).__name__)
            )
    if BASE_IMAGE_ARG not in args:
        raise ConfigError("'args' must define %s, it is what FROM resolves to" % BASE_IMAGE_ARG)

    for key in ("description", "dockerfile", "registry"):
        if key in config and not isinstance(config[key], str):
            raise ConfigError("'%s' must be a string" % key)

    return config


def read_component(component):
    path = TEMPLATE_DIR / ("Dockerfile." + component)
    if not path.is_file():
        available = sorted(p.name[len("Dockerfile."):] for p in TEMPLATE_DIR.glob("Dockerfile.*"))
        raise ConfigError(
            "unknown component %r; templates/ holds: %s" % (component, ", ".join(available))
        )

    body = path.read_text(encoding="utf-8")
    declared = []
    for number, line in enumerate(body.splitlines(), start=1):
        if FROM_LINE_RE.match(line):
            raise ConfigError(
                "%s:%d declares FROM; the compiler owns that line" % (path.name, number)
            )
        match = ARG_LINE_RE.match(line)
        if match:
            if match.group(2):
                raise ConfigError(
                    "%s:%d gives %s a default; values come from the build command line"
                    % (path.name, number, match.group(1))
                )
            declared.append(match.group(1))

    used = set()
    for line in body.splitlines():
        if ENV_LINE_RE.match(line):
            continue
        used.update(REFERENCE_RE.findall(line))
    undeclared = sorted(used - set(declared))
    if undeclared:
        raise ConfigError(
            "%s uses %s without declaring it with ARG" % (path.name, ", ".join(undeclared))
        )

    return body, declared


def derive_ubuntu_args(base_image):
    """Map the BASE_IMAGE tag to UBUNTU_VERSION and UBUNTU_CODENAME."""
    tag = base_image.rsplit(":", 1)[1] if ":" in base_image else ""

    if tag in UBUNTU_CODENAMES:
        return {"UBUNTU_VERSION": tag, "UBUNTU_CODENAME": UBUNTU_CODENAMES[tag]}
    if tag in UBUNTU_VERSIONS:
        return {"UBUNTU_VERSION": UBUNTU_VERSIONS[tag], "UBUNTU_CODENAME": tag}

    if re.match(r"^\d+\.\d+$", tag) and tag < "24.04":
        raise ConfigError(
            "%s is Ubuntu %s; only 24.04 and newer are supported" % (BASE_IMAGE_ARG, tag)
        )
    return {}


def resolve_args(config, required):
    """Values for the required args: config first, derived Ubuntu values second."""
    args = dict(config.get("args", {}))
    for arg_name, value in args.items():
        args[arg_name] = os.path.expandvars(value)

    derived = derive_ubuntu_args(args[BASE_IMAGE_ARG])

    resolved = {BASE_IMAGE_ARG: args[BASE_IMAGE_ARG]}
    missing = []
    for arg_name, component in required.items():
        if arg_name in args:
            resolved[arg_name] = args[arg_name]
        elif arg_name in derived:
            resolved[arg_name] = derived[arg_name]
        else:
            missing.append("%s (required by the %s component)" % (arg_name, component))
    if missing:
        raise ConfigError("no value for " + "; ".join(missing))

    unused = sorted(set(args) - set(resolved))
    for arg_name in unused:
        print(
            "compile-dockerfile: warning: %s is not used by any component" % arg_name,
            file=sys.stderr,
        )

    return resolved


def compile_dockerfile(config, config_path):
    components = list(config["components"])
    if config.get("machine", True):
        components.append(MACHINE_COMPONENT)

    snippets = []
    required = {}
    for component in components:
        body, declared = read_component(component)
        snippets.append((component, body))
        for arg_name in declared:
            required.setdefault(arg_name, component)

    build_args = resolve_args(config, required)

    lines = [
        "# Dockerfile generated from %s by compile-dockerfile.py - do not edit"
        % Path(config_path).name,
    ]
    if config.get("description"):
        lines.append("# " + config["description"])
    lines += [
        "",
        "ARG %s" % BASE_IMAGE_ARG,
        "",
        "FROM ${%s}" % BASE_IMAGE_ARG,
        "",
        "ARG %s" % BASE_IMAGE_ARG,
        "",
        "# bash, so that pipelines below fail on the first failing stage rather than the last",
        'SHELL ["/bin/bash", "-o", "pipefail", "-c"]',
    ]
    for component, body in snippets:
        lines += ["", "# --- component: %s ---" % component, body.rstrip("\n")]

    return "\n".join(lines) + "\n", build_args, len(components)


def read_registry(config):
    """The registry recreate-machine.sh would use: the default, overridden by
    CONTAINER_MACHINES_REGISTRY in ~/.config/container-machines.env."""
    if config.get("registry"):
        return config["registry"]

    registry = DEFAULT_REGISTRY
    if not REGISTRY_ENV_FILE.is_file():
        return registry

    for line in REGISTRY_ENV_FILE.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.startswith("export "):
            line = line[len("export "):]
        name, separator, value = line.partition("=")
        if separator and name.strip() == REGISTRY_ENV_NAME:
            words = shlex.split(value, comments=True)
            registry = words[0] if words else ""
    return registry


def build_command(config, build_args, dockerfile):
    registry = read_registry(config)
    version = build_args.get("UBUNTU_VERSION") or derive_ubuntu_args(
        build_args[BASE_IMAGE_ARG]
    ).get("UBUNTU_VERSION", "latest")

    command = ["container", "build"]
    for arg_name, value in build_args.items():
        command += ["--build-arg", "%s=%s" % (arg_name, value)]
    command += [
        "--tag", "%s/%s:%s" % (registry, config["name"], version),
        "--file", str(dockerfile),
        ".",
    ]
    return command


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("config", help="YAML configuration file")
    parser.add_argument(
        "--build", action="store_true", help="run the container build command"
    )
    options = parser.parse_args()

    try:
        config = load_config(options.config)
        content, build_args, count = compile_dockerfile(config, options.config)
    except ConfigError as error:
        sys.exit("compile-dockerfile: %s: %s" % (options.config, error))
    except OSError as error:
        sys.exit("compile-dockerfile: %s" % error)

    dockerfile = Path(config.get("dockerfile") or DEFAULT_DOCKERFILE)
    if dockerfile.parent != Path("."):
        dockerfile.parent.mkdir(parents=True, exist_ok=True)
    dockerfile.write_text(content, encoding="utf-8")
    print("wrote %s (%d components)" % (dockerfile, count), file=sys.stderr)

    command = build_command(config, build_args, dockerfile)
    print("==> %s" % shlex.join(command), file=sys.stderr)
    if not options.build:
        return 0

    return subprocess.run(command).returncode


if __name__ == "__main__":
    sys.exit(main())
