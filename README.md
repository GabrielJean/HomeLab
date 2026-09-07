# HomeLab

Infrastructure-as-code repository for a personal homelab. It manages virtual-machine workloads, Docker Compose applications, host configuration, scheduled maintenance, and deployment automation.

This README intentionally uses generic names and examples. Do not add real hostnames, IP addresses, domains, user names, credentials, private keys, VPN profiles, service tokens, or inventory contents to this file.

## What This Repository Manages

The homelab is organized around the following layers:

| Layer | Responsibility | Primary implementation |
| --- | --- | --- |
| Virtualization | Runs the virtual machines that host services. | External hypervisor configuration; historical provisioning material is in `Archives/`. |
| Configuration management | Applies base configuration, deploys Compose projects, and performs host maintenance. | `Ansible/` |
| Application workloads | Defines self-contained container stacks and their supporting configuration. | `Docker/<application>/` |
| Host services | Version-controls selected NAS, SMART, filesystem-snapshot, and scheduled-task configuration. | `etc/` |
| Automation | Deploys changed application stacks and runs recurring operating-system updates. | `.github/workflows/` |

## Architecture

```text
Git repository
    |
    +--> Ansible playbooks ----> managed virtual machines
    |                                 |
    |                                 +--> Docker Compose application stacks
    |
    +--> GitHub Actions -------> authenticated deployment runner
                                      |
                                      +--> private network access --> managed virtual machines

Container services --> reverse proxy / DNS --> local clients
Container metrics  --> monitoring stack --> dashboards
Media workloads    --> network storage --> media applications
```

Docker applications are deployed per host through Ansible. Each application has a directory under `Docker/`; the deployment role copies that directory to its target host and starts the Compose project when the application is enabled. The Docker-app playbooks also ensure that container metrics collection is deployed alongside declared applications.

Some application entries can be deliberately disabled. Disabled entries are retained in the deployment map but are stopped rather than started, allowing a stack to remain defined without being active.

## Repository Layout

| Path | Purpose |
| --- | --- |
| `Ansible/ansible.cfg` | Ansible configuration for this repository. |
| `Ansible/inventories/` | Encrypted inventory and inventory-related data. Do not expose its contents. |
| `Ansible/playbooks/` | Playbooks for baseline hosts, Docker workloads, storage, media, networking, and updates. |
| `Ansible/roles/common/` | Shared tasks, including reachability checks. |
| `Ansible/roles/docker_apps/` | Docker installation, Compose deployment, and orphan-directory cleanup tasks. |
| `Ansible/Makefile` | Local shortcuts for the supported playbooks. |
| `Docker/<application>/` | One Docker Compose project per application, with application configuration and optional helper scripts. |
| `Docker/update.sh` | Utility used for Docker-related maintenance. |
| `etc/` | Managed host configuration, including Samba, SMART, snapshotting, and cron settings. |
| `.github/workflows/` | Continuous deployment and scheduled-maintenance workflows. |
| `Archives/` | Historical or retired material; not part of the active deployment path unless explicitly restored. |

## Application Categories

The active Docker tree includes services in these broad categories:

| Category | Examples |
| --- | --- |
| Edge and network services | Reverse proxy, DNS filtering, dynamic DNS updates, uptime/UPS utilities. |
| Observability | Metrics collection, monitoring, dashboards, and health checks. |
| Media and automation | Media server, media-management tools, home automation, and game servers. |
| Developer and productivity tools | Source hosting, browser IDE, document processing, terminal access, and AI interfaces. |
| Portals and administration | Dashboards and container-management services. |

The authoritative host-to-application mapping is maintained in the Docker-app playbooks, not in this table. Update the appropriate mapping whenever an application is added, moved, enabled, or retired.

## Prerequisites

Use a trusted administrator workstation with access to the private management network. Typical local requirements are:

- Ansible compatible with the playbooks in `Ansible/`.
- Docker CLI and Compose plugin for local validation when needed.
- SSH access to the managed hosts.
- Access to the Ansible Vault password or vault identity.
- Any private-network client required by the environment.

GitHub Actions additionally requires repository secrets for the vault, deployment SSH authentication, and private-network authentication. Secret names and values should be configured in the repository settings, never documented or committed here.

## Local Operations

Run Ansible commands from `Ansible/`. The Makefile supplies the supported targets:

```sh
cd Ansible
make help
```

Run a dry run before making infrastructure changes:

```sh
cd Ansible
make pve-1-docker-apps CHECK='--check'
```

Run a deployment with an interactive vault prompt:

```sh
cd Ansible
make pve-1-docker-apps VAULT='--vault-id @prompt'
```

Other available targets include baseline configuration, the second Docker-app group, NAS configuration, media-server configuration, network routing, and operating-system updates. Use `make help` as the source of truth for the current list.

