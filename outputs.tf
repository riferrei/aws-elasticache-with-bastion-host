output "bastion_host" {
    value = "ssh ec2-user@${aws_instance.bastion_host.public_ip} -i cert.pem"
}
