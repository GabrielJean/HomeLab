# HomeLab

> A personal infrastructure lab for learning how self-hosted services, automation, observability, networking, and reliable deployments fit together.

This repository documents and automates my homelab environment. It is not intended to be a turnkey deployment guide or a shared operations manual. Configuration is deliberately presented at a high level: private infrastructure details, credentials, addresses, domains, and inventory data are excluded.

## Overview

HomeLab is a practical platform for building experience with the systems that support real applications after they leave a developer's laptop. The environment combines virtual machines, Docker Compose workloads, Ansible automation, monitoring, network-facing services, and CI/CD workflows.

The project emphasizes repeatability over one-off configuration. Application definitions live in version control, deployments are performed through Ansible, and routine updates are automated through GitHub Actions.

```text
Source control
    |
    +--> Ansible automation ---> virtual machines ---> Docker Compose services
    |
    +--> GitHub Actions ------> deployment and maintenance workflows

Services ---> reverse proxy and DNS ---> local clients
Metrics  ---> monitoring stack -------> dashboards
```

## What I Built

| Area | Implementation |
| --- | --- |
| Compute platform | Virtualized service hosts running a mix of application, network, storage, media, and utility workloads. |
| Configuration management | Ansible playbooks that bootstrap hosts, deploy container stacks, perform maintenance, and handle reachability gracefully. |
| Container platform | Independent Docker Compose projects for each service, enabling focused changes and isolated configuration. |
| Deployment automation | GitHub Actions detects changed application directories and deploys only the affected workloads when possible. |
| Observability | Container and proxy metrics feed a monitoring stack and dashboards for service visibility. |
| Network services | Reverse proxy, DNS filtering, dynamic DNS, and private-network access support the self-hosted applications. |
| Data services | Storage, media, and host-maintenance configuration are captured alongside the application infrastructure. |

## Technology Stack

| Category | Technologies |
| --- | --- |
| Virtualization | Proxmox-based virtual machine infrastructure |
| Automation | Ansible and YAML playbooks |
| Containers | Docker Engine and Docker Compose |
| Continuous delivery | GitHub Actions |
| Monitoring | Prometheus, Grafana, and cAdvisor |
| Networking | Traefik, AdGuard Home, private-network connectivity, and dynamic DNS tooling |
| Storage and maintenance | NAS services, SMART monitoring, scheduled tasks, and filesystem snapshot configuration |
| Self-hosted applications | Media, home automation, developer tools, dashboards, document processing, game servers, and administrative services |

## Repository Tour

| Path | Description |
| --- | --- |
| `Ansible/` | The automation layer. Playbooks describe host setup, Docker application deployment, updates, networking, storage, and media-related configuration. |
| `Ansible/roles/` | Reusable Ansible tasks for reachability checks, Docker installation, Compose deployment, and deployment cleanup. |
| `Docker/` | Self-contained Docker Compose projects. Each application owns its Compose definition and non-sensitive supporting configuration. |
| `.github/workflows/` | CI/CD workflows for selective Docker deployment and scheduled operating-system updates. |
| `etc/` | Version-controlled host configuration for services such as file sharing, monitoring, snapshotting, and scheduled jobs. |
| `Archives/` | Historical infrastructure experiments and retired configuration retained for reference. |

## Deployment Design

The deployment model is intentionally simple:

1. Each application is defined in its own directory under `Docker/`.
2. An Ansible playbook maps application stacks to their intended host groups.
3. The Docker deployment role copies the requested application definition to the target host.
4. Docker Compose starts, recreates, pulls, or builds the stack according to its declared deployment options.
5. Asynchronous Compose jobs allow independent applications to deploy in parallel while Ansible waits for completion.

This approach keeps the source repository as the desired-state definition without introducing the operational complexity of a full container orchestrator for every workload.

## Continuous Delivery

The deployment workflow is designed to reduce unnecessary changes:

1. A push that changes Docker-related files starts the workflow.
2. The workflow identifies which application directories changed.
3. Known application-to-host mappings select the smallest relevant deployment scope.
4. Broad or shared changes fall back to a full deployment for safety.
5. Jobs connect through the private network, unlock the encrypted inventory at run time, and execute the matching Ansible playbook.

Scheduled automation also applies operating-system updates through Ansible. This separates application delivery from routine host maintenance while keeping both processes version-controlled.

## Engineering Decisions

### Compose Per Application

Each service is isolated in its own Compose project rather than being collected in a single large file. This makes configuration easier to understand, changes easier to review, and deployments easier to target.

### Ansible as the Control Plane

Ansible connects the repository to the running infrastructure. It installs prerequisites, copies desired application state, starts enabled stacks, stops intentionally disabled stacks, and cleans up application directories that are no longer declared for a host.

### Selective Deployments

The CI workflow detects changed application directories and limits deployments accordingly. This reduces the blast radius and feedback time of routine service updates, while retaining a safe full-deployment fallback for shared changes.

### Observability by Default

Metrics collection is treated as part of the platform rather than an afterthought. Application hosts include baseline container metrics, with dashboards and monitoring services providing a consolidated view of the environment.

### Secrets Outside Source Control

Sensitive values are intentionally excluded from the repository. Encrypted inventory data, ignored environment files, and CI secret storage keep credentials and private infrastructure details separate from the code that defines the platform.

## Skills Demonstrated

- Designing and operating a multi-service self-hosted environment.
- Automating infrastructure and deployments with Ansible.
- Structuring Docker Compose applications for independent lifecycle management.
- Building selective, path-aware deployment workflows with GitHub Actions.
- Applying secrets-management boundaries across local development, automation, and managed hosts.
- Operating reverse-proxy, DNS, monitoring, storage, and media workloads together.
- Documenting infrastructure as code while separating active configuration from archived experiments.

## Scope and Safety

This is a personal learning and experimentation environment. It may contain integrations and configuration patterns tailored to my own infrastructure, so it should not be deployed unchanged elsewhere.

To protect the environment, this repository and README do not publish:

- Credentials, tokens, private keys, certificates, or vault passwords.
- Host addresses, internal DNS names, network topology, or management endpoints.
- Private service URLs, personal data, media metadata, or deployment logs.
- Unredacted environment files or infrastructure inventory values.

## Selected Services

The environment hosts a varied set of services to explore different operational concerns:

| Focus | Examples of capabilities |
| --- | --- |
| Platform services | Reverse proxying, DNS, container administration, and service dashboards. |
| Reliability and visibility | Metrics collection, monitoring dashboards, health checks, and host maintenance. |
| Personal infrastructure | Home automation, media serving and management, network storage, and backup-oriented configuration. |
| Developer productivity | Source control, browser-based development, terminal access, document conversion, and AI-assisted tooling. |
| Learning and recreation | Dedicated game-server workloads and experimental self-hosted applications. |

## Project Status

Active personal project. The repository evolves as services are added, replaced, automated, or retired, with older experiments preserved under `Archives/` when they remain useful as technical reference.
