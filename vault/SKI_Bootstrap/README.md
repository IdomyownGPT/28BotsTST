# SKI Bootstrap Scripts

Installer scripts for setting up the SKI system from scratch.
These scripts live in the Obsidian Vault at `SKI_Bootstrap/` and are accessible from both the Host and the VM.

## Paths

| Location | Path |
|----------|------|
| Host (Windows) | `D:\28Bots_Core\Obsidian_Vault\root\SKI_Bootstrap\` |
| VM (Ubuntu) | `/mnt/28bots_core/Obsidian_Vault/SKI_Bootstrap/` |
| Repo | `vault/SKI_Bootstrap/` |

## Host Scripts (PowerShell)

Run these **on the Windows Server host** in an elevated PowerShell terminal.

| Script | Purpose |
|--------|---------|
| `host/01_setup_directories.ps1` | Create directory structure on D:\ |
| `host/02_setup_smb_share.ps1` | Create SMB share for Obsidian Vault |
| `host/03_setup_firewall.ps1` | Configure firewall rules (ports 1234, 445) |
| `host/04_create_vm.ps1` | Create Hyper-V VM with recommended specs |
| `host/05_verify_host.ps1` | Verify host setup is complete |
| `host/06_ssh_vm_setup.ps1` | Run VM setup scripts remotely via SSH |

### Usage (Host)

```powershell
# Run from elevated PowerShell on Host
cd D:\28Bots_Core\Obsidian_Vault\root\SKI_Bootstrap\host

# Step by step:
.\01_setup_directories.ps1
.\02_setup_smb_share.ps1
.\03_setup_firewall.ps1
.\04_create_vm.ps1        # Only if VM doesn't exist yet
.\05_verify_host.ps1

# Or run VM setup remotely:
.\06_ssh_vm_setup.ps1
```

## VM Scripts (Bash)

Run these **on the Ubuntu VM** via SSH or directly in a terminal.

| Script | Purpose |
|--------|---------|
| `vm/01_setup_base.sh` | Install base packages and configure system |
| `vm/02_setup_smb_mount.sh` | Configure SMB mount with fstab |
| `vm/03_setup_docker.sh` | Install Docker and Docker Compose |
| `vm/04_deploy_containers.sh` | Clone repo and start containers |
| `vm/05_setup_hermes.sh` | Configure Hermes profiles |
| `vm/06_verify_vm.sh` | Run full verification suite |

### Usage (VM)

```bash
# SSH from Host:
ssh archat@192.168.178.124

# On the VM:
cd /mnt/28bots_core/Obsidian_Vault/SKI_Bootstrap/vm

# Step by step:
chmod +x *.sh
./01_setup_base.sh
./02_setup_smb_mount.sh
./03_setup_docker.sh
# Log out and back in for Docker group, then:
./04_deploy_containers.sh
./05_setup_hermes.sh
./06_verify_vm.sh
```

### Usage from Host via SSH (one-liner)

```powershell
# Run a specific VM script from the Host:
ssh archat@192.168.178.124 "bash /mnt/28bots_core/Obsidian_Vault/SKI_Bootstrap/vm/01_setup_base.sh"
```
