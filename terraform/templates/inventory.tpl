[master]
${master_ip} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_rsa private_dns=${master_private_dns}

[workers]
%{ for idx, ip in worker_ips ~}
${ip} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_rsa private_dns=${worker_private_dns[idx]}
%{ endfor ~}

[all:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
