# Security Policy

## Supported versions

This repository is a pre-release research-software project. No tagged or
versioned release is currently supported. Security reports will be assessed
against the current `main` branch.

| Repository state | Security support |
|---|---|
| Current `main` branch | Eligible for review and fixes |
| Earlier commits, forks, or unofficial copies | Not supported |
| Tagged releases | None published |

## Reporting a vulnerability

Do not report a suspected security vulnerability in a public issue, pull
request, discussion, commit message, or other public channel.

This repository does not currently provide GitHub's private vulnerability
reporting form. To request a private reporting channel:

1. Open the
   [Private security contact form](https://github.com/nikolvolfova-web/Analysis-of-Mitochondrial-Ultrastructure-and-Morphology/issues/new?template=03-security-contact.yml).
2. Submit only the form's required confirmations.
3. Do not include any vulnerability details, affected paths, reproduction
   steps, screenshots, logs, data, or secrets in that issue.
4. Wait for the maintainer to arrange an appropriate private channel before
   sharing further information.

Once a private channel has been arranged, include only the information needed
to understand the problem:

- the affected file, component, or commit;
- a clear description of the vulnerability and its possible impact;
- privacy-safe reproduction steps using synthetic or redacted inputs;
- the relevant R, operating-system, and package versions; and
- a suggested mitigation, if known.

Do not attach, paste, or link research workbooks, real subject- or image-level
values, microscopy files, unpublished tables or figures, internal identifiers,
article drafts, credentials, access tokens, or other confidential material.
No vulnerability-reporting channel is approved for transferring research data.

If a credential or secret may have been exposed, revoke or rotate it
immediately. In the report, identify the affected path or commit without
reproducing the secret.

## What belongs in a security report

Examples include:

- unintended disclosure of data, credentials, or local file contents caused
  by the repository code;
- unsafe file-path or input handling that could overwrite or expose files;
- arbitrary code execution or dependency vulnerabilities affecting this
  workflow; and
- a repository configuration problem that could expose protected material.

Scientific disagreements, statistical-model questions, ordinary software
bugs, documentation corrections, and reproducibility problems without a
security impact should use a regular GitHub issue with a minimal synthetic
example. Never include confidential or unpublished material in a public issue.

## Disclosure and response

Please allow the maintainer a reasonable opportunity to investigate and
address a confirmed vulnerability before public disclosure. Reports will be
reviewed as resources permit; this pre-release project does not currently
offer a guaranteed response time, service-level agreement, bug bounty, or
monetary reward.
