FROM debian:jessie

ENV SPLUNK_PRODUCT splunk
ENV SPLUNK_VERSION 7.1.2
ENV SPLUNK_BUILD a0c72a66db66
ENV SPLUNK_FILENAME splunk-${SPLUNK_VERSION}-${SPLUNK_BUILD}-Linux-x86_64.tgz


ENV SPLUNK_HOME /opt/splunk
ENV SPLUNK_GROUP splunk
ENV SPLUNK_USER splunk
ENV SPLUNK_BACKUP_DEFAULT_ETC /var/opt/splunk
ARG DEBIAN_FRONTEND=noninteractive

# add splunk:splunk user
RUN groupadd -r ${SPLUNK_GROUP} \
    && useradd -r -m -g ${SPLUNK_GROUP} ${SPLUNK_USER}

# make the "en_US.UTF-8" locale so splunk will be utf-8 enabled by default
RUN apt-get update  && apt-get install -y --no-install-recommends apt-utils && apt-get install -y locales && rm -rf /var/lib/apt/lists/* \
	&& localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
ENV LANG en_US.utf8

# pdfgen dependency
RUN apt-get update && apt-get install -y libgssapi-krb5-2 && rm -rf /var/lib/apt/lists/*

# Download official Splunk release, verify checksum and unzip in /opt/splunk
# Also backup etc folder, so it will be later copied to the linked volume
RUN apt-get update && apt-get install -y wget curl sudo \
    && mkdir -p ${SPLUNK_HOME} \
    && wget -qO /tmp/${SPLUNK_FILENAME} https://download.splunk.com/products/${SPLUNK_PRODUCT}/releases/${SPLUNK_VERSION}/linux/${SPLUNK_FILENAME} \
    && wget -qO /tmp/${SPLUNK_FILENAME}.md5 https://download.splunk.com/products/${SPLUNK_PRODUCT}/releases/${SPLUNK_VERSION}/linux/${SPLUNK_FILENAME}.md5 \
    && (cd /tmp && md5sum -c ${SPLUNK_FILENAME}.md5) \
    && tar xzf /tmp/${SPLUNK_FILENAME} --strip 1 -C ${SPLUNK_HOME} \
    && rm /tmp/${SPLUNK_FILENAME} \
    && rm /tmp/${SPLUNK_FILENAME}.md5 \
    && apt-get purge -y --auto-remove wget \
    && mkdir -p /var/opt/splunk \
    && cp -R ${SPLUNK_HOME}/etc ${SPLUNK_BACKUP_DEFAULT_ETC} \
    && rm -fR ${SPLUNK_HOME}/etc \
    && chown -R ${SPLUNK_USER}:${SPLUNK_GROUP} ${SPLUNK_HOME} \
    && chown -R ${SPLUNK_USER}:${SPLUNK_GROUP} ${SPLUNK_BACKUP_DEFAULT_ETC} \
    && rm -rf /var/lib/apt/lists/*

# Splunk DB Connect uses JDBC and requires JRE 8. Open JDK would work but the
# Splunk container is based on a version of Debian that only has OpenJava 7
RUN mkdir -p /usr/java \
    && cd /usr/java \
    && curl \
        -H 'Cookie: oraclelicense=accept-securebackup-cookie;' \
        -LO http://download.oracle.com/otn-pub/java/jdk/8u181-b13/96a7b8442fe848ef90c96a2fad6ed6d1/jre-8u181-linux-x64.tar.gz \
    && tar -zxf jre-8u181-linux-x64.tar.gz \
    && ln -s jre1.8.0_181 latest
ENV JAVA_HOME=/usr/java/latest

# Install Splunk DB Connect. Pre-downloaded from the Splunk app store because
# downloading apps requires being logged in
COPY splunk-db-connect_313.tgz /opt/splunk/etc/apps/
RUN cd /opt/splunk/etc/apps/ && tar -zxvf splunk-db-connect_313.tgz && rm -f splunk-db-connect_313.tgz

# Install Snowflake JDBC driver
RUN cd /opt/splunk/etc/apps/splunk_app_db_connect/drivers/ \
    && curl -LO https://repo1.maven.org/maven2/net/snowflake/snowflake-jdbc/3.6.10/snowflake-jdbc-3.6.10.jar

# Add Snowflake JDBC to the list of supported Splunk DB Connect connectors
RUN echo '[snowflake]' >> /opt/splunk/etc/apps/splunk_app_db_connect/default/db_connection_types.conf \
    && echo 'displayName = Snowflake' >> /opt/splunk/etc/apps/splunk_app_db_connect/default/db_connection_types.conf \
    && echo 'serviceClass = com.splunk.dbx2.DefaultDBX2JDBC' >> /opt/splunk/etc/apps/splunk_app_db_connect/default/db_connection_types.conf \
    && echo 'jdbcUrlFormat = jdbc:snowflake://<host>/<database>' >> /opt/splunk/etc/apps/splunk_app_db_connect/default/db_connection_types.conf \
    && echo 'jdbcUrlSSLFormat = jdbc:snowflake://<host>/<database>' >> /opt/splunk/etc/apps/splunk_app_db_connect/default/db_connection_types.conf \
    && echo 'jdbcDriverClass = net.snowflake.client.jdbc.SnowflakeDriver' >> /opt/splunk/etc/apps/splunk_app_db_connect/default/db_connection_types.conf \
    && echo -n ' -Ddw.server.applicationConnectors[0].port=9998' > /opt/splunk/etc/apps/splunk_app_db_connect/jars/server.vmopts

COPY entrypoint.sh /sbin/entrypoint.sh
RUN chmod +x /sbin/entrypoint.sh

# Copy new license
#COPY ./Splunk_Enterprise_Q3FY17.lic /var/opt/splunk/etc/licenses/download-trial/Splunk_Enterprise_Q3FY17.lic

# Ports Splunk Web, Splunk Daemon, KVStore, Splunk Indexing Port, Network Input, HTTP Event Collector
EXPOSE 8000/tcp 8089/tcp 8191/tcp 9997/tcp 1514 8088/tcp

WORKDIR /opt/splunk

# Configurations folder, var folder for everything (indexes, logs, kvstore)
VOLUME [ "/opt/splunk/etc", "/opt/splunk/var" ]

ENTRYPOINT ["/sbin/entrypoint.sh"]
CMD ["start-service"]
