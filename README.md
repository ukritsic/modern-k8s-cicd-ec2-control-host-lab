# Modern Kubernetes CI/CD Lab with an EC2 Control Host

This project teaches a modern GitOps CI/CD process using:

- An existing self-managed Kubernetes cluster on Amazon EC2
- A separate Ubuntu EC2 instance as the administration/control host
- GitHub Actions for CI
- Amazon ECR for container images
- Argo CD for continuous delivery
- Kustomize for Kubernetes configuration

It does **not** use Amazon EKS and does **not** create or delete EC2 instances.

## Architecture

```text
Your computer
    |
    | SSH
    v
Ubuntu EC2 control host
  - aws
  - kubectl
  - helm
  - argocd CLI
  - kustomize
  - docker
  - project setup scripts
    |
    | private network: Kubernetes API TCP 6443
    v
Self-managed Kubernetes cluster on EC2
  - control-plane node(s)
  - worker node(s)
  - Argo CD
  - application Pods

Developer pushes code
    |
    v
GitHub Actions
  - test application
  - build immutable image
  - push image to Amazon ECR
  - update image SHA in Git
    |
    v
Argo CD detects Git change
    |
    v
Kubernetes rolls out the new Pods on EC2 workers
```

The important separation is:

```text
EC2 control host: install and operate the platform
GitHub Actions:    test, build, push, and update Git
Argo CD:           deploy Git state into Kubernetes
```

GitHub Actions does not require your Kubernetes admin kubeconfig.

---

# 1. Prepare the EC2 control host

Recommended lab configuration:

```text
Operating system: Ubuntu Server 22.04 or 24.04
Instance size:    t3.small or larger
Disk:             20 GB or more
Network:          same VPC, or routable network, as the Kubernetes API server
```

Security-group rules:

```text
Control host inbound:
  TCP 22 from your public IP only

Kubernetes control-plane inbound:
  TCP 6443 from the control-host security group
```

Do not expose SSH or the Kubernetes API server to `0.0.0.0/0`.

Connect to the control host:

```bash
ssh -i YOUR_KEY.pem ubuntu@CONTROL_HOST_PUBLIC_IP
```

Clone or copy this project onto that EC2 instance.

---

# 2. Install all tools on Ubuntu EC2

Run:

```bash
chmod +x scripts/*.sh
./scripts/install-tools-ubuntu.sh
```

The installer supports x86_64 and ARM64 Ubuntu instances and installs:

```text
AWS CLI v2
kubectl
Helm
Argo CD CLI
Kustomize
Docker Engine
Git
jq
Python 3
```

Reconnect by SSH after installation so Docker group membership takes effect:

```bash
exit
ssh -i YOUR_KEY.pem ubuntu@CONTROL_HOST_PUBLIC_IP
```

Verify:

```bash
aws --version
kubectl version --client
helm version
argocd version --client
kustomize version
docker version
```

You do not need `eksctl`.

## Match kubectl to an older cluster

The installer gets the current stable `kubectl` by default. To install a specific version:

```bash
KUBECTL_VERSION=v1.34.0 ./scripts/install-tools-ubuntu.sh
```

Use a client version close to the Kubernetes server version.

---

# 3. Give the control host AWS permissions

The recommended method is an IAM role attached to the EC2 instance, rather than storing permanent access keys with `aws configure`.

Create an EC2 IAM role with the policy in:

```text
infra/ec2-control-host-ecr-policy.json
```

Attach that role to the control-host EC2 instance:

```text
EC2 console
  -> Instances
  -> select the control host
  -> Actions
  -> Security
  -> Modify IAM role
```

Verify from the EC2 host:

```bash
aws sts get-caller-identity
```

The control-host role is used to create the lab ECR repository and generate an ECR login token for the Kubernetes image-pull Secret.

GitHub Actions uses a different IAM role through GitHub OIDC later in the lab.

---

# 4. Put kubeconfig on the control host

The control host must be able to reach the Kubernetes API endpoint using its private IP or internal DNS name.

## kubeadm lab cluster

On the Kubernetes control-plane EC2 instance:

```bash
sudo install \
  -o ubuntu \
  -g ubuntu \
  -m 600 \
  /etc/kubernetes/admin.conf \
  /home/ubuntu/k8s-admin.conf
```

From the separate control host, copy it over the private network:

```bash
scp -i YOUR_KEY.pem \
  ubuntu@CONTROL_PLANE_PRIVATE_IP:/home/ubuntu/k8s-admin.conf \
  /tmp/k8s-admin.conf
```

Install it:

```bash
./scripts/setup-kubeconfig.sh /tmp/k8s-admin.conf
rm -f /tmp/k8s-admin.conf
```

Validate:

```bash
./scripts/validate-cluster.sh
```

Expected shape:

```text
control-plane-1   Ready   control-plane
worker-1          Ready   <none>
worker-2          Ready   <none>
```

`admin.conf` grants powerful cluster-administrator access. Keep the control host private, protect SSH access, and keep `~/.kube/config` permission set to `600`. For production, create a dedicated identity and RBAC permissions instead of distributing `admin.conf`.

## k3s

On the k3s server, the kubeconfig is commonly:

```text
/etc/rancher/k3s/k3s.yaml
```

Copy it to the control host and replace the local server address in the file with a Kubernetes API address reachable from the control host.

---

# 5. Create the GitHub repository

Create a repository such as:

```text
modern-k8s-cicd-ec2-control-host-lab
```

For the first exercise, a public repository is simpler because Argo CD can read it without repository credentials.

From the control host:

```bash
git init
git branch -M main
git remote add origin \
  https://github.com/YOUR_GITHUB_USER/modern-k8s-cicd-ec2-control-host-lab.git

git add .
git commit -m "initial EC2 Kubernetes GitOps lab"
git push -u origin main
```

---

# 6. Create the ECR repository

```bash
export AWS_REGION=ap-southeast-1
./scripts/create-ecr.sh
```

Default repository:

```text
modern-k8s-cicd-app
```

Check:

```bash
aws ecr describe-repositories \
  --region "$AWS_REGION" \
  --repository-names modern-k8s-cicd-app
```

---

# 7. Configure project placeholders

Run:

```bash
export AWS_REGION=ap-southeast-1

./scripts/configure-project.sh \
  YOUR_GITHUB_USER \
  modern-k8s-cicd-ec2-control-host-lab
```

This updates:

```text
k8s/overlays/prod/kustomization.yaml
argocd/application.yaml
```

Review and push:

```bash
cat k8s/overlays/prod/kustomization.yaml
cat argocd/application.yaml

git add k8s argocd
git commit -m "configure ECR and GitOps repository"
git push
```

---

# 8. Configure GitHub OIDC for ECR push

GitHub Actions should use temporary AWS credentials, not permanent access keys.

Create GitHub's OIDC provider in AWS IAM:

```text
Provider URL: https://token.actions.githubusercontent.com
Audience:     sts.amazonaws.com
```

Create an ECR push policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "ecr:GetAuthorizationToken",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:CompleteLayerUpload",
        "ecr:InitiateLayerUpload",
        "ecr:PutImage",
        "ecr:UploadLayerPart"
      ],
      "Resource": "arn:aws:ecr:ap-southeast-1:AWS_ACCOUNT_ID:repository/modern-k8s-cicd-app"
    }
  ]
}
```

Create an IAM role with this trust policy, replacing the placeholders:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::AWS_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_GITHUB_USER/modern-k8s-cicd-ec2-control-host-lab:ref:refs/heads/main"
        }
      }
    }
  ]
}
```

Attach the ECR push policy to the role.

Add its ARN as this GitHub repository secret:

```text
AWS_ROLE_ARN
```

The workflow already requests:

```yaml
permissions:
  id-token: write
  contents: write
```

---

# 9. Allow Kubernetes to pull the ECR image

For the first lab, create an ECR registry Secret:

```bash
export AWS_REGION=ap-southeast-1
./scripts/configure-ecr-pull-secret.sh
```

The Deployment references:

```yaml
imagePullSecrets:
  - name: ecr-registry
```

ECR login tokens expire, so refresh the Secret when required:

```bash
./scripts/configure-ecr-pull-secret.sh
```

For production, configure the ECR kubelet image credential provider and an EC2 instance role on every worker node so kubelet obtains short-lived pull credentials automatically.

---

# 10. Install Argo CD in the existing cluster

From the EC2 control host:

```bash
./scripts/install-argocd.sh
```

Check:

```bash
kubectl get pods -n argocd
```

Register the application:

```bash
kubectl apply -f argocd/application.yaml
kubectl get applications -n argocd
```

Argo CD runs inside the target cluster, so the Application uses:

```yaml
server: https://kubernetes.default.svc
```

---

# 11. Access the Argo CD UI through SSH

On the EC2 control host:

```bash
kubectl port-forward \
  svc/argocd-server \
  -n argocd \
  8080:443
```

From your computer, open a second SSH connection with local forwarding:

```bash
ssh -i YOUR_KEY.pem \
  -L 8080:localhost:8080 \
  ubuntu@CONTROL_HOST_PUBLIC_IP
```

Open locally:

```text
https://localhost:8080
```

Username:

```text
admin
```

Get the password on the control host:

```bash
argocd admin initial-password -n argocd
```

---

# 12. Trigger the complete CI/CD process

Change `app/main.py`, then push:

```bash
git add app/main.py
git commit -m "release version 2"
git push
```

GitHub Actions performs:

