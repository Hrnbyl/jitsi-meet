# Phase 1: Local Setup, Architecture, and Observability Analysis

---

## 1. Executive Summary & Objective

Phase 1 focuses on setting up **Jitsi Meet locally** using Docker Compose. The objective of this phase is to:

* Containerize and execute the full Jitsi Meet stack on a local development machine.
* Configure Git remotes to manage a private fork while remaining capable of pulling upstream open-source updates.
* Gain a deep, hands-on understanding of Jitsi’s microservices architecture and component interactions.
* Inspect real-time signaling protocols (**XMPP**) and media transport mechanisms (**WebRTC / SFU**) using browser telemetry and container logging.

---

## 2. Jitsi Architecture & Component Responsibilities

Jitsi Meet is not a single monolith; it is an ecosystem of decoupled microservices working together to facilitate real-time video conferencing.

```
                  +-----------------------------------+
                  |        Client Browser             |
                  +-----------------------------------+
                        |                     |
           HTTP/WS      |                     | WebRTC (SRTP)
         (Port 8443)    v                     v
                  +-----------+         +-----------+
                  |   Jitsi   |         |   Jitsi   |
                  |    WEB    |         | Videobridge|
                  |  (Nginx)  |         |   (JVB)   |
                  +-----------+         +-----------+
                        |                     ^
             WebSocket  |                     | COLIBRI2
            (Port 5280) v                     | (XMPP)
                  +-----------+               |
                  |  Prosody  |<--------------+
                  |   (XMPP)  |
                  +-----------+
                        ^
                  XMPP  |
                (Focus) |
                  +-----------+
                  |  Jicofo   |
                  +-----------+

```

| Component | Technology | Primary Responsibility |
| --- | --- | --- |
| **Jitsi Web (`web`)** | Nginx, React, WebRTC JS SDK | Serves the frontend web interface, static assets, and WebRTC JavaScript logic to client browsers. Acts as a reverse proxy inside the container environment. |
| **Prosody (`prosody`)** | Lua-based XMPP Server | The central signaling backbone. Manages client connections (via WebSockets), user authentication, chat messages, and multi-user virtual conference rooms (MUCs). |
| **Jicofo (`jicofo`)** | Java | The **J**itsi **Co**nference **Fo**cus component. Acts as the meeting orchestrator/controller that negotiates media sessions between clients and media bridges. |
| **Jitsi Videobridge (`jvb`)** | Java / C++ | The Selective Forwarding Unit (**SFU**). Receives audio/video streams from participants and forwards them to all other participants in the meeting room instead of mixing video directly. |

---

## 3. Tooling, Dependencies, and Prerequisites

Before deploying the local environment, the following core software utilities and host-level components are required:

### Tools & Engines Installed

* **Docker Engine (v20.10+)**: Container runtime used to isolate each microservice.
* **Docker Compose (v2.x+)**: Orchestration tool used to define, networking, environment variables, and manage multi-container applications via a declarative `docker-compose.yml`.
* **Git**: Distributed version control system used to manage codebases and remotes.
* **OpenSSL**: Utility used during initial environment generation to construct secure random cryptographic tokens and keys.

---

## 4. Local Repository Setup & Version Control Management

To maintain a custom configuration while preserving the ability to fetch updates from the official open-source Jitsi repository, a dual-remote Git setup was established.

### Step 1: Clone Upstream Open-Source Repository

```bash
git clone https://github.com/jitsi/docker-jitsi-meet.git hrnbyl-meet
cd hrnbyl-meet

```

### Step 2: Configure Dual-Remote Management

To decouple custom data tracking from upstream, the primary default remote (`origin`) was modified to point to a private repository, while the original open-source repository was preserved under the `upstream` remote tag:

```bash
# Rename original remote to 'upstream'
git remote rename origin upstream

# Add private repository as new 'origin'
git remote add origin https://github.com/YOUR-USERNAME/YOUR-PRIVATE-REPO.git

# Verify remote layout
git remote -v

```

**Expected Output:**

