FROM centos:8 

ARG rocket_version=2.7.0-1
ARG rocket_major_version=2.7

ENV KAFKA_HOME=/opt/tibco/akd/core/${rocket_major_version}
ENV PATH=${PATH}:${KAFKA_HOME}/bin

COPY bin/TIB_msg-akd-core*${rocket_version}_linux_x86_64.rpm /tmp/
COPY config/* /tmp/
COPY scripts/* /tmp/

RUN  yum install -q -y /tmp/TIB_msg-akd-core*${rocket_version}_linux_x86_64.rpm \
 && yum -q -y install java \
 && yum -q -y update \
 && chmod +x /tmp/*.sh \
 && mv /tmp/*.sh ${KAFKA_HOME}/bin/ \
 && mv /tmp/*.properties ${KAFKA_HOME}/config/ \
 && rm /tmp/*rpm 

EXPOSE 9092

VOLUME ["/volume/kafka/data", "/volume/kafka/config"]

CMD ["startup.sh"]
