terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # Shared identity stack keeps its OWN state, separate from every app, so each
  # app deploys independently and just reads the pool id / client ids from outputs.
  backend "s3" {
    bucket = "identity-terraform-state-byreshb"
    key    = "identity/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  name_prefix = "${var.app_name}-${var.environment}"
}

resource "random_id" "suffix" {
  byte_length = 4
}
