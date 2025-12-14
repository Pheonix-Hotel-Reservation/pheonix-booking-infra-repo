# Data source for Ubuntu 22.04 AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# SSH Key Pair
resource "aws_key_pair" "k8s_key" {
  key_name   = var.ssh_key_name
  public_key = file("~/.ssh/id_rsa.pub")

  tags = {
    Name = "${var.cluster_name}-key"
  }
}

# Kubernetes Nodes (Master + Workers)
resource "aws_instance" "k8s_nodes" {
  count                  = var.node_count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.k8s_key.key_name
  subnet_id              = aws_subnet.public[count.index % 3].id
  vpc_security_group_ids = [aws_security_group.k8s_nodes.id]
  iam_instance_profile   = aws_iam_instance_profile.k8s_node_profile.name

  # Ensure instance gets a predictable hostname
  user_data = <<-EOF
              #!/bin/bash
              # Set hostname to match EC2 Private DNS
              PRIVATE_DNS=$(ec2-metadata --local-hostname | cut -d " " -f 2)
              hostnamectl set-hostname $PRIVATE_DNS
              EOF

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
  }

  # CRITICAL: Tag instances as "owned" for controller discovery
  tags = merge(
    {
      Name = "${var.cluster_name}-node-${count.index + 1}"
      Role = count.index == 0 ? "master" : "worker"
      "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    }
  )

  # Ensure proper initialization
  depends_on = [
    aws_internet_gateway.main,
    aws_nat_gateway.main
  ]
}