```text
origin    https://github.com/YOUR-USERNAME/YOUR-PRIVATE-REPO.git (fetch)
origin    https://github.com/YOUR-USERNAME/YOUR-PRIVATE-REPO.git (push)
upstream  https://github.com/jitsi/docker-jitsi-meet.git (fetch)
upstream  https://github.com/jitsi/docker-jitsi-meet.git (push)

```

> **Git Workflow Rules:**
> * `git push origin master`: Pushes local configuration changes to the private data repository.
> * `git pull upstream master`: Fetches latest features and security updates from the open-source community.
> 
> 

---

## 5. Configuration & Environment Setup

Jitsi requires explicit secret keys, generated passwords, and storage paths before starting up.

### Step 1: Initialize Environment File

Copy the provided environment template to establish default environment configuration flags:

```bash
cp env.example .env

```

### Step 2: Generate Secure Cryptographic Passwords

Jitsi requires internal passwords for Prosody, Jicofo, and JVB authentication. A built-in shell script parses `.env` and injects generated secret keys automatically:

```bash
./gen-passwords.sh

```

### Step 3: Establish Local Configuration Directories

Create local host folders to persist configuration states, self-signed TLS certificates, and container runtime data across container restarts:

```bash
mkdir -p ~/.jitsi-meet-cfg/{web,prosody,jicofo,jvb}

```

### Step 4: Configure Local Domain & Ports in `.env`

Edit `.env` to configure ports and disable strict external SSL checks for localhost testing:

```ini
HTTP_PORT=8000
HTTPS_PORT=8443
TZ=UTC
PUBLIC_URL=https://localhost:8443
CONFIG=~/.jitsi-meet-cfg

```

---

## 6. Certificate Generation & SSL Handling

By default, WebRTC strictly requires a secure context (`HTTPS`). During local deployment:

1. The `web` container automatically generates a **Self-Signed TLS Certificate** via OpenSSL upon startup if custom certificates are not mounted.
2. The self-signed certificate is placed inside `~/.jitsi-meet-cfg/web/certs/`.
3. When accessing `https://localhost:8443`, browsers display an `NET::ERR_CERT_AUTHORITY_INVALID` security warning. You must bypass this warning manually (click *Advanced $\rightarrow$ Proceed to localhost*) to allow WebSocket connections and media stream authorizations.

---

## 7. Execution & Local Verification

Deploy the stack in detached mode using Docker Compose:

```bash
docker compose up -d

```

### Verify Running Containers

Ensure all 4 core microservice containers are in an `Up` status:

```bash
docker compose ps

```

**Expected Output:**

```text
NAME                     COMMAND                  SERVICE   STATUS
hrnbyl-meet-web-1        "/init"                  web       running (healthy)
hrnbyl-meet-prosody-1    "/init"                  prosody   running (healthy)
hrnbyl-meet-jicofo-1     "/init"                  jicofo    running (healthy)
hrnbyl-meet-jvb-1        "/init"                  jvb       running (healthy)

```

---

## 8. Deep Observability & Technical Insights

To verify operational integrity beyond simple visual rendering, detailed telemetry checks were conducted on WebRTC media pipelines, XMPP signaling streams, and JVB SFU logs.

### A. WebRTC Telemetry Observations (`chrome://webrtc-internals`)

By joining a meeting across two browser tabs on `https://localhost:8443` and inspecting `chrome://webrtc-internals`, the WebRTC transport layer was validated:

* **ICE Negotiation:** `ICE State: Connected/Completed` confirmed that local Interactive Connectivity Establishment candidates successfully paired without requiring external TURN servers.
* **DTLS Handshake:** `Transport State: Connected` confirmed that Datagram Transport Layer Security was established, encrypting media traffic (SRTP).
* **Throughput Metrics:** `bytesSent` and `bytesReceived` counters increased steadily, confirming continuous real-time media transmission.
* **Packet Loss & Jitter:** `packetsLost` remained `0` (or negligible), and `jitter` was minimal, confirming optimal localhost loopback performance.
* **RTP Streams:** Active `inbound-rtp` and `outbound-rtp` objects were instantiated upon toggling the camera/microphone.
* **Codec Selection:** Negotiated video codec defaulted to `AV1` (or `VP8` based on browser capabilities).
* **Candidate Pair State:** `Succeeded` confirmed a valid network path via SFU.

