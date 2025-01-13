#!/usr/bin/env bash

###############################################################################
# Kubeadm Installation Script with Architecture Detection,
# Version Prompt, and Step Resume on Failure
###############################################################################

set -euo pipefail

# 스크립트 실행 상태를 기록할 파일
STATE_FILE="/tmp/k8s_install_state"

# 스크립트에서 사용할 설치 버전 혹은 정보 (예: kubeadm, kubectl, 등)
# 실제 운영 시, 필요하다면 특정 버전을 명시할 수도 있습니다.
KUBE_VERSION="v1.32"
CALICO_VERSION="v3.28.1"

###############################################################################
# 함수 정의
###############################################################################

# -----------------------------------------------------------------------------
# 현재 단계 상태 조회
# -----------------------------------------------------------------------------
function get_step_status() {
  local step="$1"

  # STATE_FILE이 없으면 상태 정보가 전혀 없으므로 빈 문자열 반환
  if [[ ! -f "$STATE_FILE" ]]; then
    echo ""
    return
  fi

  # 해당 스텝의 상태 반환
  grep "^${step}=" "$STATE_FILE" 2>/dev/null | cut -d'=' -f2 || true
}

# -----------------------------------------------------------------------------
# 현재 단계 상태 기록
# -----------------------------------------------------------------------------
function set_step_status() {
  local step="$1"
  local status="$2"

  # 기존에 같은 스텝에 대한 기록이 있으면 삭제
  sed -i "/^${step}=/d" "$STATE_FILE" 2>/dev/null || true
  # 새 상태 기록
  echo "${step}=${status}" >> "$STATE_FILE"
}

# -----------------------------------------------------------------------------
# 단계를 실행하는 공통 함수
#   - 이미 성공(done)된 단계면 스킵
#   - 아직 실행 안 되었거나 실패(failed) 이력이 있으면 재시도
#   - 성공하면 done 상태로 기록, 실패하면 failed 상태로 기록 후 스크립트 종료
# -----------------------------------------------------------------------------
function run_step() {
  local step="$1"
  local step_desc="$2"
  local step_cmd="$3"

  local current_status
  current_status="$(get_step_status "$step")"

  # 이미 성공적으로 완료된 단계라면 스킵
  if [[ "$current_status" == "done" ]]; then
    echo "[$step] '$step_desc' 단계는 이미 완료되었습니다. 스킵합니다."
    return
  fi

  echo "====================================================================="
  echo "[$step] 시작: $step_desc"
  echo "====================================================================="

  # 명령어 실행
  if eval "$step_cmd"; then
    echo "[$step] '$step_desc' 성공"
    set_step_status "$step" "done"
  else
    echo "[$step] '$step_desc' 실패"
    set_step_status "$step" "failed"
    exit 1
  fi
}

###############################################################################
# 설치 진행 전 사용자 확인
###############################################################################

echo "###############################################################################"
echo " 이 스크립트는 다음 구성 요소를 설치/초기화합니다."
echo " - Kubernetes $KUBE_VERSION(stable)"
echo " - containerd (현재 시스템 아키텍처 자동 감지)"
echo " - Calico $CALICO_VERSION (CNI)"
echo "###############################################################################"
read -rp "위 버전/구성을 설치하시겠습니까? (y/N) " answer

if [[ "${answer,,}" != "y" ]]; then
  echo "사용자가 설치를 진행하지 않기로 했습니다. 스크립트를 종료합니다."
  exit 0
fi

###############################################################################
# 아키텍처 감지
###############################################################################
ARCH="$(uname -m)"

echo "감지된 아키텍처: $ARCH"

# containerd 저장소 및 패키지 설치 시 아키텍처에 따른 분기 예시
# 필요 시 아래를 수정하여 실제 저장소나 dpkg --add-architecture 등을 구성하세요.
case "$ARCH" in
  "x86_64"|"amd64")
    echo "x86_64(amd64) 환경으로 설정합니다."
    DOCKER_REPO_ARCH="amd64"
    ;;
  "arm64"|"aarch64")
    echo "ARM64 환경으로 설정합니다."
    DOCKER_REPO_ARCH="arm64"
    ;;
  *)
    echo "지원하지 않는 아키텍처입니다: $ARCH"
    echo "스크립트를 종료합니다."
    exit 1
    ;;
esac

###############################################################################
# 스텝 실행
###############################################################################

# Step 1. APT 패키지 인덱스 업데이트
run_step "STEP_01" "APT 패키지 인덱스 업데이트" "
  apt-get update -y
