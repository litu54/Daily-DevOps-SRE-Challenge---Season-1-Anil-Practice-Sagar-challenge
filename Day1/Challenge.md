📧 How to Configure Gmail SMTP on Ubuntu (ssmtp/msmtp)

Many DevOps learners face issues while trying to send emails from Linux servers using Gmail. By default, Gmail blocks less secure logins — so we must use App Passwords.

Here’s a step-by-step guide 👇

🔹 Step 1: Enable 2-Step Verification in Gmail

Open Google Account Security
.

Under “Signing in to Google”, enable 2-Step Verification.

Without this, App Passwords option won’t be available.

🔹 Step 2: Generate a 16-character App Password

Go to 👉 https://myaccount.google.com/apppasswords
.

Select:

App: Mail

Device: Linux (or “Other”)

Click Generate.

Copy the 16-character password (e.g., abcd efgh ijkl mnop).

⚠️ Important: Remove spaces before using it → abcdefghijklmnop.

🔹 Step 3: Install SMTP client

Install ssmtp and mailutils (or you can use msmtp if you prefer):

sudo apt update
sudo apt install -y ssmtp mailutils

🔹 Step 4: Configure /etc/ssmtp/ssmtp.conf

Edit config:

sudo nano /etc/ssmtp/ssmtp.conf


Paste this (replace with your email + 16-char App Password):

root=your-email@gmail.com
mailhub=smtp.gmail.com:587
AuthUser=your-email@gmail.com
AuthPass=your-16-character-app-password
UseTLS=YES
UseSTARTTLS=YES
rewriteDomain=gmail.com
hostname=LinuxSRE
FromLineOverride=YES


⚠️ Notes:

AuthPass → paste your App Password (no spaces).

Set proper permissions:

sudo chmod 600 /etc/ssmtp/ssmtp.conf
sudo chown root:root /etc/ssmtp/ssmtp.conf

🔹 Step 5: Test SMTP

Run:

echo -e "Subject: Gmail SMTP Test\n\nHello from Linux server" | ssmtp -v your-email@gmail.com


✅ If setup is correct, you will see:

[<-] 235 2.7.0 Accepted
[<-] 250 2.0.0 OK