---

### B. XMPP Signaling Observations (Chrome DevTools $\rightarrow$ Network $\rightarrow$ WS)

Inspecting the active WebSocket connection (`wss://localhost:8443/xmpp-websocket`) revealed the exact XMPP stanzas driving meeting state updates:

```
+---------------------------------------------------------------------------------------+
|                                XMPP STANZA DICTIONARY                                 |
+------------+--------------------------------------------------------------------------+
| Stanza     | Purpose & Description                                                    |
+------------+--------------------------------------------------------------------------+
| <presence> | Broadcasts participant state changes (Join/Leave, Mute/Unmute, Hand     |
|            | Raise, Display Name <nick>, Video/Audio codec capabilities <features>).  |
| <message>  | Encapsulates chat messages sent between meeting participants.           |
| <iq>       | Info/Query request/response pattern used for session control, keepalives |
|            | (pings), and COLIBRI bridge negotiations.                                |
| <r> / <a>  | Stream Management (XEP-0198) stanzas: <r> requests acknowledgment,      |
|            | <a> acknowledges stanza receipt for delivery reliability over WebSockets.|
+------------+--------------------------------------------------------------------------+

```

* **Behavioral Note:** The initial join event creates a high burst of synchronization stanzas establishing conference state. Subsequent user interactions (e.g., toggling audio) only emit tiny, incremental delta updates.

---

### C. Bridge Allocation Observations (JVB Logs)

By executing real-time log tailing on the Videobridge container:

```bash
docker compose logs -f jvb

```

The following events verified SFU media routing:

* **COLIBRI2 Protocol:** Log entries confirmed incoming `conference-modify` requests originating from **Jicofo** to allocate media channels.
* **Endpoint Allocation:** JVB created unique `<endpoint>` IDs for each joined participant.
* **Media Sources:** `media-source` tags registered audio and video SSRC IDs to track incoming streams.
* **SFU Confirmation:** Verified that video transmission routes through the JVB container rather than establishing direct peer-to-peer (P2P) connections between clients.
* **Log Idle Pattern:** JVB logs primarily register signaling control events (endpoint creation, allocation, teardown) and remain quiet during ongoing static media forwarding.
# Phase 2: Infrastructure as Code (IaC) with Terraform & AWS EKS

---

## 1. Executive Summary & Objective

Phase 2 focuses on automating the base cloud infrastructure on **AWS** using **Terraform** and **eksctl**. The primary objectives of this phase were:

* Declare and provision a dedicated, isolated Virtual Private Cloud (**VPC**) with public/private subnet topology.
* Attach essential tagging to subnets so the AWS Load Balancer Controller can auto-discover them.
* Deploy a managed **Amazon EKS Cluster** (`jitsi-eks-cluster`) and EC2 Worker Node Groups.
* Establish AWS IAM OpenID Connect (**OIDC**) provider integration to enable IAM Roles for Service Accounts (**IRSA**).
* Document terraform workflows, state lock troubleshooting, security practices, and files to exclude from version control.

---

## 2. Infrastructure Architecture & Network Strategy

Before provisioning resources, the AWS environment was designed according to EKS best practices:

```
+-----------------------------------------------------------------------------------+
| AWS Cloud (Region: ap-south-1)                                                   |
|                                                                                   |
|  +-----------------------------------------------------------------------------+  |
|  | VPC: 10.0.0.0/16                                                            |  |
|  |                                                                             |  |
|  |   +---------------------------------+   +---------------------------------+ |  |
|  |   | Public Subnet A (10.0.1.0/24)   |   | Public Subnet B (10.0.2.0/24)   | |  |
|  |   | Tag: kubernetes.io/role/elb = 1 |   | Tag: kubernetes.io/role/elb = 1 | |  |
|  |   | (Hosts Internet-Facing ALB)     |   | (Hosts Internet-Facing ALB)     | |  |
|  |   +---------------------------------+   +---------------------------------+ |  |
|  |                                                                             |  |
|  |   +---------------------------------+   +---------------------------------+ |  |
|  |   | Private Subnet A (10.0.3.0/24)  |   | Private Subnet B (10.0.4.0/24)  | |  |
|  |   | Tag: kubernetes.io/role/internal-elb = 1                              | |  |
|  |   | (Hosts EKS EC2 Worker Nodes)    |                                       | |  |
|  |   +---------------------------------+   +---------------------------------+ |  |
|  +-----------------------------------------------------------------------------+  |
|                                                                                   |
|  +-----------------------------------------------------------------------------+  |
|  | EKS Control Plane (Managed by AWS)                                          |  |
|  | Cluster Name: jitsi-eks-cluster                                            |  |
|  +-----------------------------------------------------------------------------+  |
+-----------------------------------------------------------------------------------+

```

