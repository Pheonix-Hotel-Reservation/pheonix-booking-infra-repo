# Output EC2 instance information
output "master_public_ip" {
  description = "Public IP of the master node"
  value       = aws_instance.k8s_nodes[0].public_ip
}

output "master_private_ip" {
  description = "Private IP of the master node"
  value       = aws_instance.k8s_nodes[0].private_ip
}

output "worker_public_ips" {
  description = "Public IPs of worker nodes"
  value       = slice(aws_instance.k8s_nodes[*].public_ip, 1, length(aws_instance.k8s_nodes))
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "cluster_name" {
  description = "Kubernetes cluster name"
  value       = var.cluster_name
}

# Generate Ansible inventory file
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/templates/inventory.tpl", {
    master_ip     = aws_instance.k8s_nodes[0].public_ip
    master_private_dns = aws_instance.k8s_nodes[0].private_dns
    worker_ips    = slice(aws_instance.k8s_nodes[*].public_ip, 1, length(aws_instance.k8s_nodes))
    worker_private_dns = slice(aws_instance.k8s_nodes[*].private_dns, 1, length(aws_instance.k8s_nodes))
    ssh_key       = var.ssh_key_name
  })
  filename = "${path.module}/../ansible/inventory.ini"
}
