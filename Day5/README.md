[200~# ☁️ Azure Custom Golden Image Creation & Replication

This project demonstrates how to **create a custom Azure VM image**, 
**harden it**, and **replicate it across multiple Azure regions** using a 
**Shared Image Gallery (SIG)** — a real-world enterprise scenario.

---

## 🚀 Objectives
- Create a custom VM and install software (NGINX)
- Apply basic security hardening
- Generalize the VM for image capture
- Capture a golden image into a Shared Image Gallery
- Replicate the image to another Azure region
- Launch a new VM using the replicated image and validate setup

---

## 🏗️ Steps Followed

### 1️⃣ Create Source VM
- **Region:** Central India  
- **Image:** Ubuntu 24.04 LTS (Canonical)
- **Size:** Standard_B1s (Free tier friendly)
- **Username:** azureuser  

After VM creation:
```bash
sudo apt update -y
sudo apt install nginx -y
sudo systemctl enable nginx --now
Verify NGINX:

bash
Copy code
systemctl status nginx
curl localhost
2️⃣ Apply Basic Security Hardening
Quick hardening steps performed:

bash
Copy code
# Disable root SSH login
sudo sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sudo systemctl restart sshd

# Remove unnecessary packages
sudo apt autoremove -y

# Apply all updates
sudo apt upgrade -y
3️⃣ Generalize the VM
Before capturing an image, deprovision the VM:

bash
Copy code
sudo waagent -deprovision+user
Then stop and deallocate the VM:

bash
Copy code
az vm deallocate --resource-group SaiRg --name LinuxVm
4️⃣ Capture the VM as a Golden Image
In the Azure Portal:

Navigate to Virtual Machine → Capture

Select:

Share image to Azure Compute Gallery ✅

Operating system state: Generalized

Gallery: Create new → Nginxvm1

Image Definition: nginx-ubuntu-golden

Version number: 1.0.0

Region: Central India

Click Review + Create → Create

This will create:

A Shared Image Gallery (SIG) → Nginxvm1

An Image Definition → nginx-ubuntu-golden

A Version 1.0.0 → Central India

5️⃣ Verify Image Creation
Go to:

vbnet
Copy code
Azure Portal → Shared Image Galleries → Nginxvm1 → nginx-ubuntu-golden → Versions
Status should show: ✅ Available

6️⃣ Replicate the Image to Another Region
From the same image version:

Click on Update replication

Add new target region → ✅ South India

Replica count: 1

Storage SKU: Zone-redundant

Save changes

Wait until replication status = Completed ✅

Now image version 1.0.1 (or updated version) is available in:

nginx
Copy code
Central India + South India
7️⃣ Launch a VM from the Replicated Image
Go to:

pgsql
Copy code
Shared Image Gallery → nginx-ubuntu-golden → Version 1.0.1 → Create VM
Configuration:

Region: South India ✅

VM Name: NginxReplicatedVM

Size: Standard_B1s

Authentication: SSH Key

Resource Group: SaiRg

Deploy → Wait for completion → Connect via SSH:

bash
Copy code
ssh azureuser@<public_ip>
Verify:

bash
Copy code
systemctl status nginx
curl localhost
If you see the default “Welcome to nginx!” page → replication success 🎉

✅ Final Verification
Task    Status
NGINX installed & running   ✅
VM generalized  ✅
Golden image created    ✅
Shared Image Gallery created    ✅
Image replicated to another region  ✅
VM launched in target region    ✅
NGINX verified in new region    ✅

🧠 Key Learnings
How to use Azure Shared Image Gallery (SIG) for versioning and replication.

How to generalize a VM using waagent.

How to replicate images across Azure regions for disaster recovery.

Real-world cloud lifecycle: Build → Harden → Capture → Replicate → Deploy
