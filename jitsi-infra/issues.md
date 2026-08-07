

# Post-Mortem & Troubleshooting Guide: Jitsi Meet Deployment on AWS EKS

## 1. Executive Summary

During the deployment of a highly available Jitsi Meet infrastructure on Amazon Elastic Kubernetes Service (EKS), several infrastructural and networking bottlenecks were encountered. These challenges ranged from AWS Elastic Network Interface (ENI) density limits and Free Tier vCPU quotas to Kubernetes internal DNS resolution and WebSocket protocol mismatches.

This document outlines the problems faced, the diagnostic approaches taken, and the final configurations implemented to achieve a stable, fully operational video conferencing platform. As verified in the final testing phase, the XMPP WebSocket connections are now successfully established and transmitting data frames.

---

## 2. Issue #1: Kubernetes Pods Stuck in "Pending" State

**Symptom:**
After deploying the Jitsi Helm chart, the `jitsi-web` and `jitsi-prosody` pods remained indefinitely in a `Pending` state. The Kubernetes scheduler logged the warning: `0/4 nodes are available: 4 Too many pods.`

**Root Cause:**
AWS EKS limits the maximum number of pods that can run on a single EC2 worker node based on the instance's physical size (specifically, its Elastic Network Interfaces and IP limits). The cluster was initially provisioned with 4x `t3.micro` instances. A `t3.micro` instance supports a maximum of only **4 pods per node**. Because essential Kubernetes system pods (like networking and DNS) consume these slots automatically, the cluster was at 100% capacity before the Jitsi application could even be scheduled.

**Approaches Tried:**

* **Manual Pod Deletion:** Attempted to delete older pods to make room. This failed because system pods immediately reclaimed the freed slots.
* **VPC CNI Prefix Delegation:** Attempted to enable IP prefix delegation (`ENABLE_PREFIX_DELEGATION=true`) to increase pod density. This failed to take immediate effect because the EC2 node's `kubelet` engine hardcodes the pod limit at the exact moment the server boots up; changing the setting later requires a node restart.

**Final Resolution:**
The node group instance type was upgraded. A `t3.small` instance supports up to 11 pods per node.

---

## 3. Issue #2: AWS vCPU Quota Exhaustion (`VcpuLimitExceeded`)

**Symptom:**
While attempting to upgrade the node sizes via Terraform to resolve Issue #1, the AWS API returned a `VcpuLimitExceeded` error, blocking the creation of the new EC2 instances.

**Root Cause:**
AWS Free Tier and newly created accounts enforce a strict soft limit of **8 vCPUs** total across a single region.
Terraform utilizes a "Create Before Destroy" strategy to prevent downtime. The environment had 4 old `t3.micro` nodes (8 vCPUs) running. When Terraform attempted to provision the new nodes (requiring an additional 4 to 8 vCPUs), the total requested vCPUs spiked to 12-16, violating the 8 vCPU account limit.

**Final Resolution:**

1. **Optimized Node Count:** Instead of 4 nodes, the configuration was reduced to **2x `t3.small` nodes**. This provides 22 total pod slots (11 per node) while utilizing only 4 vCPUs total, comfortably fitting within the 8 vCPU limit.
2. **Sequential Replacement:** A manual targeted destroy command (`terraform destroy -target=...`) was executed to explicitly delete the old servers *first*, dropping the utilized vCPU count back to zero.
3. **Apply New Configuration:** Once the quota was freed, the new 2-node configuration was successfully applied.

---

## 4. Issue #3: Helm Deployment Context Mismatch

**Symptom:**
When attempting to run the `helm upgrade --install` command to deploy Jitsi, the terminal returned an error stating: `namespaces "jitsi" not found`.

**Root Cause:**
The workstation was being used to manage multiple AWS accounts and projects. Although the AWS CLI profile was correctly set, the Kubernetes local remote control (`kubectl`) was still mapped to a different cluster (`go-web-app`) from a previous session.

**Final Resolution:**
The kubeconfig file was updated to point specifically to the correct EKS cluster using the AWS CLI:
`aws eks update-kubeconfig --region ap-south-1 --name jitsi-eks-cluster`

---

## 5. Issue #4: WebSocket `502 Bad Gateway` & Connection Drops

**Symptom:**
The Jitsi Meet UI loaded successfully in the browser, but the meeting immediately displayed a "Disconnected - Reconnecting in 10 sec" error. Network inspections revealed a `502 Bad Gateway` error specifically on the `/xmpp-websocket` path.

**Root Cause 1: Protocol/Port Mismatch**
The `jitsi-web` Nginx container was configured to route WebSocket traffic to Prosody on port `5222`. However, port `5222` is reserved for raw TCP XMPP traffic (traditional chat clients). Prosody's HTTP/BOSH server (which handles WebSockets) runs on port `5280`. Nginx received a rejection because it was speaking HTTP to a port expecting raw XML.

**Root Cause 2: Kubernetes Internal DNS Resolution**
After correcting the port, Nginx logs reported `jitsi-prosody could not be resolved (3: Host not found)`. Lightweight containers like Alpine Linux (often used for Nginx) can struggle to resolve short Kubernetes service names across namespaces.

**Final Resolution:**

1. **Expose Port 5280:** The d `prosody-deployment.yaml` file is updated to explicitly open and map `containerPort: 5280`.
2. **Implement FQDN (Fully Qualified Domain Name):** The `web-deployment.yaml` environment variables were updated to use the full internal Kubernetes DNS routing path instead of the short name.
* *Old configuration:* `http://jitsi-prosody:5222`
* *New configuration:* `[http://jitsi-prosody.jitsi.svc.cluster.local:5280](http://jitsi-prosody.jitsi.svc.cluster.local:5280)`


3. **Restart & Flush:** The Helm chart was upgraded and a `kubectl rollout restart deployment jitsi-web` was executed to flush the old DNS cache.

---

## 6. Verification and Final Status

Following the final DNS and port adjustments, the application was re-tested. As shown in the network payload capture (`image_4673dd.jpg`), the client successfully initiates the XMPP handshake.

The console confirms:

* `HTTP 101 Switching Protocols` is achieved.
* `<open xml:lang='en'...>` XMPP frames are successfully passing back and forth.
* The video meeting stabilizes with no further disconnections.

The Jitsi Meet infrastructure is now stable, optimized for cost on AWS Free Tier, and fully operational.