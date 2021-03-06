#!/usr/bin/env bash

sudo mkdir -p /etc/cni/net.d /etc/kubernetes /etc/kubernetes/ssl /var/log/kube

if [ ! -f /etc/kubernetes/environment.sh ] ; then
    wget http://assets.example.com/k8s/environment.sh -O /etc/kubernetes/environment.sh
fi

source /etc/kubernetes/environment.sh

if [ ! -f /etc/kubernetes/token.csv ] ; then
    wget http://assets.example.com/k8s/ca.tar.gz -O /tmp/ca.tar.gz
    sudo tar -zxvf /tmp/ca.tar.gz -C /etc/kubernetes/
    rm -rf /tmp/ca.tar.gz
fi

id kube >& /dev/null
if [ $? -ne 0 ]
then
   groupadd kube
   useradd -g kube kube -s /sbin/nologin
fi

SERVER_IP=`/sbin/ifconfig  | grep 'inet'| grep -v '127.0.0.1' |head -n1 |tr -s ' '|cut -d ' ' -f3 | cut -d: -f2`
HOSTNAME=`hostname -f`

if [ ! -f /usr/bin/kube-apiserver ] ; then
    wget http://assets.example.com/k8s/kube-apiserver -O /usr/bin/kube-apiserver
    chmod a+x /usr/bin/kube-apiserver
fi

if [ ! -f /usr/bin/kube-controller-manager ] ; then
    wget http://assets.example.com/k8s/kube-controller-manager -O /usr/bin/kube-controller-manager
    chmod a+x /usr/bin/kube-controller-manager
fi

if [ ! -f /usr/bin/kube-scheduler ] ; then
    wget http://assets.example.com/k8s/kube-scheduler -O /usr/bin/kube-scheduler
    chmod a+x /usr/bin/kube-scheduler
fi


if [ ! -f /usr/sbin/pipework ];then
    wget http://assets.example.com/k8s/pipework -O /usr/sbin/pipework
    chmod a+x /usr/sbin/pipework
fi

echo -ne '[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes
After=network.target
After=etcd.service

[Service]
EnvironmentFile=-/etc/kubernetes/config
EnvironmentFile=-/etc/kubernetes/apiserver
User=kube
ExecStart=/usr/bin/kube-apiserver \
    $KUBE_LOGTOSTDERR \
    $KUBE_LOG_LEVEL \
    $KUBE_ETCD_SERVERS \
    $KUBE_API_ADDRESS \
    $KUBE_API_PORT \
    $KUBE_ALLOW_PRIV \
    $KUBE_SERVICE_ADDRESSES \
    $KUBE_ADMISSION_CONTROL \
    $KUBE_API_ARGS \
    $KUBE_API_METRIC_SERVER_ARGS
Restart=on-failure
Type=notify
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
'>/usr/lib/systemd/system/kube-apiserver.service


echo -ne '
KUBE_LOGTOSTDERR="--logtostderr=false --log-dir=/var/log/kube"
KUBE_LOG_LEVEL="--v=4"
KUBE_ALLOW_PRIV="--allow-privileged=true"
KUBE_MASTER="--master='$KUBE_APISERVER'"
'>/etc/kubernetes/config

