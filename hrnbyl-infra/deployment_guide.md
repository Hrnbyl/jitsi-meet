

# Phase 1 — Local Setup, Architecture & Observability

## Executive Summary

The first phase focused on establishing a fully functional local Jitsi Meet environment using Docker Compose. The objective was to understand the internal architecture of Jitsi, configure a development environment, validate service interactions, and analyze the signaling and media flow before migrating the platform to Kubernetes and AWS infrastructure. The implementation included repository management, local environment configuration, container orchestration, and protocol-level observability. 

---

# Local Development Environment

The local environment was built using Docker Compose to deploy the complete Jitsi Meet stack as independent microservices. The following tools were installed to support development and execution:

| Tool           | Purpose                              |
| -------------- | ------------------------------------ |
| Docker Engine  | Container runtime for Jitsi services |
| Docker Compose | Multi-container orchestration        |
| Git            | Source code and version control      |
| OpenSSL        | Secure credential generation         |

---

# Jitsi Microservice Architecture

The local deployment consisted of four primary services working together to establish video conferencing.

| Service                     | Responsibility                                                                                      |
| --------------------------- | --------------------------------------------------------------------------------------------------- |
| **Web**                     | Hosts the frontend application, serves static assets, and acts as the reverse proxy.                |
| **Prosody**                 | Provides XMPP signaling, authentication, chat messaging, and conference room management.            |
| **Jicofo**                  | Coordinates conference creation and negotiates media sessions between clients and the media bridge. |
| **Jitsi Videobridge (JVB)** | Acts as the Selective Forwarding Unit (SFU), forwarding media streams between participants.         |

The communication model consists of:

* HTTP/HTTPS for serving the web application.
* WebSocket-based XMPP signaling.
* WebRTC (SRTP) for encrypted media transport.
* COLIBRI2 protocol between Jicofo and JVB for bridge allocation. 

---

# Repository Configuration

A dual-remote Git workflow was configured to separate custom project development from the upstream open-source repository.

### Repository Initialization

```bash
git clone https://github.com/jitsi/docker-jitsi-meet.git hrnbyl-meet
cd hrnbyl-meet
```

### Remote Configuration

```bash
git remote rename origin upstream

git remote add origin https://github.com/YOUR-USERNAME/YOUR-PRIVATE-REPO.git

git remote -v
```

This configuration enables:

* **origin** → Private project repository
* **upstream** → Official Jitsi repository for future updates

Typical workflow:

```bash
git push origin master
git pull upstream master
```



---

# Environment Configuration

The local environment was initialized using Jitsi's default configuration template and secure credentials were generated automatically.

### Environment Initialization

```bash
cp env.example .env
```

### Generate Internal Passwords

```bash
./gen-passwords.sh
```

### Persistent Configuration Storage

```bash
mkdir -p ~/.jitsi-meet-cfg/{web,prosody,jicofo,jvb}
```

### Local Configuration

```ini
HTTP_PORT=8000
HTTPS_PORT=8443
TZ=UTC
PUBLIC_URL=https://localhost:8443
CONFIG=~/.jitsi-meet-cfg
```

These configurations define the local runtime environment, networking ports, persistent storage locations, and secure authentication credentials used by the Jitsi services. 

---

# SSL Configuration

Local execution uses automatically generated self-signed TLS certificates. During the first startup, the web container generates certificates and stores them under the persistent configuration directory.

Because the certificates are self-signed, browsers display a security warning (`NET::ERR_CERT_AUTHORITY_INVALID`) when accessing:

```
https://localhost:8443
```

The warning must be bypassed to allow secure WebRTC communication during local development. 

---

# Local Deployment

The Jitsi stack was deployed using Docker Compose.

```bash
docker compose up -d
```

Container status was verified using:

```bash
docker compose ps
```

A successful deployment results in all four core services (`web`, `prosody`, `jicofo`, and `jvb`) running in a healthy state. 

---

# Validation & Observability

Beyond verifying that the application loaded successfully, multiple protocol-level validation techniques were performed to confirm the correctness of the deployment.

### WebRTC Verification

Browser telemetry (`chrome://webrtc-internals`) confirmed:

* Successful ICE negotiation
* DTLS handshake establishment
* Continuous RTP media transmission
* Minimal packet loss and jitter
* Active inbound and outbound RTP streams
* Successful codec negotiation
* Valid ICE candidate pairing

### XMPP Signaling Verification

Using Chrome DevTools WebSocket inspection (`wss://localhost:8443/xmpp-websocket`), the following XMPP stanzas were observed:

* `<presence>` – Participant state synchronization
* `<message>` – Chat communication
* `<iq>` – Session control and bridge negotiation
* `<r>` / `<a>` – Stream management acknowledgements

These messages confirmed correct signaling between clients and the Prosody XMPP server.

### Jitsi Videobridge Verification

Real-time bridge activity was monitored using:

```bash
docker compose logs -f jvb
```

The logs confirmed:

* Conference allocation through the COLIBRI2 protocol
* Endpoint creation for connected participants
* Media source registration
* SFU-based media forwarding
* Stable bridge operation throughout active conferences

Together, these observations verified that both the signaling layer and media forwarding layer were operating correctly in the local environment. 

---
# Phase 2 — Infrastructure as Code (IaC) with Terraform & AWS EKS

## Executive Summary

The second phase focused on automating the cloud infrastructure required for deploying Jitsi Meet on AWS using **Terraform** and **eksctl**. The infrastructure was provisioned following Infrastructure as Code (IaC) principles, enabling repeatable, version-controlled deployments. This phase included creating a dedicated Virtual Private Cloud (VPC), deploying an Amazon Elastic Kubernetes Service (EKS) cluster, configuring networking for Kubernetes load balancers, integrating IAM Roles for Service Accounts (IRSA) through OpenID Connect (OIDC), and establishing Terraform operational and security best practices. 

---

# Infrastructure Architecture

The cloud infrastructure was designed following AWS EKS networking best practices to provide secure, scalable, and highly available Kubernetes networking.

### Network Layout

| Component                          | Configuration                |
| ---------------------------------- | ---------------------------- |
| **AWS Region**                     | `ap-south-1`                 |
| **VPC**                            | `10.0.0.0/16`                |
| **Public Subnets**                 | `10.0.1.0/24`, `10.0.2.0/24` |
| **Private Subnets**                | `10.0.3.0/24`, `10.0.4.0/24` |
| **Internet-facing Load Balancers** | Hosted in public subnets     |
| **Worker Nodes**                   | Hosted in private subnets    |
| **Amazon EKS Cluster**             | `jitsi-eks-cluster`          |

The networking architecture separates externally accessible resources from compute resources, ensuring Kubernetes worker nodes remain isolated while allowing public Application Load Balancers (ALBs) to expose services securely. 

---

# Terraform Project Structure

The infrastructure was organized into modular Terraform configuration files to improve readability, maintainability, and reusability.

| File             | Responsibility                                 |
| ---------------- | ---------------------------------------------- |
| **providers.tf** | Terraform and AWS provider configuration       |
| **variables.tf** | Configurable deployment parameters             |
| **main.tf**      | VPC, networking, and Amazon EKS infrastructure |
| **outputs.tf**   | Exported infrastructure outputs                |



---

# Provider Configuration

Terraform was configured to use the AWS provider with a minimum supported Terraform version.

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

The deployment targeted the **ap-south-1 (Mumbai)** AWS region, selected to reduce latency while maintaining compatibility with the project infrastructure. 

---

# Infrastructure Variables

The deployment parameters were centralized using Terraform variables.

| Variable       | Value               | Purpose                    |
| -------------- | ------------------- | -------------------------- |
| `aws_region`   | `ap-south-1`        | AWS deployment region      |
| `cluster_name` | `jitsi-eks-cluster` | Amazon EKS cluster name    |
| `vpc_cidr`     | `10.0.0.0/16`       | Base network address space |

Centralizing these values allows infrastructure to be modified without changing the core Terraform modules while ensuring consistency across Terraform, `eksctl`, and Kubernetes resources. 

---

# VPC Configuration

The VPC infrastructure was provisioned using the official AWS Terraform module.

Key configuration included:

* VPC name: `jitsi-vpc`
* CIDR block: `10.0.0.0/16`
* Two Availability Zones
* Two public subnets
* Two private subnets
* DNS hostname support
* Single NAT Gateway for development cost optimization