---

## 3. Detailed Breakdown of Terraform Files & Configuration Fields

The Terraform configuration was structured into modular files (`main.tf`, `variables.tf`, `outputs.tf`, `providers.tf`). Below is the technical breakdown of each field, its purpose, and selected values.

### A. `providers.tf` (AWS & Helm Provider Setup)

```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

```

* **`required_version`**: Constrains execution to Terraform CLI `1.5.0` or higher to guarantee compatibility with provider syntax.
* **`provider "aws"`**: Configures the AWS API client.
* **`region`**: Specified as `ap-south-1` (Mumbai). Chooses the geographic region closest to end users to reduce streaming latency.



---

### B. `variables.tf` (Parameterized Values)

```hcl
variable "aws_region" {
  type        = STRING
  default     = "ap-south-1"
  description = "AWS region for infrastructure deployment"
}

variable "cluster_name" {
  type        = STRING
  default     = "jitsi-eks-cluster"
  description = "Name of the EKS cluster"
}

variable "vpc_cidr" {
  type        = STRING
  default     = "10.0.0.0/16"
  description = "Base CIDR block for the VPC"
}

```

* **`aws_region`**: Centralized regional control (`ap-south-1`).
* **`cluster_name`**: Set to `jitsi-eks-cluster`. Must match across Terraform, `eksctl`, and Helm values to ensure the AWS Load Balancer Controller targets the right cluster.
* **`vpc_cidr`**: Allocates 65,536 private IP addresses (`10.0.0.0/16`) for cluster Pods, Nodes, and Load Balancers.

---

### C. `main.tf` (VPC & EKS Cluster Declarations)

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "jitsi-vpc"
  cidr = var.vpc_cidr

  azs             = ["ap-south-1a", "ap-south-1b"]
  private_subnets = ["10.0.3.0/24", "10.0.4.0/24"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb"                  = "1"
    "kubernetes.io/cluster/jitsi-eks-cluster" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"         = "1"
    "kubernetes.io/cluster/jitsi-eks-cluster" = "shared"
  }
}

```

#### Critical Subnet Tagging Explained:

* **`kubernetes.io/role/elb = 1`**: **Mandatory for Internet-Facing Load Balancers.** This explicitly tells the AWS Load Balancer Controller which subnets are public and allowed to host public Application Load Balancers (ALBs). Without this tag, ALB creation fails silently or stays in a blank `ADDRESS` state.
* **`kubernetes.io/role/internal-elb = 1`**: Marks subnets intended for internal-only AWS Network/Application Load Balancers.
* **`enable_nat_gateway = true`**: Allows EC2 worker nodes in private subnets to reach the internet (e.g., pulling Docker images) without exposing them to incoming internet traffic.
* **`single_nat_gateway = true`**: Cost-optimization flag. Uses 1 NAT Gateway instead of 1 per Availability Zone during development to reduce hourly AWS charges.

---

### D. EKS Cluster & Node Group Configuration

```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.28"

  cluster_endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    jitsi_nodes = {
      min_size     = 1
      max_size     = 3
      desired_size = 2

      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"
    }
  }
}

```

* **`cluster_version = "1.28"`**: Sets the Kubernetes control plane version.
* **`cluster_endpoint_public_access = true`**: Allows management via local `kubectl` and `helm` CLIs over the internet using secure IAM authentication.
* **`instance_types = ["t3.medium"]`**: Provides 2 vCPUs and 4GB RAM per node—sufficient CPU/RAM overhead for running the Jitsi web frontend, Prosody, Jicofo, and JVB SFU containers simultaneously.
* **`desired_size = 2`**: Deploys two worker nodes across multiple availability zones for high availability.

---

## 4. Terraform & EKS CLI Command Reference

### Standard Execution Lifecycle

```bash
# Initialize working directory and download provider modules
terraform init

