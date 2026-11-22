# Adapting to IL5 / classified (air-gapped) enclaves

The repo runs as-is in a commercial or GovCloud account with internet access.
Here is what changes for a **DoD IL5** workload (DoD CC SRG) or a disconnected
classified enclave, which is the Ft. Meade-style customer this targets.

## 1. Region and partition
- Deploy to **AWS GovCloud (US)** (`aws-us-gov`, `us-gov-west-1` / `us-gov-east-1`); IL5 needs GovCloud or dedicated infrastructure. IL6/Secret uses the AWS Secret Region, a separate partition (`aws-iso-b`).
- All ARNs use `data.aws_partition.current.partition`, and a `check` block fails the plan if the credentials resolve to the wrong partition.

## 2. No internet egress
- Remove the NAT gateway and IGW (`single_nat_gateway` → drop the public subnets entirely); rely on **VPC interface/gateway endpoints** (already in `modules/vpc/endpoints.tf`: ECR api/dkr, S3, STS, CloudWatch Logs, KMS, EC2, EKS, ELB).
- Use regional STS endpoints (`eks.amazonaws.com/sts-regional-endpoints: "true"` on the ServiceAccount).
- NetworkPolicy egress is already restricted to DNS, Keycloak, and in-VPC 443.

## 3. Mirrored registries and dependencies
- Base images: pull from **Iron Bank** (`registry1.dso.mil`) on the low side, scan them, then mirror into an in-enclave ECR repo; pin `FROM` by `@sha256` digest.
- Python wheels: mirror to an internal PyPI (CodeArtifact, Nexus, or Artifactory); set `PIP_INDEX_URL`.
- Terraform providers: use a `provider_installation { filesystem_mirror { ... } }` or network mirror in `.terraformrc`; commit `.terraform.lock.hcl`.
- Scanner DBs: Trivy runs with `--skip-db-update` against a DB bundle that gets imported on a schedule; checkov and tflint plugins are vendored.

## 4. CI/CD inside the enclave
- GitHub.com is not reachable. Run the same stages on **GitLab CI (self-managed) or Jenkins** in the enclave; the stages map 1:1 (see `.github/workflows/devsecops-pipeline.yml`). Runners are EC2/EKS-hosted inside the VPC.
- Keyless Sigstore (public Fulcio/Rekor) is not available. Use **cosign with a KMS key** instead: `cosign sign --key awskms:///alias/image-signing`, plus a private Rekor or no tlog. Enforce verification in-cluster with **Kyverno or Sigstore policy-controller** admission policies.

## 5. FIPS 140-2/140-3
- Use AWS **FIPS endpoints** (`AWS_USE_FIPS_ENDPOINT=true`; Terraform provider `use_fips_endpoint = true`).
- Node AMIs: FIPS-enabled, STIG-hardened Bottlerocket or AL2023 (or RHEL with `fips-mode-setup --enable`) via a custom launch-template AMI.
- Container base: Iron Bank / Chainguard FIPS images, with TLS terminated by FIPS-validated modules (ALB with a FIPS TLS policy such as `ELBSecurityPolicy-TLS13-1-2-FIPS-2023-04`).

## 6. Artifact promotion across enclaves (low → high)
1. Build, scan, SBOM, and sign on the low side (this pipeline).
2. Package the image (`skopeo copy docker://...@sha256:... oci-archive:mission-api.tar`) plus SBOM, signature, and scan reports into a bundle with a SHA-256 manifest.
3. Transfer through the approved **cross-domain solution (CDS)** or data transfer process, with ISSO review.
4. On the high side: verify the hashes and signature, re-scan with the high-side Trivy DB, then push to the high-side ECR **by digest**. Deploy only digests that passed verification.

## 7. Identity
- Keycloak in-cluster (HA, PostgreSQL on RDS, FIPS mode), federated to the enclave's AD/LDAP; CAC/PIV through X.509 client-cert authentication.
- STIGs: apply the Kubernetes STIG and the relevant OS STIG; feed SCAP and checkov results into the ATO package.
