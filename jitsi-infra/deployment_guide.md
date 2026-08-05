# Deployment Guide

> Production deployment procedures for **Jitsi Meet Video Conferencing Platform** (`hrnbyl-meet`) to **AWS EKS Production Environment**.

---

## Template Metadata

| Field | Details |
| --- | --- |
| Category | Engineering / DevOps |
| Owner | Rahul Bastia (DevOps Lead) |
| Version | 1.0.0 |
| Effective Date | August 5, 2026 |
| Review Cycle | Quarterly / Event-based |
| Status | Approved |

---

## Overview

This document outlines the end-to-end production deployment of the multi-container **Jitsi Meet Video Conferencing Platform** onto Amazon Elastic Kubernetes Service (EKS).

| Item | Details | Owner | Status |
| --- | --- | --- | --- |
| Project Name | `hrnbyl-meet` / Jitsi Infrastructure | Rahul Bastia | Complete |
| Deployment Objective | Deploy scalable, containerized Jitsi Meet stack (Web, Prosody, Jicofo, JVB) on EKS with automated ingress and UDP video routing. | DevOps Team | Complete |
| Cloud Provider | Amazon Web Services (AWS) | Cloud Engineering | Complete |
| AWS Region | `ap-south-1` (Mumbai) | Cloud Engineering | Complete |
| AWS Account ID | `444455570206` | Cloud Engineering | Complete |
| Target Environment | Production (`jitsi` namespace) | DevOps Team | Complete |
| Primary Domain | `hrnbyl.rahulbastia.tech` | Platform Team | Complete |
| Root Hosted Zone | `rahulbastia.tech` (AWS Route 53) | Infrastructure Team | Complete |
| EKS Cluster Name | `jitsi-eks-cluster` | Infrastructure Team | Complete |
| VPC ID | `vpc-0d5d84bf2446a250a` | Infrastructure Team | Complete |
| ACM Certificate ARN | `arn:aws:acm:ap-south-1:444455570206:certificate/4ec194f1-f597-4fde-bc33-04f84959a2a3` | Security Team | Complete |
| Container Registry | Docker Hub (`docker.io/jitsi/*`) | Platform Team | Complete |

### Architecture Overview

```
                                [ Internet Users ]
                                        │
                         ┌──────────────┴──────────────┐
                         ▼                             ▼
              [ HTTPS Traffic (443) ]        [ UDP Video Streams (10000) ]
                         │                             │
                         ▼                             ▼
            [ AWS Application LB (ALB) ]   [ AWS Network LB (NLB) ]
                         │                             │
                         ▼                             ▼
             [ Kubernetes ALB Ingress ]    [ Service: jitsi-jvb ]
                         │                             │
                         ▼                             ▼
              [ Service: jitsi-meet-web ]   [ Pods: jitsi-jvb ]
                         │                             ▲
                         ▼                             │
               [ Pods: jitsi-web ] ────────────────────┤
                         │                             │
                         ▼                             │
             [ Service: jitsi-prosody ] ───────────────┼────────┐
                   │           ▲                       │        │
                   │           └───────────────────────┘        │
                   ▼                                            ▼
          [ Pods: jitsi-prosody ] ◄─────────────────── [ Pods: jitsi-jicofo ]
          (XMPP Ports: 5222, 5347)

```

#### Component Tier Breakdown

1. **Jitsi Web UI (`jitsi/web:stable`):** Nginx-based frontend serving the web application and proxying internal XMPP BOSH/WebSocket connections. Exposed internally via `ClusterIP` on Port 80 and externally via AWS Application Load Balancer (ALB).
2. **Jitsi Prosody (`jitsi/prosody:stable`):** XMPP Communication Server managing client authentication, chat rooms, and signaling. Listens on Port `5222` (client connections) and Port `5347` (internal service components).
3. **Jitsi Jicofo (`jitsi/jicofo:stable`):** Focus component that orchestrates video sessions and allocates videobridge instances. Operates purely as an outbound client connecting to Prosody over Port `5347`.
4. **Jitsi Videobridge / JVB (`jitsi/jvb:stable`):** WebRTC media server handling live audio/video packet routing over UDP Port `10000`. Exposed externally via AWS Network Load Balancer (NLB).

