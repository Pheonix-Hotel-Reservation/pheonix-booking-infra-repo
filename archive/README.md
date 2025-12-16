# Archive Directory

This directory contains files that are no longer needed for active operations but are kept for reference.

## Contents:

### terraform-local-state/
Old local Terraform state files. These have been (or should be) migrated to S3 remote backend.
**DO NOT USE THESE - Use remote state in S3**

### old-playbooks/
Ansible playbooks used for upgrading to Kubernetes 1.34.
Kept for reference in case we need to upgrade other clusters.

### Disabled Configurations
- `route53.tf.disabled` - Route53 configuration (not currently used)

## Can I Delete This?

Yes, but only after:
1. Confirming Terraform state is successfully in S3
2. You don't need historical playbooks for other clusters
3. Keeping a backup of the repo elsewhere

## Restoration

If you need to restore any file:
1. Check git history: `git log -- path/to/file`
2. Restore from git: `git checkout <commit> -- path/to/file`
3. Or copy from this archive directory
