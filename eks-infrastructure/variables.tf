variable "region" {
    description = "AWS region"
    default = "us-east-1"
}

variable "cluster_name" {
    description = "EKS Cluster Name"
    default = "ionos-eks-cluster"
  }

variable "key_pair" {
    description = "EC2 Key Pair Name"
    default = "key-pair"
  
}