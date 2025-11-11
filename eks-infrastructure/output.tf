output "cluster_endpoint" {
  description = "The endpoint for the EKS cluster."
  value       = module.eks.cluster_endpoint
  
}
output "cluster_security_group_id" {
  description = "The security group ID for the EKS cluster."
  value       = module.eks.cluster_security_group_id
}

output "cluster_name" {
  description = "The name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "kubeconfig_certificate_authority_data" {
  description = "The certificate authority data for the EKS cluster."
  value       = module.eks.cluster_certificate_authority_data
}
   

output "cluster_id" {
  description = "EKS cluster ID"
  value       = module.eks.cluster_id
}

output "cluster_oidc_provider" {
  description = "OIDC provider for IRSA"
  value       = module.eks.oidc_provider
}