---

## Prerequisites

Required credentials, tools, and access privileges prior to deployment execution.

| Item | Details | Owner | Status |
| --- | --- | --- | --- |
| AWS CLI | Installed and configured with `AdministratorAccess` in `ap-south-1`. | DevOps | Complete |
| `kubectl` CLI | Installed and configured to manage EKS Kubernetes resources. | DevOps | Complete |
| `helm` CLI | Version 3.x installed for Helm chart installation and template rendering. | DevOps | Complete |
| `eksctl` CLI | Installed for IAM OpenID Connect (OIDC) association and IRSA binding. | DevOps | Complete |
| Terraform | Installed (Version: Not Available in Source Conversation). | Infrastructure | Complete |
| Docker | Installed (Version: Not Available in Source Conversation). | DevOps | Complete |
| Git Repository | Repository: Not Available in Source Conversation | Branch: Not Available in Source Conversation | DevOps | Complete |
| Domain Ownership | Management access to domain registrar for `rahulbastia.tech`. | Platform Lead | Complete |

---

## Pre-Deployment Checklist

Items verified prior to executing application deployment to EKS.

| Item | Details | Owner | Status |
| --- | --- | --- | --- |
| EKS Infrastructure | EKS Cluster `jitsi-eks-cluster` provisioned via Terraform and active in `vpc-0d5d84bf2446a250a`. | Infra Team | Complete |
| Kubeconfig Context | `kubectl` context successfully pointed to `jitsi-eks-cluster`. | DevOps | Complete |
| Target Namespace | Dedicated `jitsi` namespace created inside the EKS cluster. | DevOps | Complete |
| ACM SSL Certificate | Active SSL/TLS certificate issued in AWS ACM for `*.rahulbastia.tech` / `hrnbyl.rahulbastia.tech`. | Security | Complete |
| Container Image Tags | Container image tags updated from `:latest` to official `:stable` releases. | DevOps | Complete |
| Helm Values Config | Helm `values.yaml` updated with ACM ARN, domain name, and XMPP shared secrets. | DevOps | Complete |

---

## Deployment Steps

Detailed, chronological procedures to deploy the infrastructure and platform components.

### Step 1: Cluster Authentication & Workspace Initialization

* **Purpose:** Connect local administration tools (`kubectl`, `helm`) to the AWS EKS cluster and prepare the dedicated Kubernetes namespace.
* **Commands:**
```bash
# 1. Update kubeconfig for EKS Cluster
aws eks update-kubeconfig --region ap-south-1 --name jitsi-eks-cluster

# 2. Verify cluster access
kubectl get nodes

# 3. Create dedicated namespace for Jitsi workloads
kubectl create namespace jitsi

```


* **Expected Output:**
```text
Updated context arn:aws:eks:ap-south-1:444455570206:cluster/jitsi-eks-cluster in /home/user/.kube/config
NAME                                       STATUS   ROLES    AGE
ip-10-0-2-92.ap-south-1.compute.internal   Ready    <none>   32m
ip-10-0-3-223.ap-south-1.compute.internal  Ready    <none>   32m
namespace/jitsi created

```


* **Explanation:** `update-kubeconfig` downloads cluster credentials and sets up the local `kubectl` context. Creating a isolated namespace isolates Jitsi resources from cluster system services.
* **Verification:** Run `kubectl get ns` to verify the `jitsi` namespace is in `Active` status.
* **Common Failures:** AWS IAM access denied due to expired AWS CLI credentials or incorrect region.
* **Recovery Procedure:** Re-authenticate via `aws configure` or refresh AWS SSO tokens.

---

### Step 2: Configure Helm Values and Authentication Secrets

