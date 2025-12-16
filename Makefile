.PHONY: help init plan apply destroy ansible-install ansible-upgrade ansible-check terraform-validate

# Default target
help:
	@echo "Phoenix Infrastructure Management"
	@echo ""
	@echo "Terraform Commands:"
	@echo "  make init              - Initialize Terraform"
	@echo "  make validate          - Validate Terraform configuration"
	@echo "  make plan              - Run Terraform plan"
	@echo "  make apply             - Apply Terraform changes (interactive)"
	@echo "  make destroy           - Destroy infrastructure (interactive)"
	@echo ""
	@echo "Ansible Commands:"
	@echo "  make ansible-check     - Check Ansible playbook syntax"
	@echo "  make ansible-install   - Run Ansible installation playbook (DRY RUN)"
	@echo "  make ansible-upgrade   - Run Ansible upgrade playbook (DRY RUN)"
	@echo "  make ansible-platform  - Install platform components (DRY RUN)"
	@echo ""
	@echo "Safety Commands:"
	@echo "  make pre-flight        - Run all pre-flight checks"
	@echo ""
	@echo "NOTE: Add --no-dry-run flag to ansible commands to actually apply changes"

# Terraform targets
init:
	cd terraform && terraform init

validate:
	cd terraform && terraform validate

plan:
	cd terraform && terraform plan -out=tfplan

apply:
	@echo "WARNING: This will modify your infrastructure!"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		cd terraform && terraform apply tfplan; \
	else \
		echo "Aborted."; \
	fi

destroy:
	@echo "WARNING: This will DESTROY your infrastructure!"
	@read -p "Are you absolutely sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		cd terraform && terraform destroy; \
	else \
		echo "Aborted."; \
	fi

# Ansible targets
ansible-check:
	cd ansible && ansible-playbook --syntax-check site.yml
	cd ansible && ansible-playbook --syntax-check install-platform.yml

ansible-install:
	@echo "Running in DRY RUN mode (--check)..."
	cd ansible && ansible-playbook -i inventory.ini site.yml --check

ansible-upgrade:
	@echo "Running in DRY RUN mode (--check)..."
	cd ansible && ansible-playbook -i inventory.ini upgrade-k8s-to-1.34.yml --check

ansible-platform:
	@echo "Running in DRY RUN mode (--check)..."
	cd ansible && ansible-playbook -i inventory.ini install-platform.yml --check

# Safety checks
pre-flight: validate ansible-check
	@echo "✅ All pre-flight checks passed!"

# Ansible with actual apply (use with caution)
ansible-install-apply:
	@echo "WARNING: This will modify your Kubernetes cluster!"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		cd ansible && ansible-playbook -i inventory.ini site.yml; \
	else \
		echo "Aborted."; \
	fi