"

# Step 2. vim, git 설치
run_step "STEP_02" "vim, git 설치" "
  apt-get install -y vim git
"

# Step 3. apt 패키지 업그레이드
run_step "STEP_03" "APT 패키지 업그레이드" "
  apt-get update -y && apt-get upgrade -y
"

# Step 4. 스왑 비활성화
run_step "STEP_04" "스왑 비활성화" "
  swapoff -a
  sed -i.bak -r 's/(.+ swap .+)/#\\1/' /etc/fstab
"

# Step 5. 컨테이너 관련 모듈 로드
run_step "STEP_05" "br_netfilter, overlay 모듈 설정" "
  cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf > /dev/null
overlay
br_netfilter
EOF
  modprobe br_netfilter
  modprobe overlay
"

# Step 6. sysctl 설정
run_step "STEP_06" "net.bridge.bridge-nf-call-iptables 등 설정" "
  tee /etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
  sysctl --system
"

# Step 7. APT HTTPS 등 필수 패키지 설치
run_step "STEP_07" "apt-transport-https, ca-certificates 등 설치" "
  apt-get install -y apt-transport-https ca-certificates curl gnupg2 software-properties-common
"

# Step 8. containerd 설치
# 아키텍처별로 dpkg --add-architecture 등을 사용할 수 있습니다.
# 여기서는 간단한 예시로만 구성합니다.
run_step "STEP_08" "[${ARCH}] containerd 설정 및 설치" "
  # ARM64 아키텍처인 경우 등 필요하다면 dpkg --add-architecture arm64 등을 해줄 수 있음.
  if [[ '$DOCKER_REPO_ARCH' == 'arm64' ]]; then
    dpkg --add-architecture arm64 || true
  fi

  # docker GPG 키링 디렉터리 준비
  mkdir -p /etc/apt/keyrings
  chmod 755 /etc/apt/keyrings

  # Docker GPG 키 추가
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

  # /etc/apt/sources.list.d/docker.list가 없으면 추가
  if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
    echo \"deb [arch=$DOCKER_REPO_ARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  fi

  # apt 업데이트 후 containerd 설치
  apt-get update -y
  apt-get install -y containerd.io

  # containerd 설정파일 생성
  containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1

  # SystemdCgroup = true로 수정
  sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

  # containerd 재시작 및 부팅 시 활성화
  systemctl restart containerd
  systemctl enable containerd
"

# Step 9. Kubernetes apt-key 추가
run_step "STEP_09" "Kubernetes apt-key 추가" "
  if [ ! -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg ]; then
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/$KUBE_VERSION/deb/Release.key | gpg --dearmor | sudo tee /etc/apt/keyrings/kubernetes-apt-keyring.gpg > /dev/null
  fi
"

# Step 10. Kubernetes APT 저장소 추가
run_step "STEP_10" "Kubernetes APT 저장소 추가" "
  echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$KUBE_VERSION/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null
  apt-get update -y
"

# Step 11. kubeadm, kubelet, kubectl 설치
run_step "STEP_11" "kubeadm, kubelet, kubectl 설치" "
  apt-get install -y kubeadm kubelet kubectl
  apt-mark hold kubelet kubeadm kubectl
  systemctl enable kubelet
  systemctl start kubelet
"

# Step 12. Kubernetes Cluster init
# 필요한 변수 세팅
POD_NETWORK_CIDR="172.16.0.0/16"   # 필요에 따라 수정
API_SERVER_ADDRESS="{{ master_ip_addr }}" # 필요에 따라 실제 IP로 수정

run_step "STEP_12" "kubeadm init" "
  kubeadm init --pod-network-cidr=$POD_NETWORK_CIDR --apiserver-advertise-address=$API_SERVER_ADDRESS
"

# Step 13. kubeconfig 설정
run_step "STEP_13" "kubeconfig 설정" "
  mkdir -p \$HOME/.kube
  cp -i /etc/kubernetes/admin.conf \$HOME/.kube/config
  chown \$(id -u):\$(id -g) \$HOME/.kube/config
"

# Step 14. Calico 설치
run_step "STEP_14" "Calico($CALICO_VERSION) manifest 다운로드 및 적용" "
  curl -o /tmp/calico.yaml https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml
  kubectl apply -f /tmp/calico.yaml
"

echo "###############################################################################"
echo " 모든 단계가 성공적으로 완료되었습니다."
echo " 이제 kubectl get nodes 등을 통해 클러스터 상태를 확인할 수 있습니다."
echo "###############################################################################"
