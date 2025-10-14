# Setting Up Dependencies
This guide explains *what* you’re doing and *why*, then gives you simple copy‑paste steps.

---

## What you’re setting up (in plain English)
- **Containers** are like lightweight apps that run the same way on any computer.
- An **image** is a blueprint for a container.
- A **Podman machine** is a tiny Linux virtual machine that Podman uses on Mac and Windows (because containers expect Linux).
- **VS Code settings** make the Dev Containers extension use Podman instead of Docker.

---

## Before you start
- **Windows:** Make sure you can run `.bat` files and have admin rights. Virtualization should be enabled (most PCs already have this).
- **macOS:** Podman needs a Podman machine (we’ll create it). If you don’t have Podman yet, install **Podman Desktop** or via Homebrew: `brew install podman`.
- You’ll run commands in **Terminal** (macOS) or **PowerShell** (Windows).

---

## Step 0 - Clone The Repo
```powershell
git clone https://github.com/jwyffels2/helios.git
```

## Step 1 - Windows quick setup (auto‑install)
Run the script to install **WSL2**, **Podman**, and **Alire**:

```powershell
${projectDir}/Windows_Dependencies.bat
```

> After it finishes, **close and reopen** your terminal so new tools are on your PATH.

---

## Step 2 - Create a Podman machine (Mac & Windows)
Do this **once** to set up Podman’s Linux VM:

```bash
podman machine init
```

> You only need to run this the first time.

---

## Step 3 - Start the machine when needed
Each time you want to use Podman (or after a reboot):

```bash
podman machine start
```

> Tip: If commands say the machine isn’t running, just start it again.

---

## Step 4 - Build your image
We’ll build an image named `helios-build` using a `build.dockerfile` in the project folder.

**What the flags mean**
- `-t` -> image name
- `-f` -> which Dockerfile to use
- `.` -> build context (your current folder)

**Build Image From Dockerfile Command**
```bash
podman build -t helios-build -f ./build.dockerfile .
```

> If the file is named differently or in another folder, adjust the `-f` path.

---

## Step 5 - Run the container (interactive, with your code mounted)
This starts a container you can interact with, and mounts your current folder into the container at `/workspace`.

**Run Container With Volume Attached:**
```bash
podman run --rm -it --name helios -v "$PWD :/workspace" -w /workspace helios-build
```

**What the flags mean**
- `--rm` -> auto‑remove the container when you exit
- `-it` -> interactive terminal
- `--name helios` -> friendly name for the container
- `-v "<your folder> :/workspace"` -> mount your current folder inside the container
- `-w /workspace` -> start in `/workspace` inside the container
- `helios-build` -> the image we built in Step 4

> If you see a “permission” or “path” error, double‑check the quotes and the `-v` syntax for your OS.

---

## Step 6 - Make VS Code use Podman (not Docker)
Open **VS Code -> Command Palette -> Preferences: Open User Settings (JSON)** and add:

```json
  "dev.containers.dockerPath": "podman",
  "dev.containers.mountWaylandSocket": false,
  "containers.containerClient": "com.microsoft.visualstudio.containers.podman",
  "containers.orchestratorClient": "com.microsoft.visualstudio.orchestrators.podmancompose",
```

**What this does**
- Tells the Dev Containers extension to talk to **Podman**.
- Uses Podman for both single containers and Compose‑style projects.
---

## Step 7 - Quick “did it work?” checks
Run any of these to verify things are set up:

```bash
podman --version
podman info
podman machine ls
podman images
podman ps
```

You should see:
- A **running** Podman machine after `podman machine start`.
- Your `helios-build` image after the build step.
- Your container in `podman ps` while it’s running.

---

## Handy copy‑paste (Windows to Linux/macOS side‑by‑side)

**Create machine (first time only)**
```powershell
# Windows/Mac
podman machine init
```

**Start machine (every time you restart your PC)**
```powershell
podman machine start
```


**Build image**

```powershell
podman build -t helios-build -f ${projectDir}/build.dockerfile .
```

**Run container**

```bash
podman run --rm -it --name helios -v "$PWD: /workspace" -w /workspace helios-build
```

---

## Troubleshooting (common quick fixes)
- **“machine not running”** -> run `podman machine start`.
- **Volume mount errors** -> check the `-v` syntax for your OS and that the folder exists.
- **Command not found** -> close & reopen your terminal (especially after Windows installer), then try again.
- **Need to reset** -> `podman machine stop` then `podman machine rm` (removes the VM), and re‑run `podman machine init`.

---

## Original quick reference (from your notes)
- Windows auto‑install: `Windows_Dependencies.bat` (then restart terminal)
- Create machine (once): `podman machine init`
- Start machine (when needed): `podman machine start`
- Build: `podman build -t helios-build -f <path to Dockerfile> .`
- Run: `podman run --rm -it --name helios -v "<your folder>:/workspace" -w /workspace helios-build`
