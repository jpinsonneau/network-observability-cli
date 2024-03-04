function setup {
  echo "Setting up... "

  stty -F /dev/tty cbreak min 1
  stty -F /dev/tty -echo
  setterm -linewrap off

  if ! output=$(oc whoami 2>&1); then
    printf 'You must be connected using oc login command first\n' >&2
    exit 1
  fi

  filename=""
  mkdir -p ${BASH_SOURCE%/*}/current

  if [ $1 = "flows" ]; then
    filename="flow-capture"
    sed "s/{{FLOW_FILTER_VALUE}}/$2/gi" ${BASH_SOURCE%/*}/flow-capture.yml > ${BASH_SOURCE%/*}/current/agent.yml
  elif [ $1 = "packets" ]; then
    filename="packet-capture"
    sed "s/{{PCA_FILTER_VALUE}}/$2/gi" ${BASH_SOURCE%/*}/packet-capture.yml > ${BASH_SOURCE%/*}/current/agent.yml
  else
    echo "invalid setup argument"
    return
  fi

  echo "creating netobserv-cli namespace"
  oc apply -f ${BASH_SOURCE%/*}/namespace.yml

  echo "creating service account"
  oc apply -f ${BASH_SOURCE%/*}/service-account.yml

  echo "creating $filename agents"
  oc apply -f ${BASH_SOURCE%/*}/current/agent.yml
  oc rollout status daemonset netobserv-cli -n netobserv-cli --timeout 60s
  
  echo "creating $filename collector service"
  oc apply -f ${BASH_SOURCE%/*}/collector-service.yml
}

function cleanup {
  stty -F /dev/tty echo
  setterm -linewrap on

  if output=$(oc whoami 2>&1); then
    printf "\nCleaning up... "
    oc delete namespace netobserv-cli
  else
    echo "Cleanup namespace skipped"
    return
  fi
}
