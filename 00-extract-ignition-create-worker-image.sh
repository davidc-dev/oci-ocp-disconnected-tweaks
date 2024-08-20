#!/bin/bash

##  This script is for running on an instance that can access both the internet 
#   and access the cluster with oc commands.  Make sure oc client is installed and 
#   setup before running script.  It will generate a worker.ign file that needs to 
#   be copied to the webserver serving directory (same place the rootfs is from
#   the original installation.).  It will also generate a coreos-rawdisk.raw file 
#   that needs to be uploaded to a Blob storage bucket and a pre-authenticate URL
#   created to be used in the terraform to create the custom image.  

die () {
    echo >&2 "$@"
    exit 1
}

[ "$#" -eq 1 ] || die "IP Address or Hostname of webwerver required, $# provided"
echo $1 #| grep -E -q '^[0-9]+$' || die "IP or hostname of webserver required, $1 provided"

WEBSERVER=$1

## extract worker.ign for copy to webserver
oc extract -n openshift-machine-api secret/worker-user-data --keys=userData --to=- > worker.ign

echo "Put the created worker.ign file in the webserver's serving directory"

## Get path for disk image

RAW_DISK_PATH=$(oc -n openshift-machine-config-operator get configmap/coreos-bootimages -o jsonpath='{.data.stream}' | jq -r '.architectures.x86_64.artifacts.metal.formats."raw.gz".disk.location')

## Download disk image

curl -o coreos-rawdisk.raw.gz $RAW_DISK_PATH

## Unzip image

gunzip coreos-rawdisk.raw.gz

## setup loop device for mount

LOOP_DEVICE=$(sudo losetup --find --partscan --show coreos-rawdisk.raw)

## make dir for mount

sudo mkdir /mnt/coreos-raw

## Mount raw disk

sudo mount ${LOOP_DEVICE}p3 /mnt/coreos-raw

## Append

IGNITION=ignition.config.url=http://$WEBSERVER/worker.ign
echo $IGNITION

sudo sed -i "s|metal|metal $IGNITION|g" /mnt/coreos-raw/loader/entries/ostree-1-rhcos.conf
cat /mnt/coreos-raw/loader/entries/ostree-1-rhcos.conf
## Unmount raw file

sudo umount /mnt/coreos-raw

sudo rm -rf /mnt/coreos-raw

echo "Upload coreos-rawdisk.raw to your Oracle Blob Storage Bucket and create a Custom Image.  Use that image to provision new worker nodes."