* **Purpose:** Define global parameters, image versions, networking ports, and internal XMPP shared secrets in `helm/jitsi-chart/values.yaml`.
* **Configuration Specification (`values.yaml`):**
```yaml
# ==============================================================================
# GLOBAL CONFIGURATION
# ==============================================================================
domain: hrnbyl.rahulbastia.tech
certificateArn: "arn:aws:acm:ap-south-1:444455570206:certificate/4ec194f1-f597-4fde-bc33-04f84959a2a3"

# ==============================================================================
# NETWORKING
# ==============================================================================
networking:
  jvbUdpPort: 10000

# ==============================================================================
# IMAGE REPOSITORIES (Using official :stable tags)
# ==============================================================================
images:
  web: jitsi/web:stable
  prosody: jitsi/prosody:stable
  jicofo: jitsi/jicofo:stable
  jvb: jitsi/jvb:stable

# ==============================================================================
# JITSI XMPP AUTHENTICATION SECRETS
# ==============================================================================
jitsiSecrets:
  jicofoComponentSecret: "JicofoSecret123!"
  jicofoAuthPassword: "JicofoAuthPassword123!"
  jvbAuthPassword: "JvbAuthPassword123!"

xmpp:
  authDomain: "auth.meet.jitsi"
  mucDomain: "muc.meet.jitsi"
  internalMucDomain: "internal-muc.meet.jitsi"

```


* **Explanation:** Jitsi containers require shared secrets across Prosody, Jicofo, and JVB to establish trust over XMPP. Official `:stable` image tags are specified because Docker Hub does not publish `:latest` tags for Jitsi images.

---

### Step 3: Configure AWS IAM Permissions & Install AWS Load Balancer Controller

* **Purpose:** Create a unified IAM policy combining AWS Load Balancer Controller and Route 53 permissions, link it to EKS via IAM Roles for Service Accounts (IRSA), and install the controller via Helm.
* **Policy Document (`terraform/iam_policy.json`):**
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
        },
        {
            "Effect": "Allow",
            "Action": [
                "route53:ChangeResourceRecordSets"
            ],
            "Resource": [
                "arn:aws:route53:::hostedzone/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "route53:ListHostedZones",
                "route53:ListResourceRecordSets"
            ],
            "Resource": [
                "*"
            ]
        }
    ]
}

```


* **Commands:**
```bash
# 1. Create the IAM Policy in AWS
aws iam create-policy \
    --policy-name EKS_Combined_ALB_Route53_Policy \
    --policy-document file://terraform/iam_policy.json

# 2. Associate OIDC Provider with EKS Cluster
eksctl utils associate-iam-oidc-provider \
    --region=ap-south-1 \
    --cluster=jitsi-eks-cluster \
    --approve

# 3. Create ServiceAccount with IRSA role binding
eksctl create iamserviceaccount \
  --cluster=jitsi-eks-cluster \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn=arn:aws:iam::444455570206:policy/EKS_Combined_ALB_Route53_Policy \
  --approve \
  --override-existing-serviceaccounts

# 4. Add EKS Helm repository and install AWS Load Balancer Controller
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=jitsi-eks-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

# 5. Restart Deployment to pick up IAM credentials
kubectl rollout restart deployment aws-load-balancer-controller -n kube-system

```


* **Expected Output:** `aws-load-balancer-controller` pods transition to `1/1 Running` state in `kube-system`.
* **Explanation:** EKS pods do not have AWS API access by default. IRSA attaches an IAM Role to a Kubernetes ServiceAccount using OIDC, giving the controller permissions to provision ALBs and NLBs in AWS.

---

### Step 4: Deploy Jitsi Meet Helm Chart

* **Purpose:** Template and deploy all Jitsi applications (`web`, `prosody`, `jicofo`, `jvb`), Services, and ALB Ingress to the `jitsi` namespace.
* **Commands:**
```bash
# 1. Navigate to Helm chart root directory
cd ~/Desktop/hrnbyl/hrnbyl-meet/jitsi-infra/helm

# 2. Dry-run template generation to verify variable injection
helm template jitsi-release ./jitsi-chart

# 3. Install the Helm release
helm install jitsi-release ./jitsi-chart -n jitsi

```


* **Verification Command:**
```bash
kubectl get pods,svc,ingress -n jitsi

```


* **Expected Output:**
```text
NAME                                 READY   STATUS    RESTARTS   AGE
pod/jitsi-jicofo-79f46ddd45-stlms    1/1     Running   0          2m
pod/jitsi-jvb-77c4f5c565-brvnn        1/1     Running   0          2m
pod/jitsi-jvb-77c4f5c565-gcgwx        1/1     Running   0          2m
pod/jitsi-prosody-6fd9697664-l8w68    1/1     Running   0          2m
pod/jitsi-web-574796b799-6rxjb        1/1     Running   0          2m

