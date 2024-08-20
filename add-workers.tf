## Copy needed sections into your existing OCI terraform as needed.

## Openshift infrastructure compartment
variable "compartment_ocid" {
  type        = string
  description = "The ocid of the compartment where you wish to create the OpenShift cluster."
}

## Openshift cluster name
variable "cluster_name" {
  type        = string
  description = "The name of your OpenShift cluster. It should be the same as what was specified when creating the OpenShift ISO and it should be DNS compatible. The cluster_name value must be 1-54 characters. It can use lowercase alphanumeric characters or hyphen (-), but must start and end with a lowercase letter or a number."
}

variable "compute_shape" {
  default     = "VM.Standard.E4.Flex"
  type        = string
  description = "Compute shape of the compute nodes. The default shape is VM.Standard.E4.Flex. For more detail regarding compute shapes, please visit https://docs.oracle.com/en-us/iaas/Content/Compute/References/computeshapes.htm "
}

## Compute node vars

variable "compute_ocpu" {
  default     = 4
  type        = number
  description = "The number of OCPUs available for the shape of each compute node. The default value is 4. "

  validation {
    condition     = var.compute_ocpu >= 1 && var.compute_ocpu <= 114
    error_message = "The compute_ocpu value must be between 1 and 114."
  }
}
variable "compute_boot_volume_vpus_per_gb" {
  default     = 30
  type        = number
  description = "The number of volume performance units (VPUs) that will be applied to this volume per GB of each compute node. The default value is 30. "

  validation {
    condition     = var.compute_boot_volume_vpus_per_gb >= 10 && var.compute_boot_volume_vpus_per_gb <= 120 && var.compute_boot_volume_vpus_per_gb % 10 == 0
    error_message = "The compute_boot_volume_vpus_per_gb value must be between 10 and 120, and must be a multiple of 10."
  }
}
variable "compute_memory" {
  default     = 16
  type        = number
  description = "The amount of memory available for the shape of each compute node, in gigabytes. The default value is 16."

  validation {
    condition     = var.compute_memory >= 1 && var.compute_memory <= 1760
    error_message = "The compute_memory value must be between the value of compute_ocpu and 1760."
  }
}
variable "compute_boot_size" {
  default     = 100
  type        = number
  description = "The size of the boot volume of each compute node in GBs. The minimum value is 50 GB and the maximum value is 32,768 GB (32 TB). The default value is 100 GB."

  validation {
    condition     = var.compute_boot_size >= 50 && var.compute_boot_size <= 32768
    error_message = "The compute_boot_size value must be between 50 and 32768."
  }
}


## Pre-authenticated URL of raw disk image uploaded to Blob storage.
variable "worker_image_source_uri" {
  type        = string
  description = "The OCI Object Storage URL for the OpenShift image. Before provisioning resources through this Resource Manager stack, users should upload the OpenShift image to OCI Object Storage, create a pre-authenticated requests (PAR) uri, and paste the uri to this block. For more detail regarding Object storage and PAR, please visit https://docs.oracle.com/en-us/iaas/Content/Object/Concepts/objectstorageoverview.htm and https://docs.oracle.com/en-us/iaas/Content/Object/Tasks/usingpreauthenticatedrequests.htm ."
}

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

resource "oci_core_instance" "worker-02" {
  availability_domain = data.oci_identity_availability_domain.availability_domain.name
  compartment_id      = var.compartment_ocid
  shape = var.compute_shape
  display_name = "worker-02"
  create_vnic_details {
    private_ip          = "10.0.16.104"
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