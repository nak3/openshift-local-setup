#!/bin/bash

#------------
ORIGINPATH=$(pwd)
DOCKER_LOG=/tmp/docker.log
ORIGIN_LOG=/tmp/origin.log
ORIGIN_HOST=127.0.0.1
#ORIGIN_URL=https://github.com/openshift/origin.git
#ORIGIN_BRANCH=master
#------------

cleanup()
{
  echo "Cleaning up."
  [[ -n "${DOCKER_PID-}" ]] && DOCKER_PIDS=$(pgrep -P ${DOCKER_PID} ; ps -o pid= -p ${DOCKER_PID})
  [[ -n "${DOCKER_PIDS-}" ]] && sudo kill ${DOCKER_PIDS}

  [[ -n "${ORIGIN_PID-}" ]] && ORIGIN_PIDS=$(pgrep -P ${ORIGIN_PID} ; ps -o pid= -p ${ORIGIN_PID})
  [[ -n "${ORIGIN_PIDS-}" ]] && sudo kill ${ORIGIN_PIDS}
}

trap cleanup EXIT

echo "
--------------------------------
Prepare:
- git clone https://github.com/openshift/origin.git $ORIGINPATH/origin

Requirement:
- Install packages : golang(>1.4) docker(>1.6) git
- Open ports       : 80 443 4001 7001 8443
--------------------------------
"

# prepare
#---------------------------------#
echo "
Step 1 : Prepare
"
#---------------------------------#
if netstat -an |grep -E ":80|:443|:4001|:7001|:8443" |grep LISTEN > /dev/null
then
  echo "Port(80,443,4001,7001 or 8443) is used by other process. Please stop it."
  exit 1
fi

if pgrep openshift > /dev/null
then
  echo "\"openshift\" process is already running. Please stop it"
  exit 1;
fi

if pgrep docker > /dev/null
then
  echo "\"docker\" process is already running. Please stop it"
  exit 1;
fi

# build
#---------------------------------#
echo "
Step 2 : Build
"
#---------------------------------#
set -e
if [ ! -e $ORIGINPATH/origin ]; then
  echo "$ORIGINPATH/origin not found. Please run"
  echo ""
  echo "git clone https://github.com/openshift/origin.git $ORIGINPATH/origin"
  echo ""
  exit 1
fi
cd $ORIGINPATH/origin
make build
bash ./hack/update-generated-completions.sh
set +e

# start
#---------------------------------#
echo "
Step 3 : Start docker and openshift standalone
"
#---------------------------------#
sudo docker -d --insecure-registry 172.30.0.0/16 > ${DOCKER_LOG} 2>&1 &
DOCKER_PID=$!

sudo _output/local/go/bin/openshift start --loglevel=4 --hostname=${ORIGIN_HOST} > ${ORIGIN_LOG} 2>&1 &
ORIGIN_PID=$!

echo "Wait 10 sec until start the process completely..."
sleep 10

# setup
#---------------------------------#
echo "
Step 4 : Setup
"
#---------------------------------#
export PATH="$(pwd)/_output/local/go/bin/:$PATH"
alias oc="oc --config=$(pwd)/openshift.local.config/master/admin.kubeconfig" ;
alias oadm="oadm --config=$(pwd)/openshift.local.config/master/admin.kubeconfig"
sudo chmod +r openshift.local.config/master/admin.kubeconfig

# imagestream
#---------------------------------#
echo "
Step 5 : Import CentOS imageStream
"
#---------------------------------#
if oc get is -n openshift | grep openshift > /dev/null
then
  echo "ImageStream has already imported. Skipped"
else
  oc create -f examples/image-streams/image-streams-centos7.json -n openshift
fi

# registry
#---------------------------------#
echo "
Step 6 : Deploy docker registry
"
#---------------------------------#
if oc get pod | grep docker-registry-1 > /dev/null
then
  echo "Registry has already deployed. Skipped"
else
  sudo chmod +r openshift.local.config/master/openshift-registry.kubeconfig
  oadm registry --create --credentials=openshift.local.config/master/openshift-registry.kubeconfig --config=openshift.local.config/master/admin.kubeconfig
fi

# router
#---------------------------------#
echo "
Step 7 : Deployed router
"
#---------------------------------#
if oc get pod | grep docker-router-1 > /dev/null
then
  echo "Router has already deployed. Skipped"
else
  echo '{"kind":"ServiceAccount","apiVersion":"v1","metadata":{"name":"router"}}' | oc create -f -
  oc get scc -t "{{range .items}}{{.metadata.name}}: n={{.allowHostNetwork}},p={{.allowHostPorts}}; {{end}}"
  sudo chmod a+r openshift.local.config/master/openshift-router.kubeconfig
  oc get scc privileged -o yaml > /tmp/scc-priviledged.yaml
  echo "- system:serviceaccount:default:router" >> /tmp/scc-priviledged.yaml
  oc update scc privileged -f /tmp/scc-priviledged.yaml
  oadm router --credentials="openshift.local.config/master/openshift-router.kubeconfig" --service-account=router
fi

# finish
#---------------------------------#
echo "
Step 8 : Setup finished you can use it with
-----------------------------------
Logs:
  ${DOCKER_LOG}
  ${ORIGIN_LOG}

Next steps: Open new terminal and setup it.

export PATH=\"$ORIGINPATH/origin/_output/local/go/bin/:$PATH\"
alias oc=\"oc --config=$ORIGINPATH/origin/openshift.local.config/master/admin.kubeconfig\" 
alias oadm=\"oadm --config=$ORIGINPATH/origin/openshift.local.config/master/admin.kubeconfig\"
source $ORIGINPATH/origin/rel-eng/completions/bash/oc
"

while true; do sleep 1; done