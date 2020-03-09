# Creating a AWS ElastiCache for Redis with a Bastion Host

This example show how to create a bastion host for a Redis server created on AWS using ElastiCache. Using a bastion host along with your Redis server is useful for troubleshooting purposes, where developers can easily access the Redis server otherwise only accessible by any service _running in the same private subnet_ of Redis. To allow access to Redis, the bastion host created has the `redis-cli` CLI installed by default.

## Steps to use this example:

### 1 - Create a variables file for AWS

```bash
mv variables.auto.tfvars.example variables.auto.tfvars
```

### 2 - Provide the AWS configuration

```bash
aws_access_key = "<AWS_ACCESS_KEY>"
aws_secret_key = "<AWS_SECRET_KEY>"
aws_region = "<AWS_REGION>"
```

### 3 - Create resources with Terraform

```bash
terraform init
terraform plan
terraform apply
```

### 4 - SSH to the Bastion host

```bash
ssh ec2-user@<BASTION_HOST_PUBLIC_IP> -i cert.pem
```

The bastion host public ip will be shown after Terraform finishes the creation of the resources using the outputs instruction. To force Terraform to show the output again, just execute `terraform output`.

### 5 - Access the Redis server

```bash
redis-cli -h <REDIS_CLUSTER_ENDPOINT>
```

The Redis cluster endpoint will be provided within the bastion host. To retrieve that, just inspect the `/etc/hosts` file.

## License

[Apache 2.0 License](./LICENSE).