To invoke a playbook directly:

```sh
cd Ansible
ansible-playbook playbooks/<playbook>.yml \
  -i inventories/home/inventory.ini \
  --vault-id @prompt
```

### Targeted Docker Deployment

The Docker-app playbooks accept `target_apps_csv` to restrict a run to named application directories. This is useful for validating a single changed stack without deploying unrelated applications.

```sh
cd Ansible
ansible-playbook playbooks/pve-1-docker-apps.yml \
  -i inventories/home/inventory.ini \
  --vault-id @prompt \
  --extra-vars 'target_apps_csv=example-app'
```

The deployment role supports application flags in the playbook mappings:

| Flag | Effect |
| --- | --- |
| `online` | Starts the stack when true; stops an existing stack when false. |
| `restart` | Recreates containers during `docker compose up`. |
| `pull_latest` | Pulls images before starting the stack. |
| `build` | Builds the Compose project before starting it. |

By default, the Docker-app playbooks remove deployed application directories that are no longer declared for a host. Review mapping changes carefully. Set `cleanup_orphans_enabled=false` only when a temporary exception is necessary.

## Deployment Automation

The Docker deployment workflow runs when relevant Docker files are pushed to the default branch or when it is manually dispatched. It detects the changed application directories and limits deployments to the applicable host groups where possible; broader changes trigger a full Docker deployment.

The updates workflow runs on a schedule and can also be dispatched manually. It uses Ansible to apply the repository's operating-system update playbook.

Workflows authenticate with GitHub Actions secrets and access hosts through the private network. Treat workflow logs as potentially sensitive operational output and avoid printing configuration values or credentials from scripts.

## Adding or Changing an Application

1. Create or update `Docker/<application>/docker-compose.yml` and the application configuration required by the stack.
2. Keep credentials in ignored local secret files or an approved secret-management system. Commit only sanitized templates or non-sensitive defaults.
3. Add or update the application's host mapping in the relevant Docker-app playbook.
4. If the application must be included in automated changed-app detection, update the corresponding workflow allowlist.
5. Validate the Compose configuration locally when possible.
6. Run the targeted Ansible deployment in check mode, then deploy to the intended host group.
7. Confirm service health through the normal monitoring and administrative interfaces without recording private endpoints in documentation.

## Secrets and Sensitive Data

Sensitive data must not be committed, copied into issues, or added to documentation. This includes:

- Passwords, API keys, tokens, certificates, private keys, and vault passwords.
- Hostnames, IP addresses, DNS zones, internal URLs, and inventory variables.
- VPN profiles, network-share paths containing credentials, and private topology details.
- Application database dumps, media metadata, and deployment logs containing configuration values.

Use these controls:

- Store encrypted inventory data in Ansible Vault and provide the vault secret at run time.
- Keep `.env`, key, certificate, and machine-specific files out of version control. The root `.gitignore` covers common secret-file patterns.
- Use GitHub Actions secrets for CI/CD credentials.
- Prefer redacted examples such as `example-app`, `example.internal`, and `REPLACE_ME` in committed configuration and documentation.
- Before committing, inspect `git diff --check` and `git status`, then review the staged diff for accidental secrets.

If a credential is exposed, revoke or rotate it immediately. Removing it from a later commit does not remove it from repository history or workflow logs.

## Validation and Troubleshooting

Start with low-risk checks:

```sh
cd Ansible
ansible-playbook playbooks/<playbook>.yml \
  -i inventories/home/inventory.ini \
  --vault-id @prompt \
  --check
```

For a Compose stack, validate its resolved configuration only on a trusted machine with the required local secret files available:

```sh
docker compose -f Docker/<application>/docker-compose.yml config
```

When a deployment does not behave as expected:

1. Confirm access to the private management network and the target host's reachability.
2. Run the relevant playbook in check mode with a host limit.
3. Check that the application directory name matches both the `Docker/` path and the playbook mapping.
4. Review the target host's Compose status and logs without copying sensitive environment values into tickets or commits.
5. Verify that any expected images, volumes, networks, and external dependencies are available to that host.

## Contribution Guidelines

- Keep each Docker application self-contained under `Docker/<application>/`.
- Make the smallest change that produces the intended operational result.
- Preserve existing Ansible formatting and use fully qualified module names in new tasks.
- Test deployment changes with `--check` before applying them to active infrastructure.
- Do not modify `Archives/` as part of normal operational work unless intentionally restoring a retired component.
- Never commit sensitive data, even encrypted copies, unless the repository's established vault workflow explicitly requires it.

## Scope

This is an operational repository for a private environment, not a turnkey public deployment. Adapting it for another environment requires replacing the inventory, secrets, host mappings, storage integrations, and network configuration with values appropriate for that environment.