```text
1. Run Python tests
2. Obtain temporary AWS credentials through OIDC
3. Build the Docker image
4. Tag the image with the Git commit SHA
5. Push the image to ECR
6. Update the Kustomize image reference
7. Commit the desired-state change to Git
```

Argo CD then performs:

```text
1. Detect the Git change
2. Compare Git with the running cluster
3. Update the Deployment
4. Wait for readiness checks
5. Replace old Pods with new Pods
```

The EC2 control host does not need to stay connected for Argo CD to continue reconciling Git.

---

# 13. Verify deployment from the control host

```bash
./scripts/verify-deployment.sh
```

Or run:

```bash
kubectl get applications -n argocd
kubectl get deployment,pods,svc -n modern-cicd -o wide
kubectl rollout status deployment/fastapi-app -n modern-cicd
```

The `NODE` column shows which EC2 worker runs each Pod.

Access without opening NodePort publicly:

```bash
kubectl port-forward \
  svc/fastapi-app \
  -n modern-cicd \
  8000:80
```

From your computer, create an SSH tunnel:

```bash
ssh -i YOUR_KEY.pem \
  -L 8000:localhost:8000 \
  ubuntu@CONTROL_HOST_PUBLIC_IP
```

Then open or call:

```bash
curl http://localhost:8000/
```

---

# 14. Practice rollback

Find the deployment commits:

```bash
git log --oneline -- k8s/overlays/prod/kustomization.yaml
```

Revert the latest deployment commit:

```bash
git revert COMMIT_SHA
git push
```

Flow:

```text
Git returns to the previous image SHA
        |
        v
Argo CD detects the change
        |
        v
Kubernetes rolls back the Deployment
```

---

# 15. Practice Argo CD self-healing

Manually change the live replica count:

```bash
kubectl scale deployment fastapi-app \
  -n modern-cicd \
  --replicas=5
```

Watch:

```bash
kubectl get deployment fastapi-app -n modern-cicd -w
```

Because Git declares two replicas and `selfHeal` is enabled, Argo CD should restore the replica count to two.

---

# 16. Is the control host also a GitHub Actions runner?

Not by default.

The included workflow uses:

```yaml
runs-on: ubuntu-latest
```

Therefore, GitHub-hosted infrastructure executes the CI job. Your EC2 control host is used for installation, Kubernetes administration, verification, and troubleshooting.

To execute GitHub Actions jobs on this EC2 instance, register it as a GitHub self-hosted runner and change the workflow to:

```yaml
runs-on: [self-hosted, linux, x64]
```

Use a private repository, restrict who can modify workflows, and avoid placing a cluster-admin kubeconfig in the runner account. A workflow running on a self-hosted runner can execute commands on that machine.

---

# 17. Troubleshooting

## kubectl times out

Check the API address in kubeconfig:

```bash
kubectl config view --minify
```

Check connectivity from the control host:

```bash
nc -vz CONTROL_PLANE_PRIVATE_IP 6443
```

Verify routing and the control-plane security group.

## Pod shows ImagePullBackOff

```bash
kubectl describe pod -n modern-cicd POD_NAME
kubectl get secret ecr-registry -n modern-cicd
./scripts/configure-ecr-pull-secret.sh
kubectl delete pod -n modern-cicd POD_NAME
```

## GitHub Actions cannot push to ECR

Check:

```text
AWS_ROLE_ARN repository secret
OIDC trust-policy repository name
OIDC trust-policy branch
ECR repository ARN and region
```

## GitHub Actions cannot push the manifest commit

Check:

```text
Repository workflow permissions allow read and write
Branch protection rules
contents: write in the workflow
```

---

# 18. Cleanup

Remove only the sample application:

```bash
./scripts/cleanup-app.sh
```

This does not delete:

```text
Kubernetes cluster
EC2 instances
VPC
Argo CD
ECR repository
```

Remove Argo CD separately when no longer needed:

```bash
kubectl delete namespace argocd
```

Delete the lab ECR repository separately:

```bash
aws ecr delete-repository \
  --region ap-southeast-1 \
  --repository-name modern-k8s-cicd-app \
  --force
```

---

# Recommended production evolution

1. Replace the ECR image-pull Secret with the kubelet ECR credential provider.
2. Create a dedicated Kubernetes administrator identity instead of copying `admin.conf`.
3. Separate application source and GitOps configuration into different repositories.
4. Make CI open a pull request for production changes.
5. Require review before merging production image updates.
6. Pin Argo CD and GitHub Actions to tested immutable versions.
7. Add container vulnerability scanning, signing, and admission policies.
8. Add HTTPS ingress, DNS, monitoring, and alerting.
9. Add Argo Rollouts for canary or blue-green releases.
10. Back up etcd and test Kubernetes control-plane recovery.
