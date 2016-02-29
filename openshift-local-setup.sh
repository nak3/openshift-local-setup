#!/bin/bash

#------------
ORIGINPATH=$(pwd)
DOCKER_LOG=/tmp/docker.log
ORIGIN_LOG=/tmp/origin.log
ORIGIN_HOST=127.0.0.1
ETCD_DIR=`mktemp -d /tmp/etcd-XXX`
VOLUME_DIR=`mktemp -d /tmp/volumes-XXX`
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

# inspired by kubernetes's hack/local-up-cluster.sh
function detect_binary {
    # Detect the OS name/arch so that we can find our binary
    case "$(uname -s)" in
      Darwin)
        host_os=darwin
        ;;
      Linux)
        host_os=linux
        ;;
      *)
        echo "Unsupported host OS.  Must be Linux or Mac OS X." >&2
        exit 1
        ;;
    esac

    case "$(uname -m)" in
      x86_64*)
        host_arch=amd64
        ;;
      i?86_64*)
        host_arch=amd64
        ;;
      amd64*)
        host_arch=amd64
        ;;
      arm*)
        host_arch=arm
        ;;
      i?86*)
        host_arch=x86
        ;;
      *)
        echo "Unsupported host arch. Must be x86_64, 386 or arm." >&2
        exit 1
        ;;
    esac

   OUT_PATH="${ORIGINPATH}/origin/_output/local/bin/${host_os}/${host_arch}"
}

detect_binary

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

if netstat -an |grep -E ":80 |:443 |:4001 |:7001 |:8443 " |grep LISTEN > /dev/null
then
  echo "Port(80,443,4001,7001 or 8443) is used by other process. Please stop it."
  exit 1
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
OS_OUTPUT_GOPATH=1 make build
OS_OUTPUT_GOPATH=1 bash ./hack/update-generated-completions.sh
set +e

# start
#---------------------------------#
echo "
Step 3 : Start docker and openshift standalone
"
#---------------------------------#
sudo -E docker -d --insecure-registry 172.30.0.0/16 > ${DOCKER_LOG} 2>&1 &
DOCKER_PID=$!

sudo -E ${OUT_PATH}/openshift start --latest-images=true --loglevel=5 --hostname=${ORIGIN_HOST} --volume-dir=${VOLUME_DIR} --etcd-dir=${ETCD_DIR} > ${ORIGIN_LOG} 2>&1 &
ORIGIN_PID=$!

# *NOTE* 
# Need to wait until namespace "openshift" create
while ! ${OUT_PATH}/oc --config=$(pwd)/openshift.local.config/master/admin.kubeconfig get namespace openshift > /dev/null 2>&1
do
  echo "Wait until openshift process start..."
  sleep 1
done

if ! pgrep -P ${DOCKER_PID} > /dev/null ; then
  echo "Failed to start docker. Please check $DOCKER_LOG" ; exit 1
fi
if ! pgrep -P ${ORIGIN_PID} > /dev/null ; then
  echo "Failed to start openshift. Please check $ORIGIN_LOG" ; exit 1
fi

# setup
#---------------------------------#
echo "
Step 4 : Setup
"
#---------------------------------#
#NOTE: Some environment can't validate alias command in script.
OC="${OUT_PATH}/oc --config=$(pwd)/openshift.local.config/master/admin.kubeconfig"
OADM="${OUT_PATH}/oadm --config=$(pwd)/openshift.local.config/master/admin.kubeconfig"
sudo chmod +r openshift.local.config/master/admin.kubeconfig
# This is for using new project by general users
sudo chmod o+w openshift.local.config/master/admin.kubeconfig
# To login by other users as well
su--latest-images=true do chmod o+w openshift.local.config/master/admin.kubeconfig

# imagestream
#---------------------------------#
echo "
Step 5 : Import CentOS imageStream
"
#---------------------------------#
if $OC get is -n openshift | grep openshift > /dev/null
then
  echo "ImageStream has already imported. Skipped"
else
  $OC create -f examples/image-streams/image-streams-centos7.json -n openshift
fi

# registry
#---------------------------------#
echo "
Step 6 : Deploy docker registry
"
#---------------------------------#
if $OC get pod | grep docker-registry-1 > /dev/null
then
  echo "Registry has already deployed. Skipped"
else
  sudo chmod +r openshift.local.config/master/openshift-registry.kubeconfig
  $OADM registry --latest-images=true --create --credentials=openshift.local.config/master/openshift-registry.kubeconfig
fi

# router
#---------------------------------#
echo "
Step 7 : Deploy router
"
#---------------------------------#
if $OC get pod | grep docker-router-1 > /dev/null
then
  echo "Router has already deployed. Skipped"
else
  echo '{"kind":"ServiceAccount","apiVersion":"v1","metadata":{"name":"router"}}' | $OC create -f -
  $OC get scc -t "{{range .items}}{{.metadata.name}}: n={{.allowHostNetwork}},p={{.allowHostPorts}}; {{end}}"
  sudo chmod a+r openshift.local.config/master/openshift-router.kubeconfig
  $OC get scc privileged -o yaml > /tmp/scc-priviledged.yaml
  echo "- system:serviceaccount:default:router" >> /tmp/scc-priviledged.yaml
  $OC update scc privileged -f /tmp/scc-priviledged.yaml
  $OADM router --latest-images=true --credentials="openshift.local.config/master/openshift-router.kubeconfig" --service-account=router
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

export PATH=\"${OUT_PATH}/:$PATH\"
export KUBECONFIG=\"$ORIGINPATH/origin/openshift.local.config/master/admin.kubeconfig\" 
export KUBECONFIG=\"$ORIGINPATH/origin/openshift.local.config/master/admin.kubeconfig\"
export KUBECONFIG=\"$ORIGINPATH/origin/openshift.local.config/master/admin.kubeconfig\"
source $ORIGINPATH/origin/contrib/completions/bash/oc
source $ORIGINPATH/origin/contrib/completions/bash/oadm
source $ORIGINPATH/origin/contrib/completions/bash/openshift
"

while true; do sleep 1; done
