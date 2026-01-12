# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Ranger is a Terraform-based infrastructure project for setting up Attack/Defense (A/D) CTF ranges on AWS. It provisions VPCs, networking, VPN servers, and per-team infrastructure for CTF competitions.

## Requirements

- Terraform >= 1.13
- Packer (for custom AMI builds)
- AWS credentials configured

## Common Commands

```bash
# Load environment variables from .env
source init.sh

# Initialize Terraform (download providers/modules)
terraform init

# Preview changes
terraform plan

# Apply infrastructure changes
terraform apply

# Destroy infrastructure
terraform destroy
```

## Architecture

### Network Layout

Two VPCs peered together:
- **ranger_main** (10.50.0.0/16): Contains public-facing infrastructure
  - `ranger_public` subnet (10.50.0.0/25): VPN servers, internet gateway
  - `ranger_routers` subnet (10.50.1.0/24): Internal routers
- **ranger_teams** (10.32.0.0/16): Contains team infrastructure
  - Each team gets a /24 subnet (10.32.X.0/24 where X = team_id)

### Terraform Modules

- **Root module** (`/`): Main configuration, providers, network setup, VPN, admin instance
  - `main.tf`: AWS provider, team module instantiation
  - `network_config.tf`: VPC, subnet, gateway, and routing configuration
  - `vpn.tf`: VPN security group and module instantiation
  - `admin.tf`: Administrative EC2 instance with SSH key pair
  - `ami.tf`: Ubuntu 24.04 AMI data source
  - `variables.tf`: Instance types, region, number of teams, admin SSH CIDR

- **team** (`/team`): Per-team infrastructure (subnet, vulnbox, thrower)
  - Instantiated N times based on `num_teams` variable

- **vpn_server** (`/vpn_server`): VPN server EC2 instance and network interface

### Admin Instance

The admin instance is an EC2 instance in the `ranger_routers` subnet for administrative access and management tasks. It is accessible via SSH only through the VPN (no public IP). Access is controlled by the `admin_ssh_cidr` variable, which can be set to:
- `10.50.0.0/16` (default): Allow SSH from all VPN users
- A narrower range (e.g., `10.50.0.128/25`): Restrict SSH to admin-only VPN clients

The SSH private key is automatically generated and saved to `admin_key.pem` in the project root with 0600 permissions.

### Key Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `num_teams` | 4 | Number of teams to provision |
| `aws_region` | us-east-1 | AWS region |
| `*_instance_type` | t3.micro | Various instance types (vulnbox, router, vpn, etc.) |
| `admin_ssh_cidr` | 10.50.0.0/16 | CIDR block allowed to SSH into admin instance (VPC CIDR or narrower range for admin-only VPN) |

### Environment Configuration

Create a `.env` file for AWS credentials and other environment variables. Load with `source init.sh`.
