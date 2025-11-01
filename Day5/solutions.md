Azure — Create Hardened Golden Image (step-by-step)

Goal: install NGINX on an Ubuntu VM, apply basic hardening, capture a reusable golden image, and (optionally) replicate it to another region.
Commands include placeholders — replace <rg>, <vm-name>, <subscription-id>, <target-location> etc. with your values.

0. Prerequisites

Azure CLI installed & logged in: az login

Subscription selected: az account set --subscription "<SUB_NAME_OR_ID>"

A running Ubuntu VM (example: LinuxVm) in a resource group (example: SaiRg)

SSH access to the VM

1. Verify NGINX installation (on the VM)

SSH to VM:

ssh azureuser@<public_ip>


Check nginx:

sudo systemctl status nginx
# if not active:
sudo systemctl enable nginx --now
# quick local test:
curl localhost
# or from browser:
# http://<public_ip>  -> "Welcome to nginx!"

2. Apply Basic Security Hardening (on the VM)

Run on the VM as root/with sudo:

# Disable root SSH login
sudo sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config

# Disable password authentication (SSH key only)
sudo sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

# Restart SSH
sudo systemctl restart sshd

# Enable automatic security updates
sudo apt update -y
sudo apt install unattended-upgrades -y
sudo dpkg-reconfigure --priority=low unattended-upgrades

# Optional: basic firewall open for nginx (HTTP & HTTPS)
sudo apt install ufw -y
sudo ufw allow 'Nginx Full'
sudo ufw enable


Note: After changing SSH settings, ensure your SSH key works before closing current session.

3. (Optional) Add a test file to a data disk (if present)

If your VM has a separate data disk and you want to verify snapshot → mount → test later:

# mount path may vary; example:
sudo mkdir -p /mnt/data_disk
sudo mount /dev/sdc1 /mnt/data_disk   # adjust device
echo "hello from source vm $(date)" | sudo tee /mnt/data_disk/testfile.txt
sync
sudo umount /mnt/data_disk

4. Generalize / Deprovision VM (prepare for golden image)

Run on the VM to remove machine-specific info (Linux):

sudo waagent -deprovision+user
# confirm with 'y' when prompted


Then shutdown & deallocate VM from CLI (or via Portal):

az vm deallocate --resource-group <rg> --name <vm-name>
# verify
az vm get-instance-view -g <rg> -n <vm-name> --query "instanceView.statuses[?starts_with(code,'PowerState/')].displayStatus" -o tsv


Important: After waagent -deprovision+user, you cannot SSH into that source VM again — that is expected.

5. Create a Managed Image (OS-only) from the deallocated VM

From Azure CLI:

az image create \
  --resource-group <rg> \
  --name nginx-hardened-image \
  --source <vm-name>


Confirm:

az image show -g <rg> -n nginx-hardened-image --query "provisioningState" -o tsv
# should be 'Succeeded'

6. (Recommended) Publish to Shared Image Gallery (SIG) — Portal or CLI
Portal (GUI) quick steps

Azure Portal → Shared Image Galleries → + Create (if not exist) → create gallery (e.g., NginxGallery) in Central India.

From image page or gallery: create Image definition (publisher/offer/sku) — e.g., nginx-ubuntu-golden.

Create Image version (e.g., 1.0.0) from the managed image and set replication regions (add South India if you want cross-region).

CLI quick example (create SIG & version)
# variables
GALLERY_RG=<gallery-rg>
GALLERY_NAME="NginxGallery"
IMAGE_DEF="nginx-ubuntu-golden"
IMAGE_VER="1.0.0"
LOCATION="centralindia"   # source

# create gallery RG & gallery
az group create -n $GALLERY_RG -l $LOCATION
az sig create -g $GALLERY_RG --gallery-name $GALLERY_NAME --location $LOCATION