Public subnets were tagged with:

```text
kubernetes.io/role/elb = 1
kubernetes.io/cluster/jitsi-eks-cluster = shared
```

Private subnets were tagged with:

```text
kubernetes.io/role/internal-elb = 1
kubernetes.io/cluster/jitsi-eks-cluster = shared
```

These subnet tags enable the AWS Load Balancer Controller to automatically discover the correct subnets for public and internal Kubernetes services. Without these tags, Kubernetes cannot provision AWS load balancers successfully. 

---

# Amazon EKS Configuration

The Kubernetes cluster was deployed using the official Terraform EKS module.

| Configuration      | Value               |
| ------------------ | ------------------- |
| Cluster Name       | `jitsi-eks-cluster` |
| Kubernetes Version | `1.28`              |
| Endpoint Access    | Public              |
| Worker Nodes       | Managed Node Group  |
| Instance Type      | `t3.medium`         |
| Minimum Nodes      | 1                   |
| Desired Nodes      | 2                   |
| Maximum Nodes      | 3                   |

Worker nodes were deployed inside the private subnets while the Kubernetes control plane remained fully managed by AWS. Public endpoint access enabled secure cluster administration using `kubectl` and Helm from the local development environment. 

---

# Infrastructure Deployment

Terraform was used to provision and manage all cloud resources.

```bash
terraform init
```

Initializes the working directory and downloads required providers and modules.

```bash
terraform validate
```

Validates the Terraform configuration for syntax and logical consistency.

```bash
terraform plan
```

Generates an execution plan showing the infrastructure changes before deployment.

```bash
terraform apply --auto-approve
```

Creates the infrastructure automatically without interactive approval.

```bash
terraform destroy --auto-approve
```

Removes all Terraform-managed cloud resources when no longer required.

A successful deployment provisions the VPC, networking resources, Amazon EKS cluster, managed worker nodes, and outputs essential information such as the cluster endpoint and VPC identifier. 

---

# Operational Challenges

During infrastructure provisioning, Terraform encountered a state lock issue caused by an interrupted execution.

Typical error:

```text
Error acquiring the state lock
```

The lock was released using:

```bash
terraform force-unlock <LOCK_ID>
```

If the local Terraform cache became corrupted, recovery involved rebuilding the local working directory:

```bash
rm -rf .terraform/ .terraform.lock.hcl
terraform init
```

This process restores provider dependencies while preserving the infrastructure configuration and Terraform state. 

---

# Security & Version Control

Sensitive infrastructure files were excluded from version control using a dedicated `.gitignore` configuration.

Key exclusions included:

* `.terraform/`
* `*.tfstate`
* `*.tfstate.*`
* `.terraform.tfstate.lock.info`
* `*.tfvars`
* `override.tf`
* `.env`
* AWS credential files
* IAM policy files

Excluding these files prevents accidental exposure of infrastructure state, cloud credentials, resource metadata, and sensitive configuration values in public repositories. 

---

# Infrastructure Verification

Following successful deployment, the Kubernetes configuration was updated to allow local administration of the Amazon EKS cluster.

```bash
aws eks update-kubeconfig --region ap-south-1 --name jitsi-eks-cluster
```

At the completion of this phase:

* A dedicated VPC (`jitsi-vpc`) was successfully provisioned.
* Public and private subnets were configured with the required Kubernetes discovery tags.
* The Amazon EKS cluster (`jitsi-eks-cluster`) was deployed and operational.
* Two managed `t3.medium` worker nodes were available for workload deployment.
* Local `kubectl` access to the Kubernetes control plane was successfully established.

The infrastructure was fully prepared for the next phase involving IAM integration, AWS Load Balancer Controller deployment, and application deployment onto Kubernetes. 

Here is a comprehensive, production-grade deployment document capturing your post-Terraform setup, permission consolidation, networking manifests, custom domain integration, and troubleshooting history.

---

# Production Deployment Guide: Jitsi Meet on AWS EKS with Custom Domain & HTTPS

## 1. Prerequisites & Terraform Baseline (Phase 2 Output)

