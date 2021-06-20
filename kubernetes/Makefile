.PHONY: build clean

build:
	kubectl -n kafka apply -f ./namespace.json
	kubectl -n kafka apply -f ./zookeeper/zookeeper-storage.yaml,./zookeeper/zookeeper-service.yaml,./zookeeper/zookeeper.yaml
	kubectl -n kafka apply -f ./kafka/kafka-storage.yaml,./kafka/kafka-service.yaml,./kafka/kafka.yaml

clean:
	-kubectl -n kafka delete -f ./kafka/kafka-storage.yaml,./kafka/kafka-service.yaml,./kafka/kafka.yaml
	-kubectl -n kafka delete -f ./zookeeper/zookeeper-storage.yaml,./zookeeper/zookeeper-service.yaml,./zookeeper/zookeeper.yaml

default: build
