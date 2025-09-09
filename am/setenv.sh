#!/bin/bash
CATALINA_OPTS="-Djavax.net.ssl.trustStore={{AM_TRUSTSTORE}} -Djavax.net.ssl.trustStorePassword={{TRUSTSTORE_PASSWORD}} -Djavax.net.ssl.trustStoreType=jks"
