## This is the first of 2 script to run if you do not have an instance 
## that has access to both the internet and the cluster.  Run this 
## this script on an instance that has access to the cluster.  Copy 
## the worker.ign file that is created to the webserver's serving 
## directory (same place the rootfs is from the original installation.)
## Copy the RAW_DISK_PATH URL to use in the second script.

## extract worker.ign for copy to webserver
oc extract -n openshift-machine-api secret/worker-user-data --keys=userData --to=- > worker.ign
echo "WORKER_IGN_FILE=$(pwd)/worker.ign"
## Get path for disk image

RAW_DISK_PATH=$(oc -n openshift-machine-config-operator get configmap/coreos-bootimages -o jsonpath='{.data.stream}' | jq -r '.architectures.x86_64.artifacts.metal.formats."raw.gz".disk.location')

echo "RAW_DISK_PATH=$RAW_DISK_PATH"