terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }

  # Do NOT add a backend block here. The Platformr build environment injects
  # the state backend configuration at run time (one state per customization
  # per target account). Adding one here will conflict with it.
}
