# pv-azure-file.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-azure-file
spec:
  capacity:
    storage: 5Gi
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""              # static provisioning
  csi:
    driver: file.csi.azure.com
    readOnly: false
    volumeHandle: stork8sstorage_k8sfileshare   # "<account>_<shareName>"
    volumeAttributes:
      shareName: k8sfileshare
      storageAccount: stork8sstorage
    nodeStageSecretRef:
      name: azure-file-secret       # ← your KV‑populated Secret
      namespace: default
# pvc-azure-file.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-azure-file
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 5Gi
  volumeName: pv-azure-file       # binds to that PV
  storageClassName: ""
