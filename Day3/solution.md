# 🔒 Secure Jenkins & Grafana Behind NGINX Reverse Proxy with SSL & Basic Auth (Docker Setup)

This guide walks through how to securely expose **Jenkins** and **Grafana** running in Docker containers behind **NGINX** with:
- ✅ Self-signed SSL certificates  
- 🔐 Basic Authentication (per app)
- ⚙️ Reverse Proxy using HTTPS  
- 🧠 Clean URL paths like `https://jenkins.local/jenkins` and `https://grafana.local/grafana`

> 🧩 Ideal for home-lab / Azure VM / bare-metal setups where you want full control & secure access.

---

## 🏗️ Architecture Overview

Client (Browser)
↓ HTTPS + Basic Auth
[ NGINX Reverse Proxy :443 ]
├──> Jenkins container (http://127.0.0.1:8080/jenkins)
└──> Grafana container (http://127.0.0.1:3000/grafana)

markdown
Copy code

**Nginx handles**
- SSL termination  
- Basic authentication  
- Reverse proxy routing  

---

## ⚙️ Prerequisites

- Ubuntu 24.04+ VM (Azure / local)
- Docker & Docker Compose installed
- NGINX installed
- Domain mapping in `/etc/hosts` (or Windows hosts file):
  ```bash
  4.240.89.179 grafana.local jenkins.local
🔧 Step 1: Generate a Self-Signed SSL Certificate
bash
Copy code
sudo mkdir -p /etc/ssl/selfsigned
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/selfsigned/nginx-self.key \
  -out /etc/ssl/selfsigned/nginx-self.crt \
  -subj "/C=IN/ST=Karnataka/L=Bangalore/O=SelfSigned/OU=DevOps/CN=jenkins.local"
🧱 Step 2: Create Basic Auth Files
bash
Copy code
sudo mkdir -p /etc/nginx/auth

# For Jenkins
sudo htpasswd -cb /etc/nginx/auth/htpasswd_jenkins jenkinsadmin 'Jenkins@123'

# For Grafana
sudo htpasswd -cb /etc/nginx/auth/htpasswd_grafana grafanaadmin 'Grafana@123'
🧠 These credentials protect access at the Nginx layer (before Jenkins/Grafana UI).

🐳 Step 3: Run Jenkins & Grafana with Docker
bash
Copy code
# Jenkins
docker run -d \
  --name jenkins \
  -p 8080:8080 \
  -e JENKINS_OPTS="--prefix=/jenkins" \
  jenkins/jenkins:lts-jdk17

# Grafana
docker run -d \
  --name grafana \
  -p 3000:3000 \
  -e GF_SERVER_ROOT_URL="https://grafana.local/grafana" \
  grafana/grafana
Check containers:

bash
Copy code
docker ps
🌐 Step 4: Configure NGINX Reverse Proxy
Edit /etc/nginx/sites-available/default (or create a new file):

nginx
Copy code
server {
    listen 443 ssl http2 default_server;
    listen [::]:443 ssl http2 default_server;
    server_name _;

    ssl_certificate     /etc/ssl/selfsigned/nginx-self.crt;
    ssl_certificate_key /etc/ssl/selfsigned/nginx-self.key;

    # 🔸 GRAFANA (https://grafana.local/grafana)
    location /grafana/ {
        proxy_pass          http://127.0.0.1:3000/;
        proxy_set_header    Host $host;
        proxy_set_header    X-Real-IP $remote_addr;
        proxy_set_header    X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header    X-Forwarded-Proto $scheme;

        auth_basic "Grafana Login";
        auth_basic_user_file /etc/nginx/auth/htpasswd_grafana;
    }

    # 🔸 JENKINS (https://jenkins.local/jenkins)
    location /jenkins/ {
        proxy_pass          http://127.0.0.1:8080/;
        proxy_set_header    Host $host;
        proxy_set_header    X-Real-IP $remote_addr;
        proxy_set_header    X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header    X-Forwarded-Proto $scheme;

        # Jenkins-specific (important fixes)
        proxy_set_header    Upgrade $http_upgrade;
        proxy_set_header    Connection $connection_upgrade;
        proxy_http_version  1.1;
        proxy_buffering     off;
        proxy_read_timeout  3600;

        # 🧩 The critical fix — don't forward Nginx Basic Auth to Jenkins
        proxy_set_header    Authorization "";

        auth_basic "Jenkins Login";
        auth_basic_user_file /etc/nginx/auth/htpasswd_jenkins;
    }
}
Test and reload:

bash
Copy code
sudo nginx -t
sudo systemctl reload nginx
🧠 Step 5: Configure Windows /etc/hosts
Open Notepad as Administrator →
Edit file: C:\Windows\System32\drivers\etc\hosts

Add:

lua
Copy code
4.240.89.179 grafana.local jenkins.local
Flush DNS cache:

cmd
Copy code
ipconfig /flushdns
🚀 Step 6: Access in Browser
Jenkins:
🔗 https://jenkins.local/jenkins/

Basic Auth → jenkinsadmin / Jenkins@123

Jenkins unlock password (inside container):

bash
Copy code
docker exec -it jenkins cat /var/jenkins_home/secrets/initialAdminPassword
Grafana:
🔗 https://grafana.local/grafana/

Basic Auth → grafanaadmin / Grafana@123

Grafana login → admin / Grafana@123

🔄 Step 7: Reset Grafana Password (if forgotten)
bash
Copy code
docker exec -it grafana grafana-cli admin reset-admin-password Grafana@123
docker restart grafana
🔍 Step 8: Verify Nginx Proxy Connectivity
bash
Copy code
curl -k -I -u jenkinsadmin:'Jenkins@123' -H "Host: jenkins.local" https://127.0.0.1/jenkins/
curl -k -I -u grafanaadmin:'Grafana@123' -H "Host: grafana.local" https://127.0.0.1/grafana/
✅ Should return 302 (redirect) or 200 OK
