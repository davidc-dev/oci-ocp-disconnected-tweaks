## Use this file if you do not have a instance with access to both the 
#  internet and to the cluster.  

#!/bin/bash

echo "WebserverIP or Hostname: ${1?' You forgot to supply an IP Address or Hostname for your webserver'}";
echo "RAW_DISK_PATH Url: ${2?' You fogot to supply the URL for the RAW_DISK_PATH from first script'}";

WEBSERVER=$1

RAW_DISK_PATH=$2

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