# create image definition
az sig image-definition create \
  --resource-group $GALLERY_RG \
  --gallery-name $GALLERY_NAME \
  --gallery-image-definition $IMAGE_DEF \
  --publisher "anil" --offer "ubuntu-nginx" --sku "v1" --os-type Linux

# create a version from managed image (and replicate to regions)
az sig image-version create \
  --resource-group $GALLERY_RG \
  --gallery-name $GALLERY_NAME \
  --gallery-image-definition $IMAGE_DEF \
  --gallery-image-version $IMAGE_VER \
  --managed-image "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Compute/images/nginx-hardened-image" \
  --target-regions centralindia=1 southindia=1 westindia=1

7. (Optional) Snapshot & copy data disk to target region

If you had a data disk and want the same data on target VM, snapshot it and copy:

# create snapshot (source region)
az snapshot create \
  --resource-group <rg> \
  --source "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Compute/disks/<data-disk-name>" \
  --name data-snap-$(date +%F)

# copy snapshot to target RG/location
az snapshot create \
  --resource-group <target-rg> \
  --source "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Compute/snapshots/data-snap-$(date +%F)" \
  --location <target-location> \
  --name data-snap-copy-$(date +%F)

# create disk from snapshot in target RG
az disk create -g <target-rg> -n data-disk-from-snap --source data-snap-copy-$(date +%F) --zone 1


Then attach to the new VM (see next step).

8. Launch a VM from the custom image (target region)

If you used a managed image:

az vm create \
  --resource-group <rg> \
  --name nginx-test-vm \
  --image nginx-hardened-image \
  --admin-username azureuser \
  --ssh-key-values ~/.ssh/id_rsa.pub \
  --location <region>   # centralindia or replicated region


If you used SIG image version:

Use portal “Create VM” from SIG version, pick the replicated region (e.g., South India).

Or CLI with --image <sig-image-id>.

If attaching data disk:

az vm disk attach --resource-group <target-rg> --vm-name <new-vm> --name data-disk-from-snap

9. Verify on new VM

SSH into the new VM:

ssh azureuser@<new_public_ip>
# check nginx service
sudo systemctl status nginx
curl localhost
# if data disk attached:
lsblk
sudo mkdir /mnt/data
sudo mount /dev/sdc1 /mnt/data   # adjust device
cat /mnt/data/testfile.txt


You should see the NGINX default page and your test data (if attached/needed).

10. Cleanup & Best Practices

Keep images OS-only (data disks separate) for smaller, reusable golden images.

Use SIG versioning (1.0.0 → 1.0.1 → ...) for patches.

Lock/delete prevention: enable Lock deleting replicated locations if needed.

Test every image by deploying a VM from it before mass rollout.

Keep tags and documentation in repo (image version, created date, notes).

11. Troubleshooting quick tips

If portal says “You can only create VM in the replication regions of this image” → choose a region that is listed or add that region to replication (Update Replication in SIG).

If image copy fails for encrypted disks → ensure KMS/CMEK keys exist in target region and have proper permissions.

If mount device not visible → use lsblk and check partition (e.g., /dev/sdc1 vs /dev/sdc).

If create-image fails → ensure VM is deallocated before capture.

12. Useful commands summary (replace placeholders)
az login
az account set --subscription "<sub>"

# stop & deallocate
az vm deallocate -g <rg> -n <vm-name>

# create managed image
az image create -g <rg> -n nginx-hardened-image --source <vm-name>

# create sig gallery and version (example)
az sig image-version create \
  --resource-group <gallery-rg> \
  --gallery-name <gallery-name> \
  --gallery-image-definition <image-def> \
  --gallery-image-version 1.0.0 \
  --managed-image "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Compute/images/nginx-hardened-image" \
  --target-regions centralindia=1 southindia=1

# create vm from image
az vm create -g <rg> -n nginx-test-vm --image nginx-hardened-image --admin-username azureuser --ssh-key-values ~/.ssh/id_rsa.pub
