#!/bin/bash

if [[ -z "${_ZOOKEEPER_ID}" && -z "${_COMMAND_ZOOKEEPER_ID}" ]]; then
  echo -e "\033[0;31mError: Unknown ZooKeeper ID. Please configure _ZOOKEEPER_ID or _COMMAND_ZOOKEEPER_ID environment variable.\033[0m"
  exit 1
fi

if [[ -n "${_COMMAND_ZOOKEEPER_ID}" ]]; then
  export ZK_ID=$(eval "${_COMMAND_ZOOKEEPER_ID}")
  export _ZOOKEEPER_ID=$((ZK_ID+1))
fi

if [[ -z "${_ZOOKEEPER_SERVERS}" ]]; then
  echo -e "\033[0;31mError: Unknown ZooKeeper server list. Please configure _ZOOKEEPER_SERVERS environment variable.\033[0m"
  exit 1
fi

function update_configuration() {
  if grep -E -q "^#?[ \t]*$1=" "$3"; then
    sed -r -i "s@^#?[ \t]*$1=.*@$1=$2@g" "$3"
  else
    echo "$1=$2" >> "$3"
  fi
}

# Persist ZooKeeper ID.
echo ${_ZOOKEEPER_ID} > /volume/zookeeper/data/myid

# Run only during first run of the container.
# Volume will not store any configuration at this time.
if [[ "${_RECREATE_CONFIGURATION:-true}" == "true" || ! -f /volume/zookeeper/config/zookeeper.properties ]]; then
  # Remove any server declaration from ZK configuration.
  grep -v -E '^server.' ${ZOOKEEPER_HOME}/config/zookeeper.properties > ${ZOOKEEPER_HOME}/config/zookeeper.properties.bak
  mv ${ZOOKEEPER_HOME}/config/zookeeper.properties.bak ${ZOOKEEPER_HOME}/config/zookeeper.properties

  # Append server list based on environment variable.
  index=1
  IFS=","; for server in ${_ZOOKEEPER_SERVERS}; do
    echo "server.${index}=${server}" >> ${ZOOKEEPER_HOME}/config/zookeeper.properties
    index=$((index + 1))
  done

  sed -i "s/server\.${_ZOOKEEPER_ID}\=[a-z0-9.-]*/server.${_ZOOKEEPER_ID}=0.0.0.0/" ${ZOOKEEPER_HOME}/config/zookeeper.properties

  # Update ZooKeeper configuration.
  exclusions="|_ZOOKEEPER_ID|_ZOOKEEPER_SERVERS|_ZOOKEEPER_HEAP_OPTS|"
  IFS=$'\n'; for e in `env | grep -E "^_ZOOKEEPER_"`;
  do
    key=`echo "$e" | cut -d'=' -f1`
    value=`echo "$e" | cut -d'=' -f2`
    if [[ "$exclusions" == *"|$key|"* ]]; then
      continue
    fi
    update_configuration `echo ${key:1} | cut -d'_' -f2- | tr _ .` $value "${ZOOKEEPER_HOME}/config/zookeeper.properties"
  done
  # Update Log4J configuration.
  for e in `env | grep -E "^_LOG4J_"`;
  do
    key=`echo "$e" | cut -d'=' -f1`
    value=`echo "$e" | cut -d'=' -f2`
    update_configuration `echo ${key:1} | cut -d'_' -f2- | tr _ .` $value "${ZOOKEEPER_HOME}/config/log4j.properties"
  done

  cp ${ZOOKEEPER_HOME}/config/zookeeper.properties /volume/zookeeper/config/
  cp ${ZOOKEEPER_HOME}/config/log4j.properties /volume/zookeeper/config/
fi

if [[ -n "${_ZOOKEEPER_HEAP_OPTS}" ]]; then
  export KAFKA_HEAP_OPTS="${_ZOOKEEPER_HEAP_OPTS}"
fi

export KAFKA_LOG4J_OPTS="-Dlog4j.configuration=file:/volume/zookeeper/config/log4j.properties"
export EXTRA_ARGS="-name zookeeper -Dcom.sun.management.jmxremote.port=${_ZOOKEEPER_JMX_PORT} -Dcom.sun.management.jmxremote.rmi.port=${_ZOOKEEPER_JMX_PORT} -Djava.rmi.server.hostname=${_ZOOKEEPER_JMX_HOST}" # Disables GC logging and sets up JMX.

trap 'kill -TERM $pid' SIGINT SIGTERM

# Simple execution is sufficient, but Java process will report exit code 143 (128 + 15)
# upon clean shutdown (SIGTERM triggered by Docker container).
# exec "${ZOOKEEPER_HOME}/bin/zookeeper-server-start.sh" "${ZOOKEEPER_HOME}/config/zookeeper.properties"
${ZOOKEEPER_HOME}/bin/zookeeper-server-start.sh /volume/zookeeper/config/zookeeper.properties &

pid=$!
wait $pid
trap - SIGTERM SIGINT
wait $pid
exit_code=$?

if [[ $exit_code -eq 143 || $exit_code -eq 130 ]]; then
  # Expected 143 (128 + 15, SIGTERM) or 130 (128 + 2, SIGINT) exit status code,
  # as they represent SIGINT or SIGTERM respectively.
  exit 0
fi

exit $((exit_code - 128))
