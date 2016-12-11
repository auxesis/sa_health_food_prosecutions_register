variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "aws_region" {
	default = "us-east-1"
}
variable "aws_availability_zones" {
	default = "us-east-1b"
}
# Comma separated list of CIDRs the ELB should allow access from.
variable "morph_cidrs" {
	default = "50.116.3.88/32,104.237.132.0/24"
}
