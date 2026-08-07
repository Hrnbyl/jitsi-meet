

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


## 7. Issue #5: Unclickable "Join Meeting" Button (JVB & Jicofo Connection Failures)

**Symptom:**
Users could load the Jitsi frontend, but the "Join meeting" button remained greyed out and unclickable on the pre-join screen.

**Diagnostic Approach:**
When the frontend loads but a meeting cannot be initiated, it indicates a failure in the backend components (Jicofo for room allocation, JVB for video bridging).

1. Executed `kubectl logs deploy/jitsi-jicofo -n jitsi --tail=50` to check the Focus Manager.
2. Executed `kubectl logs deploy/jitsi-jvb -n jitsi --tail=50` to check the Videobridge.

**Root Cause:**
Both backend components were failing to register with the Prosody XMPP server due to missing or incorrect environment variables:

* **JVB:** The `XMPP_SERVER` environment variable was entirely missing from `jvb-deployment.yaml`. The system defaulted to a non-existent DNS record (`xmpp.meet.jitsi`), throwing an `UnknownHostException`.
* **Jicofo:** The deployment was using the short DNS name (`jitsi-prosody`) instead of the Kubernetes FQDN, and it was missing the `XMPP_MUC_DOMAIN` variable, causing it to attempt room creation on the external domain rather than the internal network.

**Final Resolution:**

1. Updated `jvb-deployment.yaml` to explicitly include `XMPP_SERVER` pointing to the internal FQDN (`jitsi-prosody.jitsi.svc.cluster.local`).
2. Updated `jicofo-deployment.yaml` to use the FQDN and injected the missing `XMPP_MUC_DOMAIN` variable.
3. Restarted both deployments via `kubectl rollout restart` to force fresh connections.

---

## 8. Issue #6: WebSocket `<host-unknown>` Error & Domain Mismatch

**Symptom:**
After fixing the backend connections, the UI attempted to connect but immediately fell into a "Disconnected - Reconnecting" loop. Inspecting the browser's Network tab for the WebSocket connection revealed an XMPP stream error: `<stream:error><host-unknown.../></stream:error>`. Concurrently, Prosody logs showed it returning an `<iq type='error'>` stating: `Communication with remote domains is not enabled`.

**Diagnostic Approach:**

1. Checked Prosody logs for exact stanza rejections.
2. Verified the active environment variables injected into the running containers using `kubectl exec deploy/jitsi-web -n jitsi -- env | grep -i XMPP`.
3. Inspected the global Helm chart `values.yaml`.

**Root Cause (The "Split Personality" Configuration):**
The infrastructure suffered from a domain mismatch between the public frontend and the internal backend components.

* The web client sent an XMPP handshake requesting the public domain (`hrnbyl.rahulbastia.tech`).
* However, the `values.yaml` file left the internal XMPP variables (`authDomain`, `mucDomain`) set to the default placeholder (`meet.jitsi`).
* When Jicofo requested room creation for the public domain, Prosody—which was only listening for the internal `meet.jitsi` domain—treated the request as an unauthorized external server-to-server connection and blocked it.

**Final Resolution:**

1. **Unified Global Variables:** Edited the `values.yaml` file to explicitly map all internal XMPP domains to the active public domain:
* `authDomain: "auth.hrnbyl.rahulbastia.tech"`
* `mucDomain: "muc.hrnbyl.rahulbastia.tech"`
* `internalMucDomain: "internal-muc.hrnbyl.rahulbastia.tech"`


2. **Cluster-Wide Restart:** Because Prosody must generate new internal VirtualHosts based on these domains, the Helm chart was upgraded, and a sequential rollout restart was performed on all four primary components (`prosody`, `jicofo`, `jvb`, `web`).

---

## 9. Final Verification & Sign-off

Following the cluster-wide domain synchronization, the Jitsi Meet architecture stabilized completely.

**Success Metrics Achieved:**

* **Infrastructure:** EKS nodes running efficiently within AWS Free Tier limits (using `t3.small` nodes).
* **Networking:** WebSockets reliably maintain stateful connections without `502` or `<host-unknown>` drops.
* **Application:** Multi-user sessions are successfully brokered by Jicofo and handled by JVB. As evidenced by final testing (reference: `image_0419b7.png`), multiple distinct user profiles can join the same room with stable audio/video transmission and active moderator controls. The deployment is considered fully functional and production-ready.