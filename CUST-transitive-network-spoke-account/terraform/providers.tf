provider "aws" {
  region = var.region

  default_tags {
    tags = {
      managed_by    = "platformr_Customizations"
      customization = var.customization_name
    }
  }
}
