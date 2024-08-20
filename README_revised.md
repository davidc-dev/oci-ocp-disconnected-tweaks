
# OpenShift Disconnected Installation on Oracle Cloud Tweaks

## Overview
This guide provides instructions and tweaks for addressubg issues setting up an OpenShift Disconnected Installation on Oracle Cloud Infrastructure (OCI). It addresses common issues and offers solutions to ensure a smooth installation and configuration process. This document is intended for administrators familiar with OpenShift and Oracle Cloud.

## Table of Contents
1. [Node Hostname Defaults to MAC Address](#1-node-hostname-defaults-to-mac-address)
2. [Adding Worker Nodes](#3-adding-worker-nodes)


## 1. Node Hostname Defaults to the MAC Address

### Overview
When the `assign private dns record` setting in OCI is set to `false`, the hostname on openshift nodes defaults to the MAC address of the instance. While it doesn't affect the install, it makes it difficult for administrators to quikcly identify nodes by name.

### For New Cluster Installs
To address this issue in new cluster installs, replace the `machineconfig-ccm.yml` file with the version included in this repository when creating the installation image using the OpenShift installer.

### Node Role Issues
In some cases, worker nodes might be incorrectly joined as master nodes during new cluster installation because there is no direct way to specify the node type outside of the `agent-config.yaml` file. Unfortunately, Oracle Cloud does not allow specifying a MAC address during installation, and the CCM agent does not pick up the role from instance tags.

To ensure that the nodes intended to be masters are deployed as masters, set the replica count of the compute nodes to `0` in the `install-config.yaml` file.  This will create a cluster with nodes that have the roles for master and worker.  We will fix this in the next section.

### Remove Worker Role from Master Nodes

1. Run the [Adding Worker Nodes](#3-adding-worker-nodes), workflow to add the necessary number of worker nodes you want to use for the new cluster.

2. Once the workers are deployed and show as *Ready*, run the command below to remove the *worker* role from the master nodes:

    ```bash
    oc patch scheduler cluster --type merge -p '{"spec":{"mastersSchedulable":false}}'
    ```

3. Now, redeploy the pods that need to be moved off the master nodes and onto the new worker nodes using the following commands:

    ```bash
    oc rollout -n openshift-ingress restart deployment/router-default
    oc rollout -n openshift-image-registry restart deploy/image-registry
    oc rollout -n openshift-monitoring restart statefulset/alertmanager-main
    oc rollout -n openshift-monitoring restart statefulset/prometheus-k8s
    oc rollout -n openshift-monitoring restart deployment/grafana
    oc rollout -n openshift-monitoring restart deployment/kube-state-metrics
    oc rollout -n openshift-monitoring restart deployment/telemeter-client
    oc rollout -n openshift-monitoring restart deployment/thanos-querier
    ```


## 2. Adding Worker Nodes

### Overview
To scale your OpenShift cluster, you may need to add additional worker nodes. There are issues adding nodes in OCP versions < 4.16 which can be addressed by the workaround below.

### Steps to Add Worker Nodes
1. Run the scripts included in this repository to create the **worker.ign** file for hosting on a webserver and the **coreos-rawdisk.raw** image file for creating a custom OCI image.
    - **Using and instance with a connection to internet and to the cluster**

      If you have an instance with access to both the cluster and to the internet, run only the **00-extract-ignition-create-worker.sh script.**

      Before running the script, ensure oc client is setup and configured with access to the cluster.

      Run the script with the IP address or resolvable hostname of the webserver you used to serve up the raw disk file during the installation. 

      ```
      WEBSERVER=<server IP or hostname>
      ./00-extract-ignition-create-worker.sh $WEBSERVER
      ```
      Copy the **worker.ign** that the script outputs to your webservers serving directory.

      Upload the **coreos-rawdisk.raw** file to a blob storage bucket and create a pre-authenticated URL to use in the terraform to create the custom image.
    - **When running on seperate instances.  One with cluster access and one with internet access.**

      Run the **01-extract-worker-ign-and-raw-disk-path.sh** script on an instance that has cluster access and the oc client installed and configured.

      Copy the **worker.ign** that the script outputs to your webservers serving directory.

      Save the RAW_DISK_PATH URL output for use in the second script below.

      On an instance that has internet access, run the **02-create-worker-image.sh** script.  It has 2 arguments.  The first is the IP address or hostname of the webserver and the second is the RAW_DISK_PATH output from the first script.

      ```
      WEBSERVER=<server IP or hostname>
      RAW_DISK_PATH=<url output from first script>
      ./02-create-worker-image.sh $WEBSERVER $RAW_DISK_PATH
      ```
      This script downloads the raw disk file of the base coreos image specific to your openshift cluster version and modifies the ignition file in the raw disk to point at the worker.ign file you copied to the webserver.  

      Upload the **coreos-rawdisk.raw** file to a blob storage bucket and create a pre-authenticated URL to use in the terraform to create the custom image.
            

2. Create the custom image for the worker nodes 
  - Either manually create the new custom image for the worker nodes using the uploaded raw disk file, or use the examples in the **add-workers.tf** file in this repo.  Updated variables and details as needed for your environment.

    ```hcl
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
3. Create new worker nodes
  - Either manually create the new worker nodes using the new custom image, or add them using the terraform examples.  Update details, variables as needed for your environment.

    hcl
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


4. Approving CSRs for New Worker Nodes

  - When adding new worker nodes, they will generate Certificate Signing Requests (CSRs) that need to be approved for the nodes to join the cluster successfully.

    - View the pending CSRs with the following command:

      ```bash
      oc get CSR | grep Pending
      ```

    - Approve each CSR individually:

      ```bash
      oc adm certificate approve <csr-name>
      ```

    - Alternatively, approve all pending CSRs at once:

      ```bash
      oc get csr -o go-template='{{range .items}}{{if not .status}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}' | xargs --no-run-if-empty oc adm certificate approve
      ```

  - Once the CSRs are approved, the new worker nodes should appear as "Ready" when running `oc get nodes`.
