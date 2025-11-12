
data "aws_availability_zones" "available" {}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.1"

  name = "ionos-vpc"
  cidr = "10.0.0.0/16"

  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"  # Compatible with AWS provider 5.x

  cluster_name                   = var.cluster_name
  cluster_version                = "1.33"
  cluster_endpoint_public_access = true

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets

  # EKS Cluster IAM Role
  create_iam_role = true
  iam_role_name   = "eks-cluster-role"
  iam_role_use_name_prefix = false
  iam_role_additional_policies = {
    additional = aws_iam_policy.eks_additional.arn
  }

  # EKS Cluster Security Group
  create_cluster_security_group = true
  cluster_security_group_name   = "eks-cluster-sg"
  cluster_security_group_description = "EKS cluster security group"

  # Node Group Security Group
  create_node_security_group = true
  node_security_group_name   = "eks-node-sg"

  # EKS Cluster Logging
  cloudwatch_log_group_retention_in_days = 30
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # Enable new access entry API (EKS v20 uses this instead of aws-auth ConfigMap)
  # This automatically grants admin access to the IAM principal that creates the cluster
  enable_cluster_creator_admin_permissions = true
  authentication_mode = "API_AND_CONFIG_MAP"

  # EKS Managed Node Groups
  eks_managed_node_groups = {
    main_v2 = {
      name            = "main-v2"
      use_name_prefix = true  # Allow Terraform to create new node group with unique name

      subnet_ids = module.vpc.private_subnets

      min_size     = 1
      max_size     = 20
      desired_size = 3

      capacity_type  = "ON_DEMAND"
      instance_types = ["t3.small"]  
      # Block Device Mappings
      disk_size = 20
      disk_type = "gp3"

      # IAM Role for Node Group
      iam_role_name                 = "eks-node-role"
      iam_role_use_name_prefix      = false
      iam_role_attach_cni_policy    = true
      iam_role_additional_policies = {
        AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
        ClusterAutoscaler                  = aws_iam_policy.cluster_autoscaler.arn
      }

      labels = {
        role = "worker"
      }

      tags = {
        Name = "eks-node"
      }
    }
  }


  tags = {
    Terraform   = "true"
    Environment = "dev"
  }

  depends_on = [ module.vpc ]
}

resource "aws_kms_key" "eks" {
  description             = "EKS cluster encryption key"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  
  tags = {
    Name = "${var.cluster_name}"
  }

  lifecycle {
    prevent_destroy = false
  }
}

# Additional IAM policy for EKS cluster
resource "aws_iam_policy" "eks_additional" {
  name        = "eks-additional-policy"
  description = "Additional policy for EKS cluster"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM policy for Cluster Autoscaler
resource "aws_iam_policy" "cluster_autoscaler" {
  name        = "cluster-autoscaler-policy"
  description = "Policy for Cluster Autoscaler"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeTags",
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:DescribeInstanceTypes",
          "eks:DescribeNodegroup"
        ]
        Resource = "*"
      }
    ]
  })
}

# IRSA for Cluster Autoscaler
module "irsa_cluster_autoscaler" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "5.20.0"

  create_role                   = true
  role_name                     = "cluster-autoscaler"
  provider_url                  = module.eks.oidc_provider
  role_policy_arns              = [aws_iam_policy.cluster_autoscaler.arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:kube-system:cluster-autoscaler"]
}