# Pipeline and platform controls → NIST SP 800-53 Rev 5 / RMF

How the controls in this repo produce evidence for an RMF package (DoD
Cloud Computing SRG impact levels inherit the FedRAMP Moderate/High
baseline plus DoD-specific "FedRAMP+" controls). This shows **how the
pipeline produces evidence**; it is not a complete System Security Plan.

| 800-53 control | What it requires (short) | Implementation in this repo | Evidence produced |
|---|---|---|---|
| **AC-2** Account Management | Manage system accounts | Keycloak realm as the IdP; EKS **access entries** (not aws-auth); CI uses a federated OIDC role, not IAM users | Keycloak realm export, `aws_eks_access_entry` in TF state, CloudTrail `AssumeRoleWithWebIdentity` |
| **AC-3 / AC-6** Access Enforcement / Least Privilege | Enforce approved authorizations, minimum privilege | `require_role` dependency (403 without `mission-reader`); IRSA role scoped to one ServiceAccount; CI role limited to ECR push + `eks:DescribeCluster` + read-only | Unit tests `test_missing_role_is_403`; IAM policy JSON |
| **AC-4 / SC-7** Info Flow / Boundary Protection | Control flows, monitor boundary | Private subnets, private EKS endpoint, default-deny NetworkPolicy, VPC endpoints, locked-down default SG | `k8s/base/networkpolicy.yaml`, VPC flow logs |
| **AU-2 / AU-12** Event Logging | Generate audit records | EKS control-plane logs incl. `audit`; VPC flow logs; GitHub Actions run logs | CloudWatch log groups (365-day retention, KMS) |
| **CM-2** Baseline Configuration | Documented, version-controlled baseline | Everything is code: Terraform, Kustomize, Dockerfile; immutable image tags | Git history; `terraform plan` artifact per run |
| **CM-3** Configuration Change Control | Review/approve changes | PR checks must pass; GitHub Environments with required reviewers for stage/prod | PR approvals, environment deployment history |
| **CM-6 / CM-7** Config Settings / Least Functionality | Hardened settings, disable unneeded functions | Distroless image (no shell / pkg manager), PSA `restricted`, `readOnlyRootFilesystem`, drop ALL caps, IMDSv2 hop-limit 1 | checkov results (Dockerfile, K8s), manifests |
| **CM-8** Component Inventory | Inventory of components | Syft SPDX SBOM per image, attested with cosign | `sbom.spdx.json` artifact + attestation in registry |
| **IA-2** Identification & Authentication | Uniquely identify and authenticate users | OIDC bearer tokens; signature/issuer/audience/expiry validated; alg pinned to RS256 (blocks `alg=none` / HS256 confusion) | `app/auth.py`; tests `test_hs256_alg_confusion_rejected`, `test_wrong_signing_key_is_401` |
| **IA-5** Authenticator Management | Protect authenticators | No static cloud keys (OIDC federation); Keycloak password policy + brute-force protection; gitleaks blocks committed secrets | Workflow config, realm settings, gitleaks report |
| **RA-5** Vulnerability Monitoring & Scanning | Scan for vulns, remediate | Trivy gate (fixable HIGH/CRITICAL fail the build), ECR scan-on-push + Inspector continuous scan, checkov/tflint for IaC, Dependabot | SARIF in GitHub Security tab, ECR findings |
| **SA-11** Developer Testing & Evaluation | Unit, SAST, security testing | pytest (≥85% coverage gate), bandit SAST, IaC scanning in every PR | JUnit + coverage XML artifacts, SARIF |
| **SA-15 / SR-3/SR-4** Dev Process / Supply Chain | Controlled tooling, provenance | Actions pinned by commit SHA; SLSA provenance (`provenance: mode=max`); SBOM | Workflow file, provenance attestation |
| **SC-8** Transmission Confidentiality | Encrypt in transit | TLS-only S3 bucket policy for state; HSTS header; endpoints over 443 | Bucket policy, response headers |
| **SC-12 / SC-13 / SC-28** Key Mgmt / Crypto / Protection at Rest | Manage keys, FIPS crypto, encrypt at rest | Customer-managed KMS keys with rotation for EKS secrets, EBS, ECR, logs, state (KMS uses FIPS 140-validated HSMs in GovCloud) | TF config, `aws kms get-key-rotation-status` |
| **SI-2** Flaw Remediation | Patch in a timely manner | EKS managed add-ons + managed node group rolling updates; Dependabot for actions/pip/docker/terraform | Dependabot PRs, node group update history |
| **SI-7** Software & Information Integrity | Detect unauthorized changes | Cosign keyless signatures; deploy job runs `cosign verify` (identity pinned to this repo's `main` workflow) before `kubectl apply`; deploy by digest | Rekor transparency log entries, deploy logs |

## RMF lifecycle tie-in

- **Implement / Assess:** each pipeline run is a repeatable assessment; SARIF + reports are retained as artifacts.
- **Authorize:** the evidence above feeds the SSP and Security Assessment Report; `.trivyignore` entries map to POA&M items with expiry dates.
- **Monitor (continuous ATO / cATO):** Inspector continuous scanning, Dependabot, and scheduled pipeline runs support ongoing authorization, as described in the DoD DevSecOps Reference Design and cATO guidance.
