# jenkins-agent_esp-rs

English | [한국어 (Korean)](README_ko.md)

A specialized **Jenkins SSH Agent** Docker image designed for compiling **Rust embedded firmware (`esp-rs`, `esp-idf`, `esp-hal`)** for Espressif chips (ESP32, ESP32-S2/S3, ESP32-C2/C3/C6/H2, etc.).

Built on top of the official [`jenkins/ssh-agent:latest`](https://hub.docker.com/r/jenkins/ssh-agent) base image, supporting both **`linux/amd64`** and **`linux/arm64`** multi-architecture platforms.

---

## Features & Included Toolchains

- **Jenkins SSH Agent**: Ready for controller-agent communication over SSH via built-in `sshd`.
- **Rust Toolchain**: Latest stable Rust (`rustup`, `cargo`, `rustc`).
- **Espressif Rust Tools**:
  - `espup`: Espressif Rust ecosystem and toolchain installer.
  - `ldproxy`: Linker proxy required for linking Rust binaries with ESP-IDF.
  - Pre-installed toolchains for both Xtensa (ESP32, S2, S3) and RISC-V (C2, C3, C6, H2) architectures.
- **ESP-IDF Build Dependencies**: `clang`, `libclang-dev` (essential for `bindgen`), `python3`, `python3-pip`, `python3-venv`, `ninja-build`, `cmake`, `libudev-dev`, `libssl-dev`, `libusb-1.0-0`, etc.
- **Automatic Environment Sourcing**: Automatically sources `/home/jenkins/export-esp.sh` during SSH logins and non-interactive shell executions, making tools and `LIBCLANG_PATH` immediately available.

---

## Prerequisites: Generate SSH Key Pair

Generate an SSH key pair on your Jenkins Controller (or host machine) to authenticate with the agent container:

```bash
ssh-keygen -t ed25519 -C "jenkins@controller" -f ~/.ssh/jenkins_agent_ed25519
```

- **Public Key (`~/.ssh/jenkins_agent_ed25519.pub`)**: Injected into the agent container via environment variables.
- **Private Key (`~/.ssh/jenkins_agent_ed25519`)**: Stored in Jenkins Controller's Credential Store.

---

## How to Run the Agent

### Method 1. Using Docker Compose (Recommended)

1. Create a configuration file from the example:
   ```bash
   cp .env.example .env
   ```
2. Open `.env` and set your controller's public SSH key:
   ```bash
   JENKINS_AGENT_SSH_PUBKEY=ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... jenkins@controller
   ```
3. Start the container:
   ```bash
   docker compose up -d
   ```

### Method 2. Using Docker CLI Directly

```bash
docker run -d \
  --name jenkins-agent-esp-rs \
  --restart unless-stopped \
  -p 2222:22 \
  -e "JENKINS_AGENT_SSH_PUBKEY=ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... jenkins@controller" \
  ghcr.io/suapapa/ssh-agent_esp-rs:latest
```

---

## Register Node in Jenkins Controller

1. In the Jenkins Web UI, navigate to **`Manage Jenkins` > `Credentials` > `System` > `Global credentials`**.
2. Click **Add Credentials**:
   - **Kind**: `SSH Username with private key`
   - **ID**: `jenkins-ssh-agent-key`
   - **Username**: `jenkins`
   - **Private Key**: Select `Enter directly` and paste the contents of `~/.ssh/jenkins_agent_ed25519`.
3. Go to **`Manage Jenkins` > `Nodes` > `New Node`**:
   - **Node name**: `esp-rs-agent` (or your preferred name)
   - Select **Permanent Agent**, then click **Create**.
4. Configure Node details:
   - **Remote root directory**: `/home/jenkins/agent` (default)
   - **Labels**: `esp-rs rust`
   - **Launch method**: **`Launch agents via SSH`**
     - **Host**: IP or hostname where the agent container is running
     - **Credentials**: Select `jenkins-ssh-agent-key` created in Step 2
     - **Port**: `2222` (mapped host port)
     - **Host Key Verification Strategy**: `Non verifying verification strategy` (or Known hosts)
5. Click **Save**. The controller will connect to the agent container via SSH and initiate the build agent.

---

## Jenkinsfile Pipeline Example

Since the ESP environment variables are automatically loaded, you can directly run `cargo` commands in pipeline stages without needing manual `source` commands:

```groovy
pipeline {
    agent {
        node {
            label 'esp-rs'
        }
    }

    stages {
        stage('Check Environment') {
            steps {
                sh 'rustc --version'
                sh 'cargo --version'
                sh 'espup --version'
            }
        }

        stage('Checkout') {
            steps {
                git branch: 'main', url: 'https://github.com/my-org/esp-project.git'
            }
        }

        stage('Build') {
            steps {
                // Build your ESP-RS project
                sh 'cargo build --release'
            }
        }
    }
}
```

---

## CI/CD (GitHub Actions)

The repository workflow ([`.github/workflows/docker.yml`](.github/workflows/docker.yml)) builds multi-architecture images **natively without QEMU emulation**:

- **AMD64 Build**: GitHub-hosted `ubuntu-24.04` (x86_64) runner
- **ARM64 Build**: GitHub-hosted `ubuntu-24.04-arm` (AArch64) runner
- **Manifest Merge**: Assembles both native builds into a unified multi-platform manifest using `docker buildx imagetools create`
- **Registry**: Automatically pushed to GitHub Container Registry (`ghcr.io/suapapa/ssh-agent_esp-rs`) using the default `GITHUB_TOKEN`