echo -ne '
KUBE_API_PORT=" --insecure-port=8080 --secure-port=443"
KUBE_API_ADDRESS=" --advertise-address='$SERVER_IP' --bind-address='$SERVER_IP' --insecure-bind-address='$SERVER_IP'"
KUBE_ETCD_SERVERS=" --etcd-servers='$ETCD_ENDPOINTS' --etcd-servers-overrides="/events#'$EVENT_ETCD_ENDPOINTS'""
KUBE_SERVICE_ADDRESSES=" --service-cluster-ip-range='$SERVICE_CIDR' --service-node-port-range=8400-32767 --tls-cert-file=/etc/kubernetes/ssl/kubernetes.pem --tls-private-key-file=/etc/kubernetes/ssl/kubernetes-key.pem --client-ca-file=/etc/kubernetes/ssl/ca.pem --service-account-key-file=/etc/kubernetes/ssl/ca-key.pem --token-auth-file=/etc/kubernetes/token.csv"
KUBE_ADMISSION_CONTROL=" --admission-control=NamespaceLifecycle,LimitRanger,ServiceAccount,ResourceQuota,DefaultStorageClass,Initializers,PersistentVolumeClaimResize,PodNodeSelector,PodPreset,PodTolerationRestriction,Priority,DefaultTolerationSeconds,NamespaceExists,NodeRestriction,DenyEscalatingExec,PersistentVolumeLabel"
KUBE_API_ARGS=" --max-requests-inflight=3000 --max-mutating-requests-inflight=1000 --runtime-config=api/all=true --authorization-mode=RBAC --max-requests-inflight=10000 --audit-log-maxage=30 --audit-log-maxbackup=3 --audit-log-maxsize=100 --audit-log-path=/var/log/audit.log --feature-gates=AllAlpha=true "
KUBE_API_METRIC_SERVER_ARGS = "--requestheader-client-ca-file=/etc/kubernetes/ssl/proxy-ca.crt --proxy-client-cert-file=/etc/kubernetes/ssl/proxy.crt --proxy-client-key-file=/etc/kubernetes/ssl/proxy.key --requestheader-allowed-names=aggregator --requestheader-extra-headers-prefix=X-Remote-Extra- --requestheader-group-headers=X-Remote-Group --requestheader-username-headers=X-Remote-User"
'>/etc/kubernetes/apiserver

echo -ne '[Manager]
DefaultCPUAccounting=yes
DefaultMemoryAccounting=yes
'>/etc/systemd/system.conf.d/kubernetes-accounting.conf

echo -ne 'd /var/run/kubernetes 0755 kube kube -
'>/usr/lib/tmpfiles.d/kubernetes.conf


echo -ne '
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
EnvironmentFile=-/etc/kubernetes/config
EnvironmentFile=-/etc/kubernetes/controller-manager
User=kube
ExecStart=/usr/bin/kube-controller-manager \
    $KUBE_LOGTOSTDERR \
    $KUBE_LOG_LEVEL \
    $KUBE_MASTER \
    $KUBE_CONTROLLER_MANAGER_ARGS
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
'>/usr/lib/systemd/system/kube-controller-manager.service

echo -ne '
KUBE_CONTROLLER_MANAGER_ARGS=" --kube-api-qps=100 --kube-api-burst=100 --feature-gates=AllAlpha=true --address='$SERVER_IP' --service-cluster-ip-range='$SERVICE_CIDR' --cluster-name=kubernetes --controllers=*,bootstrapsigner,tokencleaner --cluster-signing-cert-file=/etc/kubernetes/ssl/ca.pem --cluster-signing-key-file=/etc/kubernetes/ssl/ca-key.pem  --service-account-private-key-file=/etc/kubernetes/ssl/ca-key.pem --root-ca-file=/etc/kubernetes/ssl/ca.pem --leader-elect=true --cloud-config= --cloud-provider="
'>/etc/kubernetes/controller-manager



echo '
[Unit]
Description=Kubernetes Scheduler Plugin
Documentation=https://github.com/kubernetes/kubernetes

[Service]
EnvironmentFile=-/etc/kubernetes/config
EnvironmentFile=-/etc/kubernetes/scheduler
User=kube
ExecStart=/usr/bin/kube-scheduler \
    $KUBE_LOGTOSTDERR \
    $KUBE_LOG_LEVEL \
    $KUBE_MASTER \
    $KUBE_SCHEDULER_ARGS
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
'>/usr/lib/systemd/system/kube-scheduler.service

echo -ne '
KUBE_SCHEDULER_ARGS=" --kube-api-qps=100 --address='$SERVER_IP' --feature-gates=AllAlpha=true"
'>/etc/kubernetes/scheduler

chown -R kube:kube /etc/kubernetes /var/log/kube

systemctl daemon-reload
systemctl enable kube-apiserver
systemctl start kube-apiserver
systemctl status kube-apiserver
systemctl enable kube-controller-manager
systemctl start kube-controller-manager
systemctl status kube-controller-manager
systemctl enable kube-scheduler
systemctl start kube-scheduler
systemctl status kube-scheduler
