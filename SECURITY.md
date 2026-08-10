# Security Policy

## Supported versions

This repository is a research-software and analysis companion project.

Security reports are assessed against the current `main` branch and, once
versioned releases are published, against the latest supported release.

| Repository state | Security support |
|---|---|
| Current `main` branch | Eligible for review and fixes |
| Latest tagged release | Eligible for review and fixes |
| Earlier commits, older releases, forks, or unofficial copies | Not supported |

## Reporting a vulnerability

Do not report a suspected security vulnerability in a public issue, pull
request, discussion, commit message, or other public channel.

After public release, security vulnerabilities should be reported using
GitHub's private vulnerability reporting feature available from the
repository's **Security** page via **Report a vulnerability**.

While the repository remains private, collaborators should report suspected
security issues to the maintainer using an existing private communication
channel rather than a GitHub issue.

When submitting a security report, include only the information needed to
understand the problem:

- the affected file, component, or commit;
- a clear description of the vulnerability and its possible impact;
- privacy-safe reproduction steps using synthetic or redacted inputs;
- the relevant R or Python version, operating system, and package versions;
- and a suggested mitigation, if known.

Do not attach, paste, or link research workbooks, real subject- or image-level
values, microscopy files, unpublished tables or figures, internal identifiers,
article drafts, credentials, access tokens, or other confidential material.

The vulnerability-reporting channel is not approved for transferring research
data.

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
example.

Never include confidential, protected, or unpublished research material in a
public issue.

## Disclosure and response

Please allow the maintainer a reasonable opportunity to investigate and
address a confirmed vulnerability before public disclosure.

Reports will be reviewed as resources permit. This research repository does
not provide a guaranteed response time, service-level agreement, bug bounty,
or monetary reward.
