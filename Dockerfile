FROM jenkins/ssh-agent:latest

# 1. 시스템 설정 및 패키지 설치 (jenkins/ssh-agent는 기본 실행 사용자가 root입니다)
USER root

# 타임존 설정 (비대화형)
ENV TZ=Asia/Seoul
RUN ln -snf /usr/share/zoneinfo/"${TZ}" /etc/localtime && echo "${TZ}" > /etc/timezone \
    && dpkg-reconfigure -f noninteractive tzdata

# esp-rs / esp-idf 빌드에 필요한 시스템 패키지 설치
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    wget \
    git \
    gcc \
    clang \
    libclang-dev \
    pkg-config \
    libudev-dev \
    libssl-dev \
    libusb-1.0-0 \
    python3 \
    python3-pip \
    python3-venv \
    ninja-build \
    cmake \
    unzip \
    xz-utils \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. jenkins 사용자로 전환하여 Rust 및 espup 설치
USER jenkins
WORKDIR /home/jenkins

# Rust 기본 툴체인 설치
ENV PATH="/home/jenkins/.cargo/bin:${PATH}"
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable

# espup 및 ldproxy 사전 빌드 바이너리 설치 (고속 설치)
RUN ARCH=$(rustup show | grep "Default host" | sed -e 's/.* //') && \
    curl -L "https://github.com/esp-rs/espup/releases/latest/download/espup-${ARCH}" -o "/home/jenkins/.cargo/bin/espup" && \
    chmod +x "/home/jenkins/.cargo/bin/espup" && \
    curl -L "https://github.com/esp-rs/embuild/releases/latest/download/ldproxy-${ARCH}.zip" -o "/tmp/ldproxy.zip" && \
    unzip "/tmp/ldproxy.zip" -d "/home/jenkins/.cargo/bin/" && \
    rm "/tmp/ldproxy.zip" && \
    chmod +x "/home/jenkins/.cargo/bin/ldproxy"

# espup을 통한 ESP Toolchain 설치
# (필요에 따라 --targets esp32,esp32s3 등으로 원하는 타깃만 한정 가능)
RUN espup install --export-file /home/jenkins/export-esp.sh

# install sccache
RUN cargo install sccache --locked

# SSH 세션 및 쉘 실행 시 ESP 환경변수 자동 로드
RUN echo "source /home/jenkins/export-esp.sh" >> /home/jenkins/.bashrc && \
    echo "source /home/jenkins/export-esp.sh" >> /home/jenkins/.profile

# 3. sshd 실행을 위해 root 사용자로 복귀 (jenkins/ssh-agent 엔트리포인트는 root 권한 필요)
USER root
RUN echo "source /home/jenkins/export-esp.sh" >> /etc/profile.d/esp.sh

ENV BASH_ENV="/home/jenkins/export-esp.sh"
ENV ENV="/home/jenkins/export-esp.sh"

# jenkins/ssh-agent의 기본 ENTRYPOINT(["setup-sshd"]) 및 22번 포트 사용
EXPOSE 22
