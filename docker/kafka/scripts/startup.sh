#!/bin/bash

if [[ -z "${_KAFKA_ZOOKEEPER_CONNECT}" ]]; then
  echo -e "\033[0;31mError: ZooKeeper connection string empty. Please configure _KAFKA_ZOOKEEPER_CONNECT environment variable.\033[0m"
  exit 1
fi

function update_configuration() {
  if grep -E -q "^#?[ \t]*$1=" "$3"; then
    sed -r -i "s@^#?[ \t]*$1=.*@$1=$2@g" "$3"
  else
    echo "$1=$2" >> "$3"
  fi
}

if [[ "${_JVM_DISABLE_DNS_CACHE:true}" == "true" ]]; then
  # Disable infinite DNS cache, because IP addresses may change in cloud environments.
  update_configuration "networkaddress.cache.ttl" 30 "${JAVA_HOME}/lib/security/java.security"
fi

# Broker ID.
if [[ -z "${_KAFKA_BROKER_ID}" ]]; then
  if [[ -n "${_COMMAND_KAFKA_BROKER_ID}" ]]; then
    export _KAFKA_BROKER_ID=$(eval "${_COMMAND_KAFKA_BROKER_ID}")
  else
    export _KAFKA_BROKER_ID=-1
  fi
fi

# Broker rack.
if [[ -z "${_KAFKA_BROKER_RACK}" && -n "${_COMMAND_KAFKA_BROKER_RACK}" ]]; then
  export _KAFKA_BROKER_RACK=$(eval "${_COMMAND_KAFKA_BROKER_RACK}")
fi

# Run only during first run of the container.
# Volume will not store any configuration at this time.
if [[ "${_RECREATE_CONFIGURATION:-true}" == "true" || ! -f /volume/kafka/config/kafka.properties ]]; then
  update_configuration "broker.id" ${_KAFKA_BROKER_ID} "${KAFKA_HOME}/config/kafka.properties"

  if [[ -n "${_KAFKA_BROKER_RACK}" ]]; then
    update_configuration "broker.rack" ${_KAFKA_BROKER_RACK} "${KAFKA_HOME}/config/kafka.properties"
  fi

  if [[ -n "${_COMMAND_HOSTNAME}" ]]; then
    export _PUBLIC_HOSTNAME=$(eval "${_COMMAND_HOSTNAME}")
  fi

  if [[ -n "${_COMMAND_PORT}" ]]; then
    export _PUBLIC_PORT=$(eval "${_COMMAND_PORT}")
  fi

  exclusions="|_KAFKA_BROKER_ID|_KAFKA_BROKER_RACK|_KAFKA_HEAP_OPTS|"
  # Update broker configuration.
  for e in `env | grep -E "^_KAFKA_"`;
  do
    key=`echo "$e" | cut -d'=' -f1`
    value=`echo "$e" | cut -d'=' -f2`
    if [[ "$exclusions" == *"|$key|"* ]]; then
      continue
    fi
    # Replace '%HOSTNAME%' placeholder with discovered public IP address or host.
    value=${value//%HOSTNAME%/${_PUBLIC_HOSTNAME}}
    # Replace '%PORT%' placeholder with discovered public TCP port.
    value=${value//%PORT%/${_PUBLIC_PORT}}
    update_configuration `echo ${key:1} | cut -d'_' -f2- | tr A-Z_ a-z.` $value "${KAFKA_HOME}/config/kafka.properties"
  done
  # Update Log4J configuration.
  for e in `env | grep -E "^_LOG4J_"`;
  do
    key=`echo "$e" | cut -d'=' -f1`
    value=`echo "$e" | cut -d'=' -f2`
    update_configuration `echo ${key:1} | cut -d'_' -f2- | tr _ .` $value "${KAFKA_HOME}/config/log4j.properties"
  done

  cp ${KAFKA_HOME}/config/kafka.properties ${KAFKA_HOME}/config/log4j.properties /volume/kafka/config/
fi

if [[ -n "${_KAFKA_HEAP_OPTS}" ]]; then
  export KAFKA_HEAP_OPTS="${_KAFKA_HEAP_OPTS}"
fi

export KAFKA_LOG4J_OPTS="-Dlog4j.configuration=file:/volume/kafka/config/log4j.properties"
export EXTRA_ARGS="-name kafkaServer -Dcom.sun.management.jmxremote.port=${_KAFKA_JMX_PORT} -Dcom.sun.management.jmxremote.rmi.port=${_KAFKA_JMX_PORT} -Djava.rmi.server.hostname=${_KAFKA_JMX_HOST}" # Disables GC logging and JMX.

# Enable JMX for health-check command.
export JMX_PORT=${_KAFKA_JMX_PORT}

trap 'kill -TERM $kafka_pid' SIGINT SIGTERM

# Simple execution is sufficient, but Java process will report exit code 143 (128 + 15)
# upon clean shutdown (SIGTERM triggered by Docker container).
# exec "${KAFKA_HOME}/bin/kafka-server-start.sh" "${KAFKA_HOME}/config/kafka.properties"
${KAFKA_HOME}/bin/kafka-server-start.sh /volume/kafka/config/kafka.properties &

kafka_pid=$!

if [[ "${_AUTO_PARTITION_REASSIGNMENT}" == "true" ]]; then
  java -Xmx128M -cp "${KAFKA_HOME}/libs/*" kafka.admin.AutoPartitionReassignCommand -zookeeper ${_KAFKA_ZOOKEEPER_CONNECT} -broker ${_KAFKA_BROKER_ID} &
  extension_pid=$!
fi

wait $kafka_pid
trap - SIGTERM SIGINT
wait $kafka_pid
exit_code=$?

if [[ "${_AUTO_PARTITION_REASSIGNMENT}" == "true" ]]; then
  kill -TERM $extension_pid
  wait $extension_pid
fi

if [[ $exit_code -eq 143 || $exit_code -eq 130 ]]; then
  # Expected 143 (128 + 15, SIGTERM) or 130 (128 + 2, SIGINT) exit status code,
  # as they represent SIGINT or SIGTERM respectively.
  exit 0
fi

exit $((exit_code - 128))
