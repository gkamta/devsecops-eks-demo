# Architecture

## Runtime (AWS GovCloud, us-gov-west-1)

```mermaid
flowchart LR
    user([Mission user<br/>CAC/PIV via IdP]) -->|OIDC auth code + PKCE| kc[Keycloak realm<br/>devsecops]
    user -->|HTTPS + Bearer JWT| alb[Internal ALB / Ingress]

    subgraph vpc[VPC 10.40.0.0/16 - flow logs to CloudWatch, KMS]
      subgraph priv[Private subnets x3 AZ]
        alb --> svc[Service mission-api]
        subgraph eks[EKS cluster - private API endpoint, KMS-encrypted secrets]
          svc --> pod1[mission-api pod<br/>non-root, read-only FS,<br/>caps dropped]
          svc --> pod2[mission-api pod]
          np{{NetworkPolicy<br/>default deny}}
        end
        vpce[VPC endpoints<br/>ECR, STS, S3, Logs, KMS, EKS]
      end
      nat[NAT GW<br/>removed in IL5 enclave]
    end

    pod1 -.->|JWKS fetch, cache| kc
    pod1 -.->|IRSA: AssumeRoleWithWebIdentity| sts[(AWS STS)]
    eks -.->|pull by digest| ecr[(ECR<br/>immutable tags,<br/>scan on push, KMS)]
    eks -.-> vpce
```

## Delivery pipeline

```mermaid
flowchart LR
    dev([git push / PR]) --> lint[Lint + pytest]
    dev --> gl[gitleaks]
    dev --> sast[bandit SAST]
    dev --> iac[checkov + tflint]
    dev --> tf[terraform fmt/validate<br/>plan via OIDC]
    lint & gl & sast & iac & tf --> build[docker build]
    build --> trivy{Trivy<br/>HIGH/CRITICAL?}
    trivy -- fail --> stop([blocked])
    trivy -- pass, main --> pub[push GHCR + ECR<br/>syft SBOM<br/>cosign sign + attest]
    pub --> d1[deploy dev]
    d1 -->|env approval| d2[deploy stage]
    d2 -->|env approval| d3[deploy prod]
    d1 & d2 & d3 -.->|cosign verify<br/>before apply| pub
```

## Key design points

| Concern | Decision |
|---|---|
| Identity for users | Keycloak OIDC; API validates RS256 JWT signature, `iss`, `aud`, `exp`, and realm role. |
| Identity for workloads | IRSA: one IAM role per ServiceAccount, scoped by `sub` + `aud` conditions. |
| Identity for CI | GitHub OIDC to AWS STS. No long-lived access keys anywhere. |
| Network | Private subnets only for nodes; private EKS API; default-deny NetworkPolicy; VPC endpoints. |
| Data at rest | Customer-managed KMS keys (rotation on) for EKS secrets, EBS, ECR, logs, TF state. |
| Supply chain | SHA-pinned actions, immutable ECR tags, deploy by digest, cosign keyless signatures, SPDX SBOM. |
| Auditability | EKS control-plane logs (api, audit, authenticator, ...), VPC flow logs, 365-day retention. |
