# Day-4 — Public + Private Subnet: Flask (Public) + MySQL (Private)

## Overview

This repository documents the manual, step-by-step setup you completed for the Day-4 Sagar Challenge: a 2‑tier architecture on Azure consisting of a public subnet hosting a Flask application and a private subnet hosting a MySQL database. The database is accessible only from the Flask app via private IP. NAT provides outbound-only internet access to the private subnet.

**Tags:** `#getfitwithsagar` `#SRELife` `#DevOpsForAll`

---

## Architecture (summary)

* **VNet:** `10.0.0.0/16`

  * **Public subnet:** `10.0.1.0/24` → Flask VM (Public IP + private IP like `10.0.1.x`)
  * **Private subnet:** `10.0.2.0/24` → MySQL VM (private IP only like `10.0.2.x`)
* **Route tables:**

  * Public RT → `0.0.0.0/0` → Internet Gateway (public)
  * Private RT → `0.0.0.0/0` → NAT Gateway (outbound only)
* **NSG rules:**

  * Public NSG: allow inbound 22 (SSH from your IP), 80/8080/443 (HTTP/HTTPS)
  * Private NSG: allow inbound 22 from public subnet, allow inbound 3306 only from public subnet (or specific Flask private IP)

---

## Prerequisites

* Azure subscription and Portal access
* SSH key pair used for VMs (private key available locally)
* Basic knowledge of SSH, Linux, and Python

---

## Repo layout (suggested)

```
sagar-day4/
├── flask_app/
│   ├── app.py
│   ├── requirements.txt
├── mysql/
│   ├── setup.sql
├── infra/  (optional notes)
├── docs/
│   └── postmortem.md
└── README.md
```

---

## Step-by-step setup (manual)

> Do these steps in this order. All Azure clicks are via Portal unless otherwise noted.

### 1. Create VNet and subnets

1. Azure Portal → **Virtual Networks → + Create**
2. Name: `sagar-vnet` (example)  Address space: `10.0.0.0/16`
3. Under **Subnets** add:

   * `public-subnet` → `10.0.1.0/24`
   * `private-subnet` → `10.0.2.0/24`
4. Create resource group if needed.

### 2. Create Route Tables & NAT

1. Create a **route table** `public-rt` with route `0.0.0.0/0` → Internet.
2. Associate `public-rt` with `public-subnet`.
3. Create **NAT Gateway** in public subnet and create `private-rt` route table with `0.0.0.0/0` → NAT Gateway.
4. Associate `private-rt` with `private-subnet`.

### 3. Create NSGs

* Public NSG (`public-nsg`): inbound allow 22 (your IP), 80, 8080, 443 (any). Outbound allow all.
* Private NSG (`private-nsg`): inbound allow 22 from `10.0.1.0/24` (for SSH from jump host), inbound allow 3306 from `10.0.1.0/24` (Flask). Outbound allow all.

Attach NSGs at subnet level (recommended).

### 4. Provision VMs

* **Flask VM (public-subnet)**

  * Image: Ubuntu 24.04 LTS
  * Choose existing SSH public key
  * Assign Public IP
  * Place in `public-subnet` and attach `public-nsg`
* **MySQL VM (private-subnet)**

  * Image: Ubuntu 24.04 LTS
  * Choose same SSH key (or note key used)
  * No Public IP
  * Place in `private-subnet` and attach `private-nsg`

> If using different keys, keep track. To SSH to private VM, use the public VM as jump host and copy the private key to the public VM temporarily.

### 5. SSH into public VM and jump into private VM

On local machine:

```bash
ssh -i ~/.ssh/mykey.pem azureuser@<Flask-Public-IP>
# copy private key if needed
scp -i ~/.ssh/mykey.pem ~/.ssh/mykey.pem azureuser@<Flask-Public-IP>:/home/azureuser/
# on public VM
chmod 400 pvtkey.pem
ssh -i pvtkey.pem azureuser@10.0.2.x
```

### 6. Install & configure MySQL (on private VM)

```bash
sudo apt update
sudo apt install mysql-server -y
# edit config
sudo vim /etc/mysql/mysql.conf.d/mysqld.cnf
# set bind-address = 10.0.2.x (private IP of MySQL VM)
sudo systemctl restart mysql
```

Create DB and user:

```sql
sudo mysql
CREATE DATABASE flaskdb;
CREATE USER 'flaskuser'@'10.0.%' IDENTIFIED BY 'flaskpass';
GRANT ALL PRIVILEGES ON flaskdb.* TO 'flaskuser'@'10.0.%';
FLUSH PRIVILEGES;
EXIT;
```

### 7. Install Flask app (on public VM)

```bash
# on public VM
sudo apt update
sudo apt install python3-venv python3-pip -y
mkdir ~/flask_app && cd ~/flask_app
python3 -m venv venv
source venv/bin/activate
pip install flask mysql-connector-python gunicorn
# create app.py (see code snippet below)
```

**app.py** (example):

```python
from flask import Flask, jsonify
import mysql.connector
app = Flask(__name__)

def get_db_conn():
    return mysql.connector.connect(
        host="10.0.2.x",    # MySQL private IP
        user="flaskuser",
        password="flaskpass",
        database="flaskdb"
    )

@app.route('/')
def index():
    return "Flask app up. Hit /users to see DB rows."

@app.route('/users')
def users():
    conn = get_db_conn()
    cur = conn.cursor(dictionary=True)
    cur.execute("SELECT id, name, email FROM users;")
    rows = cur.fetchall()
    cur.close(); conn.close()
    return jsonify(rows)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
```

### 8. Run & test Flask

```bash
# from public VM (inside venv)
python3 app.py
# or run on port 8080 with gunicorn
gunicorn -w2 -b 0.0.0.0:8080 app:app
```

From your laptop:

```bash
curl http://<Flask-Public-IP>:8080/users
```

Should return JSON (rows from `users` table).

### 9. Connectivity tests checklist

From **public VM**:

```bash
ping 10.0.2.x
nc -vz 10.0.2.x 3306
mysql -h 10.0.2.x -u flaskuser -p
```

From **local laptop**:

```bash
curl http://<Flask-Public-IP>:8080
```

### 10. Failure simulation

On private VM:

```bash
sudo systemctl stop mysql
# refresh Flask /users -> should fail
sudo systemctl start mysql
# refresh -> should succeed
```

Check logs:

```bash
journalctl -u mysql -n 100
journalctl -u gunicorn -n 100    # if using gunicorn systemd
```

---


---




---


