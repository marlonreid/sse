# Use the Debezium server image as the base image
FROM quay.io/debezium/server:3.1.0.Final

# Switch to root to install additional software and download files
USER root

# Update package lists and install wget (if not already installed)
RUN apt-get update && apt-get install -y wget && rm -rf /var/lib/apt/lists/*

# Download the OpenTelemetry JMX Metrics Gatherer jar
# Update the URL to point to your desired version; here we use version 1.9.0 as an example.
RUN wget -O /opt/opentelemetry-java-contrib-jmx-metrics.jar \
    "https://github.com/open-telemetry/opentelemetry-java-contrib-jmx-metrics/releases/download/v1.9.0/opentelemetry-java-contrib-jmx-metrics.jar"

# Adjust file permissions if necessary
RUN chmod 644 /opt/opentelemetry-java-contrib-jmx-metrics.jar

# Switch back to the non-root user expected by the Debezium image
USER debezium

# The default entrypoint from the base image is preserved.