NAME                      TYPE           CLUSTER-IP       EXTERNAL-IP                                       PORT(S)
service/jitsi-jvb         LoadBalancer   172.20.168.252   k8s-jitsi-jitsijvb-xxx.elb.ap-south-1.amazonaws.com 10000:31585/UDP
service/jitsi-meet-web    ClusterIP      172.20.241.171   <none>                                            80/TCP
service/jitsi-prosody     ClusterIP      172.20.178.78    <none>                                            5222/TCP,5347/TCP

NAME                                      CLASS   HOSTS                     ADDRESS                                           PORTS
ingress.networking.k8s.io/jitsi-ingress   alb     hrnbyl.rahulbastia.tech   k8s-jitsi-jitsiing-ca12b0ba1d-1019588070...      80

```



---

### Step 5: Configure Route 53 & Registrar DNS Delegation

* **Purpose:** Delegate domain management from registrar (`manage.get.tech`) to AWS Route 53 and map `hrnbyl.rahulbastia.tech` to the ALB endpoint.
* **Commands & Configuration Steps:**
**1. Create Public Hosted Zone in AWS Route 53:**
```bash
aws route53 create-hosted-zone --name rahulbastia.tech --caller-reference $(date +%s)

```


**2. Update Name Servers at Domain Registrar (`.tech` Portal):**
Retrieve the 4 assigned AWS Name Servers from Route 53 NS record:
* `ns-1436.awsdns-51.org`
* `ns-1557.awsdns-02.co.uk`
* `ns-497.awsdns-62.com`
* `ns-687.awsdns-21.net`


Set the custom Name Servers in registrar dashboard under `rahulbastia.tech` $\rightarrow$ **Nameservers**.
**3. Create Route 53 CNAME Record:**
* **Record Name:** `hrnbyl`
* **Record Type:** `CNAME`
* **Target Value:** `k8s-jitsi-jitsiing-ca12b0ba1d-1019588070.ap-south-1.elb.amazonaws.com`
* **TTL:** `300`



---

## Troubleshooting & Root Cause Analysis

A summary of issues encountered during deployment, root cause analyses, diagnostic steps, and resolutions.

### Incident 1: Pods Stuck in `ImagePullBackOff`

* **Problem:** All Jitsi pods (`web`, `prosody`, `jicofo`, `jvb`) remained in `0/1 Pending` / `ImagePullBackOff` status.
* **Root Cause:** Helm configuration specified image tag `:latest` (e.g., `jitsi/web:latest`). Jitsi maintainers do not publish `:latest` tags on Docker Hub; they publish under the tag `:stable`.
* **Diagnosis:**
```bash
kubectl describe pod -l app=jitsi-web -n jitsi

```


*Output:* `Failed to pull image "jitsi/web:latest": rpc error: code = NotFound desc = failed to pull and unpack image "docker.io/jitsi/web:latest": not found`
* **Resolution:** Updated `values.yaml` image tags to `:stable` and executed `helm upgrade jitsi-release ./jitsi-chart -n jitsi`.

---

### Incident 2: Pods Crashing in `CrashLoopBackOff`

* **Problem:** `jitsi-web` was running (`1/1`), but `prosody`, `jicofo`, and `jvb` pods entered `CrashLoopBackOff`.
* **Root Cause:** Missing XMPP authentication variables (`JICOFO_COMPONENT_SECRET`, `JICOFO_AUTH_PASSWORD`, `JVB_AUTH_PASSWORD`, and XMPP internal domain configurations).
* **Diagnosis:**
```bash
kubectl logs -l app=jitsi-prosody -n jitsi --tail=30

```


* **Resolution:** Added `jitsiSecrets` and `xmpp` domains to `values.yaml` and injected corresponding `env` variables into deployment templates for Prosody, Jicofo, and JVB.

---

### Incident 3: ALB Address Remaining Blank & JVB Service `<pending>`

* **Problem:** Ingress showed no `ADDRESS` and `service/jitsi-jvb` remained in `<pending>` state indefinitely.
* **Root Cause:** The `aws-load-balancer-controller` was not installed in `kube-system`.
* **Diagnosis:**
```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

