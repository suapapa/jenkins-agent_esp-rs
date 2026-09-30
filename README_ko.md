# jenkins-agent_esp-rs

[English](README.md) | 한국어

Espressif 칩셋(ESP32, ESP32-S2/S3, ESP32-C2/C3/C6/H2 등)을 위한 **Rust(`esp-rs`, `esp-idf`, `esp-hal`) 빌드 전용 Jenkins SSH Agent** Docker 이미지입니다.

공식 [`jenkins/ssh-agent:latest`](https://hub.docker.com/r/jenkins/ssh-agent) 이미지를 기반으로 제작되었으며, **`linux/amd64`** 및 **`linux/arm64`** 멀티 아키텍처를 지원합니다.

---

## 주요 기능 및 구성 환경

- **Jenkins SSH Agent**: Jenkins Controller가 SSH로 접속하여 작업을 위임하는 에이전트 환경 (`sshd` 내장)
- **Rust 툴체인**: 최신 Rust Stable (`rustup`, `cargo`, `rustc`)
- **Espressif Rust 도구**:
  - `espup`: ESP 툴체인 설치 및 관리 도구
  - `ldproxy`: ESP-IDF 바이너리 링킹을 위한 필수 유틸리티
  - Xtensa(ESP32, S2, S3) 및 RISC-V(C2, C3, C6, H2) 빌드 환경
- **ESP-IDF 빌드 필수 패키지**: `clang`, `libclang-dev` (`bindgen` 필수), `python3`, `python3-pip`, `python3-venv`, `ninja-build`, `cmake`, `libudev-dev`, `libssl-dev`, `libusb-1.0-0` 등
- **자동 환경 로드**: SSH 로그인 및 Jenkins 비대화형 쉘 실행 시 ESP 환경변수(`/home/jenkins/export-esp.sh`)가 자동 적용되도록 설정

---

## 사전 준비: SSH 키 쌍 생성

Jenkins Controller가 Agent 컨테이너에 접속할 때 사용할 SSH 키 쌍을 생성합니다.

```bash
ssh-keygen -t ed25519 -C "jenkins@controller" -f ~/.ssh/jenkins_agent_ed25519
```

- **공개키 (`~/.ssh/jenkins_agent_ed25519.pub`)**: 에이전트 컨테이너 실행 시 환경 변수로 주입합니다.
- **비밀키 (`~/.ssh/jenkins_agent_ed25519`)**: Jenkins Controller의 Credentials에 등록합니다.

---

## 에이전트 실행 방법

### 방법 1. Docker Compose (권장)

1. 환경 설정 파일 생성:
   ```bash
   cp .env.example .env
   ```
2. `.env` 파일을 열고 생성한 공개키 내용을 입력합니다:
   ```bash
   JENKINS_AGENT_SSH_PUBKEY=ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... jenkins@controller
   ```
3. 컨테이너 실행:
   ```bash
   docker compose up -d
   ```

### 방법 2. Docker CLI 직접 실행

```bash
docker run -d \
  --name jenkins-agent-esp-rs \
  --restart unless-stopped \
  -p 2222:22 \
  -e "JENKINS_AGENT_SSH_PUBKEY=ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... jenkins@controller" \
  ghcr.io/suapapa/ssh-agent_esp-rs:latest
```

---

## Jenkins Controller에서 노드(Agent) 등록

1. Jenkins 웹 UI에서 **`Jenkins 관리` > `Credentials` > `System` > `Global credentials`** 이동
2. **Add Credentials** 클릭:
   - **Kind**: `SSH Username with private key`
   - **ID**: `jenkins-ssh-agent-key`
   - **Username**: `jenkins`
   - **Private Key**: `Enter directly` 선택 후 `~/.ssh/jenkins_agent_ed25519` 파일의 비밀키 내용 입력
3. **`Jenkins 관리` > `Nodes` > `New Node`** 클릭:
   - **Node name**: `esp-rs-agent` (원하는 이름)
   - **Permanent Agent** 선택 후 Create
4. 세부 설정:
   - **Remote root directory**: `/home/jenkins/agent` (기본값)
   - **Labels**: `esp-rs rust`
   - **Launch method**: **`Launch agents via SSH`**
     - **Host**: Agent 컨테이너가 실행 중인 호스트 IP 또는 도메인
     - **Credentials**: 위에서 등록한 `jenkins-ssh-agent-key` 선택
     - **Port**: `2222` (호스트 매핑 포트)
     - **Host Key Verification Strategy**: `Non verifying verification strategy` (또는 Known hosts)
5. **Save**를 누르면 Jenkins Controller가 Agent 컨테이너에 접속하여 에이전트 연결을 완료합니다.

---

## Jenkinsfile 파이프라인 예제

에이전트에 ESP 환경변수가 기본 탑재되어 있으므로 파이프라인 스크립트에서 별도 `source` 명령어 없이 곧바로 `cargo` 명령을 실행할 수 있습니다.

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
                // ESP32 프로젝트 빌드 예시
                sh 'cargo build --release'
            }
        }
    }
}
```

---

## CI/CD (GitHub Actions)

이 저장소의 [`.github/workflows/docker.yml`](.github/workflows/docker.yml)은 **QEMU 에뮬레이션 없이** 네이티브 하드웨어 러너를 활용하여 멀티 아키텍처 이미지를 빌드합니다:

- **AMD64 빌드**: GitHub-hosted `ubuntu-24.04` (x86_64) 러너
- **ARM64 빌드**: GitHub-hosted `ubuntu-24.04-arm` (AArch64) 러너
- **Manifest 병합**: 각 아키텍처별 빌드 완료 후 `docker buildx imagetools create`를 통해 단일 멀티플랫폼 매니페스트로 결합
- **레지스트리**: GitHub Container Registry (`ghcr.io/suapapa/ssh-agent_esp-rs`)로 자동 푸시 (별도 외부 Secret 불필요)
