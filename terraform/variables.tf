variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Kubernetes cluster name"
  type        = string
  default     = "phoenix-cluster"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "master_instance_type" {
  description = "EC2 instance type for control plane node"
  type        = string
  default     = "t3.large"
}

variable "worker_instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t3.xlarge"
}

variable "node_count" {
  description = "Number of Kubernetes nodes"
  type        = number
  default     = 4
}

variable "ssh_key_name" {
  description = "SSH key name for EC2 instances"
  type        = string
  default     = "phoenix-k8s-key"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key file"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}
