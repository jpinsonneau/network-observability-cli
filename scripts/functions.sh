function loadYAMLs() {
  namespaceYAML='
    namespaceYAMLContent
  '
  if [ -f ./res/namespace.yml ]; then
    namespaceYAML="`cat ./res/namespace.yml`"
  fi

  saYAML='
    saYAMLContent
  '
  if [ -f ./res/service-account.yml ]; then
    saYAML="`cat ./res/service-account.yml`"
  fi

  flowAgentYAML='
    flowAgentYAMLContent
  '
  if [ -f ./res/flow-capture.yml ]; then
    flowAgentYAML="`cat ./res/flow-capture.yml`"
  fi

  packetAgentYAML='
    packetAgentYAMLContent
  '
  if [ -f ./res/packet-capture.yml ]; then
    packetAgentYAML="`cat ./res/packet-capture.yml`"
  fi

  collectorServiceYAML='
    collectorServiceYAMLContent
  '
  if [ -f ./res/collector-service.yml ]; then
    collectorServiceYAML="`cat ./res/collector-service.yml`"
  fi
}

function setup {
  echo "Setting up... "

  # check for mandatory arguments
  if ! [[ $1 =~ flows|packets ]]; then
    echo "invalid setup argument"
    return
  fi

  # check if cluster is reachable
  if ! output=$(oc whoami 2>&1); then
    printf 'You must be connected using oc login command first\n' >&2
    exit 1
  fi

  # load yaml files
  loadYAMLs

  # apply yamls
  echo "creating netobserv-cli namespace"
  echo "$namespaceYAML" | oc apply -f -

  echo "creating service account"
  echo "$saYAML" | oc apply -f -

  if [ $1 = "flows" ]; then
    echo "creating flow-capture agents"
    echo "${flowAgentYAML/"{{FLOW_FILTER_VALUE}}"/$2}" | oc apply -f -
    oc rollout status daemonset netobserv-cli -n netobserv-cli --timeout 60s

    echo "creating collector service"
    echo "$collectorServiceYAML" | oc apply -f -
  elif [ $1 = "packets" ]; then
    echo "creating packet-capture agents"
    echo "${packetAgentYAML/"{{PCA_FILTER_VALUE}}"/$2}" | oc apply -f -
    oc rollout status daemonset netobserv-cli -n netobserv-cli --timeout 60s

    # TODO: remove that part once pcap moved to gRPC
    echo "forwarding agents ports"
    pods=$(oc get pods -n netobserv-cli -l app=netobserv-cli -o name)
    port=9900
    nodes=""
    ports=""
    for pod in $pods
    do 
      echo "forwarding $pod:9999 to local port $port"
      pkill --oldest --full "$port:9999"
      oc port-forward $pod $port:9999 -n netobserv-cli & # run in background
      node=$(oc get $pod -n netobserv-cli -o jsonpath='{.spec.nodeName}')
      if [ -z "$ports" ]
      then
        nodes="$node"
        ports="$port"
      else
        nodes="$nodes,$node"
        ports="$ports,$port"
      fi
      port=$((port+1))
    done

    # TODO: find a better way to ensure port forward are running
    sleep 2
  fi
}

function cleanup {
  # TODO: remove this condition after packet capture gRPC migration
  if [ "$resetTerminal" = "true" ]; then
    echo "Resetting terminal params..."
    stty -F /dev/tty echo
    setterm -linewrap on
  fi

  if output=$(oc whoami 2>&1); then
    if [ "$copyOutput" = "true" ]; then
      echo "Copying collector output files..."
      mkdir -p ./output
      oc cp -n netobserv-cli collector:output ./output
    fi
    printf "\nCleaning up... "
    oc delete namespace netobserv-cli
  else
    echo "Cleanup namespace skipped"
    return
  fi
}