```


*Output:* `No resources found in kube-system namespace.`
* **Resolution:** Installed `aws-load-balancer-controller` via Helm in the `kube-system` namespace.

---

### Incident 4: Load Balancer Controller `403 AccessDenied` Error

* **Problem:** Even after installing the controller, Load Balancers failed to provision in AWS.
* **Root Cause:** The controller ServiceAccount lacked IAM permissions (`elasticloadbalancing:DescribeLoadBalancers`) to interact with AWS ELB APIs.
* **Diagnosis:**
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=50

```


*Output:* `api error AccessDenied: User: arn:aws:sts::444455570206:assumed-role/jitsi_nodes... is not authorized to perform: elasticloadbalancing:DescribeLoadBalancers`
* **Resolution:** Created unified IAM policy `EKS_Combined_ALB_Route53_Policy`, associated OIDC provider with EKS, attached IRSA role via `eksctl`, and restarted controller pods.

---

### Incident 5: Web UI Displaying "Connection Error" Warning

* **Problem:** Accessing `[https://hrnbyl.rahulbastia.tech](https://hrnbyl.rahulbastia.tech)` loaded the yellow Jitsi warning triangle reading "Connection error: Your device may be offline or our servers may be experiencing problems."
* **Root Cause:** The `jitsi-web` deployment template only passed `PUBLIC_URL`. Nginx inside the web container lacked internal proxy routing variables (`XMPP_SERVER`, `XMPP_BOSH_URL_BASE`, XMPP domains) required to forward BOSH/WebSocket connections to Prosody.
* **Diagnosis:** Inspected `web-deployment.yaml` environment block; identified missing Prosody proxy endpoints.
* **Resolution:** Updated `jitsi-chart/templates/web-deployment.yaml` with required XMPP environment variables:
```yaml
- name: XMPP_SERVER
  value: "jitsi-prosody"
- name: XMPP_DOMAIN
  value: {{ .Values.domain }}
- name: XMPP_AUTH_DOMAIN
  value: {{ .Values.xmpp.authDomain }}
- name: XMPP_MUC_DOMAIN
  value: {{ .Values.xmpp.mucDomain }}
- name: XMPP_INTERNAL_MUC_DOMAIN
  value: {{ .Values.xmpp.internalMucDomain }}
- name: XMPP_BOSH_URL_BASE
  value: "http://jitsi-prosody:5222"

```


Applied upgrade using `helm upgrade jitsi-release ./jitsi-chart -n jitsi` and restarted the deployment.

---

## Deployment Timeline

```
Infrastructure Creation (Terraform)
  └─► EKS Cluster & VPC Active (`jitsi-eks-cluster`)
        └─► Namespace Setup (`kubectl create namespace jitsi`)
              └─► Helm Chart Deployment (Failed: ImagePullBackOff)
                    └─► Fix: Switch image tags from :latest to :stable
                          └─► XMPP Pod Crash (Fix: Inject XMPP Secrets)
                                └─► AWS ALB Pending (Fix: Install AWS Load Balancer Controller)
                                      └─► 403 AccessDenied (Fix: Configure IRSA & IAM Policy)
                                            └─► Route 53 Hosted Zone & NS Delegation
                                                  └─► Web Connection Error (Fix: Add XMPP BOSH URLs to Web)
                                                        └─► Production Ready (200 OK)

```

---

## Command Reference

### Terraform & Infrastructure

```bash
# View Terraform outputs
terraform output
terraform output cluster_name

```

### AWS CLI

```bash
# Update local Kubeconfig
aws eks update-kubeconfig --region ap-south-1 --name jitsi-eks-cluster

# List ACM certificates
aws acm list-certificates --region ap-south-1

# Create IAM Policy
aws iam create-policy --policy-name EKS_Combined_ALB_Route53_Policy --policy-document file://iam_policy.json

# Create Route 53 Hosted Zone
aws route53 create-hosted-zone --name rahulbastia.tech --caller-reference $(date +%s)

```

### Kubernetes (`kubectl`)

