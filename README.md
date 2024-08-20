#  OpenShift Disconnected Installation on Oracle Cloud Tweaks

##  Hostname on nodes defaults to mac address when assign private dns record is set to false.

### For new cluster installs
Replace **machineconfig-ccm.yml** with one in this repo when creating the installation image in the openshift-installer.

I run into an issue where sometimes the worker nodes will get joined as masters as there is not way to specify the node type other than in the agent-config.yaml.  Unfortunately, oracle cloud doesn't seem to allow you to specify a mac address during installation and the ccm agent does not pick up the role from the instance tags.  Because of this, the best way I've found to ensure the nodes I want to be master deploy as master is to set the replica count of the compute nodes to 0 in the install-config.yaml file.  

The cluster will deploy the master nodes with the worker node role as well and you'll need to remove that once you've deployed the worker nodes.

Once the cluster deploys, use the **Add a new worker node to an existing cluster** workflow shown below to add as many worker nodes as you need.  Once the worker nodes are deployed, you will need to remove the *worker* role from the master nodes by running the oc command below:

```
oc patch scheduler cluster --type merge -p '{"spec":{"mastersSchedulable":false}}'
```

Next you will need to tell the cluster to redeploy the pods that need to be moved off the master nodes and onto the new workers.  Use the commands below:

```
oc rollout -n openshift-ingress restart deployment/router-default
oc rollout -n openshift-image-registry restart deploy/image-registry
oc rollout -n openshift-monitoring restart statefulset/alertmanager-main
oc rollout -n openshift-monitoring restart statefulset/prometheus-k8s
oc rollout -n openshift-monitoring restart deployment/grafana
oc rollout -n openshift-monitoring restart deployment/kube-state-metrics
oc rollout -n openshift-monitoring restart deployment/openshift-state-metrics
oc rollout -n openshift-monitoring restart deployment/prometheus-adapter
oc rollout -n openshift-monitoring restart deployment/telemeter-client
oc rollout -n openshift-monitoring restart deployment/thanos-querier
```

Depending on what you deployed, some of the above commands may fail due to the deployments not existing in your cluster.  That is ok.

### For existing clusters

Apply the **machineconfig-ccm.yml** to the cluster to update the machineconfig and fix the issue for any newly added nodes.

## Add new worker nodes to an existing cluster

### For instance with connection to internet and to the cluster
If you have an instance with access to both the cluster and to the internet, run only the **00-extract-ignition-create-worker.sh script.**

Before running the script, ensure oc client is setup and configured with access to the cluster.

Run the script with the IP address or resolvable hostname of the webserver you used to serve up the raw disk file during the installation. 

```
WEBSERVER=<server IP or hostname>
./00-extract-ignition-create-worker.sh $WEBSERVER
```
Copy the **worker.ign** that the script outputs to your webservers serving directory.

Upload the **coreos-rawdisk.raw** file to a blob storage bucket and create a pre-authenticated URL to use in the terraform to create the custom image.

### For running on seperate instances.  One with cluster access and one with internet access.

Run the **01-extract-worker-ign-and-raw-disk-path.sh** script on an instance that has cluster access and the oc client installed and configured.

Copy the **worker.ign** that the script outputs to your webservers serving directory.

Save the RAW_DISK_PATH URL output for use in the second script below.

On an instnace that has internet access, run the **02-create-worker-image.sh** script.  It has 2 arguments.  The first is the IP address or hostname of the webserver and the second is the RAW_DISK_PATH output from the first script.

```
WEBSERVER=<server IP or hostname>
RAW_DISK_PATH=<url output from first script>
./02-create-worker-image.sh $WEBSERVER $RAW_DISK_PATH
```
This script downloads the raw disk file of the base coreos image specific to your openshift cluster version and modifies the ignition file in the raw disk to point at the worker.ign file you copied to the webserver.  

Upload the **coreos-rawdisk.raw** file to a blob storage bucket and create a pre-authenticated URL to use in the terraform to create the custom image.


### Create the custom image for the worker nodes 

Either manually create the new custom image for the worker nodes using the uploaded raw disk file, or use the examples in the **add-workers.tf** file in this repo.  Updated variables and details as needed for your environment.


```
## Local vars
locals {
  global_image_capability_schemas = data.oci_core_compute_global_image_capability_schemas.image_capability_schemas.compute_global_image_capability_schemas
  image_schema_data = {
    "Compute.Firmware" = "{\"values\": [\"UEFI_64\"],\"defaultValue\": \"UEFI_64\",\"descriptorType\": \"enumstring\",\"source\": \"IMAGE\"}"
  }
}

### Create custom worker node image from RAW disk image uploaded to Blob Bucket.  
resource "oci_core_image" "worker_image" {
  compartment_id = var.compartment_ocid
  display_name   = "${var.cluster_name}-worker-image"
  launch_mode    = "PARAVIRTUALIZED"

  image_source_details {
    source_type = "objectStorageUri"
    source_uri  = var.worker_image_source_uri

    source_image_type = "QCOW2"
  }
}

resource "oci_core_shape_management" "imaging_compute_shape" {
  compartment_id = var.compartment_ocid
  image_id       = oci_core_image.worker_image.id
  shape_name     = var.compute_shape
}

resource "oci_core_compute_image_capability_schema" "worker_image_capability_schema" {
  compartment_id                                      = var.compartment_ocid
  compute_global_image_capability_schema_version_name = local.global_image_capability_schemas[0].current_version_name
  image_id                                            = oci_core_image.worker_image.id
  schema_data                                         = local.image_schema_data
}
```
### Create new worker nodes 

Either manually create the new worker nodes using the new custom image, or add them using the terraform examples.  Update details, variables as needed for your environment.

```
resource "oci_core_instance" "worker-01" {
  availability_domain = data.oci_identity_availability_domain.availability_domain.name
  compartment_id      = var.compartment_ocid
  shape = var.compute_shape
  display_name = "worker-01"
  create_vnic_details {
    private_ip          = "10.0.16.103"
    assign_public_ip    = "false"
    assign_private_dns_record = false
    nsg_ids = [
      oci_core_network_security_group.cluster_compute_nsg.id,
    ]
    subnet_id = oci_core_subnet.private.id
  }      
  defined_tags = {
    "openshift-${var.cluster_name}.instance-role" = "compute"
  }
  shape_config {
    memory_in_gbs = var.compute_memory
    ocpus         = var.compute_ocpu
  }
  source_details {
    boot_volume_size_in_gbs = var.compute_boot_size
    boot_volume_vpus_per_gb = var.compute_boot_volume_vpus_per_gb
    source_id                = oci_core_image.worker_image.id
    source_type             = "image"
  }

}
```
###  Approve the CSRs for the new worker nodes

Adding new worker nodes usually generates 2-3 CSRs per node.  You will need to approve the CSR records to succesffully at the node to the cluster.

View the Pending CSRs
```
oc get CSR | grep Pending
```
Approve the CSR
```
oc adm certificate approve <csr-name from above>
```

Alternativly, you can approve all pending CSRs using the command below:
```
oc get csr -o go-template='{{range .items}}{{if not .status}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}' | xargs --no-run-if-empty oc adm certificate approve
```

Once the CSRs are approved, the nodes should add after 5 minutes or so show as "Ready" when running ```oc get nodes```.