# kubeadm.sh
This is Kubeadm install .sh script file Repo

# K8s 설치 가이드 (Ubuntu 24.04 LTS, kubeadm 1.30)

## 1. VM 최소 요구사항
- **CPU**: 2core 이상  
- **Memory**: 1736MB 이상  

> 위 요구사항을 만족하지 않으면 설치 및 동작 과정에서 문제가 발생할 수 있습니다.

---

## 2. 기본 환경 정보
- **OS**: Ubuntu 24.04 LTS  
- **kubeadm 버전**: 1.31
- **kubectl 관련 권한**: root 사용자 권한이 필요  

---

## 3. 설치 전 사전 작업

### 3.1 root 비밀번호 초기화 및 전환
1. VM(Ubuntu) 생성 후 터미널(콘솔)에 접근합니다.
2. 아래 명령어를 통해 **root 계정 비밀번호를 설정**합니다.
   ```bash
   sudo passwd root # root 비밀번호 변경
   su root # root 사용자로 전환

### 3.2 영구적으로 Swap Memory Mode 끄기
    '''bash
    sudo vi /etc/systemd/system/swapoff.service # Daemon service 추가
    # 아래 내용 작성 및 저장 
    [Unit]
    Description=Turn off swap
    After=network.target

    [Service]
    Type=oneshot
    ExecStart=/sbin/swapoff -a

    [Install]
    WantedBy=multi-user.target
    
    # :wq 저장 && 종료
    sudo systemctl enable swapoff.service # swapoff 서비스 활성화
    sudo systemctl start swapoff.service # swapoff 서비스 시작

### 4. 쉘 스크립트 수행
    1. Node가 Master인 경우 Master 전용 쉘 스크립트 내용 중 변수 API_SERVER_ADDR="" 값 추가
    '''bash
    vi setup_k8s_for_master.sh # 내용 복붙 :wq 저장 & 종료
    
    chmod +x setup_k8s_for_master.sh # sh 실행 권한 부여

    ./setup_k8s_for_master.sh # sh 실행

    vi setup_k8s_for_worker.sh # 내용 복붙 :wq 저장 & 종료
    
    chmod +x setup_k8s_for_worker.sh # sh 실행 권한 부여

    ./setup_k8s_for_worker.sh # sh 실행