```bash
# Pod & Deployment status
kubectl get pods -n jitsi -w
kubectl get ingress,svc -n jitsi
kubectl describe pod -l app=jitsi-web -n jitsi

# Service logs
kubectl logs -l app=jitsi-web -n jitsi --tail=50
kubectl logs -l app=jitsi-prosody -n jitsi --tail=50
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=50

# Restarts
kubectl rollout restart deployment jitsi-web -n jitsi
kubectl rollout restart deployment aws-load-balancer-controller -n kube-system

```

### Helm

```bash
# Template dry-run & install
helm template jitsi-release ./jitsi-chart
helm install jitsi-release ./jitsi-chart -n jitsi
helm upgrade jitsi-release ./jitsi-chart -n jitsi
helm get values jitsi-release -n jitsi

```

### DNS & Verification

```bash
# Query Cloudflare Public DNS directly
dig @1.1.1.1 hrnbyl.rahulbastia.tech CNAME +short

# Flush local Linux DNS resolver cache
sudo systemctl restart systemd-resolved

```

---

## Best Practices

1. **IRSA (IAM Roles for Service Accounts):** Avoid granting broad IAM permissions to underlying EC2 worker node roles. Use OIDC identity providers to bind minimal IAM policies to specific Kubernetes ServiceAccounts.
2. **Explicit Image Tagging:** Never use `:latest` tags in production Helm charts. Immutable, explicit tags like `:stable` or specific version commit hashes prevent breaking changes during pod restarts.
3. **Decoupled Architecture:** Separate ingress controllers (ALB for Layer 7 HTTPS) from streaming endpoints (NLB for Layer 4 UDP video) to optimize network throughput and SSL termination.
4. **Environment Isolation:** Use distinct namespaces (`jitsi`, `kube-system`) to isolate application workloads from cluster management controllers.

---

## Smoke Tests

Post-deployment verification procedures to confirm system integrity.

| Test Case | Command / Action | Expected Result | Status |
| --- | --- | --- | --- |
| Pod Health | `kubectl get pods -n jitsi` | All 5 pods (`web`, `prosody`, `jicofo`, `jvb` x2) show `1/1 Running`. | Passed |
| Ingress Health | `kubectl get ingress -n jitsi` | `ADDRESS` populated with AWS ALB hostname. | Passed |
| Public DNS Resolution | `dig @1.1.1.1 hrnbyl.rahulbastia.tech CNAME +short` | Returns `k8s-jitsi...ap-south-1.elb.amazonaws.com.`. | Passed |
| Web UI Availability | Navigate to `[https://hrnbyl.rahulbastia.tech](https://hrnbyl.rahulbastia.tech)` | Jitsi Meet landing page loads cleanly with valid HTTPS SSL certificate. | Passed |
| Room Creation | Enter test room name (e.g. `hrnbyl-test-room`) | Room opens without "Connection Error" dialogs; video/audio interface initializes. | Passed |

---

## Rollback Procedures

If an upgrade causes service disruption, execute the following steps:

1. **Rollback Helm Release:**
```bash
# View release history
helm history jitsi-release -n jitsi

# Rollback to previous revision (e.g., revision 1)
helm rollback jitsi-release 1 -n jitsi

```


2. **Verify Pod Stabilization:**
```bash
kubectl get pods -n jitsi -w

```



---

## Post-Deployment

Monitoring and operational tasks following deployment completion.

1. **Monitor Ingress Health Checks:**
```bash
kubectl logs -l app=jitsi-web -n jitsi --tail=20

```


*Expected Output:* `10.0.x.x - - [...] "GET / HTTP/1.1" 200 8657 "" "ELB-HealthChecker/2.0"`
2. **Watch AWS ALB & Target Group Metrics:** Ensure target health status in AWS EC2 Console reads `Healthy` for all attached EKS worker node targets.

---

## Review and Signoff

| Role | Name | Date | Notes |
| --- | --- | --- | --- |
| Preparer | Rahul Bastia | August 5, 2026 | Initial production deployment completed successfully. |
| Reviewer | DevOps Lead | August 5, 2026 | Verified IRSA setup, ALB/NLB ingress, and SSL binding. |
| Approver | Infrastructure Lead | August 5, 2026 | Approved for production traffic. |



