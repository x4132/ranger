terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws",
      version = "~> 6.18"
    }
  }

  required_version = ">= 1.13"
}