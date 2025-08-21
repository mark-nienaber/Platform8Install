#!/bin/bash
#CATALINA_OPTS="-Djavax.net.ssl.trustStore=/home/fradmin/am/security/keystores/truststore -Djavax.net.ssl.trustStorePassword=changeit -Djavax.net.ssl.trustStoreType=jks"

CATALINA_OPTS="\
  -Dcom.sun.identity.sm.sms_object_filebased_enabled=true \
  -Dam.server.fqdn=am.example.com \
  -Dam.stores.user.servers=idrepo1.example.com:2636 \
  -Dam.stores.user.username=uid=am-identity-bind-account,ou=admins,ou=identities \
  -Dam.stores.user.password=password \
  -Dam.test.mode=true \
  -Dam.stores.application.servers=amconfig1.example.com:3636 \
  -Dam.stores.application.password=password \
  -Djavax.net.ssl.trustStore=/opt/ping/am/security/keystores/truststore \
  -Djavax.net.ssl.trustStorePassword=changeit \
  -Djavax.net.ssl.trustStoreType=jks \
  -Dam.stores.cts.servers=cts1.example.com:1636 \
  -Dam.stores.cts.password=password \
  -server \
  -Xmx2g \
  -XX:MetaspaceSize=256m \
  -XX:MaxMetaspaceSize=256m"
export CATALINA_OPTS