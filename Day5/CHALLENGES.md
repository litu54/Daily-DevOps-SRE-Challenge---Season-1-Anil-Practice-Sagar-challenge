— Azure Custom Image & Replication Challenge
# 📘 Azure Custom Image & Replication Challenge

This challenge demonstrates the **end-to-end process** of creating, generalizing, capturing, 
and replicating a custom VM image across multiple Azure regions using a **Shared Image Gallery (SIG)**.  
It mimics a real-world cloud engineering workflow — used by enterprises to standardize and deploy secure golden images.

---

## 🎯 Objective

- Create a custom Ubuntu VM  
- Install and configure NGINX  
- Apply basic OS hardening  
- Capture a **golden image**  
- Replicate it across Azure regions  
- Deploy a new VM from the replicated image  
- Validate application consistency  

---

## 🏗️ Steps Performed

### 1️⃣ Create Source VM
- **Region:** Central India  
- **OS:** Ubuntu 24.04 LTS  
- **Size:** Standard_B1s  
- **Username:** azureuser  

Commands executed:
```bash
sudo apt update -y
sudo apt install nginx -y
sudo systemctl enable nginx --now


Verification:

systemctl status nginx
curl localhost


✅ Output: “Welcome to nginx!”

2️⃣ Apply Basic Security Hardening
sudo sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sudo systemctl restart sshd
sudo apt autoremove -y
sudo apt upgrade -y

3️⃣ Generalize the VM

Prepare VM for imaging:

sudo waagent -deprovision+user


Then stop and deallocate:

az vm deallocate --resource-group SaiRg --name LinuxVm

4️⃣ Capture the Golden Image

From Azure Portal → VM → Capture
Options selected:

✅ Share to Azure Compute Gallery

Gallery Name: Nginxvm1

Image Definition: nginx-ubuntu-golden

Version: 1.0.0

OS State: Generalized

Region: Central India

Result → Golden Image Created Successfully

5️⃣ Verify Image in Shared Image Gallery

Navigate:

Azure Portal → Shared Image Galleries → Nginxvm1 → nginx-ubuntu-golden → Versions


✅ Image version 1.0.0 available in Central India.

6️⃣ Replicate Image to Another Region

Challenge Goal: Replicate the golden image to South India.

From Portal:

Shared Image Gallery → nginx-ubuntu-golden → Versions → 1.0.1 → Update Replication


Add region → ✅ (Asia Pacific) South India

Replica count → 1

Storage SKU → Zone-redundant

Save → Wait until status = Completed ✅

Now the image is available in Central India + South India.

7️⃣ Launch a VM from the Replicated Image

From nginx-ubuntu-golden → Version 1.0.1 → Create VM

Setting	Value
Region	South India ✅
VM Name	NginxReplicatedVM
Size	Standard_B1s
Authentication	SSH Key
Resource Group	SaiRg

Deploy and connect via SSH:

ssh azureuser@<public_ip>
systemctl status nginx
curl localhost


✅ NGINX running successfully in South India region VM.

✅ Verification Summary
Step	Task	Status
VM creation & NGINX setup	✅	
Hardening applied	✅	
Generalized	✅	
Image captured (Central India)	✅	
Replicated to South India	✅	
VM launched from replicated image	✅	
Application verified	✅	
🧠 Key Learnings

How to create a Golden Image from a base VM

Using Shared Image Gallery (SIG) for version control

Cross-region replication for DR (Disaster Recovery)

Deploying standardized workloads across multiple regions

Real-world Azure Cloud engineering workflow

🧰 Tools & Services Used
Category	Tools
Cloud	Microsoft Azure
OS	Ubuntu 24.04 LTS
Web Server	NGINX
Resource Type	Shared Image Gallery
Commands	waagent, az cli, ssh