# Validate configuration syntax and logical connections
terraform validate

# Generate and inspect an execution plan before applying
terraform plan

# Provision infrastructure automatically without manual prompts
terraform apply --auto-approve

# Destroy all managed infrastructure resources
terraform destroy --auto-approve

```

### Expected Output Example (`terraform apply`)

```text
Apply complete! Resources: 14 added, 0 changed, 0 destroyed.

Outputs:

cluster_endpoint = "https://A1B2C3D4E5F6.gr7.ap-south-1.eks.amazonaws.com"
cluster_name = "jitsi-eks-cluster"
vpc_id = "vpc-0123456789abcdef0"

```

---

## 5. Major Issues Encountered & Resolution Strategy

During infrastructure manipulation, the following critical state error was encountered during execution.

### The Issue: Terraform State Lock / Corrupted Lock File (`.terraform.tfstate.lock.info`)

#### Symptom & Error Log:

```text
Error: Error acquiring the state lock
Error message: Resource-attr-lock: State lock acquired by another process...
Lock Info:
  ID:        e4b8349a-5e72-4d92-850d-6178ef991c0e
  Path:      terraform.tfstate
  Operation: Operation Performing Apply

```

#### Root Cause Analysis (RCA):

This error occurs when a previous `terraform apply` command is abruptly interrupted (e.g., terminal window closed, network drop, or pressing `Ctrl+C` mid-execution). Terraform leaves behind a local lock file (`.terraform.tfstate.lock.info`) or holds an active lock ID to prevent concurrent writes from corrupting the state file.

#### Resolution Steps Executed:

**Step 1: Force Break the Lock File**

```bash
terraform force-unlock e4b8349a-5e72-4d92-850d-6178ef991c0e

```

* **Why this works:** Directly commands Terraform to release the specific lock ID from the state manager.

**Step 2: Clear Corrupted Local State Cache (Emergency Recovery)**
If `force-unlock` fails due to local cache corruption:

```bash
# Delete the local terraform lock cache file safely
rm -rf .terraform/ .terraform.lock.hcl

# Re-initialize the workspace to fetch fresh providers and rebuild state references
terraform init

```

* **Why this works:** Deleting `.terraform/` wipes broken local provider locks while preserving your actual `main.tf` code and `.tfstate` files. Re-running `terraform init` reconstructs a clean, synced workspace environment.

---

## 6. Security Governance: Files to Exclude from Git (`.gitignore`)

To ensure sensitive cloud credentials, private state files, and secrets are never leaked to public repositories, a strict `.gitignore` configuration must be maintained at the root of the project directory.

### Mandatory `.gitignore` File Contents:

```gitignore
# Local Terraform Directory
.terraform/

# Terraform State Files (Contains sensitive plain-text resource metadata, IP addresses, and tokens)
*.tfstate
*.tfstate.*
*.tfstate.backup

# Crash Logs & State Lock Files
*.log
.terraform.tfstate.lock.info

# Terraform Variable Overrides (May contain DB passwords, API keys, AWS keys)
*.tfvars
*.tfvars.json
override.tf
override.tf.json
*_override.tf
*_override.tf.json

# CLI Credentials & Environment Variable Overrides
.env
.env.local
aws-credentials.json
missing-alb-policy.json
fix-listener-policy.json

```

---

## 7. Phase Summary & Handoff Checkpoint

At the conclusion of Phase 2:

1. VPC `jitsi-vpc` was online with correct public subnet tagging for AWS ELB discovery.
2. EKS cluster `jitsi-eks-cluster` was active with 2 `t3.medium` worker nodes.
3. Local `kubectl` context was configured to communicate directly with the AWS control plane via:
```bash
aws eks update-kubeconfig --region ap-south-1 --name jitsi-eks-cluster

```


4. The cloud environment was verified ready for **Phase 3: Controller Setup, IAM Integration, Application Deployment & Ingress Routing**.