This guide picks up immediately after running `terraform apply` inside the `/terraform` directory. At this stage, the static infrastructure exists:

* **VPC:** 2 Public Subnets, 2 Private Subnets.
* **EKS Cluster:** Operational control plane (`jitsi-eks-cluster`) and 4 active EC2 worker nodes.
* **Subnet Tags:** Public subnets tagged with `kubernetes.io/role/elb = 1`.

---

## 2. Infrastructure Artifact Consolidation

To maintain a clean DevOps repository, multiple scattered policy JSONs and Kubernetes manifests were consolidated into single master files.

### Master IAM Policy (`iam_policy.json`)

Combines base AWS Load Balancer Controller permissions, missing EC2 VPC security group query rights, and listener attribute permissions into a single file placed in the root directory.

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "iam:CreateServiceLinkedRole"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "iam:AWSServiceName": "elasticloadbalancing.amazonaws.com"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeAccountAttributes",
                "ec2:DescribeAddresses",
                "ec2:DescribeAvailabilityZones",
                "ec2:DescribeInternetGateways",
                "ec2:DescribeVpcs",
                "ec2:DescribeVpcPeeringConnections",
                "ec2:DescribeSubnets",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeInstances",
                "ec2:DescribeNetworkInterfaces",
                "ec2:DescribeTags",
                "ec2:GetCoipPoolUsage",
                "ec2:DescribeCoipPools",
                "ec2:GetSecurityGroupsForVpc",
                "elasticloadbalancing:DescribeLoadBalancers",
                "elasticloadbalancing:DescribeLoadBalancerAttributes",
                "elasticloadbalancing:DescribeListeners",
                "elasticloadbalancing:DescribeListenerAttributes",
                "elasticloadbalancing:DescribeListenerCertificates",
                "elasticloadbalancing:DescribeSSLPolicies",
                "elasticloadbalancing:DescribeRules",
                "elasticloadbalancing:DescribeTargetGroups",
                "elasticloadbalancing:DescribeTargetGroupAttributes",
                "elasticloadbalancing:DescribeTargetHealth",
                "elasticloadbalancing:DescribeTags",
                "elasticloadbalancing:DescribeTrustStores"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "cognito-idp:DescribeUserPoolClient",
                "acm:ListCertificates",
                "acm:DescribeCertificate",
                "iam:ListServerCertificates",
                "iam:GetServerCertificate",
                "waf-regional:GetWebACL",
                "waf-regional:GetWebACLForResource",
                "waf-regional:AssociateWebACL",
                "waf-regional:DisassociateWebACL",
                "wafv2:GetWebACL",
                "wafv2:GetWebACLForResource",
                "wafv2:AssociateWebACL",
                "wafv2:DisassociateWebACL",
                "shield:GetSubscriptionState",
                "shield:DescribeProtection",
                "shield:CreateProtection",
                "shield:DeleteProtection"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:AuthorizeSecurityGroupIngress",
                "ec2:RevokeSecurityGroupIngress"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateSecurityGroup"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateTags"
            ],
            "Resource": "arn:aws:ec2:*:*:security-group/*",
            "Condition": {
                "StringEquals": {
                    "ec2:CreateAction": "CreateSecurityGroup"
                },
                "Null": {
                    "aws:RequestTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateTags",
                "ec2:DeleteTags"
            ],
            "Resource": "arn:aws:ec2:*:*:security-group/*",
            "Condition": {
                "Null": {
                    "aws:RequestTag/elbv2.k8s.aws/cluster": "true",
                    "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:AuthorizeSecurityGroupIngress",
                "ec2:RevokeSecurityGroupIngress",
                "ec2:DeleteSecurityGroup"
            ],
            "Resource": "*",
            "Condition": {
                "Null": {
                    "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:CreateLoadBalancer",
                "elasticloadbalancing:CreateTargetGroup"
            ],
            "Resource": "*",
            "Condition": {
                "Null": {
                    "aws:RequestTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:CreateListener",
                "elasticloadbalancing:DeleteListener",
                "elasticloadbalancing:CreateRule",
                "elasticloadbalancing:DeleteRule"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:AddTags",
                "elasticloadbalancing:RemoveTags"
            ],
            "Resource": [
                "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
                "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
                "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
            ],
            "Condition": {
                "Null": {
                    "aws:RequestTag/elbv2.k8s.aws/cluster": "true",
                    "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:AddTags",
                "elasticloadbalancing:RemoveTags"
            ],
            "Resource": [
                "arn:aws:elasticloadbalancing:*:*:listener/net/*/*/*",
                "arn:aws:elasticloadbalancing:*:*:listener/app/*/*/*",
                "arn:aws:elasticloadbalancing:*:*:listener-rule/net/*/*/*",
                "arn:aws:elasticloadbalancing:*:*:listener-rule/app/*/*/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:ModifyLoadBalancerAttributes",
                "elasticloadbalancing:SetIpAddressType",
                "elasticloadbalancing:SetSecurityGroups",
                "elasticloadbalancing:SetSubnets",
                "elasticloadbalancing:DeleteLoadBalancer",
                "elasticloadbalancing:ModifyTargetGroup",
                "elasticloadbalancing:ModifyTargetGroupAttributes",
                "elasticloadbalancing:DeleteTargetGroup"
            ],
            "Resource": "*",
            "Condition": {
                "Null": {
                    "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:AddTags"
            ],
            "Resource": [
                "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
                "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
                "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
            ],
            "Condition": {
                "StringEquals": {
                    "elasticloadbalancing:CreateAction": [
                        "CreateTargetGroup",
                        "CreateLoadBalancer"
                    ]
                },
                "Null": {
                    "aws:RequestTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:RegisterTargets",
                "elasticloadbalancing:DeregisterTargets"
            ],
            "Resource": "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:SetWebAcl",
                "elasticloadbalancing:ModifyListener",
                "elasticloadbalancing:AddListenerCertificates",
                "elasticloadbalancing:RemoveListenerCertificates",
                "elasticloadbalancing:ModifyRule"
            ],
            "Resource": "*"
        }
    ]
}

```

---

### Consolidated Kubernetes Manifest (`jitsi-networking.yaml`)

Combines the Network Load Balancer (NLB for UDP 10000 media streams) and Application Load Balancer (ALB for HTTPS web UI traffic) into a single document via `---`.

```yaml
# =========================================================
# 1. Network Load Balancer (NLB) for JVB (UDP Port 10000)
# =========================================================
apiVersion: v1
kind: Service
metadata:
  name: jitsi-jvb-nlb
  namespace: jitsi
  annotations:
    service.k8s.aws/type: "nlb"
    service.k8s.aws/nlb-target-type: "ip"
    service.k8s.aws/scheme: "internet-facing"
spec:
  type: LoadBalancer
  selector:
    app.kubernetes.io/name: jitsi-meet
    app.kubernetes.io/component: jvb
  ports:
    - name: jvb-udp
      port: 10000
      targetPort: 10000
      protocol: UDP

---
# =========================================================
# 2. Application Load Balancer (ALB) for Web UI & WebSockets
# =========================================================
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: jitsi-ingress
  namespace: jitsi
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: '443'
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:ap-south-1:444455570206:certificate/4ec194f1-f597-4fde-bc33-04f84959a2a3
spec:
  ingressClassName: alb
  rules:
    - host: hrnbyl.rahulbastia.tech
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: jitsi-jitsi-meet-web
                port:
                  number: 80

```

---

## 3. End-to-End Execution Sequence

### Step 1: Connect Terminal to EKS

```bash
# Executed inside /terraform folder or root
aws eks update-kubeconfig --region ap-south-1 --name jitsi-eks-cluster
kubectl get nodes

```

### Step 2: Establish Security Context (IRSA)

```bash
# Executed in root directory containing iam_policy.json
POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName=='AWSLoadBalancerControllerIAMPolicy'].Arn" --output text)

# If policy does not exist, create it:
# POLICY_ARN=$(aws iam create-policy --policy-name AWSLoadBalancerControllerIAMPolicy --policy-document file://iam_policy.json --query "Policy.Arn" --output text)

eksctl create iamserviceaccount \
  --cluster=jitsi-eks-cluster \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn=$POLICY_ARN \
  --approve \
  --override-existing-serviceaccounts

```

### Step 3: Deploy AWS Load Balancer Controller via Helm

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=jitsi-eks-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

```

### Step 4: Provision ACM SSL Certificate & Configure DNS

```bash
# Request Public SSL Certificate
aws acm request-certificate \
    --domain-name hrnbyl.rahulbastia.tech \
    --validation-method DNS \
    --region ap-south-1

```

1. Fetch validation records via `aws acm describe-certificate`.
2. Navigate to Domain Provider (e.g., Hostinger/GoDaddy) and add **CNAME Record 1** for SSL validation (`_d1ea5dd0...`).
3. Verify status changes to `"ISSUED"`.

### Step 5: Deploy Application Stack & Apply Networking

```bash
# Install Jitsi Stack
helm repo add jitsi https://jitsi-contrib.github.io/jitsi-helm/
helm repo update

helm install jitsi jitsi/jitsi-meet \
  -n jitsi --create-namespace \
  --set publicURL=https://hrnbyl.rahulbastia.tech

# Provision ALB and NLB
kubectl apply -f jitsi-networking.yaml

```

### Step 6: Map Custom Domain CNAME

Fetch the newly provisioned ALB DNS address:

```bash
kubectl get ingress -n jitsi

```

In your Domain DNS Dashboard, create **CNAME Record 2**:

* **Host:** `hrnbyl`
* **Points to:** `k8s-jitsi-jitsiing-ca12b0ba1d-24248817.ap-south-1.elb.amazonaws.com`

---

## 4. Issues Encountered & Resolution Matrix

| Issue Encountered | Root Cause | Diagnosis Command Used | Resolution Applied |
| --- | --- | --- | --- |
| **`EntityAlreadyExists` during policy creation** | Policy name existed from a prior execution attempt. | `aws iam list-policies` | Queried existing policy ARN and applied `aws iam create-policy-version --set-as-default` to update it. |
| **`INSTALLATION FAILED: publicURL must be set`** | Jitsi Helm chart requires explicit domain definition for config map rendering. | `helm install` stdout | Appended `--set publicURL=[https://hrnbyl.rahulbastia.tech](https://hrnbyl.rahulbastia.tech)` to bypass chart validation guardrails. |
| **"WebRTC is not available in your browser"** | Browsers block camera/microphone API access over unencrypted HTTP (`http://`). | Browser DevTools / Inspection | Configured AWS ACM SSL Certificate on Port 443 (HTTPS) via ALB annotations to enforce encrypted transport. |
| **Cluster subnet leak on `terraform destroy**` | Kubernetes created external AWS resources (ALB/NLB) outside of Terraform state management. | `terraform destroy` timeout | Executed `kubectl delete -f jitsi-networking.yaml` *before* destroying Terraform resources. |

---

## 5. Environment Teardown & Reconstruction Playbook

### Clean Teardown Procedure (Cost Saving)

```bash
# Step 1: Remove K8s Load Balancers (Frees AWS Subnets)
kubectl delete -f jitsi-networking.yaml

# Step 2: Destroy Static Infrastructure
cd terraform
terraform destroy --auto-approve

```

### Full Cold Reconstruction Procedure

```bash
# 1. Provision Core AWS Resources
cd terraform
terraform apply --auto-approve

# 2. Sync Kubeconfig
aws eks update-kubeconfig --region ap-south-1 --name jitsi-eks-cluster

# 3. Attach Service Account to Existing Policy
cd ..
POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName=='AWSLoadBalancerControllerIAMPolicy'].Arn" --output text)

eksctl create iamserviceaccount \
  --cluster=jitsi-eks-cluster \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn=$POLICY_ARN \
  --approve \
  --override-existing-serviceaccounts

# 4. Deploy Controllers & Application
helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --set clusterName=jitsi-eks-cluster --set serviceAccount.create=false --set serviceAccount.name=aws-load-balancer-controller
helm install jitsi jitsi/jitsi-meet -n jitsi --create-namespace --set publicURL=https://hrnbyl.rahulbastia.tech
kubectl apply -f jitsi-networking.yaml

# 5. Update CNAME Record
kubectl get ingress -n jitsi
# Point hrnbyl.rahulbastia.tech CNAME to the NEW address listed under ADDRESS.

```
