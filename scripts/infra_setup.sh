#!/bin/bash
set -e
REGION="us-east-1"
VPC_CIDR="10.0.0.0/24"
PRIVATE_SUBNET_CIDR="10.0.0.0/25"
PUBLIC_SUBNET_CIDR="10.0.0.128/25"
AVAILABILITY_ZONE="us-east-1a"

echo "=== [Step 1] Creating Virtual Private Cloud ==="
VPC_ID=$(aws ec2 create-vpc --cidr-block "$VPC_CIDR" --region "$REGION" --query 'Vpc.VpcId' --output text)
echo "Created VPC: $VPC_ID"
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames '{"Value":true}' --region "$REGION"
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support '{"Value":true}' --region "$REGION"
aws ec2 create-tags --resources "$VPC_ID" --tags Key=Name,Value="csd215-vpc" --region "$REGION"

echo -e "\n=== [Step 2] Creating Subnets ==="
PRIVATE_SUBNET_ID=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$PRIVATE_SUBNET_CIDR" --availability-zone "$AVAILABILITY_ZONE" --region "$REGION" --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources "$PRIVATE_SUBNET_ID" --tags Key=Name,Value="csd215-subnet-private" --region "$REGION"

PUBLIC_SUBNET_ID=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$PUBLIC_SUBNET_CIDR" --availability-zone "$AVAILABILITY_ZONE" --region "$REGION" --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources "$PUBLIC_SUBNET_ID" --tags Key=Name,Value="csd215-subnet-public" --region "$REGION"

echo -e "\n=== [Step 3] Creating Internet Gateway ==="
IGW_ID=$(aws ec2 create-internet-gateway --region "$REGION" --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --vpc-id "$VPC_ID" --internet-gateway-id "$IGW_ID" --region "$REGION"
aws ec2 create-tags --resources "$IGW_ID" --tags Key=Name,Value="csd215-igw" --region "$REGION"

echo -e "\n=== [Step 4] Customizing Route Tables ==="
PUBLIC_ROUTE_TABLE_ID=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --region "$REGION" --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id "$PUBLIC_ROUTE_TABLE_ID" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" --region "$REGION" > /dev/null
aws ec2 associate-route-table --subnet-id "$PUBLIC_SUBNET_ID" --route-table-id "$PUBLIC_ROUTE_TABLE_ID" --region "$REGION" > /dev/null

PRIVATE_ROUTE_TABLE_ID=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --region "$REGION" --query 'RouteTable.RouteTableId' --output text)
aws ec2 associate-route-table --subnet-id "$PRIVATE_SUBNET_ID" --route-table-id "$PRIVATE_ROUTE_TABLE_ID" --region "$REGION" > /dev/null
aws ec2 create-tags --resources "$PUBLIC_ROUTE_TABLE_ID" --tags Key=Name,Value="csd215-route-table-public" --region "$REGION"
aws ec2 create-tags --resources "$PRIVATE_ROUTE_TABLE_ID" --tags Key=Name,Value="csd215-route-table-private" --region "$REGION"

echo -e "\n=== [Step 5] Provisioning VPC Endpoint Gateway ==="
VPCE_ID=$(aws ec2 create-vpc-endpoint --vpc-id "$VPC_ID" --service-name "com.amazonaws.$REGION.dynamodb" --vpc-endpoint-type Gateway --route-table-ids "$PUBLIC_ROUTE_TABLE_ID" "$PRIVATE_ROUTE_TABLE_ID" --region "$REGION" --query 'VpcEndpoint.VpcEndpointId' --output text)
aws ec2 create-tags --resources "$VPCE_ID" --tags Key=Name,Value="csd215-dynamodb-endpoint" --region "$REGION"

echo -e "\n=== [Step 6] Provisioning DynamoDB Table ==="
aws dynamodb create-table --table-name dice-rolls --attribute-definitions AttributeName=source,AttributeType=S AttributeName=timestamp,AttributeType=S --key-schema AttributeName=source,KeyType=HASH AttributeName=timestamp,KeyType=RANGE --billing-mode PAY_PER_REQUEST --region "$REGION" > /dev/null
mkdir -p deliverables
aws dynamodb describe-table --table-name dice-rolls --region "$REGION" > deliverables/resource-descriptions.txt

echo -e "\n=== [Step 7] Setting Up Security Groups ==="
EC2_SG_ID=$(aws ec2 create-security-group --group-name "csd215-ec2-sg" --description "Security group for EC2 Flask API" --vpc-id "$VPC_ID" --region "$REGION" --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id "$EC2_SG_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0 --region "$REGION" > /dev/null
aws ec2 authorize-security-group-ingress --group-id "$EC2_SG_ID" --protocol tcp --port 80 --cidr 0.0.0.0/0 --region "$REGION" > /dev/null

echo -e "\n=== Infrastructure Completed Successfully! ==="
