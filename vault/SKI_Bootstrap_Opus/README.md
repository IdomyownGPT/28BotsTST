# SKI Deployment Pack — Schnellstart

**Eine ZIP. Zwei Maschinen. Ein System.**

```
┌─────────────────────────────┐          ┌─────────────────────────────┐
│  WINDOWS HOST               │          │  UBUNTU VM (Hyper-V)        │
│  192.168.178.90             │          │  192.168.178.124            │
│                             │          │                             │
│  ► SKI_Installer.ps1        │──SSH──►  │  ► install_ski_vm.sh        │
│    (Host-Setup + Remote VM) │          │    (Komplette VM-Provision) │
└─────────────────────────────┘          └─────────────────────────────┘
```

---

## Schritt 1: Host einrichten (Windows)

**Was:** Ordnerstruktur, SMB-Share, Firewall, Hyper-V VM

1. ZIP entpacken (z.B. nach `C:\SKI_Setup`)
2. PowerShell **als Administrator** öffnen
3. Ausführen:
   ```powershell
   cd "C:\SKI_Setup\vault\SKI_Bootstrap_Opus"
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
   .\SKI_Installer.ps1
   ```
4. Im Menü wählen:
   - `1` = Full Install (Schritt 1–5 automatisch)
   - `3` = Einzelne Schritte manuell ausführen
   - `4` = VM remote per SSH einrichten (→ Schritt 2)

### Was `SKI_Installer.ps1` macht (Schritte 1–5):

| Schritt | Skript | Beschreibung |
|---------|--------|-------------|
| 1 | `host/01_setup_directories.ps1` | Ordner auf D:\ anlegen |
| 2 | `host/02_setup_smb_share.ps1` | SMB-Share `SKI-Vault-Root` erstellen |
| 3 | `host/03_setup_firewall.ps1` | Ports 1234 (LM Studio) + 445 (SMB) öffnen |
| 4 | `host/04_create_vm.ps1` | Hyper-V VM anlegen (16GB RAM, 4 vCPUs) |
| 5 | `host/07_setup_autoresearch.ps1` | Auto Research (GPU-Loop) einrichten |

---

## Schritt 2: VM einrichten (Ubuntu)

**Was:** Pakete, SMB-Mount, Docker, 9 Container, Hermes

### Option A: Remote vom Host (empfohlen)

Im `SKI_Installer.ps1`-Menü Option `4` wählen (Remote VM Setup).
Das verbindet sich per SSH und führt alle VM-Skripte interaktiv aus.

### Option B: Direkt auf der VM

```bash
ssh archat@192.168.178.124
cd /mnt/28bots_core/Obsidian_Vault/SKI_Bootstrap_Opus/vm
chmod +x install_ski_vm.sh
./install_ski_vm.sh
```

### Was `install_ski_vm.sh` macht (Schritte 1–6):

| Schritt | Skript | Berechtigung | Beschreibung |
|---------|--------|-------------|-------------|
| 1 | `01_setup_base.sh` | sudo | Pakete, User `archat`, Hostname, Timezone, Static IP, SSH, linux-azure |
| 2 | `02_setup_smb_mount.sh` | sudo | SMB-Credentials, fstab, Mount-Verifikation |
| 3 | `03_setup_docker.sh` | sudo | Docker Engine, Compose, docker-Gruppe |
| 4 | `04_deploy_containers.sh` | User | Git-Repo klonen, .env, `docker compose up -d` |
| 5 | `05_setup_hermes.sh` | User | 3×3 Profil-Matrix, Milvus-Memory, Camofox |
| 6 | `06_verify_vm.sh` | User | Read-only Systemcheck aller Komponenten |

> Jeder Schritt folgt: **CHECK → REPORT → ASK → ACT → VERIFY**
> Es wird nichts verändert ohne Benutzerbestätigung.

---

## Verifikation

Nach der Installation auf der VM:
```bash
cd ~/28BotsTST
./scripts/verify_all.sh
```

---

## Dateistruktur dieser ZIP

```
SKI_Deployment_Pack.zip
└── vault/SKI_Bootstrap_Opus/
    ├── README.md              ← Diese Datei
    ├── SKI_Installer.ps1      ← HOST: Einziger Einstiegspunkt
    ├── host/
    │   ├── 01_setup_directories.ps1
    │   ├── 02_setup_smb_share.ps1
    │   ├── 03_setup_firewall.ps1
    │   ├── 04_create_vm.ps1
    │   ├── 05_verify_host.ps1
    │   ├── 06_ssh_vm_setup.ps1
    │   └── 07_setup_autoresearch.ps1
    └── vm/
        ├── install_ski_vm.sh  ← VM: Einziger Einstiegspunkt
        ├── 00_lib.sh          (Shared Library)
        ├── 01_setup_base.sh
        ├── 02_setup_smb_mount.sh
        ├── 03_setup_docker.sh
        ├── 04_deploy_containers.sh
        ├── 05_setup_hermes.sh
        └── 06_verify_vm.sh
```

---

*SKI — Sephirotische Kernintelligenz — Deployment Pack v2.1*
