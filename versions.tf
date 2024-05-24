terraform {
  required_version = ">= 1.8.4"

  cloud {
    # Organization name you created in your terraform cloud account.
    # This is different for each account. Use same name you created in your account
    organization = "learn-and-create"
    workspaces {
      tags = ["dev"]
    }
  }
}