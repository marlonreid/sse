# Use the Debezium server image as the base image
FROM quay.io/debezium/server:3.1.0.Final

# Switch to root so we can install additional packages and download files
USER root

# Update package lists and install wget (if not already available)
RUN apt-get update && apt-get install -y wget && rm -rf /var/lib/apt/lists/*

# Download the jmx_prometheus_javaagent jar, version 1.10, from Maven Central.
RUN wget -O /opt/jmx_prometheus_javaagent-1.10.jar \
    "https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/1.10/jmx_prometheus_javaagent-1.10.jar"

# Copy your JMX configuration file into the image.
COPY jmx_config.yaml /opt/jmx_config.yaml

# Adjust file permissions if needed.
RUN chmod 644 /opt/jmx_prometheus_javaagent-1.10.jar /opt/jmx_config.yaml

# Set the JAVA_TOOL_OPTIONS environment variable so that when the JVM starts,
# it loads the jmx_prometheus_javaagent. The syntax is:
#   -javaagent:<jar_path>=<port>:<config_path>
# Here we choose port 9404 for the agent to expose the metrics.
ENV JAVA_TOOL_OPTIONS="-javaagent:/opt/jmx_prometheus_javaagent-1.10.jar=9404:/opt/jmx_config.yaml"

# Switch back to the non-root user expected by the Debezium image
USER debezium

# Preserve the base image's entrypoint.
# (If the image uses a custom start script, we leave it as is.)
CMD ["/debezium/server/start.sh"]


# The default entrypoint from the base image is preserved.


docker build -t your-registry/debezium-server-custom:3.1.0 .
docker run --rm your-registry/debezium-server-custom:3.1.0 ls -l /opt/
docker tag your-registry/debezium-server-custom:3.1.0 your-registry/debezium-server-custom:3.1.0
docker push your-registry/debezium-server-custom:3.1.0
