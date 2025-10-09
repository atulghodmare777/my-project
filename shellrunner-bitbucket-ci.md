# 🧰 Setting Up a Bitbucket Self-Hosted Runner (Linux Shell)

> **Reference:** [Atlassian Support – Set up runners for Linux Shell](https://support.atlassian.com/bitbucket-cloud/docs/set-up-runners-for-linux-shell/)

---

## 📘 Overview

**Linux Shell Runners** allow you to run [Bitbucket Pipelines](https://support.atlassian.com/bitbucket-cloud/docs/use-pipelines/) builds on your own Linux infrastructure — **without Docker**.  
You also won’t be charged for build minutes used by your self-hosted runners.

---

## ⚙️ Prerequisites

Make sure your Linux VM meets the following:

| Requirement | Minimum Version |
|--------------|----------------|
| **OS** | 64-bit Linux (Ubuntu 22.04+ recommended) |
| **OpenJDK** | 11.0.15 or newer |
| **Git** | 2.35.0 or newer |
| **Bash** | 3.2 or newer |
| **RAM** | At least 8GB |

### 🧩 Install required dependencies

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y openjdk-11-jdk git curl ca-certificates tar unzip
🧪 Verify installation
bash
Copy code
java -version        # should show OpenJDK 11
git --version        # >= 2.35 recommended
free -h              # ensure you have ~8GB RAM (runner requirement)
👤 Create a Dedicated Runner User
It’s best practice to run the Bitbucket runner as a non-root user.

bash
Copy code
sudo useradd -m -s /bin/bash bitbucket-runner
sudo mkdir -p /home/bitbucket-runner/atlassian-bitbucket-pipelines-runner
sudo chown -R bitbucket-runner:bitbucket-runner /home/bitbucket-runner
🔑 Configure the Runner in Bitbucket
Login to Bitbucket Cloud

Navigate to one of the following:

Workspace runners: Workspace settings → Workspace runners

Repository runners: Repository settings → Runners

Click Add runner

Under System and architecture, select:

java
Copy code
Linux Shell (x86_64)
Provide a name for the runner (e.g., test-runner)

Click Next, and Bitbucket will show you the runner registration commands

Copy those credentials — you’ll need them for the service configuration below.

🧱 Create a Systemd Service for the Runner
Replace the {UUIDs} and OAuth credentials below with your actual values from the Bitbucket runner setup screen.

bash
Copy code
sudo tee /etc/systemd/system/bitbucket-runner.service > /dev/null <<'EOF'
[Unit]
Description=Bitbucket Pipelines Linux Shell Runner
After=network.target

[Service]
User=bitbucket-runner
WorkingDirectory=/home/bitbucket-runner/atlassian-bitbucket-pipelines-runner/bin
ExecStart=/home/bitbucket-runner/atlassian-bitbucket-pipelines-runner/bin/start.sh \
  --accountUuid {1b5d3d17-8bb2-47eb-be26-44578d489b58} \
  --repositoryUuid {438d7573-5d5a-46de-94cd-49e2df5bff38} \
  --runnerUuid {8c132044-075a-5378-ace2-a3403406e533} \
  --OAuthClientId provide_id_from_copied_content \
  --OAuthClientSecret provide_secret_from_copy_content \
  --runtime linux-shell \
  --workingDirectory ../temp
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
🚀 Enable and Start the Runner
Run the following commands as root:

bash
Copy code
sudo systemctl daemon-reload
sudo systemctl enable bitbucket-runner
sudo systemctl start bitbucket-runner
sudo systemctl status bitbucket-runner
🧭 View Runner Logs
bash
Copy code
sudo journalctl -u bitbucket-runner -f
When you see logs like:

perl
Copy code
Runner starting.
Runner runtime: linux-shell
Updating runner state to "ONLINE".
and your runner appears ONLINE 🟢 in Bitbucket, the setup is complete.

🧪 Test the Runner with a Sample Pipeline
Create a .bitbucket-pipelines.yml file in your repository root:

yaml
Copy code
pipelines:
  default:
    - step:
        name: Test Self-Hosted Runner
        runs-on:
          - self.hosted     # Ensures this step runs on your custom runner
          - linux.shell
        script:
          - echo "Running on Bitbucket self-hosted runner"
          - echo "Current user:"
          - whoami
          - echo "Hostname:"
          - hostname
Commit and push this file — Bitbucket will trigger a new pipeline.

✅ Expected output:

sql
Copy code
Running on Bitbucket self-hosted runner
Current user:
bitbucket-runner
Hostname:
bitbucket-runner
🧾 Post-Setup Notes
Your runner reconnects automatically after system restarts (systemd manages it).

External IP changes (e.g., after GCP VM reboot) do not affect runner connectivity — it connects outbound to Bitbucket.

To restart or check status:

bash
Copy code
sudo systemctl restart bitbucket-runner
sudo systemctl status bitbucket-runner
To follow logs:

bash
Copy code
sudo journalctl -u bitbucket-runner -f
🧹 Cleanup or Maintenance
If you ever need to clean up or reset the workspace:

bash
Copy code
sudo systemctl stop bitbucket-runner
rm -rf /home/bitbucket-runner/atlassian-bitbucket-pipelines-runner/temp/*
sudo systemctl start bitbucket-runner
✅ Final Verification Checklist
Check	Command	Expected
Runner service active	sudo systemctl status bitbucket-runner	Active (running)
Process owned by bitbucket-runner	`ps -ef	grep java`
Logs show ONLINE	sudo journalctl -u bitbucket-runner -f	Runner ONLINE
Bitbucket UI	Runner appears Online 🟢	Verified

🎉 Your Bitbucket Linux Shell Runner is now fully operational!
You can now build, test, and deploy directly from your own infrastructure — securely and without usage costs.

pgsql
Copy code

---

✅ **Copy the entire block above** into your `.md` file —  
it will render beautifully on GitHub with syntax highlighting, tables, and callouts.  

Would you like me to include a small **troubleshooting section** (e.g., what to do if “Runner Offline” or “Git clone failed”)? That’s often helpful in README files for long-term maintenance.


































Atlassian Support
Bitbucket
Resources
Build, test, and deploy with Pipelines
Runners
Cloud

Data Center
Set up runners for Linux Shell
Linux Shell Runners allow you to run Bitbucket Pipelines builds on your own Linux infrastructure without docker; and you won’t be charged for the build minutes used by your self-hosted runners.

Prerequisites
OpenJDK 11 (11.0.15 or newer) is installed

Git 2.35.0 and above

Bash 3.2 and above

A 64-Bit Linux instance with at least 8GB of RAM as a host for the runner.

TO install these run following commands:
sudo apt update && sudo apt upgrade -y
sudo apt install -y openjdk-11-jdk git curl ca-certificates tar unzip
java -version        # should show OpenJDK 11
git --version        # >= 2.35 recommended
free -h              # ensure you have ~8GB RAM (runner req)

Create a dedicated user and folder
sudo useradd -m -s /bin/bash bitbucket-runner
sudo mkdir -p /home/bitbucket-runner/atlassian-bitbucket-pipelines-runner
sudo chown -R bitbucket-runner:bitbucket-runner /home/bitbucket-runner


Login into the bitbucket
1.Navigate to the Runners page:
For Workspace runners, visit Workspace settings > Workspace runners.
For Repository runners, visit Repository settings > Runners.

Select Add runner.
From the Runner installation dialog, under System and architecture, select Linux Shell (x86_64).
Provide the name to the runner
When we do the next we get commands copy and save those commands and use those details in the following commands which we will run as root user

sudo tee /etc/systemd/system/bitbucket-runner.service > /dev/null <<'EOF'
[Unit]
Description=Bitbucket Pipelines Linux Shell Runner
After=network.target

[Service]
User=bitbucket-runner
WorkingDirectory=/home/bitbucket-runner/atlassian-bitbucket-pipelines-runner/bin
ExecStart=/home/bitbucket-runner/atlassian-bitbucket-pipelines-runner/bin/start.sh --accountUuid {1b5d3d17-8bb2-47eb-be26-44578d489b58} --repositoryUuid {438d7573-5d5a-46de-94cd-49e2df5bff38} --runnerUuid {8c132044-075a-5378-ace2-a3403406e533} --OAuthClientId jM52suxJBbBht2oZ8H1mmnsYopWgOEJU --OAuthClientSecret provide_copied_Secret --runtime linux-shell --workingDirectory ../temp
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

Edit the multiple id and password in above command with our copied content from bitbucket

Run following commands to start the service
systemctl daemon-reload
systemctl enable bitbucket-runner
systemctl start bitbucket-runner
systemctl status bitbucket-runner

sudo journalctl -u bitbucket-runner -f

After this we should see the runner online in the bitbucket
Sample pipeline
pipelines:
  default:
    - step:
        name: Test Self-Hosted Runner
        runs-on:
          - self.hosted     # these labels we made sure that it is running on specific runner we can give lable while creating the runner configuration command
          - linux.shell
        script:
          - echo "Running on Bitbucket self-hosted runner"
          - echo "Current user:"
          - whoami
          - echo "Hostname:"
          - hostname




