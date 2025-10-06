Great—Confluent works well for a “tools-only” pod. Here’s the quickest, disposable way to run it in AKS, exec in, and use the Kafka CLIs against Event Hubs.

0) Prereqs

az aks get-credentials … done

Your AKS egress can reach *.servicebus.windows.net:9093 (TLS 1.2)

1) Create a namespace (optional)
kubectl create ns tools

2) Launch a temporary pod (sleeping)
kubectl run kafka-tools \
  -n tools \
  --image=confluentinc/cp-kafka:7.6.1 \
  --restart=Never --command -- bash -lc "sleep infinity"

kubectl wait -n tools --for=condition=Ready pod/kafka-tools --timeout=90s

3) Put your Event Hubs client config in the pod

Create client.properties locally (example below), then copy it in:

kubectl cp ./client.properties tools/kafka-tools:/tmp/client.properties


Example client.properties for Event Hubs (Kafka endpoint):

bootstrap.servers=<namespace>.servicebus.windows.net:9093
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required \
  username="$ConnectionString" \
  password="Endpoint=sb://<namespace>.servicebus.windows.net/;SharedAccessKeyName=<keyName>;SharedAccessKey=<key>";
ssl.endpoint.identification.algorithm=https
request.timeout.ms=60000
session.timeout.ms=30000

4) Exec into the pod and use the tools
kubectl exec -it -n tools kafka-tools -- bash


Inside the shell you can run:

# Check a consumer group’s lag
kafka-consumer-groups \
  --bootstrap-server <namespace>.servicebus.windows.net:9093 \
  --command-config /tmp/client.properties \
  --describe --group <your-group>

# Ad-hoc read from the beginning
kafka-console-consumer \
  --bootstrap-server <namespace>.servicebus.windows.net:9093 \
  --topic <eventhub-name> \
  --consumer.config /tmp/client.properties \
  --group debug-consumer --from-beginning

5) Clean up
kubectl delete pod -n tools kafka-tools
kubectl delete ns tools   # if you created it

Alternative (YAML with mounted ConfigMap)

If you’d rather not kubectl cp, create a ConfigMap and mount it:

kubectl -n tools create configmap eh-client --from-file=client.properties

cat <<'EOF' | kubectl apply -n tools -f -
apiVersion: v1
kind: Pod
metadata:
  name: kafka-tools
spec:
  containers:
  - name: tools
    image: confluentinc/cp-kafka:7.6.1
    command: ["bash","-lc","sleep infinity"]
    volumeMounts:
    - name: cfg
      mountPath: /tmp
  volumes:
  - name: cfg
    configMap:
      name: eh-client
EOF


Then:

kubectl exec -it -n tools kafka-tools -- bash


That’s it—you’ve got a disposable Confluent CLI pod in AKS to debug Event Hubs via Kafka. If you want, tell me your Event Hub partition count and consumer group.id and I’ll give you the exact commands to verify assignment and lag.
