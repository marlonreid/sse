quarkus.log.level: INFO
      quarkus.log.category."io.debezium.connector.postgresql".level: DEBUG
      quarkus.log.category."io.debezium.pipeline".level: DEBUG
      quarkus.log.category."io.debezium.relational".level: DEBUG
      quarkus.log.category."io.debezium.server".level: DEBUG
      quarkus.log.category."org.apache.kafka.clients.producer".level: DEBUG
      quarkus.log.category."org.apache.kafka.clients.consumer".level: DEBUG
      # Optional cleaner format:
      # quarkus.log.console.format: "%d{yyyy-MM-dd HH:mm:ss,SSS} %-5p [%c] (%t) %s%e%n"

SELECT
  /* if no PK, use ctid instead so you can find the row */
  ctid AS row_id,
  octet_length(to_jsonb(t.*)::text) AS approx_json_bytes
FROM schema.table AS t
ORDER BY approx_json_bytes DESC
LIMIT 